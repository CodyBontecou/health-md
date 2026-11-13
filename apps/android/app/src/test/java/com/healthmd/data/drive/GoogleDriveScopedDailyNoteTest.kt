package com.healthmd.data.drive

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.*
import com.healthmd.domain.model.*
import com.healthmd.export.ExportFixtures
import java.io.File
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

/** Real host core plus production materializer, private journal and final-byte merger. */
@RunWith(RobolectricTestRunner::class)
class GoogleDriveScopedDailyNoteTest {
    private val factory = GeneratedExportBundleFactory(MarkdownExporter(), JsonExporter(), CsvExporter(), ObsidianBasesExporter())
    private val journalJson = kotlinx.serialization.json.Json { encodeDefaults = true }
    private val personal = "---\njournal: personal\n---\nPersonal introduction.\n\n## My thoughts\nKeep me.\n".encodeToByteArray()

    @Before fun useTaskOwnedCore() {
        val library = System.getenv("HEALTHMD_HOST_CORE_LIBRARY")
        assumeTrue("Requires an explicit freshly built host core", !library.isNullOrBlank())
        require(File(requireNotNull(library)).isFile)
        System.setProperty("uniffi.component.healthmd_core_uniffi.libraryOverride", library)
    }

    @Test fun `selected frontmatter survives materialization and frozen journal replay`() = runTest {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val root = File(context.noBackupFilesDir, "google-drive-operations")
        root.deleteRecursively()
        try {
            for (profile in CompatibilitySchemaProfile.entries) {
                val settings = ExportSettings(exportFormats = emptySet(),
                    formatCustomization = FormatCustomization(compatibilitySchemaProfile = profile,
                        frontmatterConfig = FrontmatterConfiguration(includeDate = false,
                            fields = FrontmatterConfiguration.defaultFields.map {
                                it.copy(isEnabled = it.originalKey == "steps",
                                    customKey = if (it.originalKey == "steps") "chosen_steps" else it.customKey)
                            })),
                    dailyNoteInjection = DailyNoteInjectionSettings(enabled = true, createIfMissing = true),
                    executionSleepCaptureContext = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.NIGHT_BEGINS))
                val id = "selected-${profile.name}"
                val bundle = factory.daily(id, null, "manual", listOf(ExportFixtures.partialDay), settings)
                val generated = bundle.artifacts.single()
                assertThat(generated.bytes.decodeToString()).isEqualTo("---\nchosen_steps: 8500\n---\n\n")
                val destination = GoogleDriveDestination(id = "destination", accountReferenceId = "account",
                    permissionId = "permission", folderId = "folder", accountLabel = "Synthetic", folderLabel = "Synthetic",
                    capabilities = GoogleDriveFolderCapabilities(true, true), lastValidatedAtEpochMillis = 0)
                GoogleDriveJournalStore(context).create(bundle, destination)
                val store = GoogleDriveJournalStore(context)
                val journal = (store.load(id) as GoogleDriveJournalLoad.Found).journal
                val retained = journal.artifacts.single()
                val fragment = requireNotNull(store.readArtifact(id, retained))
                val baseline = "---\nsleep_total_hours: 99 # keep\n---\nMy journal.\n".encodeToByteArray()
                val merged = generateDriveFinalBytes(retained.writeIntent, baseline, fragment,
                    dailyNotePolicy = retained.dailyNotePolicy)
                assertThat(merged.decodeToString()).contains("chosen_steps: 8500")
                assertThat(merged.decodeToString()).contains("sleep_total_hours: 99 # keep")
                assertThat(merged.decodeToString()).contains("My journal.")
                assertThat(merged.decodeToString()).doesNotContain("\nsteps:")
                assertThat(generateDriveFinalBytes(retained.writeIntent, merged, fragment,
                    dailyNotePolicy = retained.dailyNotePolicy)).isEqualTo(merged)
            }
        } finally { root.deleteRecursively() }
    }

    @Test fun `Morning generation and Night updates preserve scoped annotations through journal reload`() = runTest {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val root = File(context.noBackupFilesDir, "google-drive-operations")
        root.deleteRecursively()
        try {
            for (sections in listOf(false, true)) for (profile in CompatibilitySchemaProfile.entries) {
                val settings = ExportSettings(exportFormats = emptySet(),
                    dailyNoteInjection = DailyNoteInjectionSettings(enabled = true, createIfMissing = !sections, injectMarkdownSections = sections),
                    executionSleepCaptureContext = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS))
                val id = "scoped-$sections-${profile.name}"
                val morning = factory.daily(id, null, "manual", listOf(ExportFixtures.partialDay), settings)
                val destination = GoogleDriveDestination(id = "destination", accountReferenceId = "account",
                    permissionId = "permission", folderId = "folder", accountLabel = "Synthetic", folderLabel = "Synthetic",
                    capabilities = GoogleDriveFolderCapabilities(true, true), lastValidatedAtEpochMillis = 0)
                GoogleDriveJournalStore(context).create(morning, destination)
                val store = GoogleDriveJournalStore(context)
                val journal = (store.load(id) as GoogleDriveJournalLoad.Found).journal
                val artifact = journal.artifacts.single()
                assertThat(artifact.dailyNotePolicy).isEqualTo(morning.artifacts.single().dailyNotePolicy)
                val created = generateDriveFinalBytes(artifact.writeIntent, personal,
                    requireNotNull(store.readArtifact(id, artifact)), dailyNotePolicy = artifact.dailyNotePolicy)
                assertThat(created.decodeToString()).contains("healthmd_daily_injection_v1")
                assertThat(created.decodeToString()).contains("Keep me.")
                val nightSettings = settings.copy(
                    formatCustomization = settings.formatCustomization.copy(compatibilitySchemaProfile = profile),
                    executionSleepCaptureContext = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.NIGHT_BEGINS))
                val night = factory.daily("$id-night", null, "manual", listOf(ExportFixtures.partialDay), nightSettings).artifacts.single()
                org.junit.Assert.assertThrows(Exception::class.java) {
                    generateDriveFinalBytes(night.writeIntent, created, night.bytes)
                }
                org.junit.Assert.assertThrows(Exception::class.java) {
                    generateDriveFinalBytes(night.writeIntent,
                        "---\nschema: healthmd.health_data\nschema_version: 8\n---\n".encodeToByteArray(),
                        night.bytes, dailyNotePolicy = night.dailyNotePolicy)
                }
                val updated = generateDriveFinalBytes(night.writeIntent, created, night.bytes, dailyNotePolicy = night.dailyNotePolicy)
                assertThat(updated.decodeToString()).contains("healthmd_daily_injection_v2")
                assertThat(updated.decodeToString()).contains("Personal introduction.")
                assertThat(updated.decodeToString()).contains("Keep me.")
                assertThat(generateDriveFinalBytes(night.writeIntent, updated, night.bytes, dailyNotePolicy = night.dailyNotePolicy)).isEqualTo(updated)
                val staged = store.replaceFinalBytes(journal, 0, created)
                assertThat(store.readArtifact(id, (store.load(id) as GoogleDriveJournalLoad.Found).journal.artifacts.single())).isEqualTo(created)
                val changedCapture = staged.copy(artifacts = staged.artifacts.map {
                    it.copy(dailyNotePolicy = requireNotNull(it.dailyNotePolicy).copy(patch = "changed capture"))
                })
                File(root, "$id/journal.json").writeText(journalJson.encodeToString(GoogleDriveOperationJournal.serializer(), changedCapture))
                assertThat(store.load(id)).isEqualTo(GoogleDriveJournalLoad.Corrupt)
                val invalid = staged.copy(artifacts = staged.artifacts.map {
                    it.copy(dailyNotePolicy = requireNotNull(it.dailyNotePolicy).copy(recordProfile = "future"))
                })
                File(root, "$id/journal.json").writeText(journalJson.encodeToString(GoogleDriveOperationJournal.serializer(), invalid))
                assertThat(store.load(id)).isEqualTo(GoogleDriveJournalLoad.Corrupt)
                // Pre-policy final stages cannot bypass the profile-aware merger on upgrade.
                File(root, "$id/journal.json").writeText(journalJson.encodeToString(GoogleDriveOperationJournal.serializer(), staged.copy(version = 2)))
                assertThat(store.load(id)).isEqualTo(GoogleDriveJournalLoad.Corrupt)
            }
        } finally { root.deleteRecursively() }
    }
}
