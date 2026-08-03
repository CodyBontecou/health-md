package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.SleepData
import com.healthmd.widget.data.HealthWidgetSnapshotMapper
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes

class HealthWidgetSnapshotMapperTest {
    private val mapper = HealthWidgetSnapshotMapper()
    private val zone = ZoneId.of("Pacific/Honolulu")
    private val now = Instant.parse("2026-08-02T20:00:00Z")

    @Test
    fun `maps widget metrics and labels capture as successful`() {
        val data = HealthData(
            date = LocalDate.parse("2026-08-02"),
            activity = ActivityData(
                steps = 8_765,
                activeCalories = 421.5,
                exerciseMinutes = 37.0,
            ),
            sleep = SleepData(
                totalDuration = 9.hours,
                deepSleep = 90.minutes,
                remSleep = 120.minutes,
                lightSleep = 240.minutes,
                awakeTime = 90.minutes,
                sessionStart = LocalDateTime.parse("2026-08-01T22:30:00"),
                sessionEnd = LocalDateTime.parse("2026-08-02T06:30:00"),
            ),
            heart = HeartData(
                restingHeartRate = 58.0,
                averageHeartRate = 72.0,
                heartRateMin = 47.0,
                heartRateMax = 151.0,
                hrv = 46.5,
            ),
        )

        val snapshot = mapper.map(listOf(data), now, zone)
        val day = snapshot.days.single()

        assertThat(snapshot.schemaVersion).isEqualTo(HealthWidgetSnapshot.CURRENT_SCHEMA_VERSION)
        assertThat(snapshot.lastAttemptOutcome).isEqualTo(WidgetRefreshOutcome.SUCCESS)
        assertThat(snapshot.capturedZoneId).isEqualTo("Pacific/Honolulu")
        assertThat(day.steps).isEqualTo(8_765)
        assertThat(day.activeCaloriesKilocalories).isEqualTo(421.5)
        assertThat(day.exerciseMinutes).isEqualTo(37.0)
        // Awake time is excluded when stage totals are available.
        assertThat(day.sleepDurationMinutes).isEqualTo(450.0)
        assertThat(day.restingHeartRateBpm).isEqualTo(58.0)
        assertThat(day.averageHeartRateBpm).isEqualTo(72.0)
        assertThat(day.minimumHeartRateBpm).isEqualTo(47.0)
        assertThat(day.maximumHeartRateBpm).isEqualTo(151.0)
        assertThat(day.hrvRmssdMillis).isEqualTo(46.5)
        assertThat(snapshot.isValid()).isTrue()
    }

    @Test
    fun `uses session duration when sleep stages are unavailable`() {
        val data = HealthData(
            date = LocalDate.parse("2026-08-02"),
            sleep = SleepData(totalDuration = 7.hours + 15.minutes),
        )

        val snapshot = mapper.map(listOf(data), now, zone)

        assertThat(snapshot.days.single().sleepDurationMinutes).isEqualTo(435.0)
    }

    @Test
    fun `keeps calendar ordering de-duplicates and caps at fourteen days`() {
        val start = LocalDate.parse("2026-07-15")
        val records = (0L..18L).map { offset ->
            HealthData(
                date = start.plusDays(offset),
                activity = ActivityData(steps = offset.toInt()),
            )
        } + HealthData(
            date = start.plusDays(18),
            activity = ActivityData(steps = 99),
        )

        val snapshot = mapper.map(records.reversed(), now, zone)

        assertThat(snapshot.days).hasSize(14)
        assertThat(snapshot.days.map { it.localDate }).isInOrder()
        assertThat(snapshot.days.map { it.localDate }.distinct()).hasSize(14)
        // The later record in input wins for a duplicate date.
        assertThat(snapshot.days.last().steps).isEqualTo(18)
    }

    @Test
    fun `empty values produce a successful no-data capture`() {
        val snapshot = mapper.map(
            listOf(HealthData(date = LocalDate.parse("2026-08-02"))),
            now,
            zone,
        )

        assertThat(snapshot.hasAnyData).isFalse()
        assertThat(snapshot.lastAttemptOutcome).isEqualTo(WidgetRefreshOutcome.NO_DATA)
        assertThat(snapshot.capturedAtEpochMillis).isEqualTo(now.toEpochMilli())
    }

    @Test
    fun `drops invalid scalar measurements`() {
        val snapshot = mapper.map(
            listOf(
                HealthData(
                    date = LocalDate.parse("2026-08-02"),
                    activity = ActivityData(steps = -1, activeCalories = Double.NaN),
                    heart = HeartData(averageHeartRate = Double.POSITIVE_INFINITY, hrv = -3.0),
                )
            ),
            now,
            zone,
        )

        val day = snapshot.days.single()
        assertThat(day.steps).isNull()
        assertThat(day.activeCaloriesKilocalories).isNull()
        assertThat(day.averageHeartRateBpm).isNull()
        assertThat(day.hrvRmssdMillis).isNull()
        assertThat(snapshot.isValid()).isTrue()
    }
}
