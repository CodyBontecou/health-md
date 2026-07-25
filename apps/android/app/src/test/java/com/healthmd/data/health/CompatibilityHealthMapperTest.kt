package com.healthmd.data.health

import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.Percentage
import androidx.health.connect.client.units.kilograms
import androidx.health.connect.client.units.meters
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.WorkoutRoutePointData
import org.junit.Test
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset

class CompatibilityHealthMapperTest {
    private val metadata = Metadata.manualEntry()

    @Test
    fun actualHealthConnectPercentagesMapToCanonicalFractions() {
        val oxygenPercentage = Percentage(97.5)
        val bodyFat = BodyFatRecord(
            time = Instant.parse("2026-07-10T12:00:00Z"),
            zoneOffset = ZoneOffset.UTC,
            percentage = Percentage(18.25),
            metadata = metadata,
        )

        assertThat(CompatibilityHealthMapper.percentageFraction(oxygenPercentage)).isWithin(0.0001).of(0.975)
        assertThat(CompatibilityHealthMapper.latestBodyFatFraction(listOf(bodyFat))).isWithin(0.0001).of(0.1825)
    }

    @Test
    fun rangeSelectionMatchesFallbackLatestRecordSemantics() {
        val early = Instant.parse("2026-07-10T08:00:00Z")
        val late = Instant.parse("2026-07-10T20:00:00Z")
        val weights = listOf(
            WeightRecord(late, ZoneOffset.UTC, 72.0.kilograms, metadata),
            WeightRecord(early, ZoneOffset.UTC, 70.0.kilograms, metadata),
        )
        val heights = listOf(
            HeightRecord(late, ZoneOffset.UTC, 1.82.meters, metadata),
            HeightRecord(early, ZoneOffset.UTC, 1.80.meters, metadata),
        )
        val resting = listOf(
            RestingHeartRateRecord(late, ZoneOffset.UTC, 58, metadata),
            RestingHeartRateRecord(early, ZoneOffset.UTC, 62, metadata),
        )

        assertThat(CompatibilityHealthMapper.latestWeightKilograms(weights)).isEqualTo(72.0)
        assertThat(CompatibilityHealthMapper.latestHeightMeters(heights)).isEqualTo(1.82)
        assertThat(CompatibilityHealthMapper.latestRestingHeartRate(resting)).isEqualTo(58.0)
    }

    @Test
    fun clientRecordVersionZeroIsRetainedWhenClientIdExistsForParentAndChildMapping() {
        val withClientId = Metadata.manualEntry(clientRecordId = "client-record", clientRecordVersion = 0)
        val parent = CompatibilityHealthMapper.parentIdentity(withClientId, "parent", "record")
        val child = CompatibilityHealthMapper.childIdentity(withClientId, "child", "sample")

        assertThat(parent.clientRecordVersion).isEqualTo(0L)
        assertThat(parent.clientRecordId).isEqualTo("client-record")
        assertThat(child.clientRecordVersion).isEqualTo(0L)
        assertThat(child.clientRecordId).isEqualTo("client-record")
        assertThat(CompatibilityHealthMapper.clientRecordVersion(Metadata.manualEntry())).isNull()
    }

    @Test
    fun sparseRouteEmitsEveryKilometreAtInterpolatedNanosecondInstants() {
        val startInstant = Instant.parse("2026-07-10T12:00:00.123456789Z")
        val endInstant = Instant.parse("2026-07-10T12:40:00.987654321Z")
        val offset = ZoneOffset.ofHoursMinutes(5, 45)
        val route = listOf(
            WorkoutRoutePointData(
                time = LocalDateTime.of(2026, 7, 10, 17, 45),
                latitude = 0.0,
                longitude = 0.0,
                exactTime = ExactSourceTimestamp.from(startInstant, offset),
            ),
            WorkoutRoutePointData(
                time = LocalDateTime.of(2026, 7, 10, 18, 25),
                latitude = 0.0,
                longitude = 0.04,
                exactTime = ExactSourceTimestamp.from(endInstant, offset),
            ),
        )

        val splits = CompatibilityHealthMapper.deriveDistanceSplits(route, emptyList(), 1_000.0)

        assertThat(splits).hasSize(4)
        assertThat(splits.map { it.endTime }.distinct()).hasSize(4)
        assertThat(splits.zipWithNext().all { (a, b) -> a.endTime.isBefore(b.endTime) }).isTrue()
        assertThat(splits.first().exactStartTime?.nano).isEqualTo(123_456_789)
        assertThat(splits.mapNotNull { it.exactEndTime }.map { it.toIso8601() }.distinct()).hasSize(4)
        assertThat(splits.all { it.exactEndTime?.offset == "+05:45" }).isTrue()
        assertThat(splits.last().exactEndTime).isNotEqualTo(route.last().exactTime)
    }

    @Test
    fun inexactOffsetInterpolationLeavesExactBoundaryNull() {
        val route = listOf(
            WorkoutRoutePointData(
                LocalDateTime.of(2026, 7, 10, 8, 0), 0.0, 0.0,
                exactTime = ExactSourceTimestamp.from(Instant.parse("2026-07-10T08:00:00Z"), ZoneOffset.UTC),
            ),
            WorkoutRoutePointData(
                LocalDateTime.of(2026, 7, 10, 8, 20), 0.0, 0.02,
                exactTime = ExactSourceTimestamp.from(Instant.parse("2026-07-10T08:20:00Z"), ZoneOffset.ofHours(1)),
            ),
        )

        val splits = CompatibilityHealthMapper.deriveDistanceSplits(route, emptyList(), 1_000.0)

        assertThat(splits).hasSize(2)
        assertThat(splits.first().exactEndTime).isNull()
        assertThat(splits[1].exactStartTime).isNull()
    }
}
