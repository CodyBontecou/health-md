package com.healthmd.data.health.providers

import android.content.Intent
import javax.inject.Inject
import javax.inject.Singleton

/** F-Droid has no direct cloud providers, account credentials, or connection state. */
@Singleton
class FdroidHealthProviderConnectionManager @Inject constructor() : HealthProviderConnectionManager {
    override fun supportsDirectConnection(providerId: String): Boolean = false
    override fun isConfigured(providerId: String): Boolean = false
    override suspend fun hasCredential(providerId: String): Boolean = false
    override suspend fun buildConnectionIntent(providerId: String): Intent? = null
    override suspend fun disconnect(providerId: String) = Unit
}
