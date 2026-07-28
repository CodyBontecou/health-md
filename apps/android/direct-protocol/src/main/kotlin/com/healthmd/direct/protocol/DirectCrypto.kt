package com.healthmd.direct.protocol

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.security.SecureRandom
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import org.bouncycastle.crypto.InvalidCipherTextException
import org.bouncycastle.crypto.modes.ChaCha20Poly1305
import org.bouncycastle.crypto.params.AEADParameters
import org.bouncycastle.crypto.params.KeyParameter
import org.bouncycastle.crypto.params.X25519PrivateKeyParameters
import org.bouncycastle.crypto.params.X25519PublicKeyParameters

private val CODE_DOMAIN = "HealthMd.DirectCLI.Code.".toByteArray(StandardCharsets.UTF_8)
private val ANDROID_CODE_DOMAIN = "HealthMd.DirectCLI.Code.v2.".toByteArray(StandardCharsets.UTF_8)
private val PAIRING_DOMAIN = "HealthMd.DirectCLI.PairingVerifier.v1".toByteArray(StandardCharsets.UTF_8)
private val ANDROID_PAIRING_DOMAIN = "HealthMd.DirectCLI.PairingVerifier.v2".toByteArray(StandardCharsets.UTF_8)
private val SESSION_DOMAIN = "HealthMd.DirectCLI.SessionKey.v1".toByteArray(StandardCharsets.UTF_8)
private val TRUSTED_CLIENT_DOMAIN = "HealthMd.DirectCLI.TrustedClient.v1".toByteArray(StandardCharsets.UTF_8)
private val PAIRING_SERVER_DOMAIN = "HealthMd.DirectCLI.PairingServer.v1".toByteArray(StandardCharsets.UTF_8)
private val ANDROID_PAIRING_SERVER_DOMAIN = "HealthMd.DirectCLI.PairingServer.v2".toByteArray(StandardCharsets.UTF_8)
private val TRUSTED_SERVER_DOMAIN = "HealthMd.DirectCLI.TrustedServer.v1".toByteArray(StandardCharsets.UTF_8)

data class CryptoFrame(
    val nonce: ByteArray,
    val ciphertext: ByteArray,
    val tag: ByteArray,
)

data class EphemeralKeyPair(
    val privateKey: ByteArray,
    val publicKey: ByteArray,
)

object DirectCrypto {
    private val random = SecureRandom()

    fun ephemeralKeyPair(): EphemeralKeyPair {
        val privateKey = ByteArray(32).also(random::nextBytes)
        return EphemeralKeyPair(privateKey, publicKey(privateKey))
    }

    fun publicKey(privateKey: ByteArray): ByteArray {
        require(privateKey.size == 32) { "Invalid X25519 private key." }
        return X25519PrivateKeyParameters(privateKey, 0).generatePublicKey().encoded
    }

    fun randomBytes(count: Int): ByteArray = ByteArray(count).also(random::nextBytes)

    fun sharedSecret(privateKey: ByteArray, peerPublicKey: ByteArray): ByteArray {
        require(privateKey.size == 32 && peerPublicKey.size == 32) { "Invalid X25519 key material." }
        val secret = ByteArray(32)
        X25519PrivateKeyParameters(privateKey, 0).generateSecret(
            X25519PublicKeyParameters(peerPublicKey, 0),
            secret,
            0,
        )
        require(!constantTimeEquals(secret, ByteArray(32))) { "Invalid X25519 shared secret." }
        return secret
    }

    fun pairingCodeKey(pairingCode: String): ByteArray = pairingCodeKey(pairingCode, CODE_DOMAIN)

    private fun pairingCodeKey(pairingCode: String, domain: ByteArray): ByteArray = sha256(
        domain + pairingCode.filter { it in '0'..'9' }.toByteArray(StandardCharsets.US_ASCII),
    )

    fun pairingVerifier(
        pairingCode: String,
        clientInstallationId: String,
        clientPublicKey: ByteArray,
        clientNonce: ByteArray,
    ): ByteArray = hmacSha256(
        pairingCodeKey(pairingCode),
        transcript(
            PAIRING_DOMAIN,
            clientInstallationId.lowercase().toByteArray(StandardCharsets.US_ASCII),
            clientPublicKey,
            clientNonce,
        ),
    )

    fun androidPairingVerifier(
        pairingCode: String,
        clientInstallationId: String,
        clientPublicKey: ByteArray,
        clientNonce: ByteArray,
    ): ByteArray = hmacSha256(
        pairingCodeKey(pairingCode, ANDROID_CODE_DOMAIN),
        transcript(
            ANDROID_PAIRING_DOMAIN,
            clientInstallationId.lowercase().toByteArray(StandardCharsets.US_ASCII),
            clientPublicKey,
            clientNonce,
        ),
    )

    fun trustedClientVerifier(
        reconnectSecret: ByteArray,
        clientInstallationId: String,
        clientPublicKey: ByteArray,
        clientNonce: ByteArray,
    ): ByteArray = hmacSha256(
        reconnectSecret,
        transcript(
            TRUSTED_CLIENT_DOMAIN,
            clientInstallationId.lowercase().toByteArray(StandardCharsets.US_ASCII),
            clientPublicKey,
            clientNonce,
        ),
    )

    fun sessionKey(sharedSecret: ByteArray, clientNonce: ByteArray, serverNonce: ByteArray): ByteArray {
        require(sharedSecret.size == 32) { "Invalid X25519 shared secret." }
        val value = ByteArrayOutputStream().apply {
            write(SESSION_DOMAIN)
            write(sharedSecret)
            appendField(this, clientNonce)
            appendField(this, serverNonce)
        }.toByteArray()
        return sha256(value)
    }

    fun pairingServerVerifier(
        pairingCode: String,
        clientInstallationId: String,
        clientPublicKey: ByteArray,
        clientNonce: ByteArray,
        serverInstallationId: String,
        serverPublicKey: ByteArray,
        serverNonce: ByteArray,
        sealedReconnectSecret: CryptoFrame,
    ): ByteArray = serverVerifier(
        domain = PAIRING_SERVER_DOMAIN,
        key = pairingCodeKey(pairingCode),
        clientInstallationId = clientInstallationId,
        clientPublicKey = clientPublicKey,
        clientNonce = clientNonce,
        serverInstallationId = serverInstallationId,
        serverPublicKey = serverPublicKey,
        serverNonce = serverNonce,
        sealedReconnectSecret = sealedReconnectSecret,
    )

    fun androidPairingServerVerifier(
        pairingCode: String,
        clientInstallationId: String,
        clientPublicKey: ByteArray,
        clientNonce: ByteArray,
        serverInstallationId: String,
        serverPublicKey: ByteArray,
        serverNonce: ByteArray,
        sealedReconnectSecret: CryptoFrame,
    ): ByteArray = serverVerifier(
        domain = ANDROID_PAIRING_SERVER_DOMAIN,
        key = pairingCodeKey(pairingCode, ANDROID_CODE_DOMAIN),
        clientInstallationId = clientInstallationId,
        clientPublicKey = clientPublicKey,
        clientNonce = clientNonce,
        serverInstallationId = serverInstallationId,
        serverPublicKey = serverPublicKey,
        serverNonce = serverNonce,
        sealedReconnectSecret = sealedReconnectSecret,
    )

    fun trustedServerVerifier(
        reconnectSecret: ByteArray,
        clientInstallationId: String,
        clientPublicKey: ByteArray,
        clientNonce: ByteArray,
        serverInstallationId: String,
        serverPublicKey: ByteArray,
        serverNonce: ByteArray,
    ): ByteArray = serverVerifier(
        domain = TRUSTED_SERVER_DOMAIN,
        key = reconnectSecret,
        clientInstallationId = clientInstallationId,
        clientPublicKey = clientPublicKey,
        clientNonce = clientNonce,
        serverInstallationId = serverInstallationId,
        serverPublicKey = serverPublicKey,
        serverNonce = serverNonce,
        sealedReconnectSecret = null,
    )

    fun seal(plaintext: ByteArray, key: ByteArray): CryptoFrame =
        sealWithNonce(plaintext, key, randomBytes(12))

    fun sealWithNonce(plaintext: ByteArray, key: ByteArray, nonce: ByteArray): CryptoFrame {
        require(key.size == 32 && nonce.size == 12) { "Invalid authenticated-encryption input." }
        val cipher = ChaCha20Poly1305()
        cipher.init(true, AEADParameters(KeyParameter(key), 128, nonce, ByteArray(0)))
        val combined = ByteArray(cipher.getOutputSize(plaintext.size))
        var count = cipher.processBytes(plaintext, 0, plaintext.size, combined, 0)
        count += cipher.doFinal(combined, count)
        require(count >= 16)
        return CryptoFrame(
            nonce = nonce.copyOf(),
            ciphertext = combined.copyOfRange(0, count - 16),
            tag = combined.copyOfRange(count - 16, count),
        )
    }

    fun open(frame: CryptoFrame, key: ByteArray): ByteArray {
        require(key.size == 32 && frame.nonce.size == 12 && frame.tag.size == 16) {
            "Invalid encrypted frame."
        }
        val cipher = ChaCha20Poly1305()
        cipher.init(false, AEADParameters(KeyParameter(key), 128, frame.nonce, ByteArray(0)))
        val combined = frame.ciphertext + frame.tag
        val plaintext = ByteArray(cipher.getOutputSize(combined.size))
        return try {
            var count = cipher.processBytes(combined, 0, combined.size, plaintext, 0)
            count += cipher.doFinal(plaintext, count)
            plaintext.copyOf(count)
        } catch (_: InvalidCipherTextException) {
            throw IllegalArgumentException("Encrypted frame authentication failed.")
        }
    }

    fun constantTimeEquals(left: ByteArray, right: ByteArray): Boolean =
        MessageDigest.isEqual(left, right)

    private fun serverVerifier(
        domain: ByteArray,
        key: ByteArray,
        clientInstallationId: String,
        clientPublicKey: ByteArray,
        clientNonce: ByteArray,
        serverInstallationId: String,
        serverPublicKey: ByteArray,
        serverNonce: ByteArray,
        sealedReconnectSecret: CryptoFrame?,
    ): ByteArray {
        val output = ByteArrayOutputStream().apply {
            write(domain)
            appendField(this, clientInstallationId.lowercase().toByteArray(StandardCharsets.US_ASCII))
            appendField(this, clientPublicKey)
            appendField(this, clientNonce)
            appendField(this, serverInstallationId.lowercase().toByteArray(StandardCharsets.US_ASCII))
            appendField(this, serverPublicKey)
            appendField(this, serverNonce)
            if (sealedReconnectSecret == null) {
                write(0)
            } else {
                write(1)
                appendField(this, sealedReconnectSecret.nonce)
                appendField(this, sealedReconnectSecret.ciphertext)
                appendField(this, sealedReconnectSecret.tag)
            }
        }.toByteArray()
        return hmacSha256(key, output)
    }

    private fun transcript(domain: ByteArray, vararg fields: ByteArray): ByteArray =
        ByteArrayOutputStream().apply {
            write(domain)
            fields.forEach { appendField(this, it) }
        }.toByteArray()

    private fun appendField(output: ByteArrayOutputStream, field: ByteArray) {
        output.write(ByteBuffer.allocate(Long.SIZE_BYTES).putLong(field.size.toLong()).array())
        output.write(field)
    }

    private fun sha256(value: ByteArray): ByteArray =
        MessageDigest.getInstance("SHA-256").digest(value)

    private fun hmacSha256(key: ByteArray, value: ByteArray): ByteArray =
        Mac.getInstance("HmacSHA256").run {
            init(SecretKeySpec(key, "HmacSHA256"))
            doFinal(value)
        }
}
