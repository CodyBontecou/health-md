package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class SharedPairingV3InteropTest {
    private val fixture = DirectJson.json.parseToJsonElement(
        requireNotNull(javaClass.getResource("/shared-pairing-v3.json")).readText(),
    ).jsonObject

    @Test
    fun sharedPairingCryptoAndQrMatchCanonicalFixture() {
        assertThat(text("pairing_protocol_version").toInt())
            .isEqualTo(SHARED_PAIRING_PROTOCOL_VERSION)
        val code = text("pairing_code")
        val clientId = text("client_installation_id")
        val clientPublic = hex("client_public_key_hex")
        val clientNonce = hex("client_nonce_hex")
        val serverId = text("server_installation_id")
        val serverPublic = hex("server_public_key_hex")
        val serverNonce = hex("server_nonce_hex")
        val sealed = CryptoFrame(
            nonce = hex("sealed_nonce_hex"),
            ciphertext = hex("sealed_ciphertext_hex"),
            tag = hex("sealed_tag_hex"),
        )

        assertThat(
            DirectCrypto.sharedPairingVerifier(code, clientId, clientPublic, clientNonce),
        ).isEqualTo(hex("pairing_client_verifier_hex"))
        assertThat(
            DirectCrypto.sharedPairingServerVerifier(
                code,
                clientId,
                clientPublic,
                clientNonce,
                serverId,
                serverPublic,
                serverNonce,
                sealed,
            ),
        ).isEqualTo(hex("pairing_server_verifier_hex"))
        assertThat(text("qr_payload")).isEqualTo(
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=12345678901234567890",
        )
    }

    private fun text(name: String): String = fixture.getValue(name).jsonPrimitive.content

    private fun hex(name: String): ByteArray = text(name)
        .chunked(2)
        .map { it.toInt(16).toByte() }
        .toByteArray()
}
