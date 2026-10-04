package com.healthmd.accountauth

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Base64

/** Explicit synthetic injection; no SecureRandom/UUID/provider fallback or OS implementation here. */
fun interface SyntheticEntropy { fun bytes(count: Int): ByteArray }
fun interface SyntheticClock { fun seconds(): Long }

class AttemptSecrets internal constructor(
    internal val state: String,
    internal val verifier: String,
    internal val installationId: String,
    val challenge: String,
) {
    override fun toString(): String = "AttemptSecrets(<redacted>)"
}

object AccountAuthPKCE {
    private val encoder = Base64.getUrlEncoder().withoutPadding()
    private val referenceShape = Regex("[A-Za-z0-9_-]{43}")
    private val verifierShape = Regex("[A-Za-z0-9._~-]{43,128}")

    fun isReference(value: String): Boolean {
        if (!referenceShape.matches(value)) return false
        return try {
            val bytes = Base64.getUrlDecoder().decode(value)
            bytes.size == 32 && encoder.encodeToString(bytes) == value
        } catch (_: IllegalArgumentException) { false }
    }

    fun s256(verifier: String): String {
        if (!verifierShape.matches(verifier)) reject(AuthRejection.ENTROPY_UNAVAILABLE)
        return encoder.encodeToString(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray(StandardCharsets.US_ASCII)))
    }

    private fun freshReference(entropy: SyntheticEntropy): String {
        val bytes = try { entropy.bytes(32).copyOf() } catch (_: Exception) { reject(AuthRejection.ENTROPY_UNAVAILABLE) }
        if (bytes.size != 32) reject(AuthRejection.ENTROPY_UNAVAILABLE)
        return encoder.encodeToString(bytes)
    }

    /** One owner/process label, separate from per-attempt state/verifier. Restart custody is gated. */
    fun installationForSyntheticTests(entropy: SyntheticEntropy): String = freshReference(entropy)

    fun freshForSyntheticTests(entropy: SyntheticEntropy, installationId: String): AttemptSecrets {
        if (!isReference(installationId)) reject(AuthRejection.ENTROPY_UNAVAILABLE)
        val state = freshReference(entropy)
        val verifier = freshReference(entropy)
        return AttemptSecrets(state, verifier, installationId, s256(verifier))
    }

    internal fun isToken(value: String, prefix: String): Boolean =
        value.startsWith(prefix) && isReference(value.removePrefix(prefix))
}
