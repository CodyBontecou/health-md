package com.healthmd.data.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Percentage
import androidx.health.connect.client.request.AggregateRequest
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
import java.util.TimeZone
import kotlinx.coroutines.test.runTest
import org.junit.Test

class HealthConnectWidgetReadTest {
    @Test
    fun `steps-only widget read aggregates only steps`() = runTest {
        val client = mockk<HealthConnectClient>()
        val request = slot<AggregateRequest>()
        val aggregateResult = mockk<androidx.health.connect.client.aggregate.AggregationResult>()
        io.mockk.every { aggregateResult[StepsRecord.COUNT_TOTAL] } returns null
        coEvery { client.aggregate(capture(request)) } returns aggregateResult
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
        coVerify(exactly = 1) { client.aggregate(any()) }
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
    fun `widget read uses explicitly pinned zone instead of ambient system default`() = runTest {
        val client = mockk<HealthConnectClient>()
        val request = slot<ReadRecordsRequest<SleepSessionRecord>>()
        coEvery { client.readRecords(capture(request)) } returns ReadRecordsResponse(emptyList(), null)
        val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
        val date = LocalDate.parse("2026-08-02")
        val pinned = ZoneId.of("Pacific/Auckland")

        manager.fetchWidgetHealthDataRange(
            dates = listOf(date),
            selection = HealthConnectWidgetReadSelection(sleepSessions = true),
            zoneId = pinned,
        )

        assertThat(request.captured.timeRangeFilter.startTime).isEqualTo(
            date.minusDays(1).atTime(LocalTime.NOON).atZone(pinned).toInstant(),
        )
        assertThat(request.captured.timeRangeFilter.endTime).isEqualTo(
            date.plusDays(1).atTime(LocalTime.NOON).atZone(pinned).toInstant(),
        )
    }

    @Test
    fun `widget aggregate read uses exact pinned zone boundaries`() = runTest {
        val previous = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            val client = mockk<HealthConnectClient>()
            val request = slot<AggregateRequest>()
            val aggregateResult = mockk<androidx.health.connect.client.aggregate.AggregationResult>()
            io.mockk.every { aggregateResult[StepsRecord.COUNT_TOTAL] } returns null
            coEvery { client.aggregate(capture(request)) } returns aggregateResult
            val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
            val date = LocalDate.parse("2026-04-05")
            val pinned = ZoneId.of("Pacific/Chatham")

            manager.fetchWidgetHealthDataRange(
                dates = listOf(date),
                selection = HealthConnectWidgetReadSelection(steps = true),
                zoneId = pinned,
            )

            val range = request.captured.javaClass.getDeclaredField("timeRangeFilter").let { field ->
                field.isAccessible = true
                field.get(request.captured) as androidx.health.connect.client.time.TimeRangeFilter
            }
            assertThat(range.startTime).isEqualTo(date.atStartOfDay(pinned).toInstant())
            assertThat(range.endTime).isEqualTo(date.plusDays(1).atStartOfDay(pinned).toInstant())
            assertThat(range.startTime).isNotEqualTo(date.atStartOfDay(ZoneId.of("UTC")).toInstant())
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    @Test
    fun `oxygen-only read paginates and converts percent exactly once`() = runTest {
        val client = mockk<HealthConnectClient>()
        val requests = mutableListOf<ReadRecordsRequest<OxygenSaturationRecord>>()
        val date = LocalDate.parse("2026-08-02")
        fun oxygen(value: Double) = OxygenSaturationRecord(
            time = date.atStartOfDay(ZoneId.systemDefault()).toInstant(), zoneOffset = null,
            percentage = Percentage(value), metadata = Metadata.manualEntry(),
        )
        coEvery { client.readRecords(any<ReadRecordsRequest<OxygenSaturationRecord>>()) } answers {
            val request = firstArg<ReadRecordsRequest<OxygenSaturationRecord>>(); requests += request
            if (request.pageToken == null) ReadRecordsResponse(listOf(oxygen(98.0)), "next")
            else ReadRecordsResponse(listOf(oxygen(96.0)), null)
        }
        val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
        val result = manager.fetchWidgetHealthDataRange(
            dates = listOf(date), selection = HealthConnectWidgetReadSelection(oxygenSaturation = true),
        ).single()
        assertThat(requests).hasSize(2)
        assertThat(result.vitals.bloodOxygenAvg).isWithin(0.0001).of(0.97)
        assertThat(result.vitals.bloodOxygenMin).isWithin(0.0001).of(0.96)
        assertThat(result.vitals.bloodOxygenMax).isWithin(0.0001).of(0.98)
    }

    @Test
    fun `focused aggregate failures propagate so callers retain last-good data`() = runTest {
        val client = mockk<HealthConnectClient>()
        coEvery { client.aggregate(any()) } throws IOException("provider failure")
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
