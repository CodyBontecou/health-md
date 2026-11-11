package com.healthmd.data.health.oauth

/** Private credential identity; never part of health exports or provider response payloads. */
data class OAuthCredential(val token: OAuthToken, val connectionId: String)

interface OAuthTokenStore {
    suspend fun getCredential(providerId: String): OAuthCredential?
    /** Rotate only the exact credential read before the network suspension. */
    suspend fun saveRotatedToken(token: OAuthToken, replacing: OAuthCredential): Boolean
    suspend fun getToken(providerId: String): OAuthToken?
    suspend fun saveToken(token: OAuthToken)
    suspend fun clearToken(providerId: String)
    suspend fun savePendingAuthorization(pending: PendingOAuthAuthorization)
    suspend fun consumePendingAuthorization(state: String): PendingOAuthAuthorization?
}
