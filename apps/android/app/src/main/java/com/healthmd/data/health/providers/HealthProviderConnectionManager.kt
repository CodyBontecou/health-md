package com.healthmd.data.health.providers

import android.content.Intent

/** Channel-neutral boundary for optional direct-provider account connections. */
interface HealthProviderConnectionManager {
    fun supportsDirectConnection(providerId: String): Boolean
    fun isConfigured(providerId: String): Boolean
    suspend fun hasCredential(providerId: String): Boolean
    suspend fun buildConnectionIntent(providerId: String): Intent?
    suspend fun disconnect(providerId: String)
}
