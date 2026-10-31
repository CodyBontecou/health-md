package com.healthmd.data.health.providers

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.providers.cloud.CloudHealthApiClient
import com.healthmd.data.health.providers.cloud.WhoopCloudDataProvider
import com.healthmd.di.HealthDistributionModule
import com.healthmd.rawexport.RawHealthRepository
import io.mockk.every
import io.mockk.mockk
import org.junit.Test

class HealthProviderRolloutTest {
    @Test
    fun productionOAuthRegistryOnlyOffersWHOOP() {
        assertThat(OAuthConfigRegistry().all().map { it.providerId }).containsExactly("whoop")
    }

    @Test
    fun productionExportRegistriesExcludeDisabledProviders() {
        val healthConnect = mockk<HealthConnectDataProvider> {
            every { providerId } returns "health_connect"
        }
        val whoop = WhoopCloudDataProvider(mockk<CloudHealthApiClient>())
        val normalized = HealthDistributionModule.provideHealthProviderRegistry(healthConnect, whoop)
        assertThat(normalized.exportProviders.map { it.providerId }).containsExactly("health_connect", "whoop")
        val raw = HealthDistributionModule.provideRawHealthRepositoryRegistry(
            mockk<RawHealthRepository>(), mockk<CloudHealthApiClient>(), whoop,
        )
        assertThat(raw.registeredProviderIds()).containsExactly("health_connect", "whoop")
        listOf("fitbit", "oura", "withings", "polar", "samsung_health", "huawei_health", "garmin", "strava")
            .forEach { id ->
                assertThat(normalized.containsProvider(id)).isFalse()
                assertThat(raw.repositoryFor(id)).isNull()
                assertThat(OAuthConfigRegistry().get(id)).isNull()
            }
    }
}
