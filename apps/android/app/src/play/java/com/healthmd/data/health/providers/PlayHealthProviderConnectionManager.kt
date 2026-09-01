package com.healthmd.data.health.providers

import android.content.Intent
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.oauth.OAuthTokenStore
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class PlayHealthProviderConnectionManager @Inject constructor(
    private val authorizationManager: OAuthAuthorizationManager,
    private val configRegistry: OAuthConfigRegistry,
    private val tokenStore: OAuthTokenStore,
) : HealthProviderConnectionManager {
    override fun supportsDirectConnection(providerId: String): Boolean =
        configRegistry.get(providerId) != null

    override fun isConfigured(providerId: String): Boolean =
        authorizationManager.isConfigured(providerId)

    override suspend fun hasCredential(providerId: String): Boolean =
        tokenStore.getToken(providerId) != null

    override suspend fun buildConnectionIntent(providerId: String): Intent? =
        authorizationManager.buildAuthorizationIntent(providerId)

    override suspend fun disconnect(providerId: String) {
        authorizationManager.disconnect(providerId)
    }
}
