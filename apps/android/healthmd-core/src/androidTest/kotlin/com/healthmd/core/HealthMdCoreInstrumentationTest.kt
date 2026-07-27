package com.healthmd.core

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HealthMdCoreInstrumentationTest {
    @Test
    fun packagedNativeCorePassesBuildInfoSelfTestAndStableMalformedInputError() {
        val service = HealthMdCoreService()

        val buildInfo = service.getBuildInfo()
        val selfTest = service.runSelfTest()
        val registry = service.getMetricRegistry(CoreMetricRegistryProfile.ANDROID_FROZEN_V4)

        assertThat(buildInfo.coreSourceRevision).isNotEmpty()
        assertThat(buildInfo.registrySha256).hasLength(64)
        assertThat(buildInfo.coreApiVersion).isEqualTo(4u)
        assertThat(buildInfo.semanticInputVersion).isEqualTo(1u)
        assertThat(buildInfo.canonicalModelVersion).isEqualTo(1u)
        assertThat(buildInfo.registryVersion).isEqualTo(1u)
        assertThat(buildInfo.renderInputVersion).isEqualTo(1u)
        assertThat(buildInfo.artifactPlanVersion).isEqualTo(1u)
        assertThat(buildInfo.renderProfileRevision).isEqualTo(1u)
        assertThat(buildInfo.persistedStateVersion).isEqualTo(1u)
        assertThat(selfTest.passed).isTrue()
        assertThat(selfTest.buildInfo).isEqualTo(buildInfo)
        assertThat(registry.registrySha256).isEqualTo(buildInfo.registrySha256)
        assertThat(registry.metrics).hasSize(106)
        assertThat(registry.unavailableMetrics).hasSize(102)
        assertThat(registry.outputs).hasSize(161)

        val error = try {
            service.validateFixture("{}".encodeToByteArray(), "malformed-digest")
            throw AssertionError("Malformed digest unexpectedly succeeded")
        } catch (error: HealthMdCoreServiceException) {
            error
        }
        assertThat(error.code).isEqualTo(HealthMdCoreErrorCode.INVALID_FIXTURE_DIGEST)
        assertThat(error.message).isEqualTo("fixture digest must be lowercase SHA-256")

        val configuration = """
            {"schema":"healthmd.semantic_session_config","semantic_input_version":1,"canonical_model_version":1,"registry_version":1,"registry_sha256":"${buildInfo.registrySha256}","profile_revision":1,"session_id":"android-core-instrumentation","profile":"android_frozen_v4","calendar_time_zone":"UTC","selected_selection_ids":["steps"],"disabled_output_keys":[],"retain_platform_extensions":false,"rollup_periods":[]}
        """.trimIndent().encodeToByteArray()
        service.createSemanticSession(configuration).use { session ->
            val batch = """
                {"schema":"healthmd.semantic_input","semantic_input_version":1,"session_id":"android-core-instrumentation","batch_index":0,"final_batch":true,"owner_dates":[],"records":[]}
            """.trimIndent().encodeToByteArray()
            val semanticResult = session.processBatch(batch).decodeToString()
            assertThat(semanticResult).contains("\"state\":\"completed\"")
            assertThat(semanticResult).contains("\"canonical_model_version\":1")
        }
    }

    @Test
    fun packagedProtocolFoundationMatchesPureV1V2CryptoAndTransferFixtures() {
        val service = HealthMdCoreService()
        val info = service.getDirectProtocolInfo()
        assertThat(info.protocolApiRevision).isEqualTo(1u)
        assertThat(info.directPairingProtocolVersion).isEqualTo(1u)
        assertThat(info.supportedPairingProtocolVersions).containsExactly(1u, 2u).inOrder()
        assertThat(info.appleApplicationProtocolVersion).isEqualTo(1u)
        assertThat(info.androidApplicationProtocolVersion).isEqualTo(2u)
        assertThat(info.maximumChunkBytes).isEqualTo(512uL * 1_024uL)

        val v1Request = decodeBase64(V1_REQUEST_BASE64)
        assertThat(service.fingerprintAppleV1Request(v1Request)).isEqualTo(
            "b5e762d7e2c4533909c2416814a816347c3624b8254bbbe8dd906cf34b48493a",
        )
        val v2Request = decodeBase64(V2_REQUEST_BASE64)
        assertThat(service.fingerprintAndroidV2Request(v2Request)).isEqualTo(
            "04be99c9a9aa5ee13c49063032109dafd9c864386f9890809b0111dd6ddfed33",
        )
        val envelope = decodeBase64(V2_ENVELOPE_BASE64)
        assertThat(service.canonicalizeAndroidV2Envelope(envelope).contentEquals(envelope)).isTrue()

        val frame = decodeBase64(BINARY_FRAME_BASE64)
        val chunk = service.decodeTransferChunk(frame)
        assertThat(chunk.transferId).isEqualTo("11111111-2222-4333-8444-555555555555")
        assertThat(chunk.sequence).isEqualTo(1uL)
        assertThat(chunk.chunkBytes.contentEquals(ByteArray(32) { 0xab.toByte() })).isTrue()
        assertThat(service.encodeTransferChunk(chunk).contentEquals(frame)).isTrue()

        val capabilities = service.getDefaultTransferCapabilities()
        val negotiation = service.negotiateTransfer(capabilities, capabilities)
        assertThat(negotiation.partitionTargetBytes).isEqualTo(48uL * 1_024uL * 1_024uL)
        assertThat(negotiation.maximumInFlightChunks).isEqualTo(4u)

        val applePairingCode = "123456".encodeToByteArray()
        val androidPairingCode = "12345678901234567890".encodeToByteArray()
        val sharedSecret = decodeHex(
            "9663aa1da97e848a914a436d04163dfbb89178f107f1b5b77ed3854203382854",
        )
        val clientNonce = ByteArray(32) { (0x40 + it).toByte() }
        val serverNonce = ByteArray(32) { (0x60 + it).toByte() }
        try {
            assertThat(
                service.verifyPairingClientTranscript(
                    CoreDirectPairingVerifierRequest(
                        profile = CoreDirectPairingProfile.APPLE_V1,
                        pairingCodeBytes = applePairingCode,
                        clientInstallationId = "abcdefab-cdef-4abc-8def-abcdefabcdef",
                        clientPublicKey = decodeHex(
                            "8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f",
                        ),
                        clientNonce = clientNonce,
                        expectedVerifier = decodeHex(
                            "9dadfaf54d6729b004aa0a6344f7df42b4de0093cbf5cca6fe62376acbad00df",
                        ),
                    ),
                ),
            ).isTrue()
            assertThat(
                service.verifyPairingClientTranscript(
                    CoreDirectPairingVerifierRequest(
                        profile = CoreDirectPairingProfile.ANDROID_V2,
                        pairingCodeBytes = androidPairingCode,
                        clientInstallationId = "abcdefab-cdef-4abc-8def-abcdefabcdef",
                        clientPublicKey = decodeHex(
                            "8f40c5adb68f25624ae5b214ea767a6ec94d829d3d7b5e1ad1ba6f3e2138285f",
                        ),
                        clientNonce = clientNonce,
                        expectedVerifier = decodeHex(
                            "d312c74ebee3ab1c2a8c1f85568cfc95ae6cf0e3aad4e30ece3de850b262288c",
                        ),
                    ),
                ),
            ).isTrue()
            val key = service.deriveSessionKey(
                CoreDirectSessionKeyRequest(sharedSecret, clientNonce, serverNonce),
            )
            try {
                assertThat(key.contentEquals(decodeHex(SESSION_KEY_HEX))).isTrue()
            } finally {
                key.fill(0)
            }
        } finally {
            applePairingCode.fill(0)
            androidPairingCode.fill(0)
            sharedSecret.fill(0)
            clientNonce.fill(0)
            serverNonce.fill(0)
        }

        val error = try {
            service.fingerprintAppleV1Request(" private-health-value".encodeToByteArray())
            throw AssertionError("Malformed protocol JSON unexpectedly succeeded")
        } catch (error: HealthMdProtocolServiceException) {
            error
        }
        assertThat(error.code).isEqualTo(HealthMdProtocolErrorCode.INVALID_JSON)
        assertThat(error.message).isEqualTo("protocol JSON is invalid")
        assertThat(error.message).doesNotContain("private-health-value")
    }

    private fun decodeBase64(value: String): ByteArray = java.util.Base64.getDecoder().decode(value)

    private fun decodeHex(value: String): ByteArray = value.chunked(2)
        .map { it.toInt(16).toByte() }
        .toByteArray()

    companion object {
        private const val V1_REQUEST_BASE64 = "eyJjYW5vbmljYWxTZWxlY3Rpb24iOnsiYWxsTWV0cmljcyI6ZmFsc2UsImNhdGVnb3JpZXMiOlsiU2xlZXAiXSwiZGV0YWlsTGV2ZWwiOiJzdW1tYXJ5IiwiZmllbGRQb2ludGVycyI6W10sIm1ldHJpY0lEcyI6WyJzbGVlcF90b3RhbCJdLCJvYmplY3RQYXRocyI6WyIvc2xlZXAiXSwic291cmNlSURzIjpbImFwcGxlX2hlYWx0aCJdfSwiY3JlYXRlZEF0IjoiMjAyMy0xMS0xNFQyMjoxMzoyMFoiLCJkYXRlU2VsZWN0aW9uIjp7ImV4YWN0Ijp7ImVuZCI6IjIwMjYtMDctMDciLCJzdGFydCI6IjIwMjYtMDctMDEifX0sImpvYklEIjoiMDAwMDAwMDAtMDAwMC00MDAwLTgwMDAtMDAwMDAwMDAwMDAxIiwicHJvdG9jb2xWZXJzaW9uIjoxLCJyYXdQcm9maWxlIjoiaGVhbHRoX2RhdGFfcHJvamVjdGlvbiIsInJlc3BvbnNlTW9kZSI6InJhd19qc29uIiwic2V0dGluZ3NQb2xpY3kiOiJyZXF1ZXN0ZWRfZGF0ZXNfb25seSJ9"
        private const val V2_REQUEST_BASE64 = "eyJjcmVhdGVkX2F0IjoiMjAyNi0wNy0yNFQxMDoxMToxMloiLCJkYXRlX3NlbGVjdGlvbiI6eyJlbmRfZGF0ZSI6IjIwMjYtMDctMDIiLCJzdGFydF9kYXRlIjoiMjAyNi0wNy0wMSIsInR5cGUiOiJleGFjdCJ9LCJleHBpcmVzX2F0IjoiMjAyNi0wNy0zMVQxMDoxMToxMloiLCJqb2JfaWQiOiJhYWFhYWFhYS1iYmJiLTRjY2MtOGRkZC1lZWVlZWVlZWVlZWUiLCJwcm9kdWN0Ijp7ImZvcm1hdCI6Im5kanNvbiIsImluY2x1ZGVfZXhlcmNpc2Vfcm91dGVzIjpmYWxzZSwicHJvZHVjdF9pZCI6ImFuZHJvaWRfcHJvdmlkZXJfbmF0aXZlX3NuYXBzaG90X3YxIiwicHJvdmlkZXJfaWQiOiJoZWFsdGhfY29ubmVjdCIsInNjb3BlIjp7InNlbGVjdGVkX21ldHJpY19pZHMiOlsic2xlZXAiLCJzdGVwcyJdLCJ0eXBlIjoic2VsZWN0ZWRfcmVjb3JkX3R5cGVzIn19LCJzb3VyY2VfaW5zdGFsbGF0aW9uX2lkIjoiMTExMTExMTEtMjIyMi00MzMzLTg0NDQtNTU1NTU1NTU1NTU1In0="
        private const val V2_ENVELOPE_BASE64 = "eyJwYXlsb2FkIjp7InJlcXVlc3RlZF9hdCI6IjIwMjYtMDctMjRUMTA6MTE6MTJaIn0sInByb3RvY29sX3ZlcnNpb24iOjIsInR5cGUiOiJzdGF0dXNfcmVxdWVzdCJ9"
        private const val BINARY_FRAME_BASE64 = "SE1ERElSQ1QAAREREREiIkMzhERVVVVVVVUAAAABAAAAIJotsuI/FQTNBWYGVTrAScXnGOj5zpIzh23xp6GCGviFq6urq6urq6urq6urq6urq6urq6urq6urq6urq6urq6s="
        private const val SESSION_KEY_HEX = "47cea6b163b799c16e44a750893eab311521060a7266a59ec054d53f71b698e9"
    }
}
