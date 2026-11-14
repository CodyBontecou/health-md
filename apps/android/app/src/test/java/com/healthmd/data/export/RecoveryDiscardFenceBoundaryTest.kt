package com.healthmd.data.export

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.sha256Hex
import io.mockk.every
import io.mockk.mockk
import java.io.File
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RecoveryDiscardFenceBoundaryTest {
    @get:Rule val temporaryFolder = TemporaryFolder()

    @Test
    fun duplicateOperationsCannotEraseARevocationBeforeJournalCreate() = runTest {
        assertDuplicateLedgerRejected("operations")
    }

    @Test
    fun escapedDuplicateOperationsCannotEraseARevocationBeforeJournalCreate() = runTest {
        assertDuplicateLedgerRejected("oper\\u0061tions")
    }

    @Test
    fun duplicateAuthorityCannotMakeAmbiguousBindingEligibleForUnlink() = runTest {
        assertDuplicateBindingRejected("apiAuthorityJson")
    }

    @Test
    fun escapedDuplicateAuthorityCannotMakeAmbiguousBindingEligibleForUnlink() = runTest {
        assertDuplicateBindingRejected("api\\u0041uthorityJson")
    }

    @Test
    fun malformedLedgerBytesRejectBeforeAnyNewOperationIsPublished() = runTest {
        val valid = "{\"version\":1,\"operations\":[],\"profileGenerations\":[],\"defaultRequests\":[]}"
        val invalid = listOf(
            valid.replace("\"version\":1", "\"version\":2"),
            valid.replace("\"version\":1", "\"version\":1.0"),
            valid.replace("\"version\":1", "\"version\":true"),
            valid.replace("\"operations\":[]", "\"operations\":null"),
            valid.dropLast(1),
            valid.dropLast(1) + ",\"unknown\":[]}",
            "{\"version\":1}",
        ).map { it.encodeToByteArray() } + listOf(
            " ".repeat(1_048_577).encodeToByteArray(),
            valid.dropLast(1).encodeToByteArray() + byteArrayOf(0x80.toByte()) + "}".encodeToByteArray(),
        )
        for (bytes in invalid) {
            val root = temporaryFolder.newFolder()
            val store = store(root)
            store.create(compatibility("past"))
            val ledger = File(root, "recovery-discard-v1.json")
            ledger.writeBytes(bytes)
            val before = footprint(root)

            val result = runCatching { store.create(compatibility("fresh")) }

            assertThat(result.exceptionOrNull()?.message).isEqualTo("api_recovery_discard_state_invalid")
            assertThat(operationDirectory(root, "fresh").exists()).isFalse()
            assertThat(footprint(root)).isEqualTo(before)
            assertThat(ledger.readBytes()).isEqualTo(bytes)
        }
    }

    @Test
    fun validNoncanonicalLedgerOrderRetainsRevocationAndIsNotRewrittenOnRead() = runTest {
        val root = temporaryFolder.newFolder()
        val store = store(root)
        store.create(compatibility("past"))
        val ledger = File(root, "recovery-discard-v1.json")
        val valid = "{\n \"defaultRequests\":[],\"profileGenerations\": []," +
            "\"operations\":[\"${RecoveryDiscardFence.operationHash("revoked")}\"],\"version\":1\n}"
        ledger.writeText(valid)
        val before = footprint(root)

        assertThat(RecoveryDiscardFence(root).isDiscarded("revoked")).isTrue()
        assertThat(footprint(root)).isEqualTo(before)
        store.create(compatibility("fresh"))
        assertThat(operationDirectory(root, "fresh").isDirectory).isTrue()
        assertThat(ledger.readText()).isEqualTo(valid)
    }

    @Test
    fun invalidUTF8BindingCannotMatchAReplacementDecodedAuthority() = runTest {
        val root = temporaryFolder.newFolder()
        val proof = "synthetic-proof\uFFFD"
        store(root).create(compatibility("owned", proof))
        val metadata = File(operationDirectory(root, "owned"), "journal.json")
        val original = metadata.readBytes()
        val offset = original.indexOf(0xEF.toByte())
        assertThat(offset).isAtLeast(0)
        val invalid = original.copyOfRange(0, offset) + byteArrayOf(0x80.toByte()) +
            original.copyOfRange(offset + 3, original.size)
        metadata.writeBytes(invalid)
        val before = footprint(root)

        val result = runCatching {
            RecoveryDiscardFence(root).discard(listOf("owned"), expectedBindings = mapOf(
                "owned" to RecoveryDiscardFence.Binding(proof, "snapshot"),
            ))
        }

        assertThat(result.exceptionOrNull()?.message).isEqualTo("api_recovery_discard_binding_invalid")
        assertThat(File(root, "recovery-discard-v1.json").exists()).isFalse()
        assertThat(footprint(root)).isEqualTo(before)
        assertThat(metadata.readBytes()).isEqualTo(invalid)
    }

    @Test
    fun overboundedLegacySnapshotBindingRemainsUntouchedRatherThanApproximated() = runTest {
        val root = temporaryFolder.newFolder()
        val snapshot = "x".repeat(65_537)
        store(root).create(compatibility("owned", "proof", snapshot))
        val before = footprint(root)

        val result = runCatching {
            RecoveryDiscardFence(root).discard(listOf("owned"), expectedBindings = mapOf(
                "owned" to RecoveryDiscardFence.Binding("proof", snapshot),
            ))
        }

        assertThat(result.exceptionOrNull()?.message).isEqualTo("api_recovery_discard_binding_invalid")
        assertThat(File(root, "recovery-discard-v1.json").exists()).isFalse()
        assertThat(footprint(root)).isEqualTo(before)
    }

    @Test
    fun maximumSupportedSnapshotBindingKeepsExactOwnedCleanup() = runTest {
        val root = temporaryFolder.newFolder()
        val snapshot = "x".repeat(65_536)
        store(root).create(compatibility("owned", "proof", snapshot))
        val fence = RecoveryDiscardFence(root)

        fence.discard(listOf("owned"), expectedBindings = mapOf(
            "owned" to RecoveryDiscardFence.Binding("proof", snapshot),
        ))

        assertThat(operationDirectory(root, "owned").exists()).isFalse()
        assertThat(fence.isDiscarded("owned")).isTrue()
    }

    private suspend fun assertDuplicateBindingRejected(secondKey: String) {
        val root = temporaryFolder.newFolder()
        val store = store(root)
        store.create(compatibility("owned", "original-proof"))
        val metadata = File(operationDirectory(root, "owned"), "journal.json")
        val duplicate = metadata.readText().dropLast(1) +
            ",\"apiAuthorityJson\":\"different-proof\",\"$secondKey\":\"original-proof\"}"
        metadata.writeText(duplicate)
        val before = footprint(root)

        val result = runCatching {
            RecoveryDiscardFence(root).discard(listOf("owned"), expectedBindings = mapOf(
                "owned" to RecoveryDiscardFence.Binding("original-proof", "snapshot"),
            ))
        }

        // Ambiguous ownership must block the real unlink and ledger write, not just a probe.
        assertThat(metadata.exists()).isTrue()
        assertThat(File(root, "recovery-discard-v1.json").exists()).isFalse()
        assertThat(result.exceptionOrNull()?.message).isEqualTo("api_recovery_discard_binding_invalid")
        assertThat(footprint(root)).isEqualTo(before)
        assertThat(metadata.readText()).isEqualTo(duplicate)
    }

    private suspend fun assertDuplicateLedgerRejected(secondKey: String) {
        val root = temporaryFolder.newFolder()
        val store = store(root)
        store.create(compatibility("past"))
        val fence = RecoveryDiscardFence(root)
        fence.discard(listOf("revoked"))
        assertThat(fence.isDiscarded("revoked")).isTrue()
        val ledger = File(root, "recovery-discard-v1.json")
        val duplicate = ledger.readText().dropLast(1) + ",\"$secondKey\":[]}"
        ledger.writeText(duplicate)
        val before = footprint(root)

        val result = runCatching { store.create(compatibility("revoked")) }

        // This is the real production action: a lost tombstone publishes these body/journal files.
        assertThat(operationDirectory(root, "revoked").exists()).isFalse()
        assertThat(result.exceptionOrNull()?.message).isEqualTo("api_recovery_discard_state_invalid")
        assertThat(footprint(root)).isEqualTo(before)
        assertThat(ledger.readText()).isEqualTo(duplicate)
    }

    private fun store(root: File) = FileAPIExportOperationStore(mockk<Context> {
        every { noBackupFilesDir } returns root
    })

    private fun operationDirectory(root: File, id: String) =
        File(root, "scheduled-api-export-v1/${RecoveryDiscardFence.operationHash(id)}")

    private fun footprint(root: File): Map<String, String> = root.walkTopDown().associate {
        it.relativeTo(root).path to if (it.isFile) sha256Hex(it.readBytes()) else "directory"
    }

    private val day = LocalDate.ofEpochDay(10_000)
    private fun compatibility(id: String, authority: String? = null, snapshot: String = "snapshot") = DurableAPIExportOperation(
        id, "a".repeat(64), ExportEngineMode.legacy, null, snapshot, listOf(day), setOf(day), emptyList(),
        listOf(DurableAPIExportBatch(0, "POST/api-v1.json", listOf(day), "synthetic".encodeToByteArray())),
        apiAuthorityJson = authority,
    )
}
