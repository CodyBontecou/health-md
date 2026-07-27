package com.healthmd.core

import com.google.common.truth.Truth.assertThat
import java.nio.ByteBuffer
import org.junit.Test

class HealthMdCoreServiceTest {
    @Test
    fun constructingServiceDoesNotLoadNativeLibrary() {
        val service = HealthMdCoreService()

        assertThat(service).isNotNull()
    }

    @Test
    fun readinessRequiresMatchingVersionsAndPassingSelfTest() {
        val info = compatibleBuildInfo()
        val fixture = FixtureValidation(
            fixtureFormatVersion = 1u,
            byteCount = 42u,
            sha256 = "a".repeat(64),
        )
        val service = HealthMdCoreService(
            lazyOf(
                FakeBindings(
                    buildInfo = info,
                    selfTest = CoreSelfTestReport(
                        passed = true,
                        buildInfo = info,
                        fixture = fixture,
                    ),
                ),
            ),
        )

        val readiness = service.checkReadiness()

        assertThat(readiness.isReady).isTrue()
        assertThat(readiness.buildInfo).isEqualTo(info)
        assertThat(readiness.selfTest.fixture).isEqualTo(fixture)
    }

    @Test
    fun protocolWrapperPassesOwnedFixtureBytesAndMasksUnexpectedFailures() {
        val info = CoreDirectProtocolInfo(
            protocolApiRevision = 1u,
            directPairingProtocolVersion = 1u,
            supportedPairingProtocolVersions = listOf(1u, 2u),
            appleApplicationProtocolVersion = 1u,
            androidApplicationProtocolVersion = 2u,
            manualIpPort = 17_647u,
            maximumControlJsonBytes = 2uL * 1_024uL * 1_024uL,
            transferProtocolVersion = 1u,
            transferFrameHeaderBytes = 66uL,
            maximumChunkBytes = 512uL * 1_024uL,
            maximumTransferFrameBytes = 512uL * 1_024uL + 66uL,
            minimumPartitionBytes = 32uL * 1_024uL * 1_024uL,
            preferredPartitionBytes = 48uL * 1_024uL * 1_024uL,
            maximumPartitionBytes = 64uL * 1_024uL * 1_024uL,
            preferredInFlightChunks = 4u,
            maximumInFlightChunks = 8u,
            pairingCodeLifetimeSeconds = 600uL,
            durableJobLifetimeSeconds = 604_800uL,
        )
        val fixture = "{\"protocolVersion\":1}".encodeToByteArray()
        val fingerprint = "a".repeat(64)
        val compatible = compatibleBuildInfo()
        val service = HealthMdCoreService(
            lazyOf(
                FakeBindings(
                    buildInfo = compatible,
                    selfTest = CoreSelfTestReport(
                        true,
                        compatible,
                        FixtureValidation(1u, 0u, fingerprint),
                    ),
                    directProtocolInfo = info,
                    appleFingerprintFixture = fixture,
                    appleFingerprint = fingerprint,
                ),
            ),
        )

        assertThat(service.getDirectProtocolInfo()).isEqualTo(info)
        assertThat(service.fingerprintAppleV1Request(fixture)).isEqualTo(fingerprint)

        val error = try {
            service.fingerprintAndroidV2Request(fixture)
            throw AssertionError("Unexpected protocol call succeeded")
        } catch (error: HealthMdProtocolServiceException) {
            error
        }
        assertThat(error.code).isEqualTo(HealthMdProtocolErrorCode.INTERNAL_PANIC)
        assertThat(error.message).isEqualTo("shared protocol core failed internally")
        assertThat(error.message).doesNotContain("fixture")
    }

    @Test
    fun readinessFailsClosedOnBindingVersionDrift() {
        val nativeInfo = compatibleBuildInfo().copy(coreApiVersion = 5u)
        val service = HealthMdCoreService(
            lazyOf(
                FakeBindings(
                    buildInfo = nativeInfo,
                    selfTest = CoreSelfTestReport(
                        passed = true,
                        buildInfo = nativeInfo,
                        fixture = FixtureValidation(1u, 0u, "a".repeat(64)),
                    ),
                ),
            ),
        )

        assertThat(service.checkReadiness().isReady).isFalse()
    }

    private fun compatibleBuildInfo() = CoreBuildInfo(
        crateVersion = "0.1.0-alpha.1",
        coreSourceRevision = "test-revision",
        registrySha256 = "a".repeat(64),
        coreApiVersion = HealthMdCoreService.EXPECTED_CORE_API_VERSION,
        semanticInputVersion = HealthMdCoreService.EXPECTED_SEMANTIC_INPUT_VERSION,
        canonicalModelVersion = HealthMdCoreService.EXPECTED_CANONICAL_MODEL_VERSION,
        registryVersion = HealthMdCoreService.EXPECTED_REGISTRY_VERSION,
        renderInputVersion = HealthMdCoreService.EXPECTED_RENDER_INPUT_VERSION,
        artifactPlanVersion = HealthMdCoreService.EXPECTED_ARTIFACT_PLAN_VERSION,
        renderProfileRevision = HealthMdCoreService.EXPECTED_RENDER_PROFILE_REVISION,
        persistedStateVersion = HealthMdCoreService.EXPECTED_PERSISTED_STATE_VERSION,
    )

    private class FakeBindings(
        private val buildInfo: CoreBuildInfo,
        private val selfTest: CoreSelfTestReport,
        private val directProtocolInfo: CoreDirectProtocolInfo? = null,
        private val appleFingerprintFixture: ByteArray? = null,
        private val appleFingerprint: String? = null,
    ) : HealthMdCoreBindings {
        override fun getBuildInfo(): CoreBuildInfo = buildInfo

        override fun runSelfTest(): CoreSelfTestReport = selfTest

        override fun getDirectProtocolInfo(): CoreDirectProtocolInfo =
            checkNotNull(directProtocolInfo) { "private fixture protocol info is unavailable" }

        override fun fingerprintAppleV1DirectRequest(requestBytes: ByteBuffer): String {
            val actual = ByteArray(requestBytes.remaining()).also(requestBytes::get)
            val expected = checkNotNull(appleFingerprintFixture)
            check(actual.contentEquals(expected)) { "private fixture request did not match" }
            return checkNotNull(appleFingerprint)
        }

        override fun fingerprintAndroidV2DirectRequest(requestBytes: ByteBuffer): String =
            error("Android fingerprint not used by this test")

        override fun canonicalizeAppleV1DirectMessage(messageBytes: ByteBuffer): ByteArray =
            error("Apple message not used by this test")

        override fun canonicalizeAndroidV2DirectEnvelope(envelopeBytes: ByteBuffer): ByteArray =
            error("Android envelope not used by this test")

        override fun encodeDirectTransferChunk(chunk: CoreDirectTransferChunk): ByteArray =
            error("transfer encode not used by this test")

        override fun decodeDirectTransferChunk(frameBytes: ByteBuffer): CoreDirectTransferChunk =
            error("transfer decode not used by this test")

        override fun getDefaultDirectTransferCapabilities(): CoreDirectTransferCapabilities =
            error("transfer capabilities not used by this test")

        override fun negotiateDirectTransfer(
            local: CoreDirectTransferCapabilities,
            peer: CoreDirectTransferCapabilities,
        ): CoreDirectTransferNegotiation = error("transfer negotiation not used by this test")

        override fun verifyDirectPairingClientTranscript(
            request: CoreDirectPairingVerifierRequest,
        ): Boolean = error("pairing verifier not used by this test")

        override fun deriveDirectSessionKey(request: CoreDirectSessionKeyRequest): ByteArray =
            error("session key not used by this test")

        override fun getMetricRegistry(
            profile: CoreMetricRegistryProfile,
            expectedRegistryVersion: UInt,
        ): CoreMetricRegistrySnapshot = error("registry not used by this test")

        override fun createSemanticSession(configBytes: ByteBuffer): CoreSemanticSession =
            error("semantic session not used by this test")

        override fun createRenderSession(
            configBytes: ByteBuffer,
            semanticResultBytes: ByteBuffer,
        ): CoreRenderSession = error("render session not used by this test")

        override fun createLosslessArtifactStream(mode: CoreStreamMode): CoreLosslessArtifactStream =
            error("stream not used by this test")

        override fun createPlannedLosslessArtifactStream(
            mode: CoreStreamMode,
            artifact: CoreStreamArtifactConfig,
        ): CoreLosslessArtifactStream = error("planned stream not used by this test")

        override fun mergeProfileRenderedMarkdown(
            profile: CoreMetricRegistryProfile,
            existing: String,
            generated: String,
            preservePreamble: Boolean,
        ): String = error("profile merge not used by this test")

        override fun mergeRenderedMarkdown(existing: String, generated: String): String =
            error("merge not used by this test")

        override fun validateFixture(
            fixtureBytes: ByteBuffer,
            expectedSha256: String,
        ): FixtureValidation = selfTest.fixture
    }
}
