package com.healthmd.data.export

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.FailedDateDetail
import io.mockk.every
import io.mockk.mockk
import java.io.File
import java.nio.file.Files
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Test

class ScheduledAPIExportStoreTest {
    @Test
    fun exactBodiesAndAcknowledgedFrontierSurviveStoreRecreation() = runTest {
        val root = Files.createTempDirectory("scheduled-api-store-test").toFile()
        try {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            val firstStore = FileAPIExportOperationStore(context)
            val operation = operation()

            firstStore.create(operation)
            firstStore.acknowledge(operation.operationId, expectedFrontier = 0)

            val loaded = FileAPIExportOperationStore(context).load(operation.operationId)!!
            assertThat(loaded.acknowledgedBatchCount).isEqualTo(1)
            assertThat(loaded.batches.map { it.ownerDates })
                .containsExactly(listOf(first, second), listOf(third)).inOrder()
            assertThat(loaded.batches[0].bytes).isEqualTo("Café 🫀".encodeToByteArray())
            assertThat(loaded.batches[1].bytes).isEqualTo("second".encodeToByteArray())
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun conflictingCreateAndSkippedFrontierFailClosed() = runTest {
        val root = Files.createTempDirectory("scheduled-api-store-conflict-test").toFile()
        try {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            val store = FileAPIExportOperationStore(context)
            val operation = operation()
            store.create(operation)

            var conflict: Throwable? = null
            try {
                store.create(operation(bytes = "changed".encodeToByteArray()))
            } catch (error: Throwable) {
                conflict = error
            }
            assertThat(conflict).isInstanceOf(IllegalArgumentException::class.java)

            var skipped: Throwable? = null
            try {
                store.acknowledge(operation.operationId, expectedFrontier = 1)
            } catch (error: Throwable) {
                skipped = error
            }
            assertThat(skipped).isInstanceOf(IllegalArgumentException::class.java)
            assertThat(store.load(operation.operationId)!!.acknowledgedBatchCount).isEqualTo(0)
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun corruptedBodyHashNeverReturnsPreparedBytes() = runTest {
        val root = Files.createTempDirectory("scheduled-api-store-corrupt-test").toFile()
        try {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            val store = FileAPIExportOperationStore(context)
            val operation = operation()
            store.create(operation)
            root.walkTopDown().first { it.isFile && it.name.startsWith("body-") }
                .writeBytes("tampered".encodeToByteArray())

            var failure: Throwable? = null
            try {
                store.load(operation.operationId)
            } catch (error: Throwable) {
                failure = error
            }
            assertThat(failure).isInstanceOf(IllegalArgumentException::class.java)
        } finally {
            root.deleteRecursively()
        }
    }

    private fun operation(bytes: ByteArray = "Café 🫀".encodeToByteArray()) =
        DurableAPIExportOperation(
            operationId = "11111111-2222-3333-4444-555555555555",
            destinationFingerprint = "a".repeat(64),
            mode = ExportEngineMode.rust,
            enginePinJson = null,
            settingsSnapshotJson = "snapshot-v1",
            requestedDates = listOf(first, second, third),
            recordDates = setOf(first, third),
            captureFailures = listOf(FailedDateDetail(second, ExportFailureReason.NO_HEALTH_DATA)),
            batches = listOf(
                DurableAPIExportBatch(
                    index = 0,
                    relativePath = "api/request-0000.json",
                    ownerDates = listOf(first, second),
                    bytes = bytes,
                ),
                DurableAPIExportBatch(
                    index = 1,
                    relativePath = "api/request-0001.json",
                    ownerDates = listOf(third),
                    bytes = "second".encodeToByteArray(),
                ),
            ),
        )

    private companion object {
        val first: LocalDate = LocalDate.of(2026, 7, 24)
        val second: LocalDate = first.plusDays(1)
        val third: LocalDate = second.plusDays(1)
    }
}
