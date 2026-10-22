package com.healthmd.data.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.rawexport.RawExportResult
import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawSnapshotManifest
import com.healthmd.rawexport.RawSnapshotStatus
import java.nio.file.Files
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.test.runTest
import org.junit.Test

class ScheduledRawAPIExportStoreTest {
    @Test
    fun concurrentStoreInstancesCannotAdmitTheSameCaptureTwice() = runTest {
        val root = Files.createTempDirectory("raw-journal-race").toFile()
        try {
            val first = ScheduledRawAPIExportStore(root)
            val second = ScheduledRawAPIExportStore(root)
            val admitted = first.open(operation(), false)
            val results = listOf(
                async(Dispatchers.Default) { runCatching { first.markCaptureStarted(admitted, 0) } },
                async(Dispatchers.Default) { runCatching { second.markCaptureStarted(admitted, 0) } },
            ).awaitAll()
            assertThat(results.count { it.isSuccess }).isEqualTo(1)
            assertThat(results.count { it.isFailure }).isEqualTo(1)
            val recovered = second.open(operation(admitted.authorityJson), true)
            assertThat(recovered.slots.single().captureStarted).isTrue()
            assertThat(runCatching { second.markCaptureStarted(recovered, 0) }.isFailure).isTrue()
        } finally { root.deleteRecursively() }
    }

    @Test
    fun missingOrCorruptBlobAndCorruptAuthorityFailClosedWithoutReplacingTheJournal() = runTest {
        val root = Files.createTempDirectory("raw-journal-corruption").toFile()
        try {
            val store = ScheduledRawAPIExportStore(root)
            var operation = store.open(operation(), false)
            operation = store.markCaptureStarted(operation, 0)
            val source = java.io.File(root, "synthetic-source").apply { writeBytes("synthetic".encodeToByteArray()) }
            val checksum = com.healthmd.domain.exportengine.sha256Hex(source.readBytes())
            val result = RawExportResult("synthetic", source.path, operation.request.format,
                RawSnapshotManifest(snapshotId = "synthetic", status = RawSnapshotStatus.COMPLETE,
                    completedAt = RawInstant(1, 0), recordCount = 0, issueCount = 0, duplicateCount = 0,
                    identityCollisionCount = 0, typeCounts = emptyList(), typeReports = emptyList(),
                    logicalChecksumSha256 = checksum, manifestChecksumSha256 = checksum), checksum, source.length())
            operation = store.prepare(operation, 0, result)
            val artifact = store.artifact(operation, 0)
            artifact.writeText("tampered")
            assertThat(runCatching { store.artifact(operation, 0) }.isFailure).isTrue()
            artifact.delete()
            assertThat(runCatching { store.artifact(operation, 0) }.isFailure).isTrue()
            val journal = root.walkTopDown().first { it.name == "journal.json" }
            val original = journal.readText()
            journal.writeText(original.replace(operation.authorityJson.replace("\"", "\\\""), "invalid-authority"))
            assertThat(runCatching { store.open(operation(operation.authorityJson), true) }.isFailure).isTrue()
            assertThat(journal.readText()).isNotEqualTo(original)
            assertThat(artifact.exists()).isFalse()
        } finally { root.deleteRecursively() }
    }

    private fun operation(authority: String = APIRecoveryAuthorities.create(
        APIExportRequestConfiguration("https://synthetic.example.test/raw", null, emptyList(), "a".repeat(64)), null,
    )): ScheduledRawAPIExportStore.Operation {
        val day = LocalDate.ofEpochDay(10_000)
        return ScheduledRawAPIExportStore.Operation(operationId = "raw-test", authorityJson = authority,
            settingsSnapshotJson = "frozen-snapshot", ownerEpochDays = listOf(day.toEpochDay()),
            request = RawSnapshotExportRunner.buildRequest(day, day, ZoneId.of("UTC"), ExportSettings()),
            providerIds = listOf("health_connect"))
    }
}
