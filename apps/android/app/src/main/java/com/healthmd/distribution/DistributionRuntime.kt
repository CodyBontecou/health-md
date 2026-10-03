package com.healthmd.distribution

/** Flavor-owned startup and foreground integrations for the active distribution channel. */
interface DistributionRuntime {
    fun initialize()
    suspend fun reconcileForeground()
}
