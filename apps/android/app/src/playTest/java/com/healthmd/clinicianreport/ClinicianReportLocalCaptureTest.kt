package com.healthmd.clinicianreport

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.clinicianreport.ClinicianReportDateProvider
import com.healthmd.data.clinicianreport.ClinicianReportSourceLabelResolver
import com.healthmd.data.clinicianreport.DefaultClinicianReportDataSource
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthDataMerger
import com.healthmd.data.health.oauth.InMemoryOAuthTokenStore
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.oauth.OAuthConfigRegistry
import com.healthmd.data.health.oauth.OAuthProviderConfig
import com.healthmd.data.health.oauth.OAuthToken
import com.healthmd.data.health.providers.cloud.CloudHealthApiClient
import com.healthmd.data.health.providers.cloud.CloudHttpRequest
import com.healthmd.data.health.providers.cloud.CloudHttpResponse
import com.healthmd.data.health.providers.cloud.CloudHttpTransport
import com.healthmd.di.HealthDistributionModule
import com.healthmd.di.HealthModule
import com.healthmd.domain.clinicianreport.ClinicianReportWarning
import com.healthmd.domain.clinicianreport.ReportConfiguration
import com.healthmd.domain.clinicianreport.ReportDateRange
import com.healthmd.domain.clinicianreport.ReportMetric
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.LocalDate
import java.time.ZoneId

@RunWith(RobolectricTestRunner::class)
class ClinicianReportLocalCaptureTest {
    @Test fun cloudSelectionCannotCaptureReportThroughCloudApi() = runTest {
        for (attribution in SleepDayAttribution.entries) assertLocalReportCapture("whoop", attribution)
    }

    @Test fun allConnectedSelectionCannotCaptureReportThroughCloudApi() = runTest {
        for (attribution in SleepDayAttribution.entries) {
            assertLocalReportCapture(HealthDataMerger.ALL_CONNECTED_PROVIDER_ID, attribution)
        }
    }

    @Test fun localPermissionFailureCannotFallbackToSelectedCloud() = runTest {
        assertLocalReportCapture("whoop", SleepDayAttribution.NIGHT_BEGINS, SecurityException("private local failure"))
    }

    @Test fun localPermissionFailureCannotFallbackToAllConnectedCloud() = runTest {
        assertLocalReportCapture(HealthDataMerger.ALL_CONNECTED_PROVIDER_ID, SleepDayAttribution.MORNING_ENDS,
            SecurityException("private local failure"))
    }

    private suspend fun assertLocalReportCapture(
        selectedProviderId: String,
        attribution: SleepDayAttribution,
        localFailure: Exception? = null,
    ) {
        val day = LocalDate.of(2026, 4, 5)
        val zone = ZoneId.of("Pacific/Chatham")
        val settings = mockk<SettingsRepository>(relaxed = true)
        coEvery { settings.getSelectedHealthProviderId() } returns selectedProviderId
        coEvery { settings.getConnectedHealthProviderIds() } returns setOf("health_connect", "whoop")
        coEvery { settings.getSleepDayAttribution() } returns attribution
        val manager = mockk<HealthConnectManager>()
        coEvery { manager.isAvailable() } returns true
        coEvery { manager.hasAllPermissions() } returns true
        coEvery { manager.fetchHealthDataRange(any(), any(), any(), any(), any(), any(), any()) } answers {
            localFailure?.let { throw it }
            firstArg<List<LocalDate>>().map { HealthData(it, heart = HeartData(restingHeartRate = 61.0)) }
        }
        val healthConnect = HealthModule.provideHealthConnectDataProvider(manager)

        // The current Play registry and actual WHOOP adapter use synthetic credentials and
        // an in-memory transport. No socket, broker, live provider account or real health data.
        val requests = mutableListOf<CloudHttpRequest>()
        val config = OAuthProviderConfig(
            providerId = "whoop",
            displayName = "WHOOP synthetic",
            authorizationEndpoint = "https://example.invalid/authorize",
            tokenEndpoint = "https://example.invalid/token",
            clientId = "synthetic-client",
            scopes = emptyList(),
        )
        val api = CloudHealthApiClient.forTesting(
            OAuthAuthorizationManager(
                OAuthConfigRegistry(listOf(config)),
                InMemoryOAuthTokenStore(listOf(OAuthToken("whoop", "synthetic-token"))),
            ),
            CloudHttpTransport { request ->
                requests += request
                val body = if (request.url.path.endsWith("/recovery")) {
                    """{"records":[{"cycle_id":101,"score":{"resting_heart_rate":99}}]}"""
                } else """{"records":[]}"""
                CloudHttpResponse(200, "application/json", body = body.toByteArray())
            },
        )
        val registry = HealthDistributionModule.provideHealthProviderRegistry(
            healthConnect = healthConnect,
            whoop = HealthDistributionModule.provideWhoop(api),
        )
        val repository = HealthModule.provideHealthRepository(registry, settings)
        val reportSource = DefaultClinicianReportDataSource(
            repository,
            healthConnect,
            ClinicianReportSourceLabelResolver(ApplicationProvider.getApplicationContext()),
            ClinicianReportDateProvider { day },
        )

        val input = reportSource.load(
            ReportConfiguration(ReportDateRange(day, day), setOf(ReportMetric.RESTING_HEART_RATE)),
            zone,
        )

        assertThat(requests).isEmpty()
        if (localFailure == null) {
            assertThat(input.dailyValues.map { it.value }).containsExactly(61.0)
            assertThat(input.warnings).isEmpty()
        } else {
            assertThat(input.dailyValues).isEmpty()
            assertThat(input.warnings).containsExactly(ClinicianReportWarning.ReadFailure)
            assertThat(input.warnings.joinToString()).doesNotContain("private local failure")
        }
        coVerify(exactly = 1) {
            manager.fetchHealthDataRange(
                listOf(day), DataTypeSelection().deselectAll().copy(heart = true), true, zone, true,
                attribution, any(),
            )
        }
        coVerify(exactly = 1) { settings.getSleepDayAttribution() }
        coVerify(exactly = 0) { settings.getSelectedHealthProviderId() }
        coVerify(exactly = 0) { settings.getConnectedHealthProviderIds() }
        coVerify(exactly = 0) { settings.setSelectedHealthProviderId(any()) }
        coVerify(exactly = 0) { settings.setHealthProviderConnected(any(), any()) }
        assertThat(settings.getSelectedHealthProviderId()).isEqualTo(selectedProviderId)
        assertThat(settings.getConnectedHealthProviderIds()).containsExactly("health_connect", "whoop")

        // Ordinary exports still honor the same selection after the report. Distinct WHOOP
        // sentinel data proves that a successful empty transport is not masking bad routing.
        val ordinary = repository.fetchHealthDataRange(
            dates = listOf(day),
            dataTypes = DataTypeSelection().deselectAll().copy(heart = true),
            zoneId = zone,
        )
        assertThat(requests.any { it.url.path.endsWith("/recovery") }).isTrue()
        if (selectedProviderId == "whoop" || localFailure != null) {
            assertThat(ordinary.single().heart.restingHeartRate).isEqualTo(99.0)
        }
    }
}
