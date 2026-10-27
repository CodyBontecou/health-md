package com.healthmd.data.drive

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.MarkdownMerger
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.ExportArtifactPlan
import com.healthmd.domain.exportengine.ExportArtifactPlanItem
import com.healthmd.domain.exportengine.ExportArtifactWriteMode
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.exportengine.artifactIdHex
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.WriteMode
import com.healthmd.export.ExportFixtures
import java.nio.file.Files
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Test

class GeneratedExportBundleFactoryTest {
    private val markdown = MarkdownExporter()
    private val factory = GeneratedExportBundleFactory(
        markdownExporter = markdown,
        jsonExporter = JsonExporter(),
        csvExporter = CsvExporter(),
        obsidianBasesExporter = ObsidianBasesExporter(),
    )

    @Test
    fun `overwrite bundle preserves authoritative renderer bytes and profile identity`() = runTest {
        val settings = ExportSettings(
            exportFormats = setOf(ExportFormat.MARKDOWN),
            writeMode = WriteMode.OVERWRITE,
            exportTarget = ExportTarget.GOOGLE_DRIVE,
        )

        val bundle = factory.daily(
            operationId = "operation-1",
            profileId = "profile-1",
            source = "scheduled",
            data = listOf(ExportFixtures.partialDay),
            settings = settings,
        )

        val artifact = bundle.artifacts.single()
        val expected = markdown.export(
            ExportFixtures.partialDay,
            settings.includeMetadata,
            settings.groupByCategory,
            settings.formatCustomization,
            settings.includeGranularData,
        ).encodeToByteArray()
        assertThat(bundle.profileId).isEqualTo("profile-1")
        assertThat(artifact.writeIntent).isEqualTo(GeneratedArtifactWriteIntent.OVERWRITE)
        assertThat(artifact.bytes).isEqualTo(expected)
        assertThat(generateDriveFinalBytes(artifact.writeIntent, "ignored".encodeToByteArray(), artifact.bytes))
            .isEqualTo(expected)
    }

    @Test
    fun `all write intents preserve existing writer semantics including missing append`() {
        val baseline = "# Existing\n\nUser content".encodeToByteArray()
        val fragment = "# New\n\n## Activity\n\nSteps: 10".encodeToByteArray()

        assertThat(generateDriveFinalBytes(GeneratedArtifactWriteIntent.OVERWRITE, baseline, fragment))
            .isEqualTo(fragment)
        assertThat(generateDriveFinalBytes(GeneratedArtifactWriteIntent.APPEND, baseline, fragment))
            .isEqualTo("# Existing\n\nUser content\n# New\n\n## Activity\n\nSteps: 10".encodeToByteArray())
        assertThat(
            generateDriveFinalBytes(
                GeneratedArtifactWriteIntent.APPEND,
                byteArrayOf(),
                fragment,
                baselineExists = false,
            ),
        ).isEqualTo(fragment)
        assertThat(
            generateDriveFinalBytes(
                GeneratedArtifactWriteIntent.APPEND,
                byteArrayOf(),
                fragment,
                baselineExists = true,
            ),
        ).isEqualTo("\n".encodeToByteArray() + fragment)
        assertThat(generateDriveFinalBytes(GeneratedArtifactWriteIntent.MARKDOWN_UPDATE, baseline, fragment))
            .isEqualTo(
                MarkdownMerger().merge(baseline.decodeToString(), fragment.decodeToString()).encodeToByteArray(),
            )
        assertThat(generateDriveFinalBytes(GeneratedArtifactWriteIntent.DAILY_NOTE_MERGE, baseline, fragment))
            .isEqualTo(
                MarkdownMerger().merge(baseline.decodeToString(), fragment.decodeToString()).encodeToByteArray(),
            )
    }

    @Test
    fun `daily note artifact retains preamble prefix and merges fragment exactly once`() = runTest {
        val settings = ExportSettings(
            exportFormats = emptySet(),
            dailyNoteInjection = DailyNoteInjectionSettings(
                enabled = true,
                createIfMissing = true,
                injectMarkdownSections = true,
            ),
            exportTarget = ExportTarget.GOOGLE_DRIVE,
        )

        val artifact = factory.daily(
            operationId = "operation-daily-note",
            profileId = null,
            source = "manual",
            data = listOf(ExportFixtures.partialDay),
            settings = settings,
        ).artifacts.single()

        assertThat(artifact.writeIntent).isEqualTo(GeneratedArtifactWriteIntent.DAILY_NOTE_MERGE)
        val prefix = requireNotNull(artifact.missingPrefix)
        assertThat(prefix.decodeToString()).isEqualTo("# 2026-03-15\n")
        assertThat(generateDriveFinalBytes(artifact.writeIntent, prefix, artifact.bytes))
            .isEqualTo(
                MarkdownMerger().merge(prefix.decodeToString(), artifact.bytes.decodeToString()).encodeToByteArray(),
            )
    }

    @Test
    fun `raw snapshot includes exact checksum sidecar`() {
        val bytes = "{\"schema\":\"healthmd.raw-snapshot\"}\n".encodeToByteArray()
        val file = Files.createTempFile("healthmd-drive-raw", ".ndjson").toFile()
        try {
            file.writeBytes(bytes)
            val checksum = com.healthmd.domain.exportengine.sha256Hex(bytes)
            val bundle = factory.rawSnapshot(
                operationId = "raw-operation",
                profileId = "profile-1",
                startDate = LocalDate.parse("2026-03-15"),
                endDate = LocalDate.parse("2026-03-15"),
                settingsSnapshotJson = "{}",
                relativePath = "raw/snapshot.ndjson",
                mediaType = "application/x-ndjson",
                exactFile = file,
                artifactChecksumSha256 = checksum,
            )

            assertThat(bundle.artifacts.map { it.relativePath })
                .containsExactly("raw/snapshot.ndjson", "raw/snapshot.ndjson.sha256").inOrder()
            assertThat(bundle.artifacts[0].bytes).isEqualTo(bytes)
            assertThat(bundle.artifacts[1].bytes.decodeToString())
                .isEqualTo("$checksum  snapshot.ndjson\n")
        } finally {
            file.delete()
        }
    }

    @Test
    fun `planned aggregate bytes and renderer pin come from planner authority`() = runTest {
        val plannedBytes = "planner-authoritative-bytes".encodeToByteArray()
        val requestId = "request-drive-test"
        val sessionId = "session-drive-test"
        val path = "Health/2026-03-15.md"
        val mediaType = "text/markdown; charset=utf-8"
        val item = ExportArtifactPlanItem(
            artifactId = artifactIdHex(
                requestId = requestId,
                sessionId = sessionId,
                profile = AndroidExportProfile.android_frozen_v4,
                relativePath = path,
                mediaType = mediaType,
                writeMode = ExportArtifactWriteMode.overwrite,
                contentSha256 = com.healthmd.domain.exportengine.sha256Hex(plannedBytes),
            ),
            relativePath = path,
            mediaType = mediaType,
            writeMode = ExportArtifactWriteMode.overwrite,
            content = plannedBytes,
        )
        val planner = LocalDailyAggregateExportPlanner { _, authoritySettings ->
            assertThat(authoritySettings.exportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)
            LocalDailyAggregatePlanningResult.Planned(
                mode = ExportEngineMode.shadow,
                plan = ExportArtifactPlan(
                    schema = ExportArtifactPlan.SCHEMA,
                    artifactPlanVersion = ExportArtifactPlan.VERSION,
                    requestId = requestId,
                    sessionId = sessionId,
                    profile = AndroidExportProfile.android_frozen_v4,
                    items = listOf(item),
                ),
                formats = listOf(ExportFormat.MARKDOWN),
            )
        }
        val plannedFactory = GeneratedExportBundleFactory(
            markdownExporter = markdown,
            jsonExporter = JsonExporter(),
            csvExporter = CsvExporter(),
            obsidianBasesExporter = ObsidianBasesExporter(),
            dailyAggregatePlanner = planner,
        )

        val bundle = plannedFactory.daily(
            operationId = "operation-planned",
            profileId = null,
            source = "manual",
            data = listOf(ExportFixtures.partialDay),
            settings = ExportSettings(
                exportFormats = setOf(ExportFormat.MARKDOWN),
                writeMode = WriteMode.OVERWRITE,
                exportTarget = ExportTarget.GOOGLE_DRIVE,
            ),
        )

        assertThat(bundle.artifacts.single().bytes).isEqualTo(plannedBytes)
        assertThat(bundle.rendererPin).isEqualTo("android-frozen-v4:shadow")
    }
}
