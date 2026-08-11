package com.healthmd.data.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.MindfulnessSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.time.TimeRangeFilter
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.DataTypeSelection
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.Duration
import java.time.LocalDate
import java.time.ZoneId
import java.util.TimeZone

class HealthConnectPinnedZoneRangeTest {
    @Test fun reportModeAggregatesStepsOverExactPinnedDstDaysWithoutPeriodAggregation() = runTest {
        val previous = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            val pinned = ZoneId.of("Pacific/Chatham")
            assertThat(ZoneId.systemDefault()).isNotEqualTo(pinned)
            val fallBackDay = LocalDate.of(2026, 4, 5)
            val springForwardDay = LocalDate.of(2026, 9, 27)
            val aggregateRequests = mutableListOf<AggregateRequest>()
            val aggregateResult = mockk<AggregationResult>()
            every { aggregateResult[StepsRecord.COUNT_TOTAL] } returns 1_234L
            val features = mockk<HealthConnectFeatures>()
            every { features.getFeatureStatus(any()) } returns
                HealthConnectFeatures.FEATURE_STATUS_UNAVAILABLE
            val client = mockk<HealthConnectClient>()
            every { client.features } returns features
            coEvery { client.aggregate(capture(aggregateRequests)) } returns aggregateResult
            coEvery {
                client.readRecords(any<ReadRecordsRequest<ExerciseSessionRecord>>())
            } returns ReadRecordsResponse(emptyList(), null)
            coEvery {
                client.readRecords(any<ReadRecordsRequest<StepsRecord>>())
            } returns ReadRecordsResponse(emptyList(), null)
            val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)

            val result = manager.fetchHealthDataRange(
                dates = listOf(fallBackDay, springForwardDay),
                selection = DataTypeSelection().deselectAll().copy(activity = true),
                includeGranularData = true,
                zoneId = pinned,
                pinnedCalendarDays = true,
            )

            assertThat(result.map { it.activity.steps }).containsExactly(1_234, 1_234).inOrder()
            assertThat(aggregateRequests).hasSize(2)
            val requestsByStart = aggregateRequests.associateBy {
                it.timeRangeFilterForTest().startTime
            }
            for ((date, expectedHours) in listOf(fallBackDay to 25L, springForwardDay to 23L)) {
                val expectedStart = date.atStartOfDay(pinned).toInstant()
                val expectedEnd = date.plusDays(1).atStartOfDay(pinned).toInstant()
                val request = requestsByStart.getValue(expectedStart)
                assertThat(request.metricsForTest()).containsExactly(StepsRecord.COUNT_TOTAL)
                assertThat(request.timeRangeFilterForTest().endTime).isEqualTo(expectedEnd)
                assertThat(Duration.between(expectedStart, expectedEnd).toHours()).isEqualTo(expectedHours)
                assertThat(expectedStart)
                    .isNotEqualTo(date.atStartOfDay(ZoneId.of("UTC")).toInstant())
            }
            coVerify(exactly = 0) {
                client.aggregateGroupByPeriod(any<AggregateGroupByPeriodRequest>())
            }
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    @Test fun managerUsesPinnedNonDefaultZoneForInstantBoundary() = runTest {
        val previous = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
            val pinned = ZoneId.of("Pacific/Chatham")
            assertThat(ZoneId.systemDefault()).isNotEqualTo(pinned)
            val request = slot<ReadRecordsRequest<MindfulnessSessionRecord>>()
            val client = mockk<HealthConnectClient>()
            coEvery { client.readRecords(capture(request)) } returns
                ReadRecordsResponse(emptyList(), null)
            val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
            val day = LocalDate.of(2026, 4, 5)

            manager.fetchHealthDataRange(
                dates = listOf(day),
                selection = DataTypeSelection().deselectAll().copy(mindfulness = true),
                includeGranularData = true,
                zoneId = pinned,
            )

            assertThat(request.captured.timeRangeFilter.startTime)
                .isEqualTo(day.atStartOfDay(pinned).toInstant())
            assertThat(request.captured.timeRangeFilter.endTime)
                .isEqualTo(day.plusDays(1).atStartOfDay(pinned).toInstant())
            assertThat(request.captured.timeRangeFilter.startTime)
                .isNotEqualTo(day.atStartOfDay(ZoneId.of("UTC")).toInstant())
        } finally {
            TimeZone.setDefault(previous)
        }
    }

    @Suppress("UNCHECKED_CAST")
    private fun AggregateRequest.metricsForTest(): Set<AggregateMetric<*>> =
        AggregateRequest::class.java.getDeclaredField("metrics").let { field ->
            field.isAccessible = true
            field.get(this) as Set<AggregateMetric<*>>
        }

    private fun AggregateRequest.timeRangeFilterForTest(): TimeRangeFilter =
        AggregateRequest::class.java.getDeclaredField("timeRangeFilter").let { field ->
            field.isAccessible = true
            field.get(this) as TimeRangeFilter
        }
}
