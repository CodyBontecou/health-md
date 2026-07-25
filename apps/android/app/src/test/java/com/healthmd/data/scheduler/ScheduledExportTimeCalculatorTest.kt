package com.healthmd.data.scheduler

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime

class ScheduledExportTimeCalculatorTest {
    private val calculator = ScheduledExportTimeCalculator()

    @Test
    fun initialDailyOccurrence_usesConfiguredWallTime() {
        val configuration = configuration(unit = ScheduleCadenceUnit.DAYS, hour = 6)
        val now = epoch("2026-07-13T05:00:00Z")

        val occurrence = calculator.initialOccurrence(configuration, now)

        assertThat(occurrence.triggerAtMillis).isEqualTo(epoch("2026-07-13T06:00:00Z"))
        assertThat(occurrence.intendedLocalDate).isEqualTo(LocalDate.parse("2026-07-13"))
    }

    @Test
    fun nextDailyOccurrence_isAnchoredToIntendedTimeNotLateDelivery() {
        val configuration = configuration(unit = ScheduleCadenceUnit.DAYS, hour = 6)
        val previous = ScheduledExportOccurrence(
            configuration = configuration,
            triggerAtMillis = epoch("2026-07-13T06:00:00Z"),
            intendedLocalDate = LocalDate.parse("2026-07-13"),
        )

        val next = calculator.nextFutureOccurrence(previous, epoch("2026-07-13T08:41:00Z"))

        assertThat(next.triggerAtMillis).isEqualTo(epoch("2026-07-14T06:00:00Z"))
    }

    @Test
    fun nextDailyOccurrence_coalescesMissedIntervalsWithoutDrift() {
        val configuration = configuration(value = 2, unit = ScheduleCadenceUnit.DAYS, hour = 6)
        val previous = ScheduledExportOccurrence(
            configuration = configuration,
            triggerAtMillis = epoch("2026-07-01T06:00:00Z"),
            intendedLocalDate = LocalDate.parse("2026-07-01"),
        )

        val next = calculator.nextFutureOccurrence(previous, epoch("2026-07-04T07:00:00Z"))

        assertThat(next.triggerAtMillis).isEqualTo(epoch("2026-07-05T06:00:00Z"))
    }

    @Test
    fun nextMinuteOccurrence_skipsMissedIntervalsFromOriginalAnchor() {
        val configuration = configuration(value = 15, unit = ScheduleCadenceUnit.MINUTES)
        val previous = ScheduledExportOccurrence(
            configuration = configuration,
            triggerAtMillis = epoch("2026-07-13T10:00:00Z"),
            intendedLocalDate = LocalDate.parse("2026-07-13"),
        )

        val next = calculator.nextFutureOccurrence(previous, epoch("2026-07-13T10:47:00Z"))

        assertThat(next.triggerAtMillis).isEqualTo(epoch("2026-07-13T11:00:00Z"))
    }

    @Test
    fun dailyOccurrence_resolvesDaylightSavingGapToNextValidWallTime() {
        val zone = ZoneId.of("America/New_York")
        val configuration = configuration(
            unit = ScheduleCadenceUnit.DAYS,
            hour = 2,
            minute = 30,
            zoneId = zone,
        )
        val now = ZonedDateTime.parse("2026-03-07T12:00:00-05:00[America/New_York]")

        val occurrence = calculator.initialOccurrence(configuration, now.toInstant().toEpochMilli())
        val localTrigger = Instant.ofEpochMilli(occurrence.triggerAtMillis).atZone(zone)

        assertThat(localTrigger.toLocalDate()).isEqualTo(LocalDate.parse("2026-03-08"))
        assertThat(localTrigger.hour).isEqualTo(3)
        assertThat(localTrigger.minute).isEqualTo(30)
    }

    @Test
    fun dailyOccurrence_usesEarlierOffsetDuringDaylightSavingOverlap() {
        val zone = ZoneId.of("America/New_York")
        val configuration = configuration(
            unit = ScheduleCadenceUnit.DAYS,
            hour = 1,
            minute = 30,
            zoneId = zone,
        )
        val now = ZonedDateTime.parse("2026-10-31T12:00:00-04:00[America/New_York]")

        val occurrence = calculator.initialOccurrence(configuration, now.toInstant().toEpochMilli())

        assertThat(occurrence.triggerAtMillis).isEqualTo(epoch("2026-11-01T05:30:00Z"))
    }

    @Test
    fun dueRunDates_includesMissedDailyOccurrences() {
        val configuration = configuration(unit = ScheduleCadenceUnit.DAYS, hour = 6)
        val previous = ScheduledExportOccurrence(
            configuration = configuration,
            triggerAtMillis = epoch("2026-07-14T06:00:00Z"),
            intendedLocalDate = LocalDate.parse("2026-07-14"),
        )

        val dates = calculator.dueRunDates(previous, epoch("2026-07-16T07:00:00Z"))

        assertThat(dates).containsExactly(
            LocalDate.parse("2026-07-14"),
            LocalDate.parse("2026-07-15"),
            LocalDate.parse("2026-07-16"),
        ).inOrder()
    }

    @Test
    fun rebaseOccurrence_preservesMultiDayCadencePhaseInNewTimezone() {
        val oldConfiguration = configuration(
            value = 2,
            unit = ScheduleCadenceUnit.DAYS,
            hour = 6,
            zoneId = ZoneId.of("UTC"),
        )
        val previous = ScheduledExportOccurrence(
            configuration = oldConfiguration,
            triggerAtMillis = epoch("2026-07-15T06:00:00Z"),
            intendedLocalDate = LocalDate.parse("2026-07-15"),
        )
        val newConfiguration = oldConfiguration.copy(zoneId = "America/Los_Angeles")

        val rebased = calculator.rebaseOccurrence(
            previous = previous,
            configuration = newConfiguration,
            nowMillis = epoch("2026-07-14T12:00:00Z"),
        )
        val local = Instant.ofEpochMilli(rebased.triggerAtMillis)
            .atZone(ZoneId.of("America/Los_Angeles"))

        assertThat(local.toLocalDate()).isEqualTo(LocalDate.parse("2026-07-15"))
        assertThat(local.hour).isEqualTo(6)
    }

    @Test
    fun timezoneRebase_detectsCalendarOccurrenceThatAlreadyPassedLocally() {
        val oldConfiguration = configuration(
            unit = ScheduleCadenceUnit.DAYS,
            hour = 6,
            zoneId = ZoneId.of("UTC"),
        )
        val previous = ScheduledExportOccurrence(
            configuration = oldConfiguration,
            triggerAtMillis = epoch("2026-07-15T06:00:00Z"),
            intendedLocalDate = LocalDate.parse("2026-07-15"),
        )
        val tokyoConfiguration = oldConfiguration.copy(zoneId = "Asia/Tokyo")

        val due = calculator.isOccurrenceDueAfterRebase(
            previous = previous,
            configuration = tokyoConfiguration,
            nowMillis = epoch("2026-07-14T23:30:00Z"), // July 15 at 08:30 in Tokyo.
        )

        assertThat(due).isTrue()
    }

    @Test
    fun workDataRoundTrip_preservesIntendedOccurrence() {
        val configuration = configuration(value = 3, unit = ScheduleCadenceUnit.HOURS)
        val occurrence = ScheduledExportOccurrence(
            configuration = configuration,
            triggerAtMillis = epoch("2026-07-13T10:00:00Z"),
            intendedLocalDate = LocalDate.parse("2026-07-13"),
        )

        assertThat(ScheduledExportOccurrence.fromWorkData(occurrence.toWorkData()))
            .isEqualTo(occurrence)
    }

    private fun configuration(
        value: Int = 1,
        unit: ScheduleCadenceUnit,
        hour: Int = 6,
        minute: Int = 0,
        zoneId: ZoneId = ZoneId.of("UTC"),
    ) = ScheduledExportConfiguration(
        cadenceValue = value,
        cadenceUnit = unit,
        hour = hour,
        minute = minute,
        lookbackDays = 1,
        dateWindow = ScheduleDateWindow.PAST_COMPLETE_DAYS,
        target = ExportTarget.DEVICE_FOLDER,
        destinationFingerprint = null,
        zoneId = zoneId.id,
    )

    private fun epoch(instant: String): Long = Instant.parse(instant).toEpochMilli()
}
