package com.healthmd.domain.billing

import java.security.KeyFactory
import java.security.Signature
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Reviewed app configuration owns keys; tokens cannot supply new trust roots. */
class ClinicGrantVerifier(
    private val issuer: String,
    private val audience: String,
    trustedKeys: Map<String, ByteArray>,
) {
    private val keys = trustedKeys.mapValues { it.value.copyOf() }
    private val json = Json { ignoreUnknownKeys = false }

    @Serializable
    private data class Claims(
        val issuer: String,
        val audience: String,
        val installationID: String,
        val sponsorshipID: String,
        val clinicID: String,
        val destinationID: String,
        val policyVersion: Int,
        val endpoint: String,
        val issuedAtMilliseconds: Long,
        val expiresAtMilliseconds: Long,
    )

    /** v1.keyID.payload.signature; signature is P256 r||s over the first three components. */
    fun verify(token: String, installationID: String, nowMilliseconds: Long): ClinicExportGrant? = runCatching {
        require(installationID.isNotEmpty() && token.length <= 8192)
        val parts = token.split('.')
        require(parts.size == 4 && parts[0] == "v1")
        val keyData = requireNotNull(keys[parts[1]])
        val payload = decode(parts[2])
        val signature = decode(parts[3])
        require(signature.size == 64)
        val key = KeyFactory.getInstance("EC").generatePublic(X509EncodedKeySpec(keyData))
        val verifier = Signature.getInstance("SHA256withECDSA")
        verifier.initVerify(key)
        verifier.update(parts.take(3).joinToString(".").toByteArray(Charsets.US_ASCII))
        require(verifier.verify(derSignature(signature)))
        val c = json.decodeFromString<Claims>(payload.toString(Charsets.UTF_8))
        require(c.issuer == issuer && c.audience == audience && c.installationID == installationID && c.sponsorshipID.isNotEmpty())
        val grant = ClinicExportGrant(c.clinicID, c.destinationID, c.policyVersion, c.endpoint,
            c.issuedAtMilliseconds, c.expiresAtMilliseconds, false)
        val probe = ClinicExportRequest(true, c.clinicID, c.destinationID, c.policyVersion, c.endpoint, true)
        require(ClinicExportAuthorization.decide(false, grant, probe, nowMilliseconds) ==
            ClinicExportDecision.ALLOWED_CLINIC_DESTINATION)
        grant
    }.getOrNull()

    private fun decode(value: String): ByteArray {
        require(value.isNotEmpty() && value.all { it in 'A'..'Z' || it in 'a'..'z' || it in '0'..'9' || it == '-' || it == '_' })
        val bytes = Base64.getUrlDecoder().decode(value)
        require(Base64.getUrlEncoder().withoutPadding().encodeToString(bytes) == value)
        return bytes
    }

    private fun derSignature(raw: ByteArray): ByteArray {
        fun integer(bytes: ByteArray): ByteArray {
            val first = bytes.indexOfFirst { it != 0.toByte() }.let { if (it < 0) bytes.lastIndex else it }
            val significant = bytes.copyOfRange(first, bytes.size)
            val positive = if (significant[0].toInt() and 0x80 != 0) byteArrayOf(0) + significant else significant
            return byteArrayOf(2, positive.size.toByte()) + positive
        }
        val body = integer(raw.copyOfRange(0, 32)) + integer(raw.copyOfRange(32, 64))
        return byteArrayOf(0x30, body.size.toByte()) + body
    }
}
