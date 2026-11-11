package com.healthmd.clinicianreport

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.clinicianreport.ClinicianReportDateProvider
import com.healthmd.data.clinicianreport.ClinicianReportSourceLabelResolver
import com.healthmd.data.clinicianreport.DefaultClinicianReportDataSource
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthDataMerger
import com.healthmd.data.health.providers.cloud.CloudHealthApiClient
import com.healthmd.data.health.providers.cloud.CloudHealthRawResponse
import com.healthmd.di.HealthDistributionModule
import com.healthmd.di.HealthModule
import com.healthmd.domain.clinicianreport.ClinicianReportWarning
import com.healthmd.domain.clinicianreport.ReportConfiguration
import com.healthmd.domain.clinicianreport.ReportDateRange
import com.healthmd.domain.clinicianreport.ReportMetric
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportDetailSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.time.LocalDate
import java.time.ZoneId

@RunWith(RobolectricTestRunner::class)
class ClinicianReportLocalCaptureTest {
    @Test fun cloudSelectionCannotCaptureReportThroughCloudApi() = runTest {
        assertLocalReportCapture("whoop")
    }

    @Test fun allConnectedSelectionCannotCaptureReportThroughCloudApi() = runTest {
        assertLocalReportCapture(HealthDataMerger.ALL_CONNECTED_PROVIDER_ID)
    }

    @Test fun localPermissionFailureCannotFallbackToSelectedCloud() = runTest {
        assertLocalReportCapture("whoop", SecurityException("private local failure"))
    }

    @Test fun localPermissionFailureCannotFallbackToAllConnectedCloud() = runTest {
        assertLocalReportCapture(HealthDataMerger.ALL_CONNECTED_PROVIDER_ID, SecurityException("private local failure"))
    }

    private suspend fun assertLocalReportCapture(selectedProviderId: String, localFailure: Exception? = null) {
        val day = LocalDate.of(2026, 4, 5)
        val zone = ZoneId.of("Pacific/Chatham")
        val settings = mockk<SettingsRepository>(relaxed = true)
        coEvery { settings.getSelectedHealthProviderId() } returns selectedProviderId
        coEvery { settings.getConnectedHealthProviderIds() } returns setOf("health_connect", "whoop")
        coEvery { settings.getSleepDayAttribution() } returns SleepDayAttribution.NIGHT_BEGINS
        val manager = mockk<HealthConnectManager>()
        coEvery { manager.fetchHealthDataRange(any(), any(), any(), any(), any(), any(), any()) } answers {
            localFailure?.let { throw it }
            firstArg<List<LocalDate>>().map { HealthData(it, activity = ActivityData(steps = 1_234)) }
        }
        val healthConnect = HealthModule.provideHealthConnectDataProvider(manager)

        // The current Play registry and WHOOP adapter reach only a mocked API boundary.
        // Reports must never query this configured cloud source; ordinary exports still can.
        val api = mockk<CloudHealthApiClient>()
        coEvery { api.isConfigured("whoop") } returns true
        coEvery { api.token("whoop") } returns mockk()
        coEvery { api.forCaptureOperation("whoop") } returns api
        coEvery { api.captureConnectionId("whoop") } returns "11111111-1111-4111-8111-111111111111"
        coEvery { api.getJson(any(), any(), any(), any()) } returns
            Json.parseToJsonElement("""{"records":[]}""")
        val emptyPage = mockk<CloudHealthRawResponse>()
        every { emptyPage.jsonValid } returns true
        every { emptyPage.json } returns Json.parseToJsonElement("""{"records":[]}""")
        coEvery { api.getRawJsonResponse(any(), any(), any(), any(), any(), any()) } returns emptyPage
        val registry = HealthDistributionModule.provideHealthProviderRegistry(
            healthConnect = healthConnect,
            whoop = HealthDistributionModule.provideWhoop(api),
        )
        val repository = HealthModule.provideHealthRepository(registry, settings)
        val reportSource = DefaultClinicianReportDataSource(
            healthConnect,
            ClinicianReportSourceLabelResolver(ApplicationProvider.getApplicationContext()),
            ClinicianReportDateProvider { day },
        )

        val input = reportSource.load(
            ReportConfiguration(ReportDateRange(day, day), setOf(ReportMetric.STEPS)),
            zone,
        )

        coVerify(exactly = 0) { api.getJson(any(), any(), any(), any()) }
        coVerify(exactly = 0) { api.getRawJsonResponse(any(), any(), any(), any(), any(), any()) }
        coVerify(exactly = 0) { api.isConfigured(any()) }
        coVerify(exactly = 0) { api.token(any()) }
        coVerify(exactly = 0) { api.forCaptureOperation(any()) }
        coVerify(exactly = 0) { api.captureConnectionId(any()) }
        if (localFailure == null) {
            assertThat(input.dailyValues.map { it.value }).containsExactly(1_234.0)
            assertThat(input.warnings).isEmpty()
        } else {
            assertThat(input.dailyValues).isEmpty()
            assertThat(input.warnings).containsExactly(ClinicianReportWarning.ReadFailure)
            assertThat(input.warnings.joinToString()).doesNotContain("private local failure")
        }
        coVerify(exactly = 1) {
            manager.fetchHealthDataRange(
                listOf(day), DataTypeSelection().deselectAll().copy(activity = true), true, zone, true,
                SleepDayAttribution.NIGHT_BEGINS, ExportDetailSelection.uniform(true),
            )
        }
        coVerify(exactly = 0) { settings.getSelectedHealthProviderId() }
        coVerify(exactly = 0) { settings.getConnectedHealthProviderIds() }
        coVerify(exactly = 0) { settings.setSelectedHealthProviderId(any()) }
        coVerify(exactly = 0) { settings.setHealthProviderConnected(any(), any()) }
        assertThat(settings.getSelectedHealthProviderId()).isEqualTo(selectedProviderId)
        assertThat(settings.getConnectedHealthProviderIds()).containsExactly("health_connect", "whoop")

        // Ordinary export still honors the same cloud/all-connected preference after a report.
        repository.fetchHealthDataRange(
            listOf(day), DataTypeSelection().deselectAll().copy(activity = true), false, zone, false,
        )
        coVerify(atLeast = 1) { api.getRawJsonResponse("whoop", any(), any(), any(), any(), any()) }
    }
}
