package com.healthmd.direct

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.ExportAccepted
import com.healthmd.direct.protocol.PeerBinding
import com.healthmd.direct.protocol.PreparedTransfer
import com.healthmd.direct.protocol.ProductId
import com.healthmd.direct.protocol.ResolvedRange
import com.healthmd.direct.protocol.TransferSession
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.testing.syntheticExportEnginePin
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.TimeoutException
import io.mockk.every
import io.mockk.mockk
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertThrows
import org.junit.Test

class DirectJobJournalMigrationTest {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = true
        ignoreUnknownKeys = false
    }

    @Test
    fun v1WithoutVersionOrPinDecodesAsLegacy() {
        val current = DirectJobJournal(
            requestFingerprint = "request-fingerprint",
            expiresAt = "2027-01-16T00:00:00Z",
            transfer = transfer(),
        )
        val currentObject = json.parseToJsonElement(json.encodeToString(current)).jsonObject
        val oldJson = JsonObject(currentObject - "version" - "enginePin" - "protocolPin").toString()

        val decoded = json.decodeFromString<DirectJobJournal>(oldJson)

        assertThat(decoded.version).isEqualTo(DirectJobJournal.LEGACY_VERSION)
        assertThat(decoded.enginePin).isNull()
        assertThat(decoded.protocolPin).isNull()
        assertThat(decoded.transfer).isEqualTo(current.transfer)

        val unexpectedPinWithoutVersion = json.parseToJsonElement(
            json.encodeToString(current.copy(enginePin = syntheticExportEnginePin())),
        ).jsonObject.let { JsonObject(it - "version") }.toString()
        assertThat(
            json.decodeFromString<DirectJobJournal>(unexpectedPinWithoutVersion).enginePin,
        ).isNull()
    }

    @Test
    fun v3RoundTripRetainsExactPinsAndDoesNotAlterTransferBytes() {
        val pin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val protocolPin = protocolPin(AndroidDirectProtocolEngineMode.rust)
        val journal = DirectJobJournal(
            requestFingerprint = "request-fingerprint",
            expiresAt = "2027-01-16T00:00:00Z",
            transfer = transfer(),
            enginePin = pin,
            protocolPin = protocolPin,
        )

        val encoded = json.encodeToString(journal)
        val decoded = json.decodeFromString<DirectJobJournal>(encoded)

        assertThat(decoded.version).isEqualTo(DirectJobJournal.CURRENT_VERSION)
        assertThat(decoded.enginePin).isEqualTo(pin)
        assertThat(decoded.protocolPin).isEqualTo(protocolPin)
        assertThat(decoded.transfer).isEqualTo(journal.transfer)

        val v2 = json.parseToJsonElement(encoded).jsonObject.toMutableMap().apply {
            put("version", kotlinx.serialization.json.JsonPrimitive(DirectJobJournal.EXPORT_PIN_VERSION))
        }.let(::JsonObject).toString()
        assertThat(json.decodeFromString<DirectJobJournal>(v2).protocolPin).isNull()
    }

    @Test
    fun unknownJournalPinAndPinMutationAreRejected() {
        val pendingPin = syntheticExportEnginePin(mode = ExportEngineMode.shadow)
        val journal = DirectJobJournal(
            requestFingerprint = "request-fingerprint",
            expiresAt = "2027-01-16T00:00:00Z",
            transfer = transfer(),
            enginePin = pendingPin,
        )
        val unknown = json.encodeToString(journal)
            .replace("\"engine\":\"shadow\"", "\"engine\":\"future\"")

        assertThrows(SerializationException::class.java) {
            json.decodeFromString<DirectJobJournal>(unknown)
        }
        assertThrows(IllegalArgumentException::class.java) {
            requireDirectPinContinuity(
                pendingPin = pendingPin,
                journalPin = syntheticExportEnginePin(mode = ExportEngineMode.rust),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            requireDirectProtocolPinContinuity(
                pendingPin = protocolPin(AndroidDirectProtocolEngineMode.shadow),
                journalPin = protocolPin(AndroidDirectProtocolEngineMode.rust),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            DirectJobJournal(
                requestFingerprint = "request-fingerprint",
                expiresAt = "2027-01-16T00:00:00Z",
                transfer = transfer(timeZoneId = "UTC"),
                enginePin = pendingPin,
            )
        }
    }

    @Test
    fun acceptedAuthorityCannotBeReplacedAfterPendingMarkerIsRemoved() = withStore { store, root ->
        val initial = durableJournal()
        store.save(initial)
        val file = File(root, "direct-cli/jobs/${initial.transfer.accepted.jobId}/job.json")
        val original = file.readBytes()
        val alternatives = listOf(
            initial.copy(requestFingerprint = "different-synthetic-request"),
            initial.copy(expiresAt = Instant.now().plusSeconds(7200).toString()),
            initial.copy(version = DirectJobJournal.LEGACY_VERSION),
            initial.copy(enginePin = syntheticExportEnginePin(mode = ExportEngineMode.rust)),
            initial.copy(protocolPin = protocolPin(AndroidDirectProtocolEngineMode.rust)),
            initial.copy(transfer = initial.transfer.copy(session = initial.transfer.session.copy(
                sessionId = "50000000-0000-4000-8000-000000000005",
            ))),
            initial.copy(transfer = initial.transfer.copy(artifactPaths = mapOf("synthetic-artifact" to "/synthetic/changed"))),
        )
        alternatives.forEach { changed ->
            assertThrows(IllegalArgumentException::class.java) { store.save(changed) }
            assertThat(file.readBytes()).isEqualTo(original)
        }
        assertThat(store.load(initial.transfer.accepted.jobId, initial.requestFingerprint)).isEqualTo(initial)
    }

    @Test
    fun accountingAndCompletionCannotBeRolledBackByAStaleJournal() = withStore { store, root ->
        val initial = durableJournal()
        val jobId = initial.transfer.accepted.jobId
        store.save(initial)
        store.markAccounted(jobId)
        store.markCompleted(jobId)
        val file = File(root, "direct-cli/jobs/$jobId/job.json")
        val completedBytes = file.readBytes()
        assertThrows(IllegalArgumentException::class.java) { store.save(initial) }
        assertThrows(IllegalArgumentException::class.java) { store.save(initial.copy(accounted = true)) }
        assertThat(file.readBytes()).isEqualTo(completedBytes)
        val accepted = initial.copy(accounted = true, completed = true)
        store.save(accepted)
        assertThat(file.readBytes()).isEqualTo(completedBytes)
        assertThat(store.load(jobId, initial.requestFingerprint)).isEqualTo(accepted)
    }

    @Test
    fun acceptedJournalCannotStartAnotherPreparationOrReplaceCorruptAuthority() = withStore { store, root ->
        val initial = durableJournal()
        val jobId = initial.transfer.accepted.jobId
        store.save(initial)
        assertThrows(IllegalStateException::class.java) {
            store.beginPreparation(jobId, initial.requestFingerprint, initial.expiresAt)
        }
        val directory = File(root, "direct-cli/jobs/$jobId")
        assertThat(File(directory, "pending.json").exists()).isFalse()
        val file = File(directory, "job.json")
        val corruptBytes = "synthetic corrupt authority".encodeToByteArray()
        file.writeBytes(corruptBytes)
        assertThrows(IllegalStateException::class.java) { store.save(initial) }
        assertThat(file.readBytes()).isEqualTo(corruptBytes)
    }

    @Test
    fun competingStoresAdmitOnlyOneFrozenAuthority() = withStore { firstStore, root ->
        val context = mockk<Context> { every { noBackupFilesDir } returns root }
        val secondStore = DirectCliJobStore(DirectCliTrustStore(context))
        val initial = durableJournal()
        val alternative = initial.copy(requestFingerprint = "competing-synthetic-request")
        val start = CountDownLatch(1)
        val workers = Executors.newFixedThreadPool(2)
        try {
            val saves = listOf(firstStore to initial, secondStore to alternative).map { (store, journal) ->
                workers.submit<Boolean> {
                    check(start.await(10, TimeUnit.SECONDS))
                    try { store.save(journal); true } catch (_: IllegalArgumentException) { false }
                }
            }
            start.countDown()
            val results = saves.map { it.get(10, TimeUnit.SECONDS) }
            assertThat(results.count { it }).isEqualTo(1)
            val winner = if (results.first()) initial else alternative
            assertThat(firstStore.load(winner.transfer.accepted.jobId, winner.requestFingerprint))
                .isEqualTo(winner)
        } finally {
            start.countDown()
            workers.shutdownNow()
            workers.awaitTermination(10, TimeUnit.SECONDS)
        }
    }

    @Test
    fun separateJvmLockBlocksPublicationAndPurgeRetainsTheCoordinationInode() = withStore { store, root ->
        val lockFile = File(root, "direct-cli/.jobs.journal.lock")
        val source = File(root, "DirectJournalLockHolder.java")
        source.writeText("""
            import java.nio.channels.FileChannel;
            import java.nio.file.Path;
            import java.nio.file.StandardOpenOption;
            class DirectJournalLockHolder {
                public static void main(String[] args) throws Exception {
                    try (var channel = FileChannel.open(Path.of(args[0]),
                            StandardOpenOption.CREATE, StandardOpenOption.WRITE);
                         var lock = channel.lock()) {
                        System.out.println("locked");
                        System.out.flush();
                        System.in.read();
                    }
                }
            }
        """.trimIndent())
        val javaExecutable = File(System.getProperty("java.home"), "bin/java").absolutePath
        val process = ProcessBuilder(javaExecutable, source.absolutePath, lockFile.absolutePath)
            .redirectErrorStream(true).start()
        val workers = Executors.newFixedThreadPool(2)
        try {
            val ready = workers.submit<String> { process.inputStream.bufferedReader().readLine() }
            assertThat(ready.get(15, TimeUnit.SECONDS)).isEqualTo("locked")
            val initial = durableJournal()
            val started = CountDownLatch(1)
            val save = workers.submit { started.countDown(); store.save(initial) }
            check(started.await(10, TimeUnit.SECONDS))
            assertThrows(TimeoutException::class.java) { save.get(250, TimeUnit.MILLISECONDS) }
            assertThat(File(root, "direct-cli/jobs/${initial.transfer.accepted.jobId}/job.json").exists()).isFalse()
            process.outputStream.write(1)
            process.outputStream.flush()
            check(process.waitFor(10, TimeUnit.SECONDS))
            assertThat(process.exitValue()).isEqualTo(0)
            save.get(10, TimeUnit.SECONDS)
            assertThat(store.load(initial.transfer.accepted.jobId, initial.requestFingerprint)).isEqualTo(initial)
            val inode = Files.readAttributes(lockFile.toPath(), java.nio.file.attribute.BasicFileAttributes::class.java).fileKey()
            assertThat(inode).isNotNull()
            store.purgeAll()
            assertThat(Files.readAttributes(lockFile.toPath(), java.nio.file.attribute.BasicFileAttributes::class.java).fileKey())
                .isEqualTo(inode)
            store.save(initial)
            assertThat(store.load(initial.transfer.accepted.jobId, initial.requestFingerprint)).isEqualTo(initial)
        } finally {
            process.destroyForcibly()
            workers.shutdownNow()
            workers.awaitTermination(10, TimeUnit.SECONDS)
        }
    }

    @Test
    fun cancelledOrPurgedCaptureCannotPublishItsPreparedJournal() = withStore { store, root ->
        val initial = durableJournal()
        val jobId = initial.transfer.accepted.jobId
        for (purge in listOf(false, true)) {
            val lease = store.beginPreparation(jobId, initial.requestFingerprint, initial.expiresAt)
            if (purge) store.purgeAll() else store.cancel(jobId)
            assertThrows(IllegalStateException::class.java) { store.savePrepared(initial, lease) }
            assertThat(File(root, "direct-cli/jobs/$jobId/job.json").exists()).isFalse()
        }
    }

    @Test
    fun replacementPreparationHasIsolatedArtifactsAndRejectsOldPublicationAndCleanup() = withStore { store, root ->
        val initial = durableJournal().copy(
            enginePin = syntheticExportEnginePin(mode = ExportEngineMode.rust),
            protocolPin = protocolPin(AndroidDirectProtocolEngineMode.rust),
        )
        val jobId = initial.transfer.accepted.jobId
        fun admit() = store.beginPreparation(
            jobId, initial.requestFingerprint, initial.expiresAt, initial.enginePin, initial.protocolPin,
        )
        val stale = admit()
        val staleDirectory = store.directory(stale)
        assertThat(store.cancelPreparation(stale)).isTrue()
        val replacement = admit()
        val replacementDirectory = store.directory(replacement)
        assertThat(replacementDirectory).isNotEqualTo(staleDirectory)
        val artifact = File(replacementDirectory, "synthetic-artifact")
        artifact.writeText("synthetic replacement bytes")
        // An already running old producer may recreate its old staging leaf.
        // That namespace must not address the replacement's captured bytes.
        staleDirectory.mkdirs()
        File(staleDirectory, artifact.name).writeText("synthetic stale bytes")
        assertThrows(IllegalStateException::class.java) { store.directory(stale) }
        assertThrows(IllegalStateException::class.java) { store.savePrepared(initial, stale) }
        assertThat(store.cancelPreparation(stale)).isFalse()
        assertThat(artifact.readText()).isEqualTo("synthetic replacement bytes")
        val completed = initial.copy(transfer = initial.transfer.copy(
            artifactPaths = mapOf("synthetic-artifact" to artifact.absolutePath),
        ))
        store.savePrepared(completed, replacement)
        val directory = File(root, "direct-cli/jobs/$jobId")
        assertThat(File(directory, "pending.json").exists()).isFalse()
        val acceptedBytes = File(directory, "job.json").readBytes()
        assertThat(store.cancelPreparation(stale)).isFalse()
        assertThrows(IllegalStateException::class.java) { store.savePrepared(initial, stale) }
        assertThat(File(directory, "job.json").readBytes()).isEqualTo(acceptedBytes)
        assertThat(store.load(jobId, initial.requestFingerprint)).isEqualTo(completed)
        assertThat(artifact.readText()).isEqualTo("synthetic replacement bytes")
        assertThat(store.cancelPreparation(replacement)).isTrue()
        assertThat(directory.exists()).isFalse()
    }

    private fun durableJournal() = DirectJobJournal(
        requestFingerprint = "request-fingerprint",
        expiresAt = Instant.now().plusSeconds(3600).toString(),
        transfer = transfer(),
    )

    private fun withStore(action: (DirectCliJobStore, File) -> Unit) {
        val root = Files.createTempDirectory("synthetic-direct-journal").toFile()
        try {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            action(DirectCliJobStore(DirectCliTrustStore(context)), root)
        } finally { root.deleteRecursively() }
    }

    private fun protocolPin(mode: AndroidDirectProtocolEngineMode) = AndroidDirectProtocolPin(
        engine = mode,
        coreApiVersion = 4u,
        protocolApiRevision = 1u,
        androidApplicationProtocolVersion = 2u,
        transferProtocolVersion = 1u,
        coreCrateVersion = "0.1.0-test",
        coreSourceRevision = "test-revision",
    )

    private fun transfer(timeZoneId: String = "America/Los_Angeles"): PreparedTransfer {
        val jobId = UUID.fromString("10000000-0000-4000-8000-000000000001").toString()
        val binding = PeerBinding(
            sourceInstallationId = "20000000-0000-4000-8000-000000000002",
            destinationInstallationId = "30000000-0000-4000-8000-000000000003",
        )
        val accepted = ExportAccepted(
            jobId = jobId,
            acceptedAt = "2027-01-15T00:00:00Z",
            peerBinding = binding,
            productId = ProductId.GENERATED_FILES_V1,
            resolvedRange = ResolvedRange(
                startDate = "2027-01-14",
                endDate = "2027-01-14",
                timeZoneId = timeZoneId,
            ),
            requestFingerprint = "request-fingerprint",
        )
        return PreparedTransfer(
            accepted = accepted,
            session = TransferSession(
                sessionId = "40000000-0000-4000-8000-000000000004",
                jobId = jobId,
                requestFingerprint = "request-fingerprint",
                peerBinding = binding,
                partitionTargetBytes = 1_048_576,
                createdAt = "2027-01-15T00:00:00Z",
            ),
            manifests = emptyList(),
            partitions = emptyList(),
            artifactPaths = emptyMap(),
        )
    }
}
