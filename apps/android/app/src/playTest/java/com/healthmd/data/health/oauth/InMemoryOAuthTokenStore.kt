package com.healthmd.data.health.oauth

import java.util.UUID
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

class InMemoryOAuthTokenStore(
    initialTokens: Iterable<OAuthToken> = emptyList(),
) : OAuthTokenStore {
    val tokens: MutableMap<String, OAuthToken> = initialTokens.associateBy { it.providerId }.toMutableMap()
    val pendingAuthorizations: MutableMap<String, PendingOAuthAuthorization> = mutableMapOf()

    private val mutex = Mutex()
    private val credentials = mutableMapOf<String, OAuthCredential>()

    private fun credential(providerId: String): OAuthCredential? {
        val token = tokens[providerId] ?: return null
        return credentials[providerId]?.takeIf { it.token == token }
            ?: OAuthCredential(token, UUID.randomUUID().toString()).also { credentials[providerId] = it }
    }

    override suspend fun getToken(providerId: String): OAuthToken? = getCredential(providerId)?.token

    override suspend fun getCredential(providerId: String): OAuthCredential? = mutex.withLock { credential(providerId) }

    override suspend fun saveToken(token: OAuthToken) = mutex.withLock {
        tokens[token.providerId] = token
        credentials[token.providerId] = OAuthCredential(token, UUID.randomUUID().toString())
    }

    override suspend fun saveRotatedToken(token: OAuthToken, replacing: OAuthCredential): Boolean = mutex.withLock {
        if (token.providerId != replacing.token.providerId || credential(token.providerId) != replacing) false
        else {
            tokens[token.providerId] = token
            credentials[token.providerId] = OAuthCredential(token, replacing.connectionId)
            true
        }
    }

    override suspend fun clearToken(providerId: String) = mutex.withLock {
        tokens.remove(providerId)
        credentials.remove(providerId)
        Unit
    }

    override suspend fun savePendingAuthorization(pending: PendingOAuthAuthorization) {
        pendingAuthorizations[pending.state] = pending
    }

    override suspend fun consumePendingAuthorization(state: String): PendingOAuthAuthorization? =
        pendingAuthorizations.remove(state)
}
