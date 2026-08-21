package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.widget.data.HealthConnectWidgetDataSource
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class WidgetHealthDataSourceTest {
    private fun settingsRepository(mode: SleepDayAttribution = SleepDayAttribution.DEFAULT): SettingsRepository =
        mockk {
            every { sleepDayAttribution } returns flowOf(mode)
            coEvery { getSleepDayAttribution() } returns mode
        }

    @Test
    fun `reads fourteen calendar days with narrow categories and fills missing dates`() = runTest {
        val provider = mockk<HealthConnectDataProvider>()
        val today = LocalDate.parse("2026-08-02")
        coEvery {
            provider.fetchWidgetHealthDataRange(any(), any(), any(), any())
        } returns listOf(HealthData(date = today))
        val source = HealthConnectWidgetDataSource(provider, settingsRepository())
        val selection = HealthConnectWidgetReadSelection(
            steps = true,
            sleepSessions = true,
        )

        val zone = ZoneId.of("Pacific/Auckland")
        val result = source.readRecentDays(today, selection, zoneId = zone)

        assertThat(result).hasSize(14)
        assertThat(result.first().date).isEqualTo(today.minusDays(13))
        assertThat(result.last().date).isEqualTo(today)
        coVerify(exactly = 1) {
            provider.fetchWidgetHealthDataRange(
                dates = match { it.size == 14 && it.first() == today.minusDays(13) && it.last() == today },
                selection = selection,
                zoneId = zone,
                sleepDayAttribution = SleepDayAttribution.DEFAULT,
            )
        }
    }

    @Test
    fun `honors the persisted wake-up-date attribution like every other capture path`() = runTest {
        val provider = mockk<HealthConnectDataProvider>()
        val today = LocalDate.parse("2026-08-02")
        coEvery {
            provider.fetchWidgetHealthDataRange(any(), any(), any(), any())
        } returns listOf(HealthData(date = today))
        val source = HealthConnectWidgetDataSource(provider, settingsRepository(SleepDayAttribution.MORNING_ENDS))
        val selection = HealthConnectWidgetReadSelection(
            sleepSessions = true,
        )

        source.readRecentDays(today, selection)

        coVerify(exactly = 1) {
            provider.fetchWidgetHealthDataRange(
                dates = any(),
                selection = selection,
                zoneId = any(),
                sleepDayAttribution = SleepDayAttribution.MORNING_ENDS,
            )
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun `refuses a read with no installed widget requirements`() = runTest {
        val source = HealthConnectWidgetDataSource(mockk(relaxed = true), settingsRepository())
        source.readRecentDays(
            today = LocalDate.parse("2026-08-02"),
            selection = HealthConnectWidgetReadSelection(),
        )
    }
}
