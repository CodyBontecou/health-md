package com.healthmd.distribution

/** F-Droid deliberately starts no Health.md telemetry, attribution, review, or Wear work. */
class FdroidDistributionRuntime : DistributionRuntime {
    override fun initialize() = Unit
    override suspend fun reconcileForeground() = Unit
}
