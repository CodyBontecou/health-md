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
    val healthMdBroker: HealthMdOAuthBrokerConfig? = null,
) {
    val isConfigured: Boolean get() = healthMdBroker?.isConfigured ?: clientId.isNotBlank()

    companion object {
        const val DEFAULT_REDIRECT_URI = "healthmd://oauth2redirect"
    }
}

/** Mobile client gate only; provider client secrets remain on the broker. */
class HealthMdOAuthBrokerConfig(val baseUrl: String, val clientToken: String) {
    val isConfigured: Boolean get() = runCatching {
        val uri = java.net.URI(baseUrl)
        clientToken.isNotBlank() && uri.host != null && uri.userInfo == null &&
            uri.rawQuery == null && uri.rawFragment == null &&
            (uri.scheme == "https" || (uri.scheme == "http" && uri.host in listOf("localhost", "127.0.0.1")))
    }.getOrDefault(false)

    fun endpoint(path: String): String = java.net.URI(baseUrl).resolve(path).toString()
}

enum class OAuthClientAuthStyle {
    RequestBody,
    Basic,
}

data class OAuthCallbackResult(
    val providerId: String,
    val token: OAuthToken,
)
