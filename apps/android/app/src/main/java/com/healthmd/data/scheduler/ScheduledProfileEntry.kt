package com.healthmd.data.scheduler

import com.healthmd.domain.model.ExportTarget
import kotlinx.serialization.Serializable
import java.time.DayOfWeek
import java.time.Instant
import java.time.LocalDate
import java.time.LocalTime
import java.time.YearMonth
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import java.time.temporal.TemporalAdjusters

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
    /** Latest satisfied completed-day boundary; deduplicates occurrences, not overlapping dates. */
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
 * Each unsatisfied cadence boundary exports its full trailing window, including dates exported
 * by earlier occurrences. Frozen residuals take priority and Today Refresh stays independent.
 * Pure date math shared by AlarmManager arming and WorkManager execution.
 */
object ScheduledProfileOccurrenceMath {

    /**
     * Next boundary strictly after [nowMillis] for the entry's cadence and zone, or the next
     * same-day refresh slot when Today Refresh is enabled and comes first. Arming calls this so
     * one alarm covers whichever occurrence is earliest.
     */
    fun nextOccurrence(entry: ScheduledProfileEntry, nowMillis: Long): Instant? {
        val cadenceNext = cadenceBoundary(entry, nowMillis, next = true)
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
     * The latest unsatisfied boundary at or before [nowMillis], or a frozen residual / today slot.
     * A new completed-day occurrence always re-exports the full configured lookback ending the
     * day before its scheduled boundary, even if execution starts after midnight.
     */
    fun dueOccurrence(
        entry: ScheduledProfileEntry,
        nowMillis: Long,
    ): ScheduledProfileEntry.DueOccurrence? {
        if (!entry.isEnabled) return null
        val boundary = cadenceBoundary(entry, nowMillis, next = false)
        val zone = entry.zone

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

        val completedDates = if (boundary != null &&
            (entry.lastSuccessEpochMillis == null || entry.lastSuccessEpochMillis < boundary.toEpochMilli())
        ) {
            val fireDay = boundary.atZone(zone).toLocalDate()
            (entry.lookbackDays downTo 1).map { fireDay.minusDays(it.toLong()) }
        } else {
            emptyList()
        }

        // A refresh can join a new completed-day occurrence, but must not replay its lookback
        // after that boundary succeeded. Refresh-only runs never advance the cadence marker.
        val refreshSlotMillis = dueRefreshSlotMillis(entry, nowMillis)
        if (completedDates.isEmpty()) {
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
            fireAtMillis = checkNotNull(boundary).toEpochMilli(),
            exportDates = if (refreshSlotMillis == null) {
                completedDates
            } else {
                completedDates + today
            },
            refreshSlotMillis = refreshSlotMillis,
        )
    }

    /**
     * One anchored calendar calculation for arming and due evaluation. Otherwise every-N
     * schedules can invent intervening boundaries and replay a full lookback on off-cadence
     * wake-ups. Monthly addition starts from the original anchor (Jan 31 → Feb 28 → Mar 31).
     */
    private fun cadenceBoundary(entry: ScheduledProfileEntry, nowMillis: Long, next: Boolean): Instant? {
        val now = Instant.ofEpochMilli(nowMillis)
        val today = now.atZone(entry.zone).toLocalDate()
        val savedAnchor = LocalDate.ofEpochDay(entry.anchorEpochDay)
        val anchor = if (entry.cadenceUnit == ScheduledProfileCadenceUnit.WEEK) {
            savedAnchor.with(TemporalAdjusters.nextOrSame(DayOfWeek.of(entry.weekdayIso)))
        } else {
            savedAnchor
        }
        val elapsed = when (entry.cadenceUnit) {
            ScheduledProfileCadenceUnit.DAY -> ChronoUnit.DAYS.between(anchor, today)
            ScheduledProfileCadenceUnit.WEEK -> Math.floorDiv(ChronoUnit.DAYS.between(anchor, today), 7L)
            ScheduledProfileCadenceUnit.MONTH -> ChronoUnit.MONTHS.between(YearMonth.from(anchor), YearMonth.from(today))
        }
        val stride = entry.cadenceValue.toLong()
        var index = Math.floorDiv(elapsed, stride).coerceAtLeast(0)
        fun occurrence(index: Long): Instant {
            val offset = index * stride
            val day = when (entry.cadenceUnit) {
                ScheduledProfileCadenceUnit.DAY -> anchor.plusDays(offset)
                ScheduledProfileCadenceUnit.WEEK -> anchor.plusWeeks(offset)
                ScheduledProfileCadenceUnit.MONTH -> anchor.plusMonths(offset)
            }
            return day.atTime(entry.hour, entry.minute).atZone(entry.zone).toInstant()
        }
        val candidate = occurrence(index)
        if (next && !candidate.isAfter(now)) index++
        if (!next && candidate.isAfter(now)) index--
        return index.takeIf { it >= 0 }?.let(::occurrence)
    }

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

