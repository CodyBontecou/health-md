package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.widget.data.HealthConnectWidgetDataSource
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.LocalDate

class WidgetHealthDataSourceTest {
    @Test
    fun `reads fourteen calendar days with narrow categories and fills missing dates`() = runTest {
        val provider = mockk<HealthConnectDataProvider>()
        val today = LocalDate.parse("2026-08-02")
        coEvery {
            provider.fetchWidgetHealthDataRange(any(), any())
        } returns listOf(HealthData(date = today))
        val source = HealthConnectWidgetDataSource(provider)
        val selection = HealthConnectWidgetReadSelection(
            steps = true,
            sleepSessions = true,
        )

        val result = source.readRecentDays(today, selection)

        assertThat(result).hasSize(14)
        assertThat(result.first().date).isEqualTo(today.minusDays(13))
        assertThat(result.last().date).isEqualTo(today)
        coVerify(exactly = 1) {
            provider.fetchWidgetHealthDataRange(
                dates = match { it.size == 14 && it.first() == today.minusDays(13) && it.last() == today },
                selection = selection,
            )
        }
    }

    @Test(expected = IllegalArgumentException::class)
    fun `refuses a read with no installed widget requirements`() = runTest {
        val source = HealthConnectWidgetDataSource(mockk(relaxed = true))
        source.readRecentDays(
            today = LocalDate.parse("2026-08-02"),
            selection = HealthConnectWidgetReadSelection(),
        )
    }
}
