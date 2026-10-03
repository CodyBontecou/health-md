package com.healthmd.data.health.oauth

class InMemoryOAuthTokenStore(
    initialTokens: Iterable<OAuthToken> = emptyList(),
) : OAuthTokenStore {
    val tokens: MutableMap<String, OAuthToken> = initialTokens.associateBy { it.providerId }.toMutableMap()
    val pendingAuthorizations: MutableMap<String, PendingOAuthAuthorization> = mutableMapOf()

    override suspend fun getToken(providerId: String): OAuthToken? = tokens[providerId]

    override suspend fun saveToken(token: OAuthToken) {
        tokens[token.providerId] = token
    }

    override suspend fun clearToken(providerId: String) {
        tokens.remove(providerId)
    }

    override suspend fun savePendingAuthorization(pending: PendingOAuthAuthorization) {
        pendingAuthorizations[pending.state] = pending
    }

    override suspend fun consumePendingAuthorization(state: String): PendingOAuthAuthorization? =
        pendingAuthorizations.remove(state)
}
