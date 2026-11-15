package com.healthmd.data.export

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.sha256Hex
import com.healthmd.domain.model.ExportSettings
import com.healthmd.rawexport.RawExportResult
import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawPromotionExpectation
import com.healthmd.rawexport.RawSnapshotManifest
import com.healthmd.rawexport.RawSnapshotStatus
import io.mockk.every
import io.mockk.mockk
import java.io.File
import java.nio.file.Files
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RecoveryDiscardFenceTest {
    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test
    fun discardedMissingJournalCannotBeCreatedByAnotherStoreInstanceAfterRestart() = runTest {
        val root = temporaryFolder.newFolder()
        val context = context(root)
        val staleStore = FileAPIExportOperationStore(context)
        val owned = compatibility("owned")
        assertThat(staleStore.load(owned.operationId)).isNull()
        RecoveryDiscardFence(root).discard(listOf(owned.operationId))
        assertThat(runCatching { staleStore.create(owned) }.isFailure).isTrue()
        assertThat(runCatching { FileAPIExportOperationStore(context).create(owned) }.isFailure).isTrue()
        assertThat(root.walkTopDown().filter { it.name == "journal.json" || it.name.startsWith("body-") }.toList()).isEmpty()
    }

    @Test
    fun signedNanoTimeTemporariesAreCleanedOnlyForTheExactOwnedHashAndNativeLongSpelling() {
        val root = temporaryFolder.newFolder()
        val api = File(root, "scheduled-api-export-v1").apply { mkdir() }
        val hash = RecoveryDiscardFence.operationHash("owned")
        val other = RecoveryDiscardFence.operationHash("unrelated")
        val owned = listOf(".$hash.-1.tmp", ".$hash.${Long.MIN_VALUE}.tmp", ".$hash.0.tmp", ".$hash.${Long.MAX_VALUE}.tmp")
        val preserved = listOf(".$other.-1.tmp", ".$hash.-01.tmp", ".$hash.-0.tmp", ".$hash.9223372036854775808.tmp",
            ".$hash.-9223372036854775809.tmp", ".$hash.+1.tmp", ".$hash.-1.tmp.unrelated")
        (owned + preserved).forEach { File(api, it).apply { mkdir(); resolve("synthetic").writeText("synthetic") } }

        RecoveryDiscardFence(root).discard(listOf("owned"))

        assertThat(api.list()!!.toList()).containsExactlyElementsIn(preserved)
        assertThat(preserved.all { File(api, it).resolve("synthetic").readText() == "synthetic" }).isTrue()
    }

    @Test
    fun tombstoneReplaysCrashLeftJournalAndStagingCleanupWithoutTouchingPastOrExternalFiles() {
        val root = temporaryFolder.newFolder()
        val fence = RecoveryDiscardFence(root)
        fence.discard(listOf("owned"))
        val hash = RecoveryDiscardFence.operationHash("owned")
        val other = RecoveryDiscardFence.operationHash("past")
        val preserved = mutableListOf<File>()
        for (name in listOf("scheduled-api-export-v1", "scheduled-raw-api-v1")) {
            val directory = File(root, name).apply { mkdir() }
            File(directory, hash).apply { mkdir(); resolve("capture-0.partial").writeText("synthetic") }
            preserved += File(directory, other).apply { mkdir() }.resolve("journal.json").apply { writeText("synthetic past") }
        }
        val external = File(root, "synthetic-external-output").apply { writeText("acknowledged synthetic") }

        RecoveryDiscardFence(root).reconcile()

        assertThat(root.walkTopDown().filter { it.name == "capture-0.partial" }.toList()).isEmpty()
        assertThat(preserved.map { it.readText() }).containsExactly("synthetic past", "synthetic past")
        assertThat(external.readText()).isEqualTo("acknowledged synthetic")
    }

    @Test
    fun boundedIdsAndSymlinkedOwnedChildrenCannotEscapeThePrivateRoot() {
        val root = temporaryFolder.newFolder()
        val outside = temporaryFolder.newFolder()
        val external = File(outside, "synthetic").apply { writeText("preserved") }
        val fence = RecoveryDiscardFence(root)
        for (invalid in listOf("../escape", "a/b", "a\\b", "x".repeat(129), "")) {
            assertThat(runCatching { fence.discard(listOf(invalid)) }.isFailure).isTrue()
        }
        val owned = File(root, "scheduled-api-export-v1/${RecoveryDiscardFence.operationHash("owned")}").apply { mkdirs() }
        Files.createSymbolicLink(owned.resolve("synthetic-link").toPath(), outside.toPath())
        fence.discard(listOf("owned"))
        assertThat(external.readText()).isEqualTo("preserved")
        assertThat(owned.exists()).isFalse()
        Files.createSymbolicLink(File(root, "scheduled-raw-api-v1").toPath(), outside.toPath())
        assertThat(runCatching { fence.discard(listOf("another")) }.isFailure).isTrue()
        assertThat(external.readText()).isEqualTo("preserved")
    }

    @Test
    fun boundedTombstonesNeverEvictOldRevocationsToAdmitMoreDiscardedWork() {
        val root = temporaryFolder.newFolder()
        val fence = RecoveryDiscardFence(root)
        fence.discard((0 until RecoveryDiscardFence.MAX_TOMBSTONES).map { "synthetic-$it" })
        val before = File(root, "recovery-discard-v1.json").readBytes()
        assertThat(runCatching { fence.discard(listOf("overflow")) }.isFailure).isTrue()
        assertThat(File(root, "recovery-discard-v1.json").readBytes()).isEqualTo(before)
        assertThat(RecoveryDiscardFence(root).isDiscarded("synthetic-0")).isTrue()
    }

    @Test
    fun corruptOrIncompleteFenceBlocksNewMutationAndPreservesExistingBytes() = runTest {
        for (corrupt in listOf("{corrupt", "{}", "{\"version\":2,\"operations\":[],\"profileGenerations\":[]}")) {
            val root = temporaryFolder.newFolder()
            val store = FileAPIExportOperationStore(context(root))
            store.create(compatibility("past"))
            File(root, "recovery-discard-v1.json").writeText(corrupt)
            assertThat(runCatching { store.create(compatibility("new")) }.isFailure).isTrue()
            assertThat(runCatching { RecoveryDiscardFence(root).discard(listOf("past")) }.isFailure).isTrue()
            assertThat(root.walkTopDown().first { it.name.startsWith("body-") }.readText()).isEqualTo("synthetic")
        }
    }

    @Test
    fun rawPreparedAndAcknowledgedFrontiersCannotResurrectWhileUnrelatedCompletedArtifactsSurvive() = runTest {
        val root = temporaryFolder.newFolder()
        val rawRoot = File(root, "scheduled-raw-api-v1")
        val store = ScheduledRawAPIExportStore(rawRoot, RecoveryDiscardFence(root))
        val source = File(root, "synthetic-source").apply { writeText("synthetic") }
        var pending = store.open(raw("pending"), false)
        pending = store.markCaptureStarted(pending, 0)
        pending = store.prepare(pending, 0, result(source, pending))
        var completed = store.open(raw("completed"), false)
        completed = store.markCaptureStarted(completed, 0)
        completed = store.prepare(completed, 0, result(source, completed))
        completed = store.acknowledge(completed, 0)

        RecoveryDiscardFence(root).discard(listOf(pending.operationId))

        val restarted = ScheduledRawAPIExportStore(rawRoot, RecoveryDiscardFence(root))
        assertThat(runCatching { restarted.open(pending.copy(slots = listOf(ScheduledRawAPIExportStore.Slot())), false) }.isFailure).isTrue()
        assertThat(runCatching { store.acknowledge(pending, 0) }.isFailure).isTrue()
        assertThat(runCatching { store.prepare(pending, 0, result(source, pending)) }.isFailure).isTrue()
        assertThat(restarted.artifact(completed, 0).readText()).isEqualTo("synthetic")
        assertThat(source.readText()).isEqualTo("synthetic")
    }

    @Test
    fun lateRawStagingWriteAndPromoteCannotRecreateAnUnlinkedOperation() = runTest {
        val root = temporaryFolder.newFolder()
        val store = ScheduledRawAPIExportStore(File(root, "scheduled-raw-api-v1"), RecoveryDiscardFence(root))
        var operation = store.open(raw("owned"), false)
        operation = store.markCaptureStarted(operation, 0)
        val storage = store.captureStorage(operation, 0)
        val sink = storage.openPartial("a".repeat(32), operation.request.format)
        sink.output.write("synthetic".encodeToByteArray())
        RecoveryDiscardFence(root).discard(listOf(operation.operationId))
        try {
            assertThat(runCatching { sink.output.write(1) }.isFailure).isTrue()
            assertThat(runCatching { sink.promote(RawPromotionExpectation(9L, sha256Hex("synthetic".encodeToByteArray()))) }.isFailure).isTrue()
            assertThat(runCatching { storage.openPartial("b".repeat(32), operation.request.format) }.isFailure).isTrue()
        } finally { sink.abort(); sink.close() }
        assertThat(root.walkTopDown().filter { it.name.endsWith(".bin") || it.name.endsWith(".partial") || it.name == "journal.json" }.toList()).isEmpty()
    }

    private fun context(root: File) = mockk<Context> { every { noBackupFilesDir } returns root }
    private val day = LocalDate.ofEpochDay(10_000)
    private fun compatibility(id: String) = DurableAPIExportOperation(id, "a".repeat(64), ExportEngineMode.legacy,
        null, "snapshot", listOf(day), setOf(day), emptyList(),
        listOf(DurableAPIExportBatch(0, "POST/api-v1.json", listOf(day), "synthetic".encodeToByteArray())))
    private fun raw(id: String) = ScheduledRawAPIExportStore.Operation(operationId = id,
        authorityJson = APIRecoveryAuthorities.create(APIExportRequestConfiguration("https://synthetic.example.test", null, emptyList(), "a".repeat(64)), null),
        settingsSnapshotJson = "snapshot", ownerEpochDays = listOf(day.toEpochDay()),
        request = RawSnapshotExportRunner.buildRequest(day, day, ZoneId.of("UTC"), ExportSettings()), providerIds = listOf("health_connect"))
    private fun result(source: File, operation: ScheduledRawAPIExportStore.Operation): RawExportResult {
        val checksum = sha256Hex(source.readBytes())
        return RawExportResult("synthetic", source.path, operation.request.format,
            RawSnapshotManifest(snapshotId = "synthetic", status = RawSnapshotStatus.COMPLETE, completedAt = RawInstant(1, 0),
                recordCount = 0, issueCount = 0, duplicateCount = 0, identityCollisionCount = 0, typeCounts = emptyList(), typeReports = emptyList(),
                logicalChecksumSha256 = checksum, manifestChecksumSha256 = checksum), checksum, source.length())
    }
}
