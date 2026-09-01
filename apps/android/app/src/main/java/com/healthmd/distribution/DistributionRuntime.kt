package com.healthmd.distribution

/** Flavor-owned startup and foreground integrations (telemetry and phone-to-Wear on Play). */
interface DistributionRuntime {
    fun initialize()
    suspend fun reconcileForeground()
}
