package com.healthmd.data.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.records.ExerciseRouteResult
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SpeedRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.units.Velocity
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.rawexport.ExerciseRouteConsentGateway
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.test.runTest
import org.junit.Test

/**
 * Issue #431: Play reported OutOfMemoryError in buildWorkoutData. Series sources are read for the
 * whole chunk (up to 30 days), and every workout paired each of their samples with its record
 * before filtering to the workout window. A workout must only expand the samples of records that
 * overlap it, while still attributing every in-window sample.
 */
class HealthConnectWorkoutSeriesMemoryTest {

    private val utc = ZoneId.of("UTC")
    private val dates = (0L..6L).map { LocalDate.of(2026, 11, 14).plusDays(it) }
    private val sessionStart = Instant.parse("2026-11-20T06:00:00Z")
    private val sessionEnd = Instant.parse("2026-11-20T06:30:00Z")

    private fun session(): ExerciseSessionRecord = mockk {
        every { startTime } returns sessionStart
        every { endTime } returns sessionEnd
        every { startZoneOffset } returns null
        every { endZoneOffset } returns null
        every { metadata } returns Metadata.manualEntryWithId("run-1", null)
        every { exerciseType } returns ExerciseSessionRecord.EXERCISE_TYPE_RUNNING
        every { title } returns null
        every { notes } returns null
        every { segments } returns emptyList()
        every { laps } returns emptyList()
        every { plannedExerciseSessionId } returns null
        every { exerciseRouteResult } returns ExerciseRouteResult.NoData()
    }

    /** Day-long records far from the workout whose samples must never be expanded. */
    private fun untouchableHeartRate(id: String, start: Instant): HeartRateRecord = mockk {
        every { startTime } returns start
        every { endTime } returns start.plusSeconds(86_399)
        every { metadata } returns Metadata.manualEntryWithId(id, null)
        every { samples } throws AssertionError("samples of $id expanded for a workout it does not overlap")
    }

    private fun untouchableSpeed(id: String, start: Instant): SpeedRecord = mockk {
        every { startTime } returns start
        every { endTime } returns start.plusSeconds(86_399)
        every { metadata } returns Metadata.manualEntryWithId(id, null)
        every { samples } throws AssertionError("samples of $id expanded for a workout it does not overlap")
    }

    private fun heartRate(id: String, start: Instant, end: Instant, vararg bpm: Pair<Instant, Long>) = HeartRateRecord(
        startTime = start,
        startZoneOffset = null,
        endTime = end,
        endZoneOffset = null,
        samples = bpm.map { (time, value) -> HeartRateRecord.Sample(time, value) },
        metadata = Metadata.manualEntryWithId(id, null),
    )

    private fun aggregation(): AggregationResult = mockk<AggregationResult>(relaxed = true).also {
        every { it[StepsRecord.COUNT_TOTAL] } returns 0L
    }

    private fun client(records: Map<kotlin.reflect.KClass<*>, List<Any>>): HealthConnectClient {
        val client = mockk<HealthConnectClient>()
        val features = mockk<HealthConnectFeatures>()
        every { features.getFeatureStatus(any()) } returns HealthConnectFeatures.FEATURE_STATUS_UNAVAILABLE
        every { client.features } returns features
        coEvery { client.aggregate(any<AggregateRequest>()) } returns aggregation()
        coEvery { client.readRecords(any<ReadRecordsRequest<ExerciseSessionRecord>>()) } answers {
            val request = firstArg<ReadRecordsRequest<*>>()
            @Suppress("UNCHECKED_CAST")
            ReadRecordsResponse(records[request.recordType].orEmpty() as List<ExerciseSessionRecord>, null)
        }
        return client
    }

    @Test
    fun workoutOnlyExpandsSeriesRecordsOverlappingItsWindow() = runTest {
        // Spans the session start; only its in-window samples count.
        val spanning = heartRate(
            "hr-spanning",
            Instant.parse("2026-11-20T05:50:00Z"),
            Instant.parse("2026-11-20T06:10:00Z"),
            Instant.parse("2026-11-20T05:55:00Z") to 70L,
            Instant.parse("2026-11-20T06:05:00Z") to 120L,
        )
        // Ends exactly at session start: the boundary sample is inside (inclusive window).
        val boundary = heartRate(
            "hr-boundary",
            Instant.parse("2026-11-20T05:40:00Z"),
            sessionStart,
            sessionStart to 100L,
        )
        val inside = heartRate(
            "hr-inside",
            Instant.parse("2026-11-20T06:15:00Z"),
            Instant.parse("2026-11-20T06:20:00Z"),
            Instant.parse("2026-11-20T06:16:00Z") to 140L,
        )
        val farHeart = dates.filter { it != LocalDate.of(2026, 11, 20) }.map { day ->
            untouchableHeartRate("hr-far-$day", day.atStartOfDay(utc).toInstant())
        }
        val farSpeed = listOf(untouchableSpeed("speed-far", Instant.parse("2026-11-14T00:00:00Z")))
        val speed = SpeedRecord(
            startTime = Instant.parse("2026-11-20T06:00:00Z"),
            startZoneOffset = null,
            endTime = Instant.parse("2026-11-20T06:30:00Z"),
            endZoneOffset = null,
            samples = listOf(SpeedRecord.Sample(Instant.parse("2026-11-20T06:10:00Z"), Velocity.metersPerSecond(3.0))),
            metadata = Metadata.manualEntryWithId("speed-in", null),
        )

        val manager = HealthConnectManager(
            mockk<Context>(relaxed = true),
            client(
                mapOf(
                    ExerciseSessionRecord::class to listOf(session()),
                    HeartRateRecord::class to farHeart + listOf(spanning, boundary, inside),
                    SpeedRecord::class to farSpeed + listOf(speed),
                ),
            ),
            routeConsentGateway = ExerciseRouteConsentGateway { emptyMap() },
        )

        val data = manager.fetchHealthDataRange(
            dates = dates,
            selection = DataTypeSelection().deselectAll().copy(workouts = true),
            includeGranularData = true,
            zoneId = utc,
        )

        val workout = data.flatMap { it.workouts }.single()
        assertThat(workout.heartRateSamples.map { it.value }).containsExactly(100.0, 120.0, 140.0).inOrder()
        assertThat(workout.heartRateMin).isEqualTo(100.0)
        assertThat(workout.heartRateMax).isEqualTo(140.0)
        assertThat(workout.speedSamples.map { it.value }).containsExactly(3.0)
        assertThat(workout.correlatedSourceIds["heart_rate"])
            .containsExactly("hr-boundary", "hr-inside", "hr-spanning").inOrder()
        assertThat(workout.correlatedSourceIds["speed"]).containsExactly("speed-in")
    }
}
