package com.healthmd.data.health.oauth

import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.util.Base64
import java.security.MessageDigest
import java.security.SecureRandom

class OAuthAuthorizationManager(
    private val configRegistry: OAuthConfigRegistry,
    private val tokenStore: OAuthTokenStore,
) {
    private val json = Json { ignoreUnknownKeys = true }
    private val secureRandom = SecureRandom()

    suspend fun buildAuthorizationIntent(providerId: String): Intent? {
        val authorizationUrl = buildAuthorizationUrl(providerId) ?: return null
        return Intent(Intent.ACTION_VIEW, Uri.parse(authorizationUrl)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
    }

    suspend fun buildAuthorizationUrl(providerId: String): String? {
        val config = configRegistry.get(providerId)?.takeIf { it.isConfigured } ?: return null
        val state = randomUrlSafeString()
        val verifier = randomUrlSafeString(byteCount = 64)
        tokenStore.savePendingAuthorization(
            PendingOAuthAuthorization(
                providerId = providerId,
                state = state,
                codeVerifier = verifier,
            )
        )

        val params = buildMap {
            put("response_type", "code")
            put("client_id", config.clientId)
            put("redirect_uri", config.redirectUri)
            put("state", state)
            put("code_challenge", codeChallenge(verifier))
            put("code_challenge_method", "S256")
            if (config.scopes.isNotEmpty()) put("scope", config.scopes.joinToString(" "))
        }
        return config.authorizationEndpoint + "?" + formEncode(params)
    }

    suspend fun handleCallback(callbackUri: Uri): OAuthCallbackResult = handleCallback(callbackUri.toString())

    suspend fun handleCallback(callbackUri: String): OAuthCallbackResult {
        val queryParameters = queryParameters(callbackUri)
        queryParameters["error"]?.let { error ->
            throw IllegalStateException("OAuth authorization failed: $error")
        }
        val code = queryParameters["code"]
            ?: throw IllegalArgumentException("OAuth callback did not include a code")
        val state = queryParameters["state"]
            ?: throw IllegalArgumentException("OAuth callback did not include state")
        val pending = tokenStore.consumePendingAuthorization(state)
            ?: throw IllegalArgumentException("OAuth callback state was not recognized")
        val config = configRegistry.get(pending.providerId)
            ?: throw IllegalArgumentException("Unknown OAuth provider: ${pending.providerId}")
        val token = exchangeToken(
            config = config,
            params = buildMap {
                put("grant_type", "authorization_code")
                put("code", code)
                put("redirect_uri", config.redirectUri)
                put("client_id", config.clientId)
                put("code_verifier", pending.codeVerifier)
                if (config.clientAuthStyle == OAuthClientAuthStyle.RequestBody && config.clientSecret.isNotBlank()) {
                    put("client_secret", config.clientSecret)
                }
                putAll(config.tokenExtraParams)
            }
        )
        tokenStore.saveToken(token)
        return OAuthCallbackResult(providerId = config.providerId, token = token)
    }

    suspend fun validAccessToken(providerId: String): OAuthToken? {
        val token = tokenStore.getToken(providerId) ?: return null
        if (!token.isExpired()) return token
        val refreshToken = token.refreshToken ?: return token
        val config = configRegistry.get(providerId) ?: return token
        return runCatching {
            refreshToken(config, refreshToken)
        }.getOrElse { token }
    }

    suspend fun refreshToken(config: OAuthProviderConfig, refreshToken: String): OAuthToken {
        val token = exchangeToken(
            config = config,
            params = buildMap {
                put("grant_type", "refresh_token")
                put("refresh_token", refreshToken)
                put("client_id", config.clientId)
                if (config.clientAuthStyle == OAuthClientAuthStyle.RequestBody && config.clientSecret.isNotBlank()) {
                    put("client_secret", config.clientSecret)
                }
                putAll(config.tokenExtraParams)
            }
        )
        tokenStore.saveToken(token)
        return token
    }

    suspend fun disconnect(providerId: String) {
        tokenStore.clearToken(providerId)
    }

    fun isConfigured(providerId: String): Boolean = configRegistry.isConfigured(providerId)

    private suspend fun exchangeToken(
        config: OAuthProviderConfig,
        params: Map<String, String>,
    ): OAuthToken = withContext(Dispatchers.IO) {
        val body = formEncode(params)
        val connection = (URL(config.tokenEndpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = HTTP_TIMEOUT_MS
            readTimeout = HTTP_TIMEOUT_MS
            setRequestProperty("Accept", "application/json")
            setRequestProperty("Content-Type", "application/x-www-form-urlencoded")
            if (config.clientAuthStyle == OAuthClientAuthStyle.Basic && config.clientSecret.isNotBlank()) {
                val raw = "${config.clientId}:${config.clientSecret}"
                setRequestProperty("Authorization", "Basic ${Base64.getEncoder().encodeToString(raw.toByteArray())}")
            }
        }
        OutputStreamWriter(connection.outputStream).use { writer -> writer.write(body) }
        val responseCode = connection.responseCode
        val responseText = if (responseCode in 200..299) {
            connection.inputStream.bufferedReader().use { it.readText() }
        } else {
            connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
        }
        if (responseCode !in 200..299) {
            throw IllegalStateException("OAuth token request failed ($responseCode): $responseText")
        }
        val response = json.parseToJsonElement(responseText) as JsonObject
        val accessToken = response.string("access_token")
            ?: throw IllegalStateException("OAuth token response did not include access_token")
        val expiresInSeconds = response.string("expires_in")?.toLongOrNull()
        OAuthToken(
            providerId = config.providerId,
            accessToken = accessToken,
            refreshToken = response.string("refresh_token"),
            tokenType = response.string("token_type") ?: "Bearer",
            scope = response.string("scope"),
            expiresAtEpochSeconds = expiresInSeconds?.let { (System.currentTimeMillis() / 1000) + it },
            extras = response.entries.mapNotNull { (key, value) ->
                runCatching { value.jsonPrimitive.contentOrNull }.getOrNull()?.let { key to it }
            }.toMap(),
        )
    }

    private fun JsonObject.string(key: String): String? =
        this[key]?.jsonPrimitive?.contentOrNull

    private fun formEncode(params: Map<String, String>): String =
        params.entries.joinToString("&") { (key, value) ->
            "${urlEncode(key)}=${urlEncode(value)}"
        }

    private fun urlEncode(value: String): String =
        URLEncoder.encode(value, Charsets.UTF_8.name())

    private fun randomUrlSafeString(byteCount: Int = 32): String {
        val bytes = ByteArray(byteCount)
        secureRandom.nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

    private fun codeChallenge(verifier: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray())
        return Base64.getUrlEncoder().withoutPadding().encodeToString(digest)
    }

    private fun queryParameters(uri: String): Map<String, String> {
        val rawQuery = URI(uri).rawQuery ?: return emptyMap()
        return rawQuery
            .split("&")
            .filter { it.isNotBlank() }
            .associate { pair ->
                val parts = pair.split("=", limit = 2)
                val key = urlDecode(parts[0])
                val value = parts.getOrNull(1)?.let(::urlDecode).orEmpty()
                key to value
            }
    }

    private fun urlDecode(value: String): String =
        URLDecoder.decode(value, Charsets.UTF_8.name())

    companion object {
        private const val HTTP_TIMEOUT_MS = 20_000
    }
}
