package com.healthmd.direct

import android.content.ContextWrapper
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.core.HealthMdCoreService
import com.healthmd.direct.protocol.ArtifactKind
import com.healthmd.direct.protocol.ArtifactManifest
import com.healthmd.direct.protocol.ArtifactSchema
import com.healthmd.direct.protocol.DirectJson
import com.healthmd.direct.protocol.ExportAccepted
import com.healthmd.direct.protocol.FileWriteMode
import com.healthmd.direct.protocol.PeerBinding
import com.healthmd.direct.protocol.ProductId
import com.healthmd.direct.protocol.ResolvedRange
import com.healthmd.direct.protocol.TransferPlanBuilder
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePin
import java.io.File
import java.nio.file.Files
import java.time.Instant
import java.util.UUID
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real Android filesystem/fsync and packaged core; no provider, network, or user spool access. */
@RunWith(AndroidJUnit4::class)
class DirectSleepJobStorageDeviceTest {
    @Test
    fun successorSpoolSurvivesHistoricalDeletionAndStoreRelaunch() = withStore { store, root, reopen ->
        prepare(store, null)
        val successor = prepare(store, successorPin())
        val directory = successorDirectory(root, successor)
        val before = snapshot(directory)
        assertTrue(File(root, "direct-cli/jobs").deleteRecursively())
        val relaunched = reopen()
        assertEquals(successor, relaunched.load(successor.transfer.accepted.jobId, successor.requestFingerprint))
        var packets = 0
        relaunched.packetSendAuthorization(relaunched.acquireAcceptedLease(successor)).authorizeEnqueue { packets += 1 }
        assertEquals(1, packets)
        assertEquals(before, snapshot(directory))
        assertFalse(File(root, "direct-cli/jobs").exists())
    }

    @Test
    fun successorExpiryRevokesItsLeaseAndPreservesUnexpiredHistoricalBytes() = withStore { store, root, _ ->
        val historical = prepare(store, null, expiresAt = Instant.now().plusSeconds(10_000))
        val successor = prepare(store, successorPin())
        val lease = store.acquireAcceptedLease(successor)
        val historicalDirectory = File(root, "direct-cli/jobs/${historical.transfer.accepted.jobId}")
        val retained = snapshot(historicalDirectory)
        store.sweepExpired(Instant.now().plusSeconds(7_200))
        assertFalse(successorDirectory(root, successor).exists())
        assertEquals(retained, snapshot(historicalDirectory))
        assertEquals(historical, store.load(historical.transfer.accepted.jobId, historical.requestFingerprint))
        var packets = 0
        assertThrows(IllegalStateException::class.java) {
            store.packetSendAuthorization(lease).authorizeEnqueue { packets += 1 }
        }
        assertEquals(0, packets)
    }

    @Test
    fun expiryRemovesAnOrphanLinkWithoutFollowingItsTarget() = withStore { store, root, _ ->
        val successor = prepare(store, successorPin())
        val retained = File(root, "retained/foreign.txt").apply {
            check(parentFile!!.mkdirs())
            writeText("synthetic retained bytes")
        }
        Files.createSymbolicLink(File(successorDirectory(root, successor), "orphan-link").toPath(), retained.parentFile!!.toPath())
        store.sweepExpired(Instant.now().plusSeconds(7_200))
        assertFalse(successorDirectory(root, successor).exists())
        assertEquals("synthetic retained bytes", retained.readText())
    }

    private fun successorPin(): ExportEnginePin {
        val service = HealthMdCoreService()
        return ExportEnginePin.create(engine = ExportEngineMode.rust, profile = AndroidExportProfile.android_sleep_v6,
            ianaTimeZone = "America/Los_Angeles", readiness = service.checkReadiness(),
            registry = service.getMetricRegistry(CoreMetricRegistryProfile.ANDROID_SLEEP_V6, 2u))
    }

    private fun prepare(store: DirectCliJobStore, pin: ExportEnginePin?, expiresAt: Instant = Instant.now().plusSeconds(3_600)): DirectJobJournal {
        val jobId = UUID.randomUUID().toString()
        val fingerprint = "b".repeat(64)
        val lease = store.beginPreparation(jobId, fingerprint, expiresAt.toString(), pin)
        val file = File(store.directory(lease), "synthetic.json").apply { writeText("{\"synthetic\":\"device storage\"}") }
        val accepted = ExportAccepted(jobId = jobId, acceptedAt = Instant.now().toString(),
            peerBinding = PeerBinding(UUID.randomUUID().toString(), UUID.randomUUID().toString()),
            productId = ProductId.GENERATED_FILES_V1, resolvedRange = ResolvedRange("2026-10-18", "2026-10-18", "America/Los_Angeles"),
            requestFingerprint = fingerprint)
        val manifest = ArtifactManifest(jobId = jobId, artifactId = "synthetic-file", kind = ArtifactKind.GENERATED_FILE,
            schema = ArtifactSchema("healthmd.generated-files", 1), mediaType = "application/json",
            byteCount = file.length(), sha256 = DirectJson.sha256Hex(file.readBytes()), relativePath = "2026-10-18.json", writeMode = FileWriteMode.OVERWRITE)
        val transfer = TransferPlanBuilder.build(accepted, listOf(manifest), mapOf(manifest.artifactId to file), createdAt = accepted.acceptedAt)
        return DirectJobJournal(requestFingerprint = fingerprint, expiresAt = expiresAt.toString(), transfer = transfer, enginePin = pin)
            .also { store.savePrepared(it, lease) }
    }

    private fun successorDirectory(root: File, journal: DirectJobJournal): File =
        File(root, "direct-cli/jobs-sleep-attribution-v6/${journal.transfer.accepted.jobId}")

    private fun snapshot(directory: File): Map<String, List<Byte>> = directory.walkTopDown().filter { it.isFile }
        .associate { it.relativeTo(directory).path to it.readBytes().toList() }

    private fun withStore(action: (DirectCliJobStore, File, () -> DirectCliJobStore) -> Unit) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val root = File(context.cacheDir, "direct-sleep-storage-${UUID.randomUUID()}").canonicalFile
        check(root.mkdirs())
        try {
            val isolated = object : ContextWrapper(context) {
                override fun getNoBackupFilesDir(): File = root
            }
            val reopen = { DirectCliJobStore(DirectCliTrustStore(isolated)) }
            action(reopen(), root, reopen)
        } finally {
            check(root.deleteRecursively() && !root.exists()) { "Unable to remove the isolated synthetic storage fixture." }
        }
    }
}
