package com.healthmd.data.scheduler

import com.healthmd.domain.model.ExportTarget
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
 * Frozen exact residual work from one interrupted or failed profile occurrence. Separate groups
 * keep durable operation identities from mixing with dates that require a fresh capture.
 */
@Serializable
data class ScheduledProfilePendingExport(
    val id: String,
    val ownerEpochDays: List<Long>,
    val fireAtMillis: Long,
    val settingsSnapshotJson: String,
    val target: ExportTarget,
    val profileName: String,
    val apiEndpointUrl: String? = null,
    val folderUri: String? = null,
    val folderDisplayName: String? = null,
    val durableOperationId: String? = null,
) {
    val ownerDates: List<LocalDate>
        get() = ownerEpochDays.distinct().sorted().map(LocalDate::ofEpochDay)
}

/**
 * One scheduled-export configuration bound to exactly one export profile (Android phase 6).
 *
 * Mirrors iOS `ScheduledExportEntry`: cadence fields plus per-entry progress state so occurrence
 * math works independently per profile. Cancellation residuals freeze the original profile
 * destination and output snapshot until their exact owner dates are resolved.
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
    /** Whether today's partial file is also refreshed during the day (iOS Today Refresh parity). */
    val todayRefreshEnabled: Boolean = false,
    /** Hours between same-day refresh runs; Apple exposes the same {3, 6, 12} set. */
    val todayRefreshIntervalHours: Int = DEFAULT_TODAY_REFRESH_INTERVAL_HOURS,
    val zoneId: String = "UTC",
    /** Epoch millis of the most recent successful completed-day occurrence, for catch-up math. */
    val lastSuccessEpochMillis: Long? = null,
    /** Epoch millis of the most recent successful Today Refresh occurrence. */
    val lastRefreshSuccessEpochMillis: Long? = null,
    /** Exact frozen residual groups left by interrupted or failed automated export attempts. */
    val pendingExports: List<ScheduledProfilePendingExport> = emptyList(),
) {
    init {
        require(lookbackDays in 1..30) { "Lookback must stay within 1..30." }
        require(hour in 0..23 && minute in 0..59) { "Preferred time is invalid." }
        require(cadenceValue >= 1) { "Cadence value must be positive." }
        require(weekdayIso in 1..7) { "Weekday must stay within ISO 1..7." }
        require(todayRefreshIntervalHours in TODAY_REFRESH_INTERVAL_OPTIONS) {
            "Today Refresh interval must be one of $TODAY_REFRESH_INTERVAL_OPTIONS hours."
        }
        require(ZoneId.of(zoneId).id == zoneId) { "Zone id must be canonical." }
    }

    val zone: ZoneId get() = ZoneId.of(zoneId)

    /** A due, actionable occurrence for one entry. */
    data class DueOccurrence(
        val entry: ScheduledProfileEntry,
        val fireAtMillis: Long,
        /** Data days to export; empty means nothing actionable at this boundary. */
        val exportDates: List<LocalDate>,
        /** Non-null when this run is retrying one exact frozen residual group. */
        val pendingExport: ScheduledProfilePendingExport? = null,
        /**
         * Non-null when a same-day refresh slot is part of this occurrence (the fire date of the
         * slot, not of the cadence boundary). A successful export of [java.time.LocalDate.now]'s
         * date advances [lastRefreshSuccessEpochMillis] by exactly this value. When the occurrence
         * carries no completed-day work, [fireAtMillis] equals this slot and must NOT advance the
         * completed-day catch-up frontier.
         */
        val refreshSlotMillis: Long? = null,
    )

    companion object {
        /** Same-day refresh interval options, mirroring iOS Today Refresh. */
        val TODAY_REFRESH_INTERVAL_OPTIONS: List<Int> = listOf(3, 6, 12)
        const val DEFAULT_TODAY_REFRESH_INTERVAL_HOURS = 3

        /** Nearest supported interval to [hours]; used by legacy-schedule migration. */
        fun clampTodayRefreshInterval(hours: Int): Int =
            TODAY_REFRESH_INTERVAL_OPTIONS.minByOrNull { kotlin.math.abs(it - hours) }
                ?: DEFAULT_TODAY_REFRESH_INTERVAL_HOURS
    }
}

/**
 * Pure per-entry occurrence math mirroring the shipped single-schedule evaluator's two-layer
 * semantics: a boundary passed **and** catch-up work remaining. Unit-testable without Android
 * instrumentation; the runtime layers (AlarmManager arming, WorkManager execution) consume this.
 */
object ScheduledProfileOccurrenceMath {

    /**
     * Next boundary strictly after [nowMillis] for the entry's cadence and zone, or the next
     * same-day refresh slot when Today Refresh is enabled and comes first. Arming calls this so
     * one alarm covers whichever occurrence is earliest.
     */
    fun nextOccurrence(entry: ScheduledProfileEntry, nowMillis: Long): Instant? {
        val zone = entry.zone
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone).toLocalDateTime()
        val preferred = LocalTime.of(entry.hour, entry.minute)
        val cadenceNext = when (entry.cadenceUnit) {
            ScheduledProfileCadenceUnit.DAY ->
                nextDaily(now = now, preferred = preferred, everyDays = entry.cadenceValue.toLong())
            ScheduledProfileCadenceUnit.WEEK ->
                nextWeekly(now = now, preferred = preferred, weekdayIso = entry.weekdayIso, everyWeeks = entry.cadenceValue)
            ScheduledProfileCadenceUnit.MONTH ->
                nextMonthly(now = now, preferred = preferred, anchorEpochDay = entry.anchorEpochDay, everyMonths = entry.cadenceValue)
        }?.atZone(zone)?.toInstant()
        val refreshNext = nextRefreshOccurrence(entry, nowMillis)
        return listOfNotNull(cadenceNext, refreshNext).minOrNull()
    }

    /**
     * Next same-day refresh slot strictly after [nowMillis], mirroring iOS
     * `ScheduleDateMath.nextTodayRefreshRunDate`: slots run at the preferred time plus whole
     * intervals while they stay inside the same calendar day; after the last slot, the next is
     * tomorrow's preferred time (which coincides with the completed-day boundary).
     */
    fun nextRefreshOccurrence(entry: ScheduledProfileEntry, nowMillis: Long): Instant? {
        if (!entry.isEnabled || !entry.todayRefreshEnabled) return null
        val zone = entry.zone
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val today = now.toLocalDate()
        val interval = entry.todayRefreshIntervalHours
        var slotHour = entry.hour
        while (slotHour < HOURS_PER_DAY) {
            val candidate = today.atTime(LocalTime.of(slotHour, entry.minute)).atZone(zone)
            if (candidate.toInstant().isAfter(now.toInstant())) {
                return candidate.toInstant()
            }
            slotHour += interval
        }
        return today.plusDays(1).atTime(LocalTime.of(entry.hour, entry.minute)).atZone(zone).toInstant()
    }

    /**
     * The latest refresh slot at or before [nowMillis] that has not yet succeeded, mirroring iOS
     * `ScheduleDateMath.shouldRunScheduledOccurrence` for `.todayRefresh`: slots only count on the
     * current calendar day, and a slot at or before [ScheduledProfileEntry.lastRefreshSuccessEpochMillis]
     * already ran. Returns null when refresh is disabled or every slot already succeeded.
     */
    fun dueRefreshSlotMillis(entry: ScheduledProfileEntry, nowMillis: Long): Long? {
        if (!entry.isEnabled || !entry.todayRefreshEnabled) return null
        val zone = entry.zone
        val now = Instant.ofEpochMilli(nowMillis).atZone(zone)
        val today = now.toLocalDate()
        val interval = entry.todayRefreshIntervalHours
        var latest: Long? = null
        var slotHour = entry.hour
        while (slotHour < HOURS_PER_DAY) {
            val candidate = today.atTime(LocalTime.of(slotHour, entry.minute)).atZone(zone)
            if (!candidate.toInstant().isAfter(now.toInstant())) {
                latest = candidate.toInstant().toEpochMilli()
            }
            slotHour += interval
        }
        val lastSuccess = entry.lastRefreshSuccessEpochMillis
        return latest?.takeIf { slot -> lastSuccess == null || slot > lastSuccess }
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

        // Finish one frozen residual group before admitting newer profile settings or
        // owner dates. Exact dates and durable operation identity therefore survive profile edits.
        // Residual groups freeze completed-day owner dates only; a due refresh slot does not join
        // them and simply waits for its next slot once the residual clears.
        entry.pendingExports
            .sortedWith(
                compareBy<ScheduledProfilePendingExport> { it.fireAtMillis }
                    .thenBy { it.ownerEpochDays.minOrNull() ?: Long.MAX_VALUE }
                    .thenBy { it.id },
            )
            .firstNotNullOfOrNull { pending ->
                val dates = pending.ownerDates.filterNot { it.isAfter(yesterday) }
                dates.takeIf { it.isNotEmpty() }?.let {
                    ScheduledProfileEntry.DueOccurrence(
                        entry = entry,
                        fireAtMillis = pending.fireAtMillis,
                        exportDates = it,
                        pendingExport = pending,
                    )
                }
            }
            ?.let { return it }

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

        // Today Refresh joins the regular catch-up branch: one run exports the trailing window
        // plus today's partial file. A refresh-only occurrence (nothing to catch up) carries the
        // slot itself as its fire date and never advances the completed-day frontier.
        val refreshSlotMillis = dueRefreshSlotMillis(entry, nowMillis)
        if (pending.isEmpty()) {
            val slot = refreshSlotMillis ?: return null
            return ScheduledProfileEntry.DueOccurrence(
                entry = entry,
                fireAtMillis = slot,
                exportDates = listOf(today),
                refreshSlotMillis = slot,
            )
        }

        return ScheduledProfileEntry.DueOccurrence(
            entry = entry,
            fireAtMillis = boundary.toEpochMilli(),
            exportDates = if (refreshSlotMillis == null) {
                pending
            } else {
                pending + today
            },
            refreshSlotMillis = refreshSlotMillis,
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
        var candidate = withAnchorDayOfMonth(now.toLocalDate(), anchorDayOfMonth).atTime(preferred)
        if (!candidate.isAfter(now)) {
            val nextMonth = candidate.toLocalDate().plusMonths(everyMonths.toLong())
            candidate = withAnchorDayOfMonth(nextMonth, anchorDayOfMonth).atTime(preferred)
        }
        return candidate
    }

    private fun previousMonthly(
        now: LocalDateTime,
        preferred: LocalTime,
        anchorEpochDay: Long,
        everyMonths: Int,
    ): LocalDateTime? {
        val anchorDayOfMonth = LocalDate.ofEpochDay(anchorEpochDay).dayOfMonth
        var candidate = withAnchorDayOfMonth(now.toLocalDate(), anchorDayOfMonth).atTime(preferred)
        if (candidate.isAfter(now)) {
            val previousMonth = candidate.toLocalDate().minusMonths(everyMonths.toLong())
            candidate = withAnchorDayOfMonth(previousMonth, anchorDayOfMonth).atTime(preferred)
        }
        return candidate
    }

    /**
     * Calendar-natural monthly anchor day (iOS parity): an anchor like the 31st fires on the
     * 31st in 31-day months and the last day of shorter months (Jan 31 → Feb 28 → Mar 31).
     */
    private fun withAnchorDayOfMonth(month: LocalDate, anchorDayOfMonth: Int): LocalDate =
        month.withDayOfMonth(minOf(anchorDayOfMonth, month.lengthOfMonth()))

    private const val HOURS_PER_DAY = 24
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

