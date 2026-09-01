package com.healthmd.data.health

/**
 * Registry for export-capable health data providers.
 *
 * Health Connect is always authoritative. The active distribution flavor supplies any additional
 * providers so an unavailable channel cannot silently fall back to or retain a cloud adapter.
 */
class HealthProviderRegistry(
    private val healthConnectDataProvider: HealthConnectDataProvider,
    additionalProviders: List<HealthDataProvider> = emptyList(),
) {
    val exportProviders: List<HealthDataProvider> =
        (listOf(healthConnectDataProvider) + additionalProviders)
            .distinctBy(HealthDataProvider::providerId)

    fun primaryExportProvider(): HealthDataProvider = healthConnectDataProvider

    fun providerFor(providerId: String): HealthDataProvider =
        exportProviders.firstOrNull { it.providerId == providerId } ?: primaryExportProvider()
}
