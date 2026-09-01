package com.healthmd.data.health.oauth

import kotlinx.serialization.Serializable

@Serializable
data class OAuthToken(
    val providerId: String,
    val accessToken: String,
    val refreshToken: String? = null,
    val tokenType: String = "Bearer",
    val scope: String? = null,
    val expiresAtEpochSeconds: Long? = null,
    val extras: Map<String, String> = emptyMap(),
) {
    fun isExpired(nowEpochSeconds: Long = System.currentTimeMillis() / 1000): Boolean =
        expiresAtEpochSeconds?.let { it <= nowEpochSeconds + 60 } ?: false
}

@Serializable
data class PendingOAuthAuthorization(
    val providerId: String,
    val state: String,
    val codeVerifier: String,
    val createdAtEpochSeconds: Long = System.currentTimeMillis() / 1000,
)

data class OAuthProviderConfig(
    val providerId: String,
    val displayName: String,
    val authorizationEndpoint: String,
    val tokenEndpoint: String,
    val clientId: String,
    val clientSecret: String = "",
    val scopes: List<String>,
    val redirectUri: String = DEFAULT_REDIRECT_URI,
    val clientAuthStyle: OAuthClientAuthStyle = OAuthClientAuthStyle.RequestBody,
    val tokenExtraParams: Map<String, String> = emptyMap(),
) {
    val isConfigured: Boolean get() = clientId.isNotBlank()

    companion object {
        const val DEFAULT_REDIRECT_URI = "healthmd://oauth2redirect"
    }
}

enum class OAuthClientAuthStyle {
    RequestBody,
    Basic,
}

data class OAuthCallbackResult(
    val providerId: String,
    val token: OAuthToken,
)
