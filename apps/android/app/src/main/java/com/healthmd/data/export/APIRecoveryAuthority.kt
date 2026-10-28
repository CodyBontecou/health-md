package com.healthmd.data.export

import com.healthmd.domain.model.APIRecoveryExecution
import com.healthmd.domain.model.ExportSettings
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.security.MessageDigest
import java.security.SecureRandom
import java.util.Locale
import javax.crypto.Mac
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Local-only evidence, never an export field. Production proofs use an encrypted installation key. */
internal object APIRecoveryAuthorities {
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false }
    private val hex = Regex("[0-9a-f]{64}")
    const val MAX_EVIDENCE_CHARACTERS = 256

    @Serializable
    private data class Evidence(val version: Int, val nonce: String, val digest: String)

    fun create(configuration: APIExportRequestConfiguration, binding: String?, key: ByteArray? = null): String {
        val nonce = ByteArray(32).also { SecureRandom().nextBytes(it) }.hex()
        return json.encodeToString(Evidence(version = 1, nonce = nonce, digest = digest(configuration, binding, nonce, key)))
    }

    fun isValid(encoded: String?): Boolean = decode(encoded) != null

    fun matches(encoded: String?, configuration: APIExportRequestConfiguration, binding: String?, key: ByteArray? = null): Boolean {
        val evidence = decode(encoded) ?: return false
        return MessageDigest.isEqual(
            evidence.digest.toByteArray(Charsets.US_ASCII),
            digest(configuration, binding, evidence.nonce, key).toByteArray(Charsets.US_ASCII),
        )
    }

    private fun decode(encoded: String?): Evidence? {
        if (encoded == null || encoded.length > MAX_EVIDENCE_CHARACTERS) return null
        return runCatching { json.decodeFromString<Evidence>(encoded) }.getOrNull()
            ?.takeIf { it.version == 1 && hex.matches(it.nonce) && hex.matches(it.digest) }
    }

    private fun digest(configuration: APIExportRequestConfiguration, binding: String?, nonce: String, key: ByteArray?): String {
        val headers = APIExportHeaders.validate(configuration.requestHeaders).sortedBy { it.name.lowercase(Locale.ROOT) }
        require(headers.size <= 20 && configuration.endpointUrl.length <= 16_384)
        require(configuration.destinationFingerprint.length <= 256)
        require(configuration.authorizationHeader.orEmpty().length <= 16_384 && binding.orEmpty().length <= 1_024)
        val bytes = ByteArrayOutputStream().also { buffer ->
            DataOutputStream(buffer).use { out ->
                fun field(value: String?) {
                    if (value == null) out.writeInt(-1) else {
                        val encoded = value.toByteArray(Charsets.UTF_8)
                        out.writeInt(encoded.size)
                        out.write(encoded)
                    }
                }
                field("healthmd.android.api-recovery-authority.v1")
                field(nonce)
                field(binding)
                field(configuration.endpointUrl)
                field(configuration.destinationFingerprint)
                field(configuration.authorizationHeader)
                out.writeInt(headers.size)
                headers.forEach { field(it.name.lowercase(Locale.ROOT)); field(it.value) }
            }
        }.toByteArray()
        return if (key == null) {
            // Interface default supports isolated/fake stores, like Apple's nonce-bound proof.
            MessageDigest.getInstance("SHA-256").digest(bytes).hex()
        } else {
            require(key.size == 32)
            Mac.getInstance("HmacSHA256").run { init(SecretKeySpec(key, "HmacSHA256")); doFinal(bytes).hex() }
        }
    }

    private fun ByteArray.hex(): String = joinToString("") { (it.toInt() and 255).toString(16).padStart(2, '0') }
}

/** All failures are health-free; no rejected destination, header, credential or identity is retained. */
internal class APIRecoveryAuthorityException : IllegalStateException("api_recovery_authority_required")

internal class APIRecoveryGuard(
    private val credentials: APIExportCredentialStore,
    private val configuration: APIExportRequestConfiguration,
    private val execution: APIRecoveryExecution?,
    private val required: Boolean,
    private val requirePrivateOperationActive: suspend () -> Unit = {},
) {
    suspend fun markJournalPrepared() {
        if (!required && execution == null) return
        verify()
        try {
            if (execution?.onJournalPrepared?.invoke() != true) throw APIRecoveryAuthorityException()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            throw APIRecoveryAuthorityException()
        }
        verify()
    }

    suspend fun verify() {
        if (!required && execution == null) return
        val context = execution ?: throw APIRecoveryAuthorityException()
        try {
            requirePrivateOperationActive()
            if (!context.isStillAuthorized()) throw APIRecoveryAuthorityException()
            val current = credentials.requestConfiguration(configuration.endpointUrl) ?: throw APIRecoveryAuthorityException()
            if (!credentials.matchesRecoveryAuthority(context.authorityJson, current, context.profileBinding) ||
                current != configuration || !context.isStillAuthorized()
            ) throw APIRecoveryAuthorityException()
            requirePrivateOperationActive()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            throw APIRecoveryAuthorityException()
        }
    }
}

internal fun ExportSettings.apiRecoveryGuard(
    credentials: APIExportCredentialStore,
    configuration: APIExportRequestConfiguration,
    requirePrivateOperationActive: suspend () -> Unit = {},
) = APIRecoveryGuard(credentials, configuration, executionAPIRecovery, executionAPIRecoveryRequired, requirePrivateOperationActive)
