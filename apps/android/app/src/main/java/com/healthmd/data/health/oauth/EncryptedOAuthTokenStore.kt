package com.healthmd.data.health.oauth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class EncryptedOAuthTokenStore(
    context: Context,
) : OAuthTokenStore {
    private val json = Json { ignoreUnknownKeys = true }
    private val preferences: SharedPreferences by lazy {
        val masterKey = MasterKey.Builder(context)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            context,
            "health_md_oauth_tokens",
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
        )
    }

    override suspend fun getToken(providerId: String): OAuthToken? = withContext(Dispatchers.IO) {
        preferences.getString(tokenKey(providerId), null)?.let { raw ->
            runCatching { json.decodeFromString<OAuthToken>(raw) }.getOrNull()
        }
    }

    override suspend fun saveToken(token: OAuthToken) = withContext(Dispatchers.IO) {
        preferences.edit()
            .putString(tokenKey(token.providerId), json.encodeToString(token))
            .apply()
    }

    override suspend fun clearToken(providerId: String) = withContext(Dispatchers.IO) {
        preferences.edit().remove(tokenKey(providerId)).apply()
    }

    override suspend fun savePendingAuthorization(pending: PendingOAuthAuthorization) = withContext(Dispatchers.IO) {
        preferences.edit()
            .putString(pendingKey(pending.state), json.encodeToString(pending))
            .apply()
    }

    override suspend fun consumePendingAuthorization(state: String): PendingOAuthAuthorization? = withContext(Dispatchers.IO) {
        val key = pendingKey(state)
        val pending = preferences.getString(key, null)?.let { raw ->
            runCatching { json.decodeFromString<PendingOAuthAuthorization>(raw) }.getOrNull()
        }
        preferences.edit().remove(key).apply()
        pending
    }

    private fun tokenKey(providerId: String): String = "token:$providerId"
    private fun pendingKey(state: String): String = "pending:$state"
}
