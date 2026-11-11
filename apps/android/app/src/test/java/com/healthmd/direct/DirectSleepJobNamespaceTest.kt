package com.healthmd.direct

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.ArtifactKind
import com.healthmd.direct.protocol.ArtifactManifest
import com.healthmd.direct.protocol.ArtifactSchema
import com.healthmd.direct.protocol.ExportAccepted
import com.healthmd.direct.protocol.FileWriteMode
import com.healthmd.direct.protocol.PeerBinding
import com.healthmd.direct.protocol.ProductId
import com.healthmd.direct.protocol.ResolvedRange
import com.healthmd.direct.protocol.TransferPlanBuilder
import com.healthmd.direct.protocol.MINIMUM_PARTITION_BYTES
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import io.mockk.every
import io.mockk.mockk
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.security.MessageDigest
import java.util.UUID
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertThrows
import org.junit.Test

class DirectSleepJobNamespaceTest {

    @Test
    fun successorRecoveryRejectsSameLengthArtifactCorruption() = rejectsChangedTransfer("artifact")

    @Test
    fun successorRecoveryRejectsChangedManifestDigest() = rejectsChangedTransfer("manifest")

    @Test
    fun successorRecoveryRejectsChangedPartitionDigest() = rejectsChangedTransfer("partition")

    @Test
    fun successorRecoveryStreamsMultiplePartitionsAndAcceptsEmptyArtifacts() = withStores { store, root, reopen ->
        for (byteCount in listOf(0L, MINIMUM_PARTITION_BYTES + 17)) {
            val successor = prepare(store, successorPin(), artifactByteCount = byteCount)
            assertThat(successor.transfer.partitions.size).isEqualTo(if (byteCount == 0L) 0 else 2)
            val relaunched = reopen()
            assertThat(relaunched.load(successor.transfer.accepted.jobId, successor.requestFingerprint)).isEqualTo(successor)
            val lease = relaunched.acquireAcceptedLease(successor)
            var callbacks = 0
            relaunched.packetSendAuthorization(lease).authorizeEnqueue { callbacks += 1 }
            assertThat(callbacks).isEqualTo(1)
            if (byteCount > 0) {
                // Change the last byte, in the second partition, without changing length.
                java.io.RandomAccessFile(File(successor.transfer.artifactPaths.values.single()), "rw").use {
                    it.seek(byteCount - 1)
                    it.write(1)
                }
                assertThrows(IllegalStateException::class.java) {
                    reopen().load(successor.transfer.accepted.jobId, successor.requestFingerprint)
                }
                assertThat(directory(root, successor).isDirectory).isTrue()
            }
        }
    }

    private fun rejectsChangedTransfer(damage: String) = withStores { store, root, reopen ->
        val successor = prepare(store, successorPin())
        val directory = directory(root, successor)
        val changed = when (damage) {
            "artifact" -> successor.also {
                val artifact = File(it.transfer.artifactPaths.values.single())
                val bytes = artifact.readBytes()
                bytes[bytes.lastIndex] = (bytes.last().toInt() xor 1).toByte()
                artifact.writeBytes(bytes)
            }
            "manifest" -> successor.copy(transfer = successor.transfer.copy(
                manifests = successor.transfer.manifests.map { it.copy(sha256 = "0".repeat(64)) },
            ))
            "partition" -> successor.copy(transfer = successor.transfer.copy(
                partitions = successor.transfer.partitions.map { it.copy(sha256 = "0".repeat(64)) },
            ))
            else -> error("Unknown synthetic damage")
        }
        File(directory, "job.json").writeText(kotlinx.serialization.json.Json.encodeToString(changed))
        val before = snapshot(directory)
        val relaunched = reopen()
        assertThrows(IllegalStateException::class.java) {
            relaunched.load(changed.transfer.accepted.jobId, changed.requestFingerprint)
        }
        assertThrows(IllegalStateException::class.java) { relaunched.acquireAcceptedLease(changed) }
        relaunched.sweepExpired(Instant.now().plusSeconds(7_200))
        assertThat(snapshot(directory)).isEqualTo(before)
    }

    @Test
    fun successorSurvivesWholeHistoricalTreeDeletionAndStoreRelaunch() = withStores { store, root, reopen ->
        val historical = prepare(store, null)
        val successor = prepare(store, successorPin())
        val successorDirectory = directory(root, successor)
        val original = snapshot(successorDirectory)
        assertThat(File(root, "direct-cli/jobs/${historical.transfer.accepted.jobId}/job.json").isFile).isTrue()
        assertThat(File(successorDirectory, "job.json").isFile).isTrue()
        assertThat(File(root, "direct-cli/jobs").deleteRecursively()).isTrue()
        val relaunched = reopen()
        assertThat(relaunched.load(successor.transfer.accepted.jobId, successor.requestFingerprint)).isEqualTo(successor)
        val lease = relaunched.acquireAcceptedLease(successor)
        var callbacks = 0
        relaunched.packetSendAuthorization(lease).authorizeEnqueue { callbacks += 1 }
        assertThat(callbacks).isEqualTo(1)
        assertThat(snapshot(successorDirectory)).isEqualTo(original)
        assertThat(File(root, "direct-cli/jobs").exists()).isFalse()
    }

    @Test
    fun validatedSuccessorExpiryPreservesUnexpiredHistoricalAuthorityAndRevokesOldLease() = withStores { store, root, _ ->
        val historical = prepare(store, null, expiresAt = Instant.now().plusSeconds(10_000))
        val successor = prepare(store, successorPin())
        val lease = store.acquireAcceptedLease(successor)
        val historicalDirectory = directory(root, historical)
        val original = snapshot(historicalDirectory)
        store.sweepExpired(Instant.now().plusSeconds(7_200))
        assertThat(directory(root, successor).exists()).isFalse()
        assertThat(snapshot(historicalDirectory)).isEqualTo(original)
        assertThat(store.load(historical.transfer.accepted.jobId, historical.requestFingerprint)).isEqualTo(historical)
        val before = File(root, "direct-cli").walkTopDown().map { it.relativeTo(root).path }.toSet()
        var callbacks = 0
        assertThrows(IllegalStateException::class.java) { store.packetSendAuthorization(lease).authorizeEnqueue { callbacks += 1 } }
        assertThat(callbacks).isEqualTo(0)
        assertThat(File(root, "direct-cli").walkTopDown().map { it.relativeTo(root).path }.toSet()).isEqualTo(before)
    }

    @Test
    fun misplacedAndDuplicateSuccessorAuthorityRetainsEveryStoredByte() {
        for (duplicate in listOf(false, true)) withStores { store, root, _ ->
            val successor = prepare(store, successorPin())
            val current = directory(root, successor)
            val misplaced = File(root, "direct-cli/jobs/${successor.transfer.accepted.jobId}")
            check(misplaced.parentFile.mkdirs() || misplaced.parentFile.isDirectory)
            if (duplicate) current.copyRecursively(misplaced) else check(current.renameTo(misplaced))
            val before = snapshot(File(root, "direct-cli"))
            assertThrows(IllegalStateException::class.java) { store.load(successor.transfer.accepted.jobId, successor.requestFingerprint) }
            store.sweepExpired(Instant.now().plusSeconds(7_200))
            assertThat(snapshot(File(root, "direct-cli"))).isEqualTo(before)
        }
    }

    @Test
    fun incompleteUnknownAndUnownedSuccessorJobsAreNotDeletedOrMigrated() {
        for (damage in listOf("owner", "version", "legacy", "v2", "journal", "symlink", "schema", "partitions", "fingerprint", "file")) withStores { store, root, _ ->
            val successor = prepare(store, successorPin())
            val directory = directory(root, successor)
            val journal = File(directory, "job.json")
            fun replaceJournalVersion(version: Int) {
                val document = Json.parseToJsonElement(journal.readText()).jsonObject
                assertThat(document["version"]).isEqualTo(JsonPrimitive(successor.version))
                journal.writeText(JsonObject(document + ("version" to JsonPrimitive(version))).toString())
            }
            when (damage) {
                "owner" -> check(File(directory, "preparation-owner").delete())
                "version" -> replaceJournalVersion(999)
                "legacy" -> replaceJournalVersion(1)
                "v2" -> replaceJournalVersion(2)
                "journal" -> journal.writeText("synthetic unrecognized journal")
                "schema" -> journal.writeText(kotlinx.serialization.json.Json.encodeToString(successor.copy(
                    transfer = successor.transfer.copy(manifests = successor.transfer.manifests.map {
                        it.copy(schema = ArtifactSchema("healthmd.generated-files", 999))
                    }))))
                "partitions" -> journal.writeText(kotlinx.serialization.json.Json.encodeToString(successor.copy(
                    transfer = successor.transfer.copy(partitions = emptyList()))))
                "fingerprint" -> journal.writeText(kotlinx.serialization.json.Json.encodeToString(successor.copy(
                    requestFingerprint = "c".repeat(64))))
                "file" -> check(File(successor.transfer.artifactPaths.values.single()).delete())
                "symlink" -> {
                    val retained = File(root, "retained-journal.json")
                    journal.copyTo(retained)
                    check(journal.delete())
                    Files.createSymbolicLink(journal.toPath(), retained.toPath())
                }
            }
            val before = snapshot(directory)
            assertThrows(IllegalStateException::class.java) { store.load(successor.transfer.accepted.jobId, successor.requestFingerprint) }
            store.sweepExpired(Instant.now().plusSeconds(8 * 24 * 3600))
            assertThat(snapshot(directory)).isEqualTo(before)
        }
    }

    @Test
    fun staleHistoricalLeaseCannotBorrowSuccessorNamespaceAndExplicitForgetPurgesBoth() = withStores { store, root, _ ->
        val historical = prepare(store, null)
        val stale = store.acquireAcceptedLease(historical)
        store.cancel(historical.transfer.accepted.jobId)
        val successor = prepare(store, successorPin(), jobId = historical.transfer.accepted.jobId)
        val original = snapshot(directory(root, successor))
        var callbacks = 0
        assertThrows(IllegalStateException::class.java) { store.packetSendAuthorization(stale).authorizeEnqueue { callbacks += 1 } }
        assertThat(store.cancelAccepted(stale)).isFalse()
        assertThat(callbacks).isEqualTo(0)
        assertThat(snapshot(directory(root, successor))).isEqualTo(original)
        store.purgeAll()
        assertThat(directory(root, successor).exists()).isFalse()
        assertThat(store.load(successor.transfer.accepted.jobId, successor.requestFingerprint)).isNull()
    }

    @Test
    fun ambiguousExpirySyncIsRetriedEvenAfterTheLastJobWasRemoved() {
        var watched: File? = null
        var job: File? = null
        var reject = false
        var syncsAfterRemoval = 0
        withStores(directorySync = { directory ->
            if (directory == watched && job?.exists() == false) {
                syncsAfterRemoval += 1
                !reject
            } else true
        }) { store, root, _ ->
            val successor = prepare(store, successorPin())
            job = directory(root, successor)
            watched = job!!.parentFile
            reject = true
            assertThrows(IllegalStateException::class.java) { store.sweepExpired(Instant.now().plusSeconds(7_200)) }
            assertThat(job!!.exists()).isFalse()
            assertThat(syncsAfterRemoval).isEqualTo(1)
            reject = false
            store.sweepExpired(Instant.now().plusSeconds(7_200))
            assertThat(syncsAfterRemoval).isEqualTo(2)
        }
    }

    @Test
    fun successorLookupAndExpiryRejectForeignArtifactPathsBeforeAdmittingALease() = withStores { store, root, _ ->
        val successor = prepare(store, successorPin())
        val directory = directory(root, successor)
        val foreign = File(root, "foreign-artifact.json").apply { writeText("synthetic foreign artifact") }
        val changed = successor.copy(transfer = successor.transfer.copy(
            artifactPaths = successor.transfer.artifactPaths.keys.associateWith { foreign.path }))
        File(directory, "job.json").writeText(kotlinx.serialization.json.Json.encodeToString(changed))
        val before = snapshot(directory)
        assertThrows(IllegalStateException::class.java) { store.load(changed.transfer.accepted.jobId, changed.requestFingerprint) }
        assertThrows(IllegalStateException::class.java) { store.acquireAcceptedLease(changed) }
        store.sweepExpired(Instant.now().plusSeconds(7_200))
        assertThat(snapshot(directory)).isEqualTo(before)
        assertThat(foreign.readText()).isEqualTo("synthetic foreign artifact")
    }

    @Test
    fun expiryUnlinksAnOrphanSymlinkWithoutDeletingItsTarget() = withStores { store, root, _ ->
        val successor = prepare(store, successorPin())
        val foreign = File(root, "foreign-directory").apply { mkdirs() }
        File(foreign, "retained.txt").writeText("synthetic retained bytes")
        Files.createSymbolicLink(File(directory(root, successor), "orphan-link").toPath(), foreign.toPath())
        store.sweepExpired(Instant.now().plusSeconds(7_200))
        assertThat(directory(root, successor).exists()).isFalse()
        assertThat(File(foreign, "retained.txt").readText()).isEqualTo("synthetic retained bytes")
    }

    @Test
    fun unknownHistoricalJournalIsRetainedInsteadOfBeingDeletedByDirectoryAge() = withStores { store, root, _ ->
        val historical = prepare(store, null)
        val directory = directory(root, historical)
        File(directory, "job.json").writeText("synthetic unrecognized journal")
        check(directory.setLastModified(Instant.now().minusSeconds(8 * 24 * 3600).toEpochMilli()))
        val before = snapshot(directory)
        store.sweepExpired(Instant.now().plusSeconds(7_200))
        assertThat(snapshot(directory)).isEqualTo(before)
    }

    @Test
    fun incompleteSuccessorPinsCannotAdmitJobDirectories() = withStores { store, root, _ ->
        val pin = successorPin()
        val alternatives = listOf(
            pin.copy(registrySha256 = "0".repeat(64)),
            pin.copy(semanticProfileRevision = pin.semanticProfileRevision + 1u),
            pin.copy(renderProfileRevision = pin.renderProfileRevision + 1u),
            pin.copy(semanticInputVersion = 1u),
            pin.copy(coreApiVersion = pin.coreApiVersion + 1u),
            pin.copy(engine = ExportEngineMode.shadow),
            pin.copy(engine = ExportEngineMode.legacy),
            pin.copy(ianaTimeZone = "invalid-synthetic-clock"),
        )
        alternatives.forEach { invalid ->
            assertThrows(IllegalArgumentException::class.java) {
                store.beginPreparation(UUID.randomUUID().toString(), "synthetic-request", Instant.now().plusSeconds(3_600).toString(), invalid)
            }
            assertThat(File(root, "direct-cli/jobs").exists()).isFalse()
            assertThat(File(root, "direct-cli/jobs-sleep-attribution-v6").exists()).isFalse()
        }
    }

    private fun successorPin(): ExportEnginePin = requireNotNull(ExportEnginePinCodec.decodeOrNull(
        requireNotNull(javaClass.classLoader!!.getResource("direct/android-sleep-v6-storage-pin.json")).readText().trim(),
    ))

    private fun prepare(store: DirectCliJobStore, pin: ExportEnginePin?,
        expiresAt: Instant = Instant.now().plusSeconds(3_600), jobId: String = UUID.randomUUID().toString(),
        artifactByteCount: Long? = null): DirectJobJournal {
        val fingerprint = "a".repeat(64)
        val lease = store.beginPreparation(jobId, fingerprint, expiresAt.toString(), pin)
        val file = File(store.directory(lease), "synthetic.json").apply {
            if (artifactByteCount == null) writeText("{\"synthetic\":\"storage authority\"}")
            else outputStream().use { output ->
                val buffer = ByteArray(128 * 1024)
                var remaining = artifactByteCount
                while (remaining > 0) {
                    val count = minOf(buffer.size.toLong(), remaining).toInt()
                    output.write(buffer, 0, count)
                    remaining -= count
                }
            }
        }
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(128 * 1024)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        }
        val accepted = ExportAccepted(jobId = jobId, acceptedAt = Instant.now().toString(),
            peerBinding = PeerBinding(UUID.randomUUID().toString(), UUID.randomUUID().toString()),
            productId = ProductId.GENERATED_FILES_V1,
            resolvedRange = ResolvedRange("2026-10-18", "2026-10-18", "America/Los_Angeles"), requestFingerprint = fingerprint)
        val manifest = ArtifactManifest(jobId = jobId, artifactId = "synthetic-file", kind = ArtifactKind.GENERATED_FILE,
            schema = ArtifactSchema("healthmd.generated-files", 1), mediaType = "application/json",
            byteCount = file.length(), sha256 = digest.digest().joinToString("") { "%02x".format(it) }, relativePath = "2026-10-18.json", writeMode = FileWriteMode.OVERWRITE)
        val transfer = TransferPlanBuilder.build(accepted, listOf(manifest), mapOf(manifest.artifactId to file),
            partitionTargetBytes = MINIMUM_PARTITION_BYTES, createdAt = accepted.acceptedAt)
        val journal = DirectJobJournal(requestFingerprint = fingerprint, expiresAt = expiresAt.toString(), transfer = transfer, enginePin = pin)
        store.savePrepared(journal, lease)
        return journal
    }

    private fun directory(root: File, journal: DirectJobJournal): File = File(root,
        "direct-cli/${if (journal.enginePin == null) "jobs" else "jobs-sleep-attribution-v6"}/${journal.transfer.accepted.jobId}")

    private fun snapshot(directory: File): Map<String, List<Byte>> = directory.walkTopDown().filter { it.isFile }
        .associate { it.relativeTo(directory).path to it.readBytes().toList() }

    private fun withStores(directorySync: (File) -> Boolean = { true },
        action: (DirectCliJobStore, File, () -> DirectCliJobStore) -> Unit) {
        val root = Files.createTempDirectory("synthetic-direct-sleep-namespace").toFile().canonicalFile
        try {
            val context = mockk<Context> { every { noBackupFilesDir } returns root }
            val reopen = { DirectCliJobStore(DirectCliTrustStore(context), Unit, directorySync) }
            action(reopen(), root, reopen)
        } finally { root.deleteRecursively() }
    }
}
