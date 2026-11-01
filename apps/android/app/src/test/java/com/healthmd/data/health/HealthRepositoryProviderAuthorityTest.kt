package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthProviderCaptureAuthority
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepDayAttributionOverride
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Test

/** Runs in both channels: missing cloud adapters must never become Health Connect captures. */
class HealthRepositoryProviderAuthorityTest {
    private val day = LocalDate.of(2026, 7, 1)
    private val sdk = mockk<HealthConnectManager>()
    private val settings = mockk<SettingsRepository>()
    private val repository: HealthRepositoryImpl
        get() = HealthRepositoryImpl(HealthProviderRegistry(HealthConnectDataProvider(sdk)), settings)

    private fun configure() {
        coEvery { settings.getSelectedHealthProviderId() } returns "whoop"
        coEvery { sdk.isAvailable() } returns true
        coEvery { sdk.hasAllPermissions() } returns true
        coEvery { sdk.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
            firstArg<List<LocalDate>>().map { HealthData(it, activity = ActivityData(steps = 99)) }
        }
    }

    @Test
    fun restoredLocalSelectionIgnoresCurrentCloudChoiceAndKeepsLivePermissions() = runTest {
        configure()
        val authority = HealthProviderCaptureAuthority(selectedProviderId = "health_connect",
            providerIds = listOf("health_connect"), connectionIds = emptyMap())
        val restored = repository.restoreProviderAuthority(authority)
        assertThat(restored.fetchHealthDataRange(listOf(day), sleepDayAttributionOverride =
            SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS)).single().activity.steps).isEqualTo(99)
        assertThat(restored.hasPermissions()).isTrue()
        coEvery { sdk.hasAllPermissions() } returns false
        assertThat(restored.hasPermissions()).isFalse()
    }

    @Test
    fun missingAcceptedCloudAdapterNeverFallsBackToLocalData() = runTest {
        configure()
        val authority = HealthProviderCaptureAuthority(selectedProviderId = "whoop", providerIds = listOf("whoop"),
            connectionIds = mapOf("whoop" to null))
        assertThat(runCatching { repository.restoreProviderAuthority(authority) }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        coVerify(exactly = 0) { sdk.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) }
    }

    @Test
    fun missingAllConnectedAdapterRemainsAnExplicitFailureFact() = runTest {
        configure()
        val authority = HealthProviderCaptureAuthority(selectedProviderId = "all_connected",
            providerIds = listOf("health_connect", "whoop"), connectionIds = mapOf("whoop" to null))
        val data = repository.restoreProviderAuthority(authority).fetchHealthDataRange(listOf(day),
            sleepDayAttributionOverride = SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS)).single()
        assertThat(data.activity.steps).isEqualTo(99)
        assertThat(data.compatibilityProvenance?.providerFailures?.single()?.errorType).isEqualTo("ProviderNotRegistered")
        assertThat(data.compatibilityProvenance?.providerIdsAttempted).containsExactly("health_connect", "whoop")
    }
}
