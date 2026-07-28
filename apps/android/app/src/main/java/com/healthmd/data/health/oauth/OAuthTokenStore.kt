package com.healthmd.data.health.oauth

interface OAuthTokenStore {
    suspend fun getToken(providerId: String): OAuthToken?
    suspend fun saveToken(token: OAuthToken)
    suspend fun clearToken(providerId: String)
    suspend fun savePendingAuthorization(pending: PendingOAuthAuthorization)
    suspend fun consumePendingAuthorization(state: String): PendingOAuthAuthorization?
}
