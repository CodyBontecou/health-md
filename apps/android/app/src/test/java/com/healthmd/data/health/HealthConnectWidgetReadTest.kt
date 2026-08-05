package com.healthmd.data.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import com.google.common.truth.Truth.assertThat
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.slot
import java.io.IOException
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.Test

class HealthConnectWidgetReadTest {
    @Test
    fun `steps-only widget read aggregates only steps`() = runTest {
        val client = mockk<HealthConnectClient>()
        val request = slot<AggregateGroupByPeriodRequest>()
        coEvery { client.aggregateGroupByPeriod(capture(request)) } returns emptyList()
        val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)

        val result = manager.fetchWidgetHealthDataRange(
            dates = listOf(LocalDate.parse("2026-08-02")),
            selection = HealthConnectWidgetReadSelection(steps = true),
        )

        assertThat(result).hasSize(1)
        val metricsField = request.captured.javaClass.getDeclaredField("metrics").apply {
            isAccessible = true
        }
        @Suppress("UNCHECKED_CAST")
        val metrics = metricsField.get(request.captured) as Set<Any>
        assertThat(metrics).containsExactly(StepsRecord.COUNT_TOTAL)
        coVerify(exactly = 1) { client.aggregateGroupByPeriod(any()) }
    }

    @Test
    fun `sleep widget read sends the noon journal lookback interval to Health Connect`() = runTest {
        val client = mockk<HealthConnectClient>()
        val request = slot<ReadRecordsRequest<SleepSessionRecord>>()
        coEvery { client.readRecords(capture(request)) } returns ReadRecordsResponse(emptyList(), null)
        val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
        val date = LocalDate.parse("2026-08-02")

        val result = manager.fetchWidgetHealthDataRange(
            dates = listOf(date),
            selection = HealthConnectWidgetReadSelection(sleepSessions = true),
        )

        val zone = ZoneId.systemDefault()
        assertThat(result).hasSize(1)
        assertThat(request.captured.recordType).isEqualTo(SleepSessionRecord::class)
        assertThat(request.captured.timeRangeFilter.startTime).isEqualTo(
            date.minusDays(1).atTime(LocalTime.NOON).atZone(zone).toInstant(),
        )
        assertThat(request.captured.timeRangeFilter.endTime).isEqualTo(
            date.plusDays(1).atTime(LocalTime.NOON).atZone(zone).toInstant(),
        )
        coVerify(exactly = 1) { client.readRecords(any<ReadRecordsRequest<SleepSessionRecord>>()) }
    }

    @Test
    fun `focused aggregate failures propagate so callers retain last-good data`() = runTest {
        val client = mockk<HealthConnectClient>()
        coEvery { client.aggregateGroupByPeriod(any()) } throws IOException("provider failure")
        val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)

        val failure = runCatching {
            manager.fetchWidgetHealthDataRange(
                dates = listOf(LocalDate.parse("2026-08-02")),
                selection = HealthConnectWidgetReadSelection(steps = true),
            )
        }.exceptionOrNull()

        assertThat(failure).isInstanceOf(IOException::class.java)
    }
}
