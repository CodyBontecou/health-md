package com.healthmd.data.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.BodyWaterMassRecord
import androidx.health.connect.client.records.BoneMassRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ElevationGainedRecord
import androidx.health.connect.client.records.FloorsClimbedRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.HydrationRecord
import androidx.health.connect.client.records.LeanBodyMassRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.units.Energy
import androidx.health.connect.client.units.Length
import androidx.health.connect.client.units.Mass
import androidx.health.connect.client.units.Percentage
import androidx.health.connect.client.units.Volume
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportDetailChoice
import com.healthmd.domain.model.ExportDetailGroup
import com.healthmd.domain.model.ExportDetailSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.reflect.KClass

/**
 * android-analytical-v7 capture: one sample per Health Connect record, start-owned, with exact
 * start/end instants, offsets, identity, and metadata preserved; paged; permission-tolerant.
 */
class HealthConnectAnalyticalV7CaptureTest {
    private val zone: ZoneId = ZoneId.of("America/New_York")
    private val day: LocalDate = LocalDate.of(2026, 3, 15)
    private val next: LocalDate = day.plusDays(1)
    private val offset: ZoneOffset = ZoneOffset.ofHours(-4)
    private val endOffset: ZoneOffset = ZoneOffset.ofHours(-5)
    private val start: Instant = Instant.parse("2026-03-15T14:00:00.123456789Z")
    private val end: Instant = Instant.parse("2026-03-15T14:30:00.987654321Z")
    // Starts 23:50 local on [day] and ends after midnight: owned by its start date.
    private val lateStart: Instant = LocalDateTime.of(2026, 3, 15, 23, 50).atZone(zone).toInstant()
    private val lateEnd: Instant = lateStart.plusSeconds(1_200)
    private val nextStart: Instant = LocalDateTime.of(2026, 3, 16, 9, 0).atZone(zone).toInstant()

    private fun meta(id: String) = Metadata.manualEntryWithId(id)

    private val v7Detail = ExportDetailSelection.resolve(
        false,
        mapOf(
            ExportDetailGroup.ACTIVITY to ExportDetailChoice.DETAILED,
            ExportDetailGroup.NUTRITION to ExportDetailChoice.DETAILED,
            ExportDetailGroup.BODY to ExportDetailChoice.DETAILED,
        ),
    )

    private val selection = DataTypeSelection().deselectAll().copy(activity = true, nutrition = true, body = true)

    private fun records(): Map<KClass<out Record>, List<List<Record>>> = mapOf(
        // Two pages prove paging is followed.
        ActiveCaloriesBurnedRecord::class to listOf(
            listOf(ActiveCaloriesBurnedRecord(start, offset, end, endOffset, Energy.kilocalories(45.5), meta("ac-1"))),
            listOf(
                ActiveCaloriesBurnedRecord(lateStart, offset, lateEnd, offset, Energy.kilocalories(10.0), meta("ac-2")),
                ActiveCaloriesBurnedRecord(nextStart, offset, nextStart.plusSeconds(60), offset, Energy.kilocalories(3.0), meta("ac-3")),
            ),
        ),
        TotalCaloriesBurnedRecord::class to listOf(listOf(
            TotalCaloriesBurnedRecord(start, offset, end, endOffset, Energy.kilocalories(120.5), meta("tc-1")),
        )),
        DistanceRecord::class to listOf(listOf(
            DistanceRecord(start, offset, end, endOffset, Length.meters(850.5), meta("d-1")),
        )),
        FloorsClimbedRecord::class to listOf(listOf(
            FloorsClimbedRecord(start, offset, end, endOffset, 2.5, meta("f-1")),
        )),
        ElevationGainedRecord::class to listOf(listOf(
            ElevationGainedRecord(start, offset, end, endOffset, Length.meters(6.5), meta("e-1")),
        )),
        HydrationRecord::class to listOf(listOf(
            HydrationRecord(start, offset, end, endOffset, Volume.liters(0.25), meta("h-1")),
            HydrationRecord(start.plusSeconds(3_600), offset, end.plusSeconds(3_600), offset, Volume.liters(0.5), meta("h-2")),
        )),
        WeightRecord::class to listOf(listOf(
            WeightRecord(start, offset, Mass.kilograms(75.5), meta("w-1")),
            WeightRecord(end, offset, Mass.kilograms(75.25), meta("w-2")),
        )),
        HeightRecord::class to listOf(listOf(HeightRecord(start, offset, Length.meters(1.78), meta("ht-1")))),
        BodyFatRecord::class to listOf(listOf(BodyFatRecord(start, offset, Percentage(18.5), meta("bf-1")))),
        LeanBodyMassRecord::class to listOf(listOf(LeanBodyMassRecord(start, offset, Mass.kilograms(60.5), meta("lm-1")))),
        BoneMassRecord::class to listOf(listOf(BoneMassRecord(start, null, Mass.kilograms(3.2), meta("bm-1")))),
        BodyWaterMassRecord::class to listOf(listOf(BodyWaterMassRecord(start, offset, Mass.kilograms(45.5), meta("bw-1")))),
    )

    private fun manager(
        denied: Set<KClass<out Record>> = emptySet(),
        requested: MutableList<KClass<*>> = mutableListOf(),
    ): HealthConnectManager {
        val pages = records()
        val features = mockk<HealthConnectFeatures>()
        every { features.getFeatureStatus(any()) } returns HealthConnectFeatures.FEATURE_STATUS_UNAVAILABLE
        val aggregate = mockk<AggregationResult>()
        every { aggregate[StepsRecord.COUNT_TOTAL] } returns null
        val client = mockk<HealthConnectClient>()
        every { client.features } returns features
        coEvery { client.aggregate(any<AggregateRequest>()) } returns aggregate
        coEvery { client.aggregateGroupByPeriod(any<AggregateGroupByPeriodRequest>()) } returns emptyList()
        coEvery { client.readRecords(any<ReadRecordsRequest<Record>>()) } answers {
            val request = firstArg<ReadRecordsRequest<*>>()
            requested += request.recordType
            if (request.recordType in denied) throw SecurityException("Caller doesn't have permission to read data")
            val typePages = pages[request.recordType].orEmpty()
            val index = request.pageToken?.removePrefix("page-")?.toInt() ?: 0
            val page = typePages.getOrNull(index).orEmpty()
            val token = if (index + 1 < typePages.size) "page-${index + 1}" else null
            ReadRecordsResponse(page, token)
        }
        return HealthConnectManager(mockk<Context>(relaxed = true), client)
    }

    private suspend fun HealthConnectManager.capture(
        detail: ExportDetailSelection,
        attribution: SleepDayAttribution = SleepDayAttribution.DEFAULT,
    ): Map<LocalDate, HealthData> = fetchHealthDataRange(
        dates = listOf(day, next),
        selection = selection,
        includeGranularData = detail.any,
        zoneId = zone,
        pinnedCalendarDays = true,
        sleepDayAttribution = attribution,
        detail = detail,
    ).associateBy { it.date }

    @Test
    fun capturesOneStartOwnedSamplePerRecordWithExactProvenance() = runTest {
        val byDate = manager().capture(v7Detail)
        val activity = byDate.getValue(day).activity

        // Paged: page one and page two; the cross-midnight record stays on its start date.
        assertThat(activity.activeCaloriesSamples.map { it.value }).containsExactly(45.5, 10.0).inOrder()
        assertThat(byDate.getValue(next).activity.activeCaloriesSamples.map { it.value }).containsExactly(3.0)

        val first = activity.activeCaloriesSamples.first()
        assertThat(first.time).isEqualTo(LocalDateTime.ofInstant(start, zone))
        assertThat(first.exactTime?.instant()).isEqualTo(start)
        assertThat(first.exactTime?.offset).isEqualTo("-04:00")
        assertThat(first.exactEndTime?.instant()).isEqualTo(end)
        assertThat(first.exactEndTime?.offset).isEqualTo("-05:00")
        assertThat(first.identity?.nativeId).isEqualTo("ac-1")
        assertThat(first.identity?.isSynthetic).isFalse()
        assertThat(first.metadata["health_connect_id"]).isEqualTo("ac-1")
        assertThat(first.metadata["recording_method"]).isEqualTo("manual_entry")
        val late = activity.activeCaloriesSamples[1]
        assertThat(late.exactEndTime?.instant()).isEqualTo(lateEnd)

        assertThat(activity.totalCaloriesSamples.single().value).isEqualTo(120.5)
        assertThat(activity.distanceSamples.single().value).isEqualTo(850.5)
        assertThat(activity.floorsSamples.single().value).isEqualTo(2.5)
        assertThat(activity.elevationSamples.single().value).isEqualTo(6.5)

        val nutrition = byDate.getValue(day).nutrition
        assertThat(nutrition.hydrationSamples.map { it.value }).containsExactly(0.25, 0.5).inOrder()
        assertThat(nutrition.hydrationSamples.first().identity?.nativeId).isEqualTo("h-1")

        val body = byDate.getValue(day).body
        // No dedupe: both weigh-ins remain, in kilograms, instantaneous (no end instant).
        assertThat(body.weightSamples.map { it.value }).containsExactly(75.5, 75.25).inOrder()
        assertThat(body.weightSamples.first().exactEndTime).isNull()
        assertThat(body.weightSamples.first().exactTime?.instant()).isEqualTo(start)
        assertThat(body.weightSamples.first().identity?.nativeId).isEqualTo("w-1")
        assertThat(body.heightSamples.single().value).isEqualTo(1.78)
        assertThat(body.bodyFatSamples.single().value).isWithin(1e-12).of(0.185)
        assertThat(body.leanBodyMassSamples.single().value).isEqualTo(60.5)
        assertThat(body.boneMassSamples.single().exactTime?.offset).isNull()
        assertThat(body.bodyWaterMassSamples.single().value).isEqualTo(45.5)
        // Summaries are unchanged by the expansion: latest-of-day for weight.
        assertThat(body.weight).isEqualTo(75.25)
    }

    @Test
    fun uniformDetailAndWakeDateNeverCaptureTheExpansion() = runTest {
        for (byDate in listOf(
            manager().capture(ExportDetailSelection.UNIFORM_DETAILED),
            manager().capture(v7Detail, SleepDayAttribution.MORNING_ENDS),
        )) {
            val data = byDate.getValue(day)
            assertThat(data.activity.hasDetailExpansion).isFalse()
            assertThat(data.body.hasDetailExpansion).isFalse()
            assertThat(data.nutrition.hydrationSamples).isEmpty()
        }
        val requested = mutableListOf<KClass<*>>()
        manager(requested = requested).capture(ExportDetailSelection.UNIFORM_DETAILED)
        assertThat(requested).containsNoneOf(
            ActiveCaloriesBurnedRecord::class, TotalCaloriesBurnedRecord::class, DistanceRecord::class,
            FloorsClimbedRecord::class, ElevationGainedRecord::class, HydrationRecord::class,
        )
    }

    @Test
    fun summarizedGroupsAreNotExpandedEvenWhenAnotherGroupSelectsV7() = runTest {
        val bodyOnly = ExportDetailSelection.resolve(false, mapOf(ExportDetailGroup.BODY to ExportDetailChoice.DETAILED))
        val data = manager().capture(bodyOnly).getValue(day)
        assertThat(data.body.weightSamples).hasSize(2)
        assertThat(data.activity.hasDetailExpansion).isFalse()
        assertThat(data.nutrition.hydrationSamples).isEmpty()
    }

    @Test
    fun aMissingReadPermissionOmitsOnlyThatArray() = runTest {
        val data = manager(denied = setOf(DistanceRecord::class, WeightRecord::class)).capture(v7Detail).getValue(day)
        assertThat(data.activity.distanceSamples).isEmpty()
        assertThat(data.body.weightSamples).isEmpty()
        assertThat(data.activity.totalCaloriesSamples).hasSize(1)
        assertThat(data.body.heightSamples).hasSize(1)
        assertThat(data.nutrition.hydrationSamples).hasSize(2)
    }
}
