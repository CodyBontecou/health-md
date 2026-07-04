package com.healthmd.data.health

import com.healthmd.data.health.providers.cloud.FitbitCloudDataProvider
import com.healthmd.data.health.providers.cloud.OuraCloudDataProvider
import com.healthmd.data.health.providers.cloud.PolarCloudDataProvider
import com.healthmd.data.health.providers.cloud.WhoopCloudDataProvider
import com.healthmd.data.health.providers.cloud.WithingsCloudDataProvider
import com.healthmd.data.health.providers.direct.GarminDirectDataProvider
import com.healthmd.data.health.providers.direct.HuaweiHealthDirectDataProvider
import com.healthmd.data.health.providers.direct.SamsungHealthDirectDataProvider

/**
 * Registry for export-capable health data providers.
 *
 * Health Connect remains the default canonical provider. OAuth providers become
 * active once their client credentials and user tokens are configured; restricted
 * direct SDK/partner providers remain visible but unavailable until their vendor
 * requirements are met.
 */
class HealthProviderRegistry(
    private val healthConnectDataProvider: HealthConnectDataProvider,
    samsungHealthDirectDataProvider: SamsungHealthDirectDataProvider,
    huaweiHealthDirectDataProvider: HuaweiHealthDirectDataProvider,
    fitbitCloudDataProvider: FitbitCloudDataProvider,
    garminDirectDataProvider: GarminDirectDataProvider,
    withingsCloudDataProvider: WithingsCloudDataProvider,
    ouraCloudDataProvider: OuraCloudDataProvider,
    polarCloudDataProvider: PolarCloudDataProvider,
    whoopCloudDataProvider: WhoopCloudDataProvider,
) {
    val exportProviders: List<HealthDataProvider> = listOf(
        healthConnectDataProvider,
        samsungHealthDirectDataProvider,
        huaweiHealthDirectDataProvider,
        fitbitCloudDataProvider,
        garminDirectDataProvider,
        withingsCloudDataProvider,
        ouraCloudDataProvider,
        polarCloudDataProvider,
        whoopCloudDataProvider,
    )

    fun primaryExportProvider(): HealthDataProvider = healthConnectDataProvider

    fun providerFor(providerId: String): HealthDataProvider =
        exportProviders.firstOrNull { it.providerId == providerId } ?: primaryExportProvider()
}
