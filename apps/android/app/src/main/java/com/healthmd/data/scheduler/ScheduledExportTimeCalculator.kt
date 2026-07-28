package com.healthmd.data.scheduler

import com.healthmd.domain.model.ScheduleCadenceUnit
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ScheduledExportTimeCalculator @Inject constructor() {

    fun initialOccurrence(
        configuration: ScheduledExportConfiguration,
        nowMillis: Long = System.currentTimeMillis(),
    ): ScheduledExportOccurrence {
        val zone = ZoneId.of(configuration.zoneId)
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val trigger = when (configuration.cadenceUnit) {
            ScheduleCadenceUnit.MINUTES -> now.plusMinutes(configuration.cadenceValue.toLong())
            ScheduleCadenceUnit.HOURS -> now.plusHours(configuration.cadenceValue.toLong())
            ScheduleCadenceUnit.DAYS -> nextCalendarOccurrence(
                now = now,
                hour = configuration.hour,
                minute = configuration.minute,
                cadenceDays = configuration.cadenceValue.toLong(),
            )
            ScheduleCadenceUnit.WEEKS -> nextCalendarOccurrence(
                now = now,
                hour = configuration.hour,
                minute = configuration.minute,
                cadenceDays = configuration.cadenceValue.toLong() * DAYS_PER_WEEK,
            )
        }
        return occurrence(configuration, trigger)
    }

    /**
     * Returns every distinct intended local run date that is due, including [previous]. Frequent
     * minute/hour occurrences on the same date are coalesced before export.
     */
    fun dueRunDates(
        previous: ScheduledExportOccurrence,
        throughMillis: Long,
    ): List<LocalDate> {
        val dates = linkedSetOf<LocalDate>()
        var occurrence = previous
        while (occurrence.triggerAtMillis <= throughMillis) {
            dates += occurrence.intendedLocalDate
            occurrence = followingOccurrence(occurrence)
        }
        return dates.toList()
    }

    fun isOccurrenceDueAfterRebase(
        previous: ScheduledExportOccurrence,
        configuration: ScheduledExportConfiguration,
        nowMillis: Long,
    ): Boolean {
        if (configuration.cadenceUnit == ScheduleCadenceUnit.MINUTES ||
            configuration.cadenceUnit == ScheduleCadenceUnit.HOURS
        ) return previous.triggerAtMillis <= nowMillis

        val rebasedTrigger = ZonedDateTime.of(
            previous.intendedLocalDate,
            LocalTime.of(configuration.hour, configuration.minute),
            ZoneId.of(configuration.zoneId),
        ).toInstant().toEpochMilli()
        return rebasedTrigger <= nowMillis
    }

    /**
     * Reinterprets a future calendar occurrence in a new timezone without resetting a multi-day or
     * weekly cadence phase. Fixed minute/hour cadences retain their absolute instant.
     */
    fun rebaseOccurrence(
        previous: ScheduledExportOccurrence,
        configuration: ScheduledExportConfiguration,
        nowMillis: Long,
    ): ScheduledExportOccurrence {
        val zone = ZoneId.of(configuration.zoneId)
        val rebased = when (configuration.cadenceUnit) {
            ScheduleCadenceUnit.MINUTES,
            ScheduleCadenceUnit.HOURS -> ScheduledExportOccurrence(
                configuration = configuration,
                triggerAtMillis = previous.triggerAtMillis,
                intendedLocalDate = Instant.ofEpochMilli(previous.triggerAtMillis).atZone(zone).toLocalDate(),
            )
            ScheduleCadenceUnit.DAYS,
            ScheduleCadenceUnit.WEEKS -> occurrence(
                configuration,
                ZonedDateTime.of(
                    previous.intendedLocalDate,
                    LocalTime.of(configuration.hour, configuration.minute),
                    zone,
                ),
            )
        }
        return if (rebased.triggerAtMillis > nowMillis) {
            rebased
        } else {
            nextFutureOccurrence(rebased, nowMillis)
        }
    }

    /**
     * Returns the first occurrence after [nowMillis], anchored to the previous intended time rather
     * than the time Android eventually delivered it. Missed intervals are coalesced into one run.
     */
    fun nextFutureOccurrence(
        previous: ScheduledExportOccurrence,
        nowMillis: Long = System.currentTimeMillis(),
    ): ScheduledExportOccurrence {
        val configuration = previous.configuration
        val zone = ZoneId.of(configuration.zoneId)
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val previousTime = Instant.ofEpochMilli(previous.triggerAtMillis).atZone(zone)

        val next = when (configuration.cadenceUnit) {
            ScheduleCadenceUnit.MINUTES -> nextFixedInterval(
                previousTime = previousTime,
                now = now,
                intervalMillis = configuration.cadenceValue.toLong() * MILLIS_PER_MINUTE,
            )
            ScheduleCadenceUnit.HOURS -> nextFixedInterval(
                previousTime = previousTime,
                now = now,
                intervalMillis = configuration.cadenceValue.toLong() * MILLIS_PER_HOUR,
            )
            ScheduleCadenceUnit.DAYS -> nextCalendarInterval(
                previousDate = previous.intendedLocalDate,
                now = now,
                configuration = configuration,
                cadenceDays = configuration.cadenceValue.toLong(),
            )
            ScheduleCadenceUnit.WEEKS -> nextCalendarInterval(
                previousDate = previous.intendedLocalDate,
                now = now,
                configuration = configuration,
                cadenceDays = configuration.cadenceValue.toLong() * DAYS_PER_WEEK,
            )
        }
        return occurrence(configuration, next)
    }

    private fun followingOccurrence(
        previous: ScheduledExportOccurrence,
    ): ScheduledExportOccurrence {
        val configuration = previous.configuration
        val zone = ZoneId.of(configuration.zoneId)
        val trigger = when (configuration.cadenceUnit) {
            ScheduleCadenceUnit.MINUTES -> Instant.ofEpochMilli(previous.triggerAtMillis)
                .plusMillis(configuration.cadenceValue.toLong() * MILLIS_PER_MINUTE)
                .atZone(zone)
            ScheduleCadenceUnit.HOURS -> Instant.ofEpochMilli(previous.triggerAtMillis)
                .plusMillis(configuration.cadenceValue.toLong() * MILLIS_PER_HOUR)
                .atZone(zone)
            ScheduleCadenceUnit.DAYS -> ZonedDateTime.of(
                previous.intendedLocalDate.plusDays(configuration.cadenceValue.toLong()),
                LocalTime.of(configuration.hour, configuration.minute),
                zone,
            )
            ScheduleCadenceUnit.WEEKS -> ZonedDateTime.of(
                previous.intendedLocalDate.plusWeeks(configuration.cadenceValue.toLong()),
                LocalTime.of(configuration.hour, configuration.minute),
                zone,
            )
        }
        return occurrence(configuration, trigger)
    }

    private fun nextCalendarOccurrence(
        now: ZonedDateTime,
        hour: Int,
        minute: Int,
        cadenceDays: Long,
    ): ZonedDateTime {
        val zone = now.zone
        val time = LocalTime.of(hour, minute)
        var candidate = ZonedDateTime.of(now.toLocalDate(), time, zone)
        if (!candidate.isAfter(now)) {
            candidate = ZonedDateTime.of(now.toLocalDate().plusDays(cadenceDays), time, zone)
        }
        return candidate
    }

    private fun nextFixedInterval(
        previousTime: ZonedDateTime,
        now: ZonedDateTime,
        intervalMillis: Long,
    ): ZonedDateTime {
        val elapsed = (now.toInstant().toEpochMilli() - previousTime.toInstant().toEpochMilli())
            .coerceAtLeast(0L)
        val steps = (elapsed / intervalMillis) + 1L
        val nextMillis = previousTime.toInstant().toEpochMilli() + Math.multiplyExact(steps, intervalMillis)
        return Instant.ofEpochMilli(nextMillis).atZone(previousTime.zone)
    }

    private fun nextCalendarInterval(
        previousDate: LocalDate,
        now: ZonedDateTime,
        configuration: ScheduledExportConfiguration,
        cadenceDays: Long,
    ): ZonedDateTime {
        val zone = now.zone
        val time = LocalTime.of(configuration.hour, configuration.minute)
        var nextDate = previousDate.plusDays(cadenceDays)

        val daysBehind = ChronoUnit.DAYS.between(nextDate, now.toLocalDate())
        if (daysBehind > 0L) {
            nextDate = nextDate.plusDays((daysBehind / cadenceDays) * cadenceDays)
        }

        var candidate = ZonedDateTime.of(nextDate, time, zone)
        while (!candidate.isAfter(now)) {
            nextDate = nextDate.plusDays(cadenceDays)
            candidate = ZonedDateTime.of(nextDate, time, zone)
        }
        return candidate
    }

    private fun occurrence(
        configuration: ScheduledExportConfiguration,
        trigger: ZonedDateTime,
    ): ScheduledExportOccurrence = ScheduledExportOccurrence(
        configuration = configuration,
        triggerAtMillis = trigger.toInstant().toEpochMilli(),
        intendedLocalDate = trigger.toLocalDate(),
    )

    private companion object {
        const val DAYS_PER_WEEK = 7L
        const val MILLIS_PER_MINUTE = 60_000L
        const val MILLIS_PER_HOUR = 60L * MILLIS_PER_MINUTE
    }
}
