package com.healthmd.data.export

import android.content.Context
import android.content.SharedPreferences
import android.util.Base64
import androidx.core.content.edit
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.healthmd.domain.model.APIExportEndpoint
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.security.SecureRandom
import javax.inject.Inject

data class APIExportRequestConfiguration(
    val endpointUrl: String,
    val authorizationHeader: String?,
    val requestHeaders: List<APIExportRequestHeader>,
    val destinationFingerprint: String,
)

interface APIExportCredentialStore {
    suspend fun authorizationHeader(): String?
    suspend fun hasAuthorization(): Boolean
    suspend fun saveAuthorization(value: String)
    suspend fun clearAuthorization()

    suspend fun requestHeaders(): List<APIExportRequestHeader> = emptyList()
    suspend fun hasRequestHeaders(): Boolean = requestHeaders().isNotEmpty()
    suspend fun saveRequestHeaders(rawValue: String) = Unit
    suspend fun clearRequestHeaders() = Unit

    suspend fun requestConfiguration(endpointUrl: String): APIExportRequestConfiguration? {
        val normalized = APIExportEndpoint.normalizedOrNull(endpointUrl) ?: return null
        return APIExportRequestConfiguration(
            endpointUrl = normalized,
            authorizationHeader = authorizationHeader(),
            requestHeaders = requestHeaders(),
            destinationFingerprint = destinationFingerprint(endpointUrl) ?: return null,
        )
    }

    suspend fun destinationFingerprint(endpointUrl: String): String? =
        APIExportEndpoint.fingerprint(endpointUrl)
}

class EncryptedAPIExportCredentialStore @Inject constructor(
    @ApplicationContext context: Context,
) : APIExportCredentialStore {
    private val credentialLock = Any()
    private val preferences: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            PREFERENCES_NAME,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    override suspend fun authorizationHeader(): String? = withContext(Dispatchers.IO) {
        synchronized(credentialLock) { preferences.getString(AUTHORIZATION_KEY, null) }
    }

    override suspend fun hasAuthorization(): Boolean = authorizationHeader() != null

    override suspend fun saveAuthorization(value: String) = withContext(Dispatchers.IO) {
        val normalized = normalizeAuthorization(value)
            ?: throw IllegalArgumentException("Enter a valid bearer token or Authorization value.")
        synchronized(credentialLock) {
            val retainedHeaders = preferences.getString(REQUEST_HEADERS_KEY, null)
                ?.let { stored -> runCatching { APIExportHeaders.parse(stored) }.getOrDefault(emptyList()) }
                .orEmpty()
                .filterNot { it.name.equals("Authorization", ignoreCase = true) }
            preferences.edit {
                putString(AUTHORIZATION_KEY, normalized)
                if (retainedHeaders.isEmpty()) {
                    remove(REQUEST_HEADERS_KEY)
                } else {
                    putString(
                        REQUEST_HEADERS_KEY,
                        retainedHeaders.joinToString("\n") { "${it.name}: ${it.value}" },
                    )
                }
            }
        }
    }

    override suspend fun clearAuthorization() = withContext(Dispatchers.IO) {
        synchronized(credentialLock) { preferences.edit { remove(AUTHORIZATION_KEY) } }
    }

    override suspend fun requestHeaders(): List<APIExportRequestHeader> = withContext(Dispatchers.IO) {
        synchronized(credentialLock) {
            preferences.getString(REQUEST_HEADERS_KEY, null)
                ?.let { stored -> runCatching { APIExportHeaders.parse(stored) }.getOrDefault(emptyList()) }
                .orEmpty()
        }
    }

    override suspend fun hasRequestHeaders(): Boolean = requestHeaders().isNotEmpty()

    override suspend fun saveRequestHeaders(rawValue: String) = withContext(Dispatchers.IO) {
        val parsed = APIExportHeaders.parse(rawValue)
        val normalized = parsed.joinToString("\n") { "${it.name}: ${it.value}" }
        synchronized(credentialLock) {
            if (normalized.isEmpty()) {
                preferences.edit { remove(REQUEST_HEADERS_KEY) }
            } else {
                preferences.edit {
                    putString(REQUEST_HEADERS_KEY, normalized)
                    // Keep one unambiguous Authorization source. A raw Authorization line replaces
                    // the convenience Bearer/Basic field instead of leaving a hidden fallback.
                    if (parsed.any { it.name.equals("Authorization", ignoreCase = true) }) {
                        remove(AUTHORIZATION_KEY)
                    }
                }
            }
        }
    }

    override suspend fun clearRequestHeaders() = withContext(Dispatchers.IO) {
        synchronized(credentialLock) { preferences.edit { remove(REQUEST_HEADERS_KEY) } }
    }

    override suspend fun requestConfiguration(
        endpointUrl: String,
    ): APIExportRequestConfiguration? = withContext(Dispatchers.IO) {
        synchronized(credentialLock) {
            val endpoint = APIExportEndpoint.normalizedOrNull(endpointUrl) ?: return@synchronized null
            val authorization = preferences.getString(AUTHORIZATION_KEY, null)
            val headers = preferences.getString(REQUEST_HEADERS_KEY, null)
                ?.let { stored -> runCatching { APIExportHeaders.parse(stored) }.getOrDefault(emptyList()) }
                .orEmpty()
            val fingerprint = APIExportDestinationFingerprint.create(
                salt = fingerprintSalt(),
                endpointUrl = endpoint,
                authorizationHeader = authorization,
                requestHeaders = headers,
            ) ?: return@synchronized null
            APIExportRequestConfiguration(
                endpointUrl = endpoint,
                authorizationHeader = authorization,
                requestHeaders = headers,
                destinationFingerprint = fingerprint,
            )
        }
    }

    override suspend fun destinationFingerprint(endpointUrl: String): String? =
        requestConfiguration(endpointUrl)?.destinationFingerprint

    private fun fingerprintSalt(): ByteArray {
        preferences.getString(FINGERPRINT_SALT_KEY, null)?.let { encoded ->
            runCatching { Base64.decode(encoded, Base64.NO_WRAP) }.getOrNull()?.let { return it }
        }
        val generated = ByteArray(32).also { SecureRandom().nextBytes(it) }
        preferences.edit {
            putString(FINGERPRINT_SALT_KEY, Base64.encodeToString(generated, Base64.NO_WRAP))
        }
        return generated
    }

    companion object {
        const val PREFERENCES_NAME = "health_md_api_export_credentials"
        private const val AUTHORIZATION_KEY = "authorization"
        private const val REQUEST_HEADERS_KEY = "request_headers"
        private const val FINGERPRINT_SALT_KEY = "destination_fingerprint_salt"

        fun normalizeAuthorization(value: String): String? {
            val trimmed = value.trim()
            if (trimmed.isEmpty() || trimmed.any { it < ' ' || it >= '\u007f' }) return null

            val explicit = Regex("^(Bearer|Basic)\\s+.+$", RegexOption.IGNORE_CASE)
            return if (explicit.matches(trimmed)) trimmed else "Bearer $trimmed"
        }
    }
}
