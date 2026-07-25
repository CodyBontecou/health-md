package com.healthmd.data.health.oauth

import com.healthmd.BuildConfig

class OAuthConfigRegistry(
    providerConfigs: List<OAuthProviderConfig> = defaultConfigs(),
) {
    private val configs: Map<String, OAuthProviderConfig> = providerConfigs.associateBy { it.providerId }

    fun get(providerId: String): OAuthProviderConfig? = configs[providerId]

    fun all(): List<OAuthProviderConfig> = configs.values.toList()

    fun isConfigured(providerId: String): Boolean = configs[providerId]?.isConfigured == true

    companion object {
        private fun defaultConfigs(): List<OAuthProviderConfig> = listOf(
            OAuthProviderConfig(
                providerId = "fitbit",
                displayName = "Fitbit",
                authorizationEndpoint = "https://www.fitbit.com/oauth2/authorize",
                tokenEndpoint = tokenEndpoint(
                    brokerUrl = BuildConfig.FITBIT_TOKEN_BROKER_URL,
                    providerTokenEndpoint = "https://api.fitbit.com/oauth2/token",
                ),
                clientId = BuildConfig.FITBIT_CLIENT_ID,
                scopes = listOf("activity", "heartrate", "location", "nutrition", "profile", "settings", "sleep", "weight"),
            ),
            OAuthProviderConfig(
                providerId = "withings",
                displayName = "Withings",
                authorizationEndpoint = "https://account.withings.com/oauth2_user/authorize2",
                tokenEndpoint = tokenEndpoint(
                    brokerUrl = BuildConfig.WITHINGS_TOKEN_BROKER_URL,
                    providerTokenEndpoint = "https://wbsapi.withings.net/v2/oauth2",
                ),
                clientId = BuildConfig.WITHINGS_CLIENT_ID,
                scopes = listOf("user.metrics", "user.activity"),
                tokenExtraParams = mapOf("action" to "requesttoken"),
            ),
            OAuthProviderConfig(
                providerId = "oura",
                displayName = "Oura",
                authorizationEndpoint = "https://cloud.ouraring.com/oauth/authorize",
                tokenEndpoint = tokenEndpoint(
                    brokerUrl = BuildConfig.OURA_TOKEN_BROKER_URL,
                    providerTokenEndpoint = "https://api.ouraring.com/oauth/token",
                ),
                clientId = BuildConfig.OURA_CLIENT_ID,
                scopes = listOf("email", "personal", "daily", "heartrate", "workout", "session", "tag"),
            ),
            OAuthProviderConfig(
                providerId = "polar",
                displayName = "Polar Flow",
                authorizationEndpoint = "https://flow.polar.com/oauth2/authorization",
                tokenEndpoint = tokenEndpoint(
                    brokerUrl = BuildConfig.POLAR_TOKEN_BROKER_URL,
                    providerTokenEndpoint = "https://polarremote.com/v2/oauth2/token",
                ),
                clientId = BuildConfig.POLAR_CLIENT_ID,
                scopes = emptyList(),
            ),
            OAuthProviderConfig(
                providerId = "whoop",
                displayName = "WHOOP",
                authorizationEndpoint = "https://api.prod.whoop.com/oauth/oauth2/auth",
                tokenEndpoint = tokenEndpoint(
                    brokerUrl = BuildConfig.WHOOP_TOKEN_BROKER_URL,
                    providerTokenEndpoint = "https://api.prod.whoop.com/oauth/oauth2/token",
                ),
                clientId = BuildConfig.WHOOP_CLIENT_ID,
                scopes = listOf("offline", "read:profile", "read:cycles", "read:recovery", "read:sleep", "read:workout", "read:body_measurement"),
            ),
        )

        private fun tokenEndpoint(brokerUrl: String, providerTokenEndpoint: String): String =
            brokerUrl.takeIf { it.isNotBlank() } ?: providerTokenEndpoint
    }
}
