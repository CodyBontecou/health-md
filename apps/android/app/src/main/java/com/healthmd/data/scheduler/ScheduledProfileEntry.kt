package com.healthmd.data.scheduler

import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId

/** Cadence unit for a scheduled profile entry, mirroring the iOS entry model. */
@Serializable
enum class ScheduledProfileCadenceUnit {
    DAY,
    WEEK,
    MONTH,
}

/** How a scheduled entry picks its dates. */
@Serializable
enum class ScheduledProfileDateWindow {
    /** Trailing N days ending yesterday (includes weekends; no ISO-week gaps). */
    PAST_COMPLETE_DAYS,
}

/**
 * One scheduled-export configuration bound to exactly one export profile (Android phase 6).
 *
 * Mirrors iOS `ScheduledExportEntry`: cadence fields plus per-entry progress state so occurrence
 * math works independently per profile. The frozen snapshot lives on the referenced profile; this
 * entry never duplicates it.
 */
@Serializable
data class ScheduledProfileEntry(
    val profileId: String,
    val isEnabled: Boolean = false,
    /** Anchor day establishing the repeating phase for custom cadences. */
    val anchorEpochDay: Long,
    /** ISO day-of-week for weekly entries (1 = Monday … 7 = Sunday). */
    val weekdayIso: Int = 1,
    val hour: Int = 8,
    val minute: Int = 0,
    val cadenceValue: Int = 1,
    val cadenceUnit: ScheduledProfileCadenceUnit = ScheduledProfileCadenceUnit.DAY,
    val dateWindow: ScheduledProfileDateWindow = ScheduledProfileDateWindow.PAST_COMPLETE_DAYS,
    /** Days exported by one completed-day run. */
    val lookbackDays: Int = 1,
    val zoneId: String = "UTC",
    /** Epoch millis of the most recent successful completed-day occurrence, for catch-up math. */
    val lastSuccessEpochMillis: Long? = null,
    /** Epoch millis of the most recent successful Today Refresh occurrence. */
    val lastRefreshSuccessEpochMillis: Long? = null,
) {
    init {
        require(lookbackDays in 1..30) { "Lookback must stay within 1..30." }
        require(hour in 0..23 && minute in 0..59) { "Preferred time is invalid." }
        require(cadenceValue >= 1) { "Cadence value must be positive." }
        require(weekdayIso in 1..7) { "Weekday must stay within ISO 1..7." }
        require(ZoneId.of(zoneId).id == zoneId) { "Zone id must be canonical." }
    }

    val zone: ZoneId get() = ZoneId.of(zoneId)

    /** A due, actionable occurrence for one entry. */
    data class DueOccurrence(
        val entry: ScheduledProfileEntry,
        val fireAtMillis: Long,
        /** Data days to export; empty means nothing actionable at this boundary. */
        val exportDates: List<LocalDate>,
    )
}

/**
 * Pure per-entry occurrence math mirroring the shipped single-schedule evaluator's two-layer
 * semantics: a boundary passed **and** catch-up work remaining. Unit-testable without Android
 * instrumentation; the runtime layers (AlarmManager arming, WorkManager execution) consume this.
 */
object ScheduledProfileOccurrenceMath {

    /** Next boundary strictly after [nowMillis] for the entry's cadence and zone. */
    fun nextOccurrence(entry: ScheduledProfileEntry, nowMillis: Long): Instant? {
        val zone = entry.zone
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDateTime()
        val preferred = LocalTime.of(entry.hour, entry.minute)
        return when (entry.cadenceUnit) {
            ScheduledProfileCadenceUnit.DAY ->
                nextDaily(now = now, preferred = preferred, everyDays = entry.cadenceValue.toLong())
            ScheduledProfileCadenceUnit.WEEK ->
                nextWeekly(now = now, preferred = preferred, weekdayIso = entry.weekdayIso, everyWeeks = entry.cadenceValue)
            ScheduledProfileCadenceUnit.MONTH ->
                nextMonthly(now = now, preferred = preferred, anchorEpochDay = entry.anchorEpochDay, everyMonths = entry.cadenceValue)
        }?.atZone(zone)?.toInstant()
    }

    /**
     * The most recent boundary at or before [nowMillis] when actionable work remains:
     * for trailing-window entries, the dates not yet covered by [ScheduledProfileEntry.lastSuccessEpochMillis].
     * Returns null when no boundary passed or everything is already exported.
     */
    fun dueOccurrence(
        entry: ScheduledProfileEntry,
        nowMillis: Long,
    ): ScheduledProfileEntry.DueOccurrence? {
        if (!entry.isEnabled) return null
        val boundary = previousBoundary(entry, nowMillis) ?: return null
        val zone = entry.zone

        // Catch-up: dates in the trailing window ending yesterday that were not yet exported.
        // A successful occurrence at time T covered the window ending the day before T.
        val today = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDate()
        val yesterday = today.minusDays(1)
        val oldest = yesterday.minusDays((entry.lookbackDays - 1).toLong())

        val coveredThrough: LocalDate? = entry.lastSuccessEpochMillis?.let { successMillis ->
            Instant.ofEpochMilli(successMillis).atZone(zone).toLocalDate().minusDays(1)
        }

        val pending = if (coveredThrough == null || coveredThrough.isBefore(oldest.minusDays(1))) {
            generateSequence(oldest) { it.plusDays(1) }.takeWhile { !it.isAfter(yesterday) }
                .filter { coveredThrough == null || it.isAfter(coveredThrough) }
                .toList()
        } else {
            emptyList()
        }
        if (pending.isEmpty()) return null

        return ScheduledProfileEntry.DueOccurrence(
            entry = entry,
            fireAtMillis = boundary.toEpochMilli(),
            exportDates = pending,
        )
    }

    /** Previous boundary at or before now for the entry's cadence. */
    private fun previousBoundary(entry: ScheduledProfileEntry, nowMillis: Long): Instant? {
        val zone = entry.zone
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDateTime()
        val preferred = LocalTime.of(entry.hour, entry.minute)
        return when (entry.cadenceUnit) {
            ScheduledProfileCadenceUnit.DAY ->
                previousDaily(now = now, preferred = preferred, everyDays = entry.cadenceValue.toLong())
            ScheduledProfileCadenceUnit.WEEK ->
                previousWeekly(now = now, preferred = preferred, weekdayIso = entry.weekdayIso, everyWeeks = entry.cadenceValue)
            ScheduledProfileCadenceUnit.MONTH ->
                previousMonthly(now = now, preferred = preferred, anchorEpochDay = entry.anchorEpochDay, everyMonths = entry.cadenceValue)
        }?.atZone(zone)?.toInstant()
    }

    private fun nextDaily(now: LocalDateTime, preferred: LocalTime, everyDays: Long): LocalDateTime? {
        var candidate = now.toLocalDate().atTime(preferred)
        if (!candidate.isAfter(now)) candidate = candidate.plusDays(everyDays)
        return candidate
    }

    private fun previousDaily(now: LocalDateTime, preferred: LocalTime, everyDays: Long): LocalDateTime? {
        var candidate = now.toLocalDate().atTime(preferred)
        if (candidate.isAfter(now)) candidate = candidate.minusDays(everyDays)
        return candidate
    }

    private fun nextWeekly(
        now: LocalDateTime,
        preferred: LocalTime,
        weekdayIso: Int,
        everyWeeks: Int,
    ): LocalDateTime? {
        val target = DayOfWeek.of(weekdayIso)
        var date = now.toLocalDate()
        var daysForward = (target.value - date.dayOfWeek.value + 7) % 7
        var candidate = date.plusDays(daysForward.toLong()).atTime(preferred)
        if (!candidate.isAfter(now)) candidate = candidate.plusWeeks(everyWeeks.toLong())
        return candidate
    }

    private fun previousWeekly(
        now: LocalDateTime,
        preferred: LocalTime,
        weekdayIso: Int,
        everyWeeks: Int,
    ): LocalDateTime? {
        val target = DayOfWeek.of(weekdayIso)
        var candidate = now.toLocalDate().atTime(preferred)
        var daysBack = (now.toLocalDate().dayOfWeek.value - target.value + 7) % 7
        candidate = candidate.minusDays(daysBack.toLong())
        if (candidate.isAfter(now)) candidate = candidate.minusDays(7)
        return candidate
    }

    private fun nextMonthly(
        now: LocalDateTime,
        preferred: LocalTime,
        anchorEpochDay: Long,
        everyMonths: Int,
    ): LocalDateTime? {
        val anchorDayOfMonth = LocalDate.ofEpochDay(anchorEpochDay).dayOfMonth
        val safeDay = anchorDayOfMonth.coerceAtMost(28)
        var candidate = now.toLocalDate().withDayOfMonth(safeDay).atTime(preferred)
        if (!candidate.isAfter(now)) candidate = candidate.plusMonths(everyMonths.toLong())
        return candidate
    }

    private fun previousMonthly(
        now: LocalDateTime,
        preferred: LocalTime,
        anchorEpochDay: Long,
        everyMonths: Int,
    ): LocalDateTime? {
        val anchorDayOfMonth = LocalDate.ofEpochDay(anchorEpochDay).dayOfMonth
        val safeDay = anchorDayOfMonth.coerceAtMost(28)
        var candidate = now.toLocalDate().withDayOfMonth(safeDay).atTime(preferred)
        if (candidate.isAfter(now)) candidate = candidate.minusMonths(everyMonths.toLong())
        return candidate
    }

    /**
     * Monthly occurrence day clamped to 28 diverges from the iOS calendar math; entries using
     * MONTH cadence are accepted but the runtime must document the clamp per-platform.
     */
    fun monthDayClampNote(): String = "Monthly profile entries clamp to day <= 28 on Android."
}

/**
 * Projected monthly exporting requests for an entry list (Android mirror of
 * `ScheduledUsageProjection`): main runs plus Today Refreshes, 30-day approximation.
 */
object ScheduledProfileUsageProjection {

    fun projectedMonthlyRequests(entry: ScheduledProfileEntry): Int {
        val cadenceDays = when (entry.cadenceUnit) {
            ScheduledProfileCadenceUnit.DAY -> entry.cadenceValue.toDouble()
            ScheduledProfileCadenceUnit.WEEK -> entry.cadenceValue * 7.0
            ScheduledProfileCadenceUnit.MONTH -> entry.cadenceValue * 30.0
        }
        val runsPerDay = 1.0 / cadenceDays
        return Math.ceil(runsPerDay * 30.0).toInt().coerceAtLeast(1)
    }

    fun projectedMonthlyTotal(entries: List<ScheduledProfileEntry>): Int =
        entries.filter { it.isEnabled }.sumOf { projectedMonthlyRequests(it) }
}

/** Coalescing helper shared with the push scheduler mirror (earliest preferred time wins). */
object ScheduledProfileWorkerCoalescing {

    /** The enabled entry (or legacy schedule) with the earliest preferred time-of-day. */
    fun earliestPreferred(
        entries: List<ScheduledProfileEntry>,
        legacyHour: Int?,
        legacyMinute: Int?,
    ): Pair<Int, Int>? =
        (
            entries.filter { it.isEnabled }.map { it.hour to it.minute } +
                listOfNotNull(
                    legacyHour?.takeIf { it >= 0 }?.let { hour -> hour to (legacyMinute ?: 0) },
                )
            ).minByOrNull { (hour, minute) -> hour * 60 + minute }
}

