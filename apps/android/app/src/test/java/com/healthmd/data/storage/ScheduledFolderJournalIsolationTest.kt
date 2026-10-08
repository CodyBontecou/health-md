package com.healthmd.data.storage

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import com.healthmd.domain.exportengine.testPin
import com.healthmd.domain.exportengine.testReadiness
import com.healthmd.domain.exportengine.testRegistry
import java.io.File
import java.nio.file.Files
import java.util.Base64
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.coroutines.test.runTest
import org.junit.Test

class ScheduledFolderJournalIsolationTest {
    @Test
    fun wakeDateJournalSurvivesAnOlderBinaryDeletingItsHistoricalFile() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-journal").toFile()
        try {
            val historical = File(root, "scheduled-folder-export-v1")
            val store = ScheduledFolderExportJournalStore(historical)
            val journal = journal("wake-operation", AndroidExportProfile.android_sleep_v6)
            assertThat(store.save(journal)).isTrue()
            val oldFile = File(historical, "${sha256Hex(journal.operationId.encodeToByteArray())}.json")
            oldFile.delete()
            assertThat(ScheduledFolderExportJournalStore(historical).load(journal.operationId))
                .isEqualTo(ScheduledFolderJournalLoad.Found(journal))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun anExistingOperationCannotChangeItsFrozenProfile() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-journal").toFile()
        try {
            val store = ScheduledFolderExportJournalStore(File(root, "scheduled-folder-export-v1"))
            val wake = journal("frozen-operation", AndroidExportProfile.android_sleep_v6)
            assertThat(store.save(wake)).isTrue()
            assertThat(store.save(journal(wake.operationId, AndroidExportProfile.android_frozen_v4))).isFalse()
            assertThat(store.load(wake.operationId)).isEqualTo(ScheduledFolderJournalLoad.Found(wake))
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun changedDestinationDatesAndSettingsCannotReplaceAnAcceptedJob() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-journal").toFile()
        try {
            val historical = File(root, "scheduled-folder-export-v1")
            val store = ScheduledFolderExportJournalStore(historical)
            val initial = journal("immutable-operation", AndroidExportProfile.android_sleep_v6)
            assertThat(store.save(initial)).isTrue()
            val file = isolatedFile(historical, initial.operationId)
            val original = file.readBytes()
            val alternatives = listOf(
                initial.copy(folderUri = "content://synthetic/documents/tree/other"),
                initial.copy(ownerDates = listOf("2026-11-02")),
                initial.copy(settingsSnapshotSha256 = sha256Hex("different-settings".encodeToByteArray())),
            )
            alternatives.forEach { changed ->
                assertThat(store.save(changed)).isFalse()
                assertThat(file.readBytes()).isEqualTo(original)
            }
            assertThat(store.load(initial.operationId)).isEqualTo(ScheduledFolderJournalLoad.Found(initial))
        } finally { root.deleteRecursively() }
    }

    @Test
    fun readyPlanCannotReturnToCaptureOrReplaceItsBytesButAcknowledgmentsCanProgress() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-journal").toFile()
        try {
            val store = ScheduledFolderExportJournalStore(File(root, "scheduled-folder-export-v1"))
            val initial = readyJournal("ready-operation", "synthetic original")
            assertThat(store.save(initial)).isTrue()
            assertThat(store.save(journal(initial.operationId, AndroidExportProfile.android_sleep_v6))).isFalse()
            assertThat(store.save(readyJournal(initial.operationId, "synthetic replacement"))).isFalse()
            val acknowledged = initial.copy(days = initial.days.map { day ->
                day.copy(artifacts = day.artifacts.map { it.copy(
                    state = ScheduledFolderArtifactState.ACKNOWLEDGED, documentId = "synthetic-document",
                ) })
            })
            assertThat(store.save(initial.withArtifactState(ScheduledFolderArtifactState.BINDING, "synthetic-document"))).isTrue()
            assertThat(store.save(initial.withArtifactState(ScheduledFolderArtifactState.BOUND, "synthetic-document"))).isTrue()
            assertThat(store.save(acknowledged)).isTrue()
            assertThat(store.load(initial.operationId)).isEqualTo(ScheduledFolderJournalLoad.Found(acknowledged))
        } finally { root.deleteRecursively() }
    }

    @Test
    fun unsupportedJournalAndDuplicateIdentityRejectSavesWithoutReplacingEitherFile() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-journal").toFile()
        try {
            val historical = File(root, "scheduled-folder-export-v1")
            val store = ScheduledFolderExportJournalStore(historical)
            val initial = journal("ambiguous-operation", AndroidExportProfile.android_sleep_v6)
            assertThat(store.save(initial)).isTrue()
            val file = isolatedFile(historical, initial.operationId)
            val original = file.readBytes()
            val future = Json.encodeToString(initial.copy(version = 99)).encodeToByteArray()
            file.writeBytes(future)
            assertThat(store.load(initial.operationId)).isEqualTo(ScheduledFolderJournalLoad.Corrupt)
            assertThat(store.save(initial)).isFalse()
            assertThat(file.readBytes()).isEqualTo(future)
            file.writeBytes(original)
            historical.mkdirs()
            val duplicate = File(historical, file.name)
            duplicate.writeBytes(original)
            assertThat(store.load(initial.operationId)).isEqualTo(ScheduledFolderJournalLoad.Corrupt)
            assertThat(store.save(initial)).isFalse()
            assertThat(duplicate.readBytes()).isEqualTo(original)
            assertThat(file.readBytes()).isEqualTo(original)
            store.discard(initial.operationId)
            assertThat(store.load(initial.operationId)).isEqualTo(ScheduledFolderJournalLoad.Missing)
        } finally { root.deleteRecursively() }
    }

    @Test
    fun existingDraftLocationAndUnrelatedHistoricalBytesAreNeverMigrated() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-journal").toFile()
        try {
            val historical = File(root, "scheduled-folder-export-v1")
            val store = ScheduledFolderExportJournalStore(historical)
            val night = journal("night-operation", AndroidExportProfile.android_frozen_v4)
            assertThat(store.save(night)).isTrue()
            val nightFile = File(historical, "${sha256Hex(night.operationId.encodeToByteArray())}.json")
            val nightBytes = nightFile.readBytes()
            val wake = journal("draft-operation", AndroidExportProfile.android_sleep_v6)
            assertThat(store.save(wake)).isTrue()
            assertThat(nightFile.readBytes()).isEqualTo(nightBytes)
            val isolated = isolatedFile(historical, wake.operationId)
            val draft = File(historical, isolated.name)
            draft.writeBytes(isolated.readBytes())
            isolated.delete()
            assertThat(store.load(wake.operationId)).isEqualTo(ScheduledFolderJournalLoad.Found(wake))
            assertThat(store.save(wake)).isTrue()
            assertThat(isolated.exists()).isFalse()
            assertThat(nightFile.readBytes()).isEqualTo(nightBytes)
        } finally { root.deleteRecursively() }
    }

    @Test
    fun failedParentDirectorySyncCannotAdmitAJobAndIsRetried() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-journal").toFile()
        try {
            var admitParent = false
            val synced = mutableListOf<File>()
            val store = ScheduledFolderExportJournalStore(File(root, "scheduled-folder-export-v1"),
                testOnly = Unit, directorySync = { location ->
                    synced += location
                    location != root || admitParent
                })
            val wake = journal("sync-operation", AndroidExportProfile.android_sleep_v6)
            assertThat(store.save(wake)).isFalse()
            assertThat(store.load(wake.operationId)).isEqualTo(ScheduledFolderJournalLoad.Missing)
            admitParent = true
            assertThat(store.save(wake)).isTrue()
            assertThat(synced.count { it == root }).isEqualTo(2)
            assertThat(store.load(wake.operationId)).isEqualTo(ScheduledFolderJournalLoad.Found(wake))
        } finally { root.deleteRecursively() }
    }

    private fun isolatedFile(historical: File, id: String) = File(
        File(historical.parentFile, "${historical.name}.sleep-attribution-v1"),
        "${sha256Hex(id.encodeToByteArray())}.json",
    )

    @Test
    fun acknowledgedArtifactCannotRegressOrChangeItsBoundDocument() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-frontier").toFile()
        try {
            val historical = File(root, "scheduled-folder-export-v1")
            val store = ScheduledFolderExportJournalStore(historical)
            val plan = readyJournal("ack-frontier", "synthetic committed bytes")
            val committed = plan.withArtifactState(ScheduledFolderArtifactState.ACKNOWLEDGED, "final-document")
            assertThat(store.save(committed)).isTrue()
            val file = isolatedFile(historical, committed.operationId)
            val original = file.readBytes()
            val alternatives = listOf(
                committed.withArtifactState(ScheduledFolderArtifactState.BOUND, "final-document"),
                committed.withArtifactState(ScheduledFolderArtifactState.PREPARED, null),
                committed.withArtifactState(ScheduledFolderArtifactState.ACKNOWLEDGED, "replacement-document"),
            )
            alternatives.forEach { changed ->
                assertThat(store.isStructurallyValid(changed)).isTrue()
                assertThat(store.save(changed)).isFalse()
                assertThat(file.readBytes()).isEqualTo(original)
            }
            assertThat(store.load(committed.operationId)).isEqualTo(ScheduledFolderJournalLoad.Found(committed))
        } finally { root.deleteRecursively() }
    }

    @Test
    fun stagedWrittenArtifactCannotRegressOrReplaceItsStagingIdentity() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-frontier").toFile()
        try {
            val historical = File(root, "scheduled-folder-export-v1")
            val store = ScheduledFolderExportJournalStore(historical)
            val plan = readyJournal("staging-frontier", "synthetic staged bytes")
            val staged = plan.withArtifactState(ScheduledFolderArtifactState.STAGING_WRITTEN, "staging-document")
            assertThat(store.save(staged)).isTrue()
            val file = isolatedFile(historical, staged.operationId)
            val original = file.readBytes()
            val alternatives = listOf(
                staged.withArtifactState(ScheduledFolderArtifactState.STAGING_BOUND, "staging-document"),
                staged.withArtifactState(ScheduledFolderArtifactState.STAGING_WRITTEN, "replacement-staging"),
            )
            alternatives.forEach { changed ->
                assertThat(store.isStructurallyValid(changed)).isTrue()
                assertThat(store.save(changed)).isFalse()
                assertThat(file.readBytes()).isEqualTo(original)
            }
        } finally { root.deleteRecursively() }
    }

    @Test
    fun stagedPromotionMayChangeDocumentIdentityOnlyAtItsVerifiedCommitStep() = runTest {
        val root = Files.createTempDirectory("synthetic-sleep-frontier").toFile()
        try {
            val historical = File(root, "scheduled-folder-export-v1")
            val store = ScheduledFolderExportJournalStore(historical)
            val plan = readyJournal("promotion-frontier", "synthetic staged bytes")
            assertThat(store.save(plan)).isTrue()
            val binding = plan.withArtifactState(ScheduledFolderArtifactState.BINDING, null)
            assertThat(store.save(binding)).isTrue()
            assertThat(store.save(binding.withArtifactState(ScheduledFolderArtifactState.BOUND, "unobserved-final"))).isFalse()
            val staging = plan.withArtifactState(ScheduledFolderArtifactState.STAGING_BOUND, "staging-document")
            assertThat(store.save(staging)).isTrue()
            assertThat(store.save(staging.withArtifactState(ScheduledFolderArtifactState.ACKNOWLEDGED, "staging-document"))).isFalse()
            val written = plan.withArtifactState(ScheduledFolderArtifactState.STAGING_WRITTEN, "staging-document")
            assertThat(store.save(written)).isTrue()
            val promoted = plan.withArtifactState(ScheduledFolderArtifactState.BOUND, "renamed-final-document")
            assertThat(store.save(promoted)).isTrue()
            val acknowledged = promoted.withArtifactState(ScheduledFolderArtifactState.ACKNOWLEDGED, "renamed-final-document")
            assertThat(store.save(acknowledged)).isTrue()
            val file = isolatedFile(historical, plan.operationId)
            val bytes = file.readBytes()
            assertThat(store.save(acknowledged)).isTrue()
            assertThat(file.readBytes()).isEqualTo(bytes)
            assertThat(store.load(plan.operationId)).isEqualTo(ScheduledFolderJournalLoad.Found(acknowledged))
        } finally { root.deleteRecursively() }
    }

    private fun ScheduledFolderExportJournal.withArtifactState(
        state: ScheduledFolderArtifactState,
        documentId: String?,
    ) = copy(days = days.map { day ->
        day.copy(artifacts = day.artifacts.map { it.copy(state = state, documentId = documentId) })
    })

    private fun readyJournal(id: String, content: String): ScheduledFolderExportJournal {
        val bytes = content.encodeToByteArray()
        val unsigned = journal(id, AndroidExportProfile.android_sleep_v6).copy(
            phase = ScheduledFolderJournalPhase.READY,
            days = listOf(ScheduledFolderJournalDay("2026-11-01", listOf(ScheduledFolderJournalArtifact(
                artifactId = "synthetic-artifact",
                relativePath = "Health/2026-11-01.json",
                stagingRelativePath = "Health/.2026-11-01.json.pending",
                mediaType = "application/json",
                byteCount = bytes.size, sha256 = sha256Hex(bytes),
                contentBase64 = Base64.getEncoder().encodeToString(bytes),
            )))),
        )
        return unsigned.copy(planSha256 = scheduledFolderImmutablePlanSha256(unsigned))
    }

    private fun journal(id: String, profile: AndroidExportProfile): ScheduledFolderExportJournal {
        val pin = if (profile == AndroidExportProfile.android_sleep_v6) ExportEnginePin.create(
            engine = ExportEngineMode.rust,
            profile = profile,
            ianaTimeZone = "America/Los_Angeles",
            readiness = testReadiness(),
            registry = testRegistry(profile).copy(
                registryVersion = 2u,
                registrySha256 = "709df0ae9f583e82627bc5439c4385905a5d85000e4322a0384cfe96b35a8f78",
            ),
        ) else testPin(ExportEngineMode.rust, profile)
        return ScheduledFolderExportJournal(
            operationId = id,
            folderUri = "content://synthetic/documents/tree/test",
            settingsSnapshotSha256 = sha256Hex("synthetic-settings".encodeToByteArray()),
            enginePinJson = ExportEnginePinCodec.encodeCanonical(pin),
            ownerDates = listOf("2026-11-01"),
            phase = ScheduledFolderJournalPhase.CAPTURING,
        )
    }
}
