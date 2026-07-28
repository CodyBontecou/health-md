package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import java.util.Base64
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class InteroperabilityTest {
    private val fixture = DirectJson.json.parseToJsonElement(
        requireNotNull(javaClass.getResource("/rust-direct-v2.json")).readText(),
    ).jsonObject

    @Test
    fun cryptoMatchesRustVectors() {
        val clientPrivate = hex("client_private_key_hex")
        val clientPublic = hex("client_public_key_hex")
        val serverPrivate = hex("server_private_key_hex")
        val serverPublic = hex("server_public_key_hex")
        val clientNonce = hex("client_nonce_hex")
        val serverNonce = hex("server_nonce_hex")
        val reconnectSecret = hex("reconnect_secret_hex")
        val pairingCode = text("pairing_code")
        val clientId = "abcdefab-cdef-4abc-8def-abcdefabcdef"
        val serverId = "01234567-89ab-4cde-8fab-0123456789ab"

        assertThat(DirectCrypto.publicKey(clientPrivate)).isEqualTo(clientPublic)
        assertThat(DirectCrypto.publicKey(serverPrivate)).isEqualTo(serverPublic)
        val shared = DirectCrypto.sharedSecret(clientPrivate, serverPublic)
        assertThat(shared).isEqualTo(hex("shared_secret_hex"))
        assertThat(DirectCrypto.pairingCodeKey(pairingCode)).isEqualTo(hex("pairing_code_key_hex"))
        assertThat(
            DirectCrypto.pairingVerifier(pairingCode, clientId, clientPublic, clientNonce),
        ).isEqualTo(hex("pairing_verifier_hex"))

        val sessionKey = DirectCrypto.sessionKey(shared, clientNonce, serverNonce)
        assertThat(sessionKey).isEqualTo(hex("session_key_hex"))
        val sealed = DirectCrypto.sealWithNonce(reconnectSecret, sessionKey, hex("sealed_nonce_hex"))
        assertThat(sealed.ciphertext).isEqualTo(hex("sealed_ciphertext_hex"))
        assertThat(sealed.tag).isEqualTo(hex("sealed_tag_hex"))
        assertThat(DirectCrypto.open(sealed, sessionKey)).isEqualTo(reconnectSecret)
        assertThat(
            DirectCrypto.pairingServerVerifier(
                pairingCode,
                clientId,
                clientPublic,
                clientNonce,
                serverId,
                serverPublic,
                serverNonce,
                sealed,
            ),
        ).isEqualTo(hex("pairing_server_verifier_hex"))
        val androidCode = text("android_pairing_code")
        assertThat(
            DirectCrypto.androidPairingVerifier(androidCode, clientId, clientPublic, clientNonce),
        ).isEqualTo(hex("android_pairing_verifier_hex"))
        assertThat(
            DirectCrypto.androidPairingServerVerifier(
                androidCode,
                clientId,
                clientPublic,
                clientNonce,
                serverId,
                serverPublic,
                serverNonce,
                sealed,
            ),
        ).isEqualTo(hex("android_pairing_server_verifier_hex"))
        assertThat(
            DirectCrypto.trustedClientVerifier(reconnectSecret, clientId, clientPublic, clientNonce),
        ).isEqualTo(hex("trusted_client_verifier_hex"))
        assertThat(
            DirectCrypto.trustedServerVerifier(
                reconnectSecret,
                clientId,
                clientPublic,
                clientNonce,
                serverId,
                serverPublic,
                serverNonce,
            ),
        ).isEqualTo(hex("trusted_server_verifier_hex"))
    }

    @Test
    fun canonicalRequestAndFingerprintMatchRust() {
        val request = ExportRequest(
            jobId = "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee",
            createdAt = "2026-07-24T10:11:12Z",
            expiresAt = "2026-07-31T10:11:12Z",
            sourceInstallationId = "11111111-2222-4333-8444-555555555555",
            dateSelection = V2Codec.exactDateSelection("2026-07-01", "2026-07-02"),
            product = V2Codec.rawSnapshotProduct(
                providerId = "health_connect",
                format = ArtifactFormat.NDJSON,
                selectedMetricIds = listOf("sleep", "steps"),
                includeExerciseRoutes = false,
            ),
        )
        val requestBytes = DirectJson.canonicalBytes(
            DirectJson.json.encodeToJsonElement(ExportRequest.serializer(), request),
        )
        assertThat(requestBytes).isEqualTo(Base64.getDecoder().decode(text("request_json_base64")))
        assertThat(V2Codec.requestFingerprint(request)).isEqualTo(text("request_fingerprint"))
    }

    @Test
    fun statusEnvelopeMatchesRust() {
        val bytes = V2Codec.encode(
            "status_request",
            StatusRequest.serializer(),
            StatusRequest("2026-07-24T10:11:12Z"),
        )
        assertThat(bytes).isEqualTo(
            Base64.getDecoder().decode(text("status_request_envelope_json_base64")),
        )
        val decoded = V2Codec.decode(bytes)
        assertThat(decoded.type).isEqualTo("status_request")
        assertThat(V2Codec.decodePayload(decoded, StatusRequest.serializer()).requestedAt)
            .isEqualTo("2026-07-24T10:11:12Z")
    }

    @Test
    fun binaryFrameUsesDeployedLayout() {
        val data = ByteArray(32) { 0xab.toByte() }
        val frame = BinaryTransferFrame.encode(
            "11111111-2222-4333-8444-555555555555",
            1,
            data,
        )
        assertThat(frame.copyOfRange(0, 8).toString(Charsets.US_ASCII)).isEqualTo("HMDDIRCT")
        assertThat(frame.size).isEqualTo(66 + data.size)
    }

    private fun text(key: String): String = fixture.getValue(key).jsonPrimitive.content

    private fun hex(key: String): ByteArray = text(key).chunked(2).map { it.toInt(16).toByte() }.toByteArray()
}
