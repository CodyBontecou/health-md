package com.healthmd.data.health.providers.cloud

import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthToken
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder

class CloudHealthApiClient(
    private val oauthAuthorizationManager: OAuthAuthorizationManager,
) {
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun isConfigured(providerId: String): Boolean =
        oauthAuthorizationManager.isConfigured(providerId)

    suspend fun token(providerId: String): OAuthToken? =
        oauthAuthorizationManager.validAccessToken(providerId)

    suspend fun getJson(
        providerId: String,
        url: String,
        query: Map<String, String> = emptyMap(),
    ): JsonElement {
        val token = oauthAuthorizationManager.validAccessToken(providerId)
            ?: throw SecurityException("$providerId is not connected")
        val fullUrl = if (query.isEmpty()) url else "$url?${formEncode(query)}"
        return withContext(Dispatchers.IO) {
            val connection = (URL(fullUrl).openConnection() as HttpURLConnection).apply {
                requestMethod = "GET"
                connectTimeout = HTTP_TIMEOUT_MS
                readTimeout = HTTP_TIMEOUT_MS
                setRequestProperty("Accept", "application/json")
                setRequestProperty("Authorization", "${token.tokenType.ifBlank { "Bearer" }} ${token.accessToken}")
            }
            val responseCode = connection.responseCode
            val responseText = if (responseCode in 200..299) {
                connection.inputStream.bufferedReader().use { it.readText() }
            } else {
                connection.errorStream?.bufferedReader()?.use { it.readText() }.orEmpty()
            }
            if (responseCode !in 200..299) {
                throw IllegalStateException("$providerId request failed ($responseCode): $responseText")
            }
            json.parseToJsonElement(responseText)
        }
    }

    private fun formEncode(params: Map<String, String>): String =
        params.entries.joinToString("&") { (key, value) ->
            "${urlEncode(key)}=${urlEncode(value)}"
        }

    private fun urlEncode(value: String): String =
        URLEncoder.encode(value, Charsets.UTF_8.name())

    companion object {
        private const val HTTP_TIMEOUT_MS = 20_000
    }
}
