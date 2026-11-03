package com.healthmd.data.health.oauth

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import java.io.IOException
import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

class EncryptedOAuthTokenStore private constructor(
    preferencesFactory: () -> SharedPreferences,
) : OAuthTokenStore {
    constructor(context: Context) : this({ encryptedPreferences(context) })
    internal constructor(preferences: SharedPreferences) : this({ preferences })

    private val json = Json { ignoreUnknownKeys = true }
    private val preferences: SharedPreferences by lazy(preferencesFactory)

    override suspend fun getToken(providerId: String): OAuthToken? = getCredential(providerId)?.token

    override suspend fun getCredential(providerId: String): OAuthCredential? = withContext(Dispatchers.IO) {
        authorityMutex.withLock { readCredential(providerId) }
    }

    override suspend fun saveToken(token: OAuthToken) = withContext(Dispatchers.IO) {
        authorityMutex.withLock {
            val previous = preferences.getString(tokenKey(token.providerId), null)
            val credential = OAuthCredential(token, UUID.randomUUID().toString())
            writeCredential(credential, previous)
        }
    }

    override suspend fun saveRotatedToken(token: OAuthToken, replacing: OAuthCredential): Boolean = withContext(Dispatchers.IO) {
        authorityMutex.withLock {
            if (token.providerId != replacing.token.providerId || readCredential(token.providerId) != replacing) {
                false
            } else {
                writeCredential(OAuthCredential(token, replacing.connectionId), preferences.getString(tokenKey(token.providerId), null))
                true
            }
        }
    }

    override suspend fun clearToken(providerId: String) = withContext(Dispatchers.IO) {
        authorityMutex.withLock {
            val existing = readCredential(providerId)
            if (!preferences.edit().remove(tokenKey(providerId)).commit()) {
                existing?.let { invalidatedConnections += it.connectionId }
                throw IOException("Could not remove provider credentials")
            }
        }
    }

    // Called only under the process-wide authority lock. Encrypted preferences contain a
    // single flat record, retaining compatibility with historical OAuthToken decoders.
    private fun readCredential(providerId: String): OAuthCredential? {
        val raw = preferences.getString(tokenKey(providerId), null) ?: return null
        val fields = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return null
        val token = runCatching { json.decodeFromString<OAuthToken>(raw) }.getOrNull() ?: return null
        if (token.providerId != providerId) return null
        if (CONNECTION_KEY !in fields) {
            val migrated = OAuthCredential(token, UUID.randomUUID().toString())
            return runCatching { writeCredential(migrated, raw); migrated }.getOrNull()
        }
        val id = runCatching { fields[CONNECTION_KEY]?.jsonPrimitive?.contentOrNull }.getOrNull() ?: return null
        if (runCatching { UUID.fromString(id).toString() == id }.getOrDefault(false).not()
            || id in invalidatedConnections) return null
        return OAuthCredential(token, id)
    }

    private fun writeCredential(credential: OAuthCredential, previous: String?) {
        val token = credential.token
        val fields = json.parseToJsonElement(json.encodeToString(token)).jsonObject.toMutableMap()
        fields[CONNECTION_KEY] = JsonPrimitive(credential.connectionId)
        if (!preferences.edit().putString(tokenKey(token.providerId), JsonObject(fields).toString()).commit()) {
            // SharedPreferences can publish memory before a failed disk commit. Invalidate
            // both generations for this process, and restore the prior bytes best-effort.
            invalidatedConnections += credential.connectionId
            previous?.let { raw ->
                runCatching { json.parseToJsonElement(raw).jsonObject[CONNECTION_KEY]?.jsonPrimitive?.contentOrNull }
                    .getOrNull()?.let { invalidatedConnections += it }
            }
            val rollback = preferences.edit()
            if (previous == null) rollback.remove(tokenKey(token.providerId))
            else rollback.putString(tokenKey(token.providerId), previous)
            rollback.commit()
            throw IOException("Could not persist provider credentials")
        }
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

    companion object {
        private const val CONNECTION_KEY = "_healthmd_connection_id"
        private val authorityMutex = Mutex()
        private val invalidatedConnections = mutableSetOf<String>()

        private fun encryptedPreferences(context: Context): SharedPreferences {
            val masterKey = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
            return EncryptedSharedPreferences.create(context, "health_md_oauth_tokens", masterKey,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
        }
    }

}
