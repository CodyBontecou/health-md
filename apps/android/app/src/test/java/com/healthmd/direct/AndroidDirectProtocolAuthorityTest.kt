package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.CoreDirectTransferCapabilities
import com.healthmd.core.CoreDirectTransferChunk
import com.healthmd.core.CoreDirectTransferNegotiation
import com.healthmd.core.HealthMdCoreService
import com.healthmd.direct.protocol.ArtifactFormat
import com.healthmd.direct.protocol.ExportRequest
import com.healthmd.direct.protocol.V2Codec
import java.time.Instant
import org.junit.Test

class AndroidDirectProtocolAuthorityTest {
    @Test
    fun legacyDoesNotLoadRustAndReturnsNativeValues() {
        val authority = AndroidDirectProtocolAuthority(
            AndroidDirectProtocolEngineMode.legacy,
            lazy { error("legacy must not load Rust") },
        )
        authority.assertCompatible()
        val request = request()
        assertThat(authority.requestFingerprint(request)).isEqualTo(V2Codec.requestFingerprint(request))
        val bytes = "native".encodeToByteArray()
        assertThat(authority.canonicalizeV2Envelope(bytes)).isSameInstanceAs(bytes)
        assertThat(authority.comparisonSnapshot().comparisons).isEmpty()
    }

    @Test
    fun shadowReturnsNativeAndRecordsOnlyHealthFreeMismatchCounts() {
        val fake = FakeRustCore().apply {
            fingerprintResult = "f".repeat(64)
            canonicalResult = "rust".encodeToByteArray()
            frameResult = "rust-frame".encodeToByteArray()
        }
        val authority = AndroidDirectProtocolAuthority(
            AndroidDirectProtocolEngineMode.shadow,
            lazy { fake },
        )
        authority.assertCompatible()

        val request = request()
        assertThat(authority.requestFingerprint(request)).isEqualTo(V2Codec.requestFingerprint(request))
        val envelope = "native-envelope".encodeToByteArray()
        assertThat(authority.canonicalizeV2Envelope(envelope)).isSameInstanceAs(envelope)
        val frame = "native-frame".encodeToByteArray()
        assertThat(
            authority.encodeTransferFrame(
                "11111111-2222-4333-8444-555555555555",
                1,
                byteArrayOf(1),
                frame,
            ),
        ).isSameInstanceAs(frame)

        val evidence = authority.comparisonSnapshot()
        assertThat(evidence.comparisons[AndroidDirectProtocolStage.compatibility]).isEqualTo(1)
        assertThat(evidence.mismatches[AndroidDirectProtocolStage.compatibility]).isNull()
        assertThat(evidence.mismatches[AndroidDirectProtocolStage.requestFingerprint]).isEqualTo(1)
        assertThat(evidence.mismatches[AndroidDirectProtocolStage.v2Envelope]).isEqualTo(1)
        assertThat(evidence.mismatches[AndroidDirectProtocolStage.transferFrame]).isEqualTo(1)
    }

    @Test
    fun rustIsAuthoritativeAndNeverFallsBack() {
        val fake = FakeRustCore().apply {
            fingerprintResult = "a".repeat(64)
            canonicalResult = "rust".encodeToByteArray()
        }
        val authority = AndroidDirectProtocolAuthority(
            AndroidDirectProtocolEngineMode.rust,
            lazy { fake },
        )
        authority.assertCompatible()
        assertThat(authority.requestFingerprint(request())).isEqualTo("a".repeat(64))
        assertThat(authority.canonicalizeV2Envelope("native".encodeToByteArray()))
            .isEqualTo("rust".encodeToByteArray())

        fake.throwCanonical = true
        val error = runCatching {
            authority.canonicalizeV2Envelope("private-health-value".encodeToByteArray())
        }.exceptionOrNull()
        assertThat(error).isInstanceOf(AndroidDirectProtocolAuthorityException::class.java)
        assertThat(error?.message).doesNotContain("private-health-value")
    }

    @Test
    fun transferNegotiationMatchesNativeAndRustRecords() {
        val fake = FakeRustCore()
        val authority = AndroidDirectProtocolAuthority(
            AndroidDirectProtocolEngineMode.rust,
            lazy { fake },
        )
        val negotiated = requireNotNull(authority.negotiateTransfer(com.healthmd.direct.protocol.TransferCapabilities()))
        assertThat(negotiated.protocolVersion).isEqualTo(1)
        assertThat(negotiated.binaryFrameVersion).isEqualTo(1)
        assertThat(negotiated.partitionTargetBytes).isEqualTo(48L * 1_024 * 1_024)
        assertThat(negotiated.maximumInFlightChunks).isEqualTo(4)
    }

    private fun request() = ExportRequest(
        jobId = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
        createdAt = Instant.parse("2026-07-24T10:11:12Z").toString(),
        expiresAt = Instant.parse("2026-07-31T10:11:12Z").toString(),
        sourceInstallationId = "11111111-2222-4333-8444-555555555555",
        dateSelection = V2Codec.exactDateSelection("2026-07-01", "2026-07-02"),
        product = V2Codec.rawSnapshotProduct(
            providerId = "health_connect",
            format = ArtifactFormat.NDJSON,
            selectedMetricIds = listOf("sleep", "steps"),
            includeExerciseRoutes = false,
        ),
    )

    private class FakeRustCore : AndroidDirectProtocolRustCore {
        var fingerprintResult = "0".repeat(64)
        var canonicalResult = ByteArray(0)
        var frameResult = ByteArray(0)
        var throwCanonical = false

        override fun buildInfo() = AndroidDirectProtocolBuildInfo(
            coreApiVersion = HealthMdCoreService.EXPECTED_CORE_API_VERSION,
            crateVersion = "0.1.0-test",
            coreSourceRevision = "test-revision",
        )

        override fun protocolInfo() = AndroidDirectProtocolInfo(
            protocolApiRevision = 1u,
            supportedPairingProtocolVersions = listOf(1u, 2u, 3u),
            androidApplicationProtocolVersion = 2u,
            manualIpPort = 17_647u,
            maximumControlJsonBytes = (2 * 1_024 * 1_024).toULong(),
            transferProtocolVersion = 1u,
            transferFrameHeaderBytes = 66uL,
            maximumChunkBytes = (512 * 1_024).toULong(),
            minimumPartitionBytes = (32L * 1_024 * 1_024).toULong(),
            preferredPartitionBytes = (48L * 1_024 * 1_024).toULong(),
            maximumPartitionBytes = (64L * 1_024 * 1_024).toULong(),
            maximumInFlightChunks = 4u,
            durableJobLifetimeSeconds = (7L * 24 * 60 * 60).toULong(),
        )

        override fun fingerprintAndroidV2Request(bytes: ByteArray): String = fingerprintResult

        override fun canonicalizeAndroidV2Envelope(bytes: ByteArray): ByteArray {
            if (throwCanonical) error("private-health-value")
            return canonicalResult
        }

        override fun encodeTransferChunk(chunk: CoreDirectTransferChunk): ByteArray = frameResult

        override fun negotiateTransfer(
            local: CoreDirectTransferCapabilities,
            peer: CoreDirectTransferCapabilities,
        ) = CoreDirectTransferNegotiation(
            protocolVersion = 1u,
            binaryFrameVersion = 1u,
            partitionTargetBytes = 48uL * 1_024uL * 1_024uL,
            maximumInFlightChunks = 4u,
        )
    }
}
