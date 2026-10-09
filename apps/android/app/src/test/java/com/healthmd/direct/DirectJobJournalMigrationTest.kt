package com.healthmd.direct

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.healthmd.data.settings.SettingsRepositoryImpl
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
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
        val lease = store.acquireAcceptedLease(initial)
        assertThat(store.markAccounted(lease)).isTrue()
        assertThat(store.markCompleted(lease)).isTrue()
        assertThat(store.markAccounted(lease)).isFalse()
        assertThat(store.markCompleted(lease)).isFalse()
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
        val secondStore = DirectCliJobStore(DirectCliTrustStore(context), Unit, { true })
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

    @Test
    fun preparationPacketsRejectChangedPendingAuthorityBeforeCallbacks() = withStore { store, root ->
        val journal = durableJournal()
        val lease = store.beginPreparation(journal.transfer.accepted.jobId,
            journal.requestFingerprint, journal.expiresAt, journal.enginePin, journal.protocolPin)
        val authorization = store.preparationPacketSendAuthorization(lease)
        val pending = File(root, "direct-cli/jobs/${lease.jobId}/pending.json")
        val original = pending.readText()
        val changed = original.replace(journal.requestFingerprint, "changed-fingerprint")
        pending.writeText(changed)
        var callbacks = 0
        assertThrows(IllegalStateException::class.java) {
            authorization.authorizeEnqueue { callbacks += 1 }
        }
        assertThrows(IllegalStateException::class.java) { store.directory(lease) }
        assertThrows(IllegalStateException::class.java) { store.savePrepared(journal, lease) }
        assertThat(callbacks).isEqualTo(0)
        assertThat(pending.readText()).isEqualTo(changed)
        pending.writeText(original)
        authorization.authorizeEnqueue { callbacks += 1 }
        assertThat(callbacks).isEqualTo(1)
    }

    @Test
    fun expiredPreparationCannotEnqueuePackets() = withStore { store, _ ->
        val journal = durableJournal()
        val lease = store.beginPreparation(journal.transfer.accepted.jobId,
            journal.requestFingerprint, "2020-01-01T00:00:00Z", journal.enginePin, journal.protocolPin)
        var callbacks = 0
        assertThrows(IllegalStateException::class.java) {
            store.preparationPacketSendAuthorization(lease).authorizeEnqueue { callbacks += 1 }
        }
        assertThat(callbacks).isEqualTo(0)
    }

    @Test
    fun preparationCancellationAndAckEnqueueExcludeReplacementAdmission() = withStore { store, root ->
        val journal = durableJournal()
        fun admit() = store.beginPreparation(journal.transfer.accepted.jobId,
            journal.requestFingerprint, journal.expiresAt, journal.enginePin, journal.protocolPin)
        val original = admit()
        val executor = Executors.newSingleThreadExecutor()
        var replacement: java.util.concurrent.Future<DirectPreparationLease>? = null
        try {
            store.preparationPacketSendAuthorization(original, cancelBeforeEnqueue = true).authorizeEnqueue {
                assertThat(File(root, "direct-cli/jobs/${original.jobId}").exists()).isFalse()
                val attempting = CountDownLatch(1)
                replacement = executor.submit<DirectPreparationLease> {
                    attempting.countDown()
                    admit()
                }
                assertThat(attempting.await(2, TimeUnit.SECONDS)).isTrue()
                assertThrows(TimeoutException::class.java) { replacement!!.get(100, TimeUnit.MILLISECONDS) }
                val lockFile = File(root, "direct-cli/.jobs.journal.lock")
                java.io.RandomAccessFile(lockFile, "rw").use { file ->
                    assertThrows(java.nio.channels.OverlappingFileLockException::class.java) {
                        file.channel.tryLock()
                    }
                }
            }
            val current = replacement!!.get(2, TimeUnit.SECONDS)
            assertThat(current.token).isNotEqualTo(original.token)
            val pending = File(root, "direct-cli/jobs/${current.jobId}/pending.json")
            val bytes = pending.readBytes()
            var staleCallbacks = 0
            assertThrows(IllegalStateException::class.java) {
                store.preparationPacketSendAuthorization(original, cancelBeforeEnqueue = true)
                    .authorizeEnqueue { staleCallbacks += 1 }
            }
            assertThat(staleCallbacks).isEqualTo(0)
            assertThat(pending.readBytes()).isEqualTo(bytes)
        } finally { executor.shutdownNow() }
    }

    @Test
    fun packetEnqueueHoldsTheFilesystemLockAndRejectsIdenticalReplacement() = withStore { store, root ->
        val original = durableJournal()
        val jobId = original.transfer.accepted.jobId
        store.save(original)
        val accepted = store.acquireAcceptedLease(original)
        val authorization = store.packetSendAuthorization(accepted)
        val lockFile = File(root, "direct-cli/.jobs.journal.lock")
        var callbacks = 0
        authorization.authorizeEnqueue {
            callbacks += 1
            java.io.RandomAccessFile(lockFile, "rw").use { file ->
                assertThrows(java.nio.channels.OverlappingFileLockException::class.java) {
                    file.channel.tryLock()
                }
            }
        }
        java.io.RandomAccessFile(lockFile, "rw").use { file ->
            file.channel.tryLock().use { assertThat(it).isNotNull() }
        }
        store.cancel(jobId)
        store.save(original)
        store.acquireAcceptedLease(original)
        val journal = File(root, "direct-cli/jobs/$jobId/job.json")
        val replacementBytes = journal.readBytes()
        assertThrows(IllegalStateException::class.java) {
            authorization.authorizeEnqueue { callbacks += 1 }
        }
        assertThat(callbacks).isEqualTo(1)
        assertThat(journal.readBytes()).isEqualTo(replacementBytes)
    }

    @Test
    fun staleSenderCannotAccountOrCompleteAReplacementWithTheSameJobId() = withStore { store, root ->
        val original = durableJournal()
        val jobId = original.transfer.accepted.jobId
        store.save(original)
        val stale = store.acquireAcceptedLease(original)
        store.cancel(jobId)
        val replacement = original.copy(transfer = original.transfer.copy(session = original.transfer.session.copy(
            sessionId = "60000000-0000-4000-8000-000000000006",
        )))
        store.save(replacement)
        val file = File(root, "direct-cli/jobs/$jobId/job.json")
        val bytes = file.readBytes()
        assertThrows(IllegalStateException::class.java) { store.markAccounted(stale) }
        assertThrows(IllegalStateException::class.java) { store.markCompleted(stale) }
        assertThrows(IllegalStateException::class.java) { store.validateAcceptedLease(stale) }
        assertThat(store.cancelAccepted(stale)).isFalse()
        assertThat(file.readBytes()).isEqualTo(bytes)
        assertThat(store.load(jobId, replacement.requestFingerprint)).isEqualTo(replacement)
    }

    @Test
    fun legacyResumeRetainsJournalBytesAndAccountsAndCompletesOnlyOnceAcrossLeases() = withStore { store, root ->
        val original = durableJournal().copy(version = DirectJobJournal.LEGACY_VERSION)
        val jobId = original.transfer.accepted.jobId
        store.save(original)
        val file = File(root, "direct-cli/jobs/$jobId/job.json")
        val before = file.readBytes()
        val first = store.acquireAcceptedLease(original)
        val second = store.acquireAcceptedLease(original)
        assertThat(file.readBytes()).isEqualTo(before)
        var charges = 0
        assertThrows(IllegalStateException::class.java) {
            store.markAccounted(first) { throw IllegalStateException("synthetic accounting failure") }
        }
        assertThat(file.readBytes()).isEqualTo(before)
        assertThat(store.markAccounted(second) { charges += 1 }).isTrue()
        assertThat(store.markAccounted(first) { charges += 1 }).isFalse()
        assertThat(charges).isEqualTo(1)
        assertThat(store.markCompleted(first)).isTrue()
        val completedBytes = file.readBytes()
        assertThat(store.markCompleted(second)).isFalse()
        assertThat(file.readBytes()).isEqualTo(completedBytes)
        assertThat(store.load(jobId, original.requestFingerprint))
            .isEqualTo(original.copy(accounted = true, completed = true))
    }

    @Test
    fun failedSuccessCounterWriteCanResumeWithoutLosingTheCompletion() = withStore { store, _ ->
        val original = durableJournal()
        store.save(original)
        val first = store.acquireAcceptedLease(original)
        var successes = 0
        assertThrows(IllegalStateException::class.java) {
            store.markCompleted(first) { throw IllegalStateException("synthetic counter storage failure") }
        }
        assertThat(store.load(original.transfer.accepted.jobId, original.requestFingerprint)).isEqualTo(original)
        val resumed = store.acquireAcceptedLease(original)
        assertThat(store.markCompleted(resumed) { successes += 1 }).isTrue()
        assertThat(store.markCompleted(first) { successes += 1 }).isFalse()
        assertThat(successes).isEqualTo(1)
    }

    @Test
    fun persistedSuccessReceiptSurvivesInterruptedCheckpointAndStoreRestart() = withStore { store, root ->
        runBlocking {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            val preferences = File(root, "success.preferences_pb")
            fun settings(job: Job) = SettingsRepositoryImpl(
                PreferenceDataStoreFactory.create(
                    scope = CoroutineScope(job + Dispatchers.IO),
                    produceFile = { preferences },
                ), context,
            )
            val initial = durableJournal()
            store.save(initial)
            val lease = store.acquireAcceptedLease(initial)
            val journalFile = File(root, "direct-cli/jobs/${lease.owner.jobId}/job.json")
            val originalBytes = journalFile.readBytes()
            val firstScope = SupervisorJob()
            val firstSettings = settings(firstScope)
            try {
                assertThrows(IllegalStateException::class.java) {
                    store.markCompleted(lease) {
                        runBlocking {
                            assertThat(firstSettings.recordSuccessfulExportOnce(lease.owner.token)).isTrue()
                        }
                        // Durable counter write succeeded; completion checkpoint never ran.
                        throw IllegalStateException("synthetic interruption before checkpoint")
                    }
                }
                assertThat(journalFile.readBytes()).isEqualTo(originalBytes)
                assertThat(firstSettings.getSuccessfulExportCount()).isEqualTo(1)
            } finally {
                firstScope.cancel()
                firstScope.join()
            }
            val secondScope = SupervisorJob()
            val resumedSettings = settings(secondScope)
            try {
                val reopened = DirectCliJobStore(DirectCliTrustStore(context), Unit, { true })
                val resumed = reopened.acquireAcceptedLease(initial)
                assertThat(resumed.owner.token).isEqualTo(lease.owner.token)
                assertThat(reopened.markCompleted(resumed) {
                    runBlocking {
                        assertThat(resumedSettings.recordSuccessfulExportOnce(resumed.owner.token)).isFalse()
                    }
                }).isTrue()
                assertThat(resumedSettings.getSuccessfulExportCount()).isEqualTo(1)
                assertThat(reopened.markCompleted(resumed) { error("completed callback must not run") }).isFalse()
                reopened.cancelAccepted(resumed)
                reopened.save(initial)
                val replacement = reopened.acquireAcceptedLease(initial)
                assertThat(replacement.owner.token).isNotEqualTo(resumed.owner.token)
                assertThrows(IllegalStateException::class.java) {
                    reopened.markCompleted(resumed) { error("stale callback must not run") }
                }
                assertThat(reopened.markCompleted(replacement) {
                    runBlocking {
                        assertThat(resumedSettings.recordSuccessfulExportOnce(replacement.owner.token)).isTrue()
                    }
                }).isTrue()
                assertThat(resumedSettings.getSuccessfulExportCount()).isEqualTo(2)
                assertThrows(IllegalArgumentException::class.java) {
                    runBlocking { resumedSettings.recordSuccessfulExportOnce("invalid") }
                }
                assertThat(resumedSettings.getSuccessfulExportCount()).isEqualTo(2)
            } finally {
                secondScope.cancel()
                secondScope.join()
            }
        }
    }

    @Test
    fun identicalReplacementAndCorruptOwnerCannotReuseAnOldSenderLease() = withStore { store, root ->
        val original = durableJournal()
        val jobId = original.transfer.accepted.jobId
        store.save(original)
        val stale = store.acquireAcceptedLease(original)
        store.purgeAll()
        store.save(original)
        val current = store.acquireAcceptedLease(original)
        val file = File(root, "direct-cli/jobs/$jobId/job.json")
        val bytes = file.readBytes()
        var charges = 0
        assertThrows(IllegalStateException::class.java) { store.markAccounted(stale) { charges += 1 } }
        assertThrows(IllegalStateException::class.java) { store.markCompleted(stale) }
        assertThat(store.cancelAccepted(stale)).isFalse()
        assertThat(charges).isEqualTo(0)
        assertThat(file.readBytes()).isEqualTo(bytes)
        val owner = File(file.parentFile, "preparation-owner")
        val corrupt = "x".repeat(36)
        owner.writeText(corrupt)
        assertThrows(IllegalStateException::class.java) { store.acquireAcceptedLease(original) }
        assertThrows(IllegalStateException::class.java) { store.markAccounted(current) { charges += 1 } }
        assertThrows(IllegalStateException::class.java) { store.markCompleted(current) }
        assertThat(store.cancelAccepted(current)).isFalse()
        assertThat(owner.readText()).isEqualTo(corrupt)
        assertThat(file.readBytes()).isEqualTo(bytes)
        assertThat(charges).isEqualTo(0)
    }

    @Test
    fun directorySyncFailureCannotAcknowledgePublishedAuthority() {
        var durable = false
        val synced = mutableListOf<File>()
        withStore(directorySync = { synced += it; durable }) { store, root ->
            val original = durableJournal()
            assertThrows(IllegalStateException::class.java) { store.save(original) }
            val file = File(root, "direct-cli/jobs/${original.transfer.accepted.jobId}/job.json")
            val bytes = file.readBytes()
            assertThrows(IllegalStateException::class.java) { store.acquireAcceptedLease(original) }
            durable = true
            val lease = store.acquireAcceptedLease(original)
            assertThat(file.readBytes()).isEqualTo(bytes)
            assertThat(synced).containsAtLeast(file.parentFile, File(root, "direct-cli/jobs"), File(root, "direct-cli"), root)
            durable = false
            var callbacks = 0
            assertThrows(IllegalStateException::class.java) { store.markCompleted(lease) { callbacks += 1 } }
            assertThrows(IllegalStateException::class.java) { store.markAccounted(lease) { callbacks += 1 } }
            assertThat(callbacks).isEqualTo(0)
            assertThat(file.readBytes()).isEqualTo(bytes)
            durable = true
            assertThat(store.markCompleted(lease) { callbacks += 1 }).isTrue()
            assertThat(callbacks).isEqualTo(1)
        }
    }

    @Test
    fun preparationCaptureAndRevocationSynchronizeTheirAuthorityParents() {
        var durable = true
        val synced = mutableListOf<File>()
        withStore(directorySync = { synced += it; durable }) { store, root ->
            val journal = durableJournal()
            val jobId = journal.transfer.accepted.jobId
            val jobDirectory = File(root, "direct-cli/jobs/$jobId")
            val lease = store.beginPreparation(jobId, journal.requestFingerprint, journal.expiresAt)
            assertThat(synced.take(4)).containsExactly(
                jobDirectory, File(root, "direct-cli/jobs"), File(root, "direct-cli"), root,
            ).inOrder()
            assertThat(File(jobDirectory, "preparation-owner").readText()).isEqualTo(lease.token)
            synced.clear()
            val capture = store.directory(lease)
            assertThat(synced.first()).isEqualTo(capture)
            assertThat(synced).containsAtLeast(jobDirectory, root)
            store.savePrepared(journal, lease)
            assertThat(File(jobDirectory, "pending.json").exists()).isFalse()
            val accepted = store.acquireAcceptedLease(journal)
            synced.clear()
            durable = false
            assertThrows(IllegalStateException::class.java) { store.cancelAccepted(accepted) }
            assertThat(jobDirectory.exists()).isFalse()
            assertThat(synced).containsExactly(File(root, "direct-cli/jobs"))
            durable = true
            store.cancel(jobId)
            store.save(journal)
            val replacement = store.acquireAcceptedLease(journal)
            assertThat(replacement.owner.token).isNotEqualTo(accepted.owner.token)
            assertThrows(IllegalStateException::class.java) { store.validateAcceptedLease(accepted) }
        }
    }

    @Test
    fun failedOwnerPublicationRetainsPendingPreparationWithoutIssuingALease() {
        withStore(directorySync = { directory -> !File(directory, "preparation-owner").exists() }) { store, root ->
            val journal = durableJournal()
            val jobId = journal.transfer.accepted.jobId
            assertThrows(IllegalStateException::class.java) {
                store.beginPreparation(jobId, journal.requestFingerprint, journal.expiresAt)
            }
            val directory = File(root, "direct-cli/jobs/$jobId")
            assertThat(File(directory, "pending.json").isFile).isTrue()
            assertThat(File(directory, "preparation-owner").isFile).isTrue()
            assertThat(File(directory, "job.json").exists()).isFalse()
            assertThat(directory.listFiles()!!.any { it.name.endsWith(".tmp") }).isFalse()
            assertThat(store.hasIncompletePreparation(jobId, journal.requestFingerprint)).isTrue()
        }
    }

    private fun durableJournal() = DirectJobJournal(
        requestFingerprint = "request-fingerprint",
        expiresAt = Instant.now().plusSeconds(3600).toString(),
        transfer = transfer(),
    )

    private fun withStore(
        directorySync: (File) -> Boolean = { true },
        action: (DirectCliJobStore, File) -> Unit,
    ) {
        val root = Files.createTempDirectory("synthetic-direct-journal").toFile()
        try {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            action(DirectCliJobStore(DirectCliTrustStore(context), Unit, directorySync), root)
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
