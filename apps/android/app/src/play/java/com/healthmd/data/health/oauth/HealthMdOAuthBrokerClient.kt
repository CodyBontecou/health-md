package com.healthmd.data.health.oauth

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonPrimitive
import java.net.HttpURLConnection
import java.net.URI
import java.net.URL

/** The same gated, stateless JSON contract used by Apple. No provider secret is held here. */
internal class HealthMdOAuthBrokerClient(private val config: HealthMdOAuthBrokerConfig) {
    suspend fun authorize(provider: OAuthProviderConfig, state: String, challenge: String): String {
        val response = post("/v1/oauth/authorize-url", mapOf(
            "provider" to provider.providerId,
            "redirect_uri" to provider.redirectUri,
            "state" to state,
            "scope" to provider.scopes.joinToString(" "),
            "code_challenge" to challenge,
        ))
        val url = response["authorization_url"]?.jsonPrimitive?.contentOrNull
            ?: throw OAuthAuthorizationException(OAuthFailureReason.INVALID_TOKEN_RESPONSE, "Broker omitted authorization URL")
        val actual = URI(url)
        val expected = URI(provider.authorizationEndpoint)
        require(actual.scheme == "https" && actual.host == expected.host && actual.path == expected.path &&
            actual.userInfo == null && actual.port == expected.port && actual.fragment == null) {
            "Broker returned an unexpected authorization endpoint"
        }
        require(response["provider"]?.jsonPrimitive?.contentOrNull == provider.providerId) {
            "Broker returned an unexpected provider"
        }
        return url
    }

    suspend fun token(providerId: String, params: Map<String, String>): JsonObject {
        val refresh = params["grant_type"] == "refresh_token"
        val allowed = if (refresh) setOf("grant_type", "refresh_token", "scope")
            else setOf("grant_type", "code", "redirect_uri", "code_verifier")
        return post(if (refresh) "/v1/oauth/refresh" else "/v1/oauth/token",
            params.filterKeys { it in allowed } + ("provider" to providerId))
    }

    private suspend fun post(path: String, params: Map<String, String>): JsonObject = withContext(Dispatchers.IO) {
        check(config.isConfigured) { "Health.md OAuth broker is not configured" }
        val connection = (URL(config.endpoint(path)).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            instanceFollowRedirects = false
            connectTimeout = 20_000
            readTimeout = 20_000
            setRequestProperty("Authorization", "Bearer ${config.clientToken}")
            setRequestProperty("Content-Type", "application/json")
            setRequestProperty("Accept", "application/json")
        }
        try {
            val body = JsonObject(params.mapValues { JsonPrimitive(it.value) }).toString()
            connection.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val status = connection.responseCode
            if (status !in 200..299) {
                throw OAuthAuthorizationException(OAuthFailureReason.TOKEN_EXCHANGE_FAILED, "OAuth broker request failed ($status)")
            }
            val response = connection.inputStream.bufferedReader().use { it.readText() }
            val parsed = try {
                Json.parseToJsonElement(response)
            } catch (_: kotlinx.serialization.SerializationException) {
                throw OAuthAuthorizationException(OAuthFailureReason.INVALID_TOKEN_RESPONSE, "OAuth broker response was invalid JSON")
            }
            parsed as? JsonObject
                ?: throw OAuthAuthorizationException(OAuthFailureReason.INVALID_TOKEN_RESPONSE, "OAuth broker response was not an object")
        } finally {
            connection.disconnect()
        }
    }
}
