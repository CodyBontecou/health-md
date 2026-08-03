package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import com.healthmd.widget.model.HealthWidgetDay
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.HealthWidgetSnapshot
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import org.junit.Test

class HealthWidgetSnapshotTest {
    private val capturedAt = Instant.parse("2026-08-02T12:00:00Z")
    private val snapshot = HealthWidgetSnapshot(
        capturedAtEpochMillis = capturedAt.toEpochMilli(),
        capturedZoneId = "UTC",
        days = listOf(HealthWidgetDay("2026-08-02", steps = 1)),
    )

    @Test
    fun `freshness uses four-hour boundary`() {
        assertThat(snapshot.isFresh(capturedAt.plus(Duration.ofHours(4)))).isTrue()
        assertThat(snapshot.isFresh(capturedAt.plus(Duration.ofHours(4)).plusMillis(1))).isFalse()
    }

    @Test
    fun `measurement display stops after twenty-four hours`() {
        assertThat(snapshot.canDisplayMeasurements(capturedAt.plus(Duration.ofHours(24)))).isTrue()
        assertThat(snapshot.canDisplayMeasurements(capturedAt.plus(Duration.ofHours(24)).plusMillis(1))).isFalse()
    }

    @Test
    fun `widget kind uses its latest relevant day instead of another metrics today`() {
        val mixed = snapshot.copy(
            days = listOf(
                HealthWidgetDay("2026-08-01", sleepDurationMinutes = 480.0),
                HealthWidgetDay("2026-08-02", steps = 1_000),
            ),
        )

        assertThat(mixed.dayFor(HealthWidgetKind.SLEEP, LocalDate.parse("2026-08-02"))?.localDate)
            .isEqualTo("2026-08-01")
        assertThat(mixed.dayFor(HealthWidgetKind.ACTIVITY, LocalDate.parse("2026-08-02"))?.localDate)
            .isEqualTo("2026-08-02")
    }

    @Test
    fun `daily activity never falls back to yesterday while labeled today`() {
        val mixed = snapshot.copy(
            days = listOf(
                HealthWidgetDay("2026-08-01", steps = 9_000),
                HealthWidgetDay("2026-08-02", sleepDurationMinutes = 480.0),
            ),
        )

        assertThat(mixed.dayFor(HealthWidgetKind.ACTIVITY, LocalDate.parse("2026-08-02")))
            .isNull()
        assertThat(mixed.dayFor(HealthWidgetKind.SUMMARY, LocalDate.parse("2026-08-02"))?.steps)
            .isNull()
    }

    @Test
    fun `summary combines todays activity with latest nightly and resting values`() {
        val mixed = snapshot.copy(
            days = listOf(
                HealthWidgetDay(
                    "2026-08-01",
                    sleepDurationMinutes = 480.0,
                    restingHeartRateBpm = 55.0,
                ),
                HealthWidgetDay("2026-08-02", steps = 1_000),
            ),
        )

        val summary = mixed.dayFor(HealthWidgetKind.SUMMARY, LocalDate.parse("2026-08-02"))

        assertThat(summary?.steps).isEqualTo(1_000)
        assertThat(summary?.sleepDurationMinutes).isEqualTo(480.0)
        assertThat(summary?.restingHeartRateBpm).isEqualTo(55.0)
    }

    @Test
    fun `future timestamps fail closed`() {
        assertThat(snapshot.age(capturedAt.minusMillis(1))).isNull()
        assertThat(snapshot.canDisplayMeasurements(capturedAt.minusMillis(1))).isFalse()
    }
}
