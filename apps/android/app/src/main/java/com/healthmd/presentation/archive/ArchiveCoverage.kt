package com.healthmd.presentation.archive

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import java.time.LocalDate
import java.time.YearMonth

/**
 * How one health date stands for one export profile, derived from Android export history.
 * The states and the "All" aggregation mirror the Apple Archive (`CoverageStatus` and
 * `ArchiveAggregation`); Android has no paused-schedule ledger, so it has no paused state.
 */
enum class CoverageStatus {
    COMPLETE,
    PARTIAL,
    MISSING,

    /** Nothing in history covered this date, or it is in the future. */
    NOT_DUE,

    /** Today: an export may still update this date. */
    IN_PROGRESS,
}

/** One automation lane in the Archive. A null name is the app's current settings. */
data class ArchiveProfile(val name: String?)

data class ArchiveIssueDot(val profile: ArchiveProfile, val isFilled: Boolean)

data class ArchiveDay(
    val date: LocalDate,
    val status: CoverageStatus,
    val issueDots: List<ArchiveIssueDot>,
    val hasIssueOverflow: Boolean,
)

data class ArchiveProfileDay(
    val profile: ArchiveProfile,
    val status: CoverageStatus,
    /** The most recent history entry that covered the date for this profile. */
    val latestEntry: ExportHistoryEntry?,
)

data class ArchiveStats(
    val archivedCount: Int,
    val gapCount: Int,
    val earliestGap: LocalDate?,
    val streak: Int,
)

data class ArchiveMonth(
    val month: YearMonth,
    val profiles: List<ArchiveProfile>,
    val days: List<ArchiveDay>,
    val stats: ArchiveStats,
)

object ArchiveCoverage {
    const val MAXIMUM_ISSUE_DOTS = 3

    /** Profiles in the order they were most recently exported. */
    fun profiles(entries: List<ExportHistoryEntry>): List<ArchiveProfile> =
        entries.sortedByDescending { it.timestamp }
            .map { ArchiveProfile(it.profileName) }
            .distinct()

    /**
     * The best outcome any covering entry produced for [date]. Outcomes merge so that a
     * later failure never hides a file that an earlier run already wrote.
     */
    fun status(
        entries: List<ExportHistoryEntry>,
        profile: ArchiveProfile,
        date: LocalDate,
        today: LocalDate,
    ): CoverageStatus {
        if (date == today) return CoverageStatus.IN_PROGRESS
        if (date.isAfter(today)) return CoverageStatus.NOT_DUE
        val covering = covering(entries, profile, date)
        if (covering.isEmpty()) return CoverageStatus.NOT_DUE
        return covering.maxOf { outcome(it, date) }.status
    }

    /** "All": over profiles due for the date, missing > partial > complete. */
    fun aggregate(statuses: List<CoverageStatus>, isToday: Boolean): CoverageStatus {
        if (isToday) return CoverageStatus.IN_PROGRESS
        val due = statuses.filter(::isDue)
        return when {
            due.isEmpty() -> CoverageStatus.NOT_DUE
            CoverageStatus.MISSING in due -> CoverageStatus.MISSING
            CoverageStatus.PARTIAL in due -> CoverageStatus.PARTIAL
            else -> CoverageStatus.COMPLETE
        }
    }

    /** "All" for one date across every profile in [entries]. */
    fun aggregateDay(entries: List<ExportHistoryEntry>, date: LocalDate, today: LocalDate): CoverageStatus =
        aggregate(profiles(entries).map { status(entries, it, date, today) }, isToday = date == today)

    /** "x of y on track" over due profiles; an update in progress counts as on track. */
    fun onTrack(days: List<ArchiveProfileDay>): Pair<Int, Int> {
        val due = days.map { it.status }.filter(::isDue)
        return due.count { it == CoverageStatus.COMPLETE || it == CoverageStatus.IN_PROGRESS } to due.size
    }

    /**
     * Days archived = complete + partial. The streak runs back from the latest past date,
     * skips dates with nothing due, and stops at the first gap. Today is excluded.
     */
    fun stats(days: List<Pair<LocalDate, CoverageStatus>>, today: LocalDate): ArchiveStats {
        var archived = 0
        var gaps = 0
        var earliestGap: LocalDate? = null
        var streak = 0
        var streakIsOpen = true
        days.filter { it.first.isBefore(today) }
            .sortedByDescending { it.first }
            .forEach { (date, status) ->
                when (status) {
                    CoverageStatus.COMPLETE, CoverageStatus.PARTIAL -> {
                        archived += 1
                        if (streakIsOpen) streak += 1
                    }
                    CoverageStatus.MISSING -> {
                        gaps += 1
                        streakIsOpen = false
                        earliestGap = date
                    }
                    CoverageStatus.NOT_DUE, CoverageStatus.IN_PROGRESS -> Unit
                }
            }
        return ArchiveStats(archived, gaps, earliestGap, streak)
    }

    /** Per-profile rows for the selected day, in profile order. */
    fun profileDays(
        entries: List<ExportHistoryEntry>,
        profiles: List<ArchiveProfile>,
        date: LocalDate,
        today: LocalDate,
    ): List<ArchiveProfileDay> = profiles.map { profile ->
        ArchiveProfileDay(
            profile = profile,
            status = status(entries, profile, date, today),
            latestEntry = covering(entries, profile, date).maxByOrNull { it.timestamp },
        )
    }

    /**
     * The calendar for [month]. With a [filter] the days show that profile alone and carry
     * no issue dots; without one they aggregate every profile ("All").
     */
    fun month(
        entries: List<ExportHistoryEntry>,
        month: YearMonth,
        today: LocalDate,
        filter: ArchiveProfile?,
    ): ArchiveMonth {
        val profiles = profiles(entries)
        val lanes = filter?.let(::listOf) ?: profiles
        val days = (1..month.lengthOfMonth()).map { dayOfMonth ->
            val date = month.atDay(dayOfMonth)
            val laneStatuses = lanes.map { it to status(entries, it, date, today) }
            val status = if (filter != null) {
                laneStatuses.firstOrNull()?.second ?: CoverageStatus.NOT_DUE
            } else {
                aggregate(laneStatuses.map { it.second }, isToday = date == today)
            }
            val dots = if (filter != null) {
                emptyList()
            } else {
                laneStatuses.mapNotNull { (profile, laneStatus) ->
                    when (laneStatus) {
                        CoverageStatus.PARTIAL -> ArchiveIssueDot(profile, isFilled = true)
                        CoverageStatus.MISSING -> ArchiveIssueDot(profile, isFilled = false)
                        else -> null
                    }
                }
            }
            ArchiveDay(
                date = date,
                status = status,
                issueDots = dots.take(MAXIMUM_ISSUE_DOTS),
                hasIssueOverflow = dots.size > MAXIMUM_ISSUE_DOTS,
            )
        }
        return ArchiveMonth(
            month = month,
            profiles = profiles,
            days = days,
            // Archived days and gaps belong to the shown month; the streak is the current one,
            // the same number the Archive widget shows, so it does not reset on the 1st.
            stats = stats(days.map { it.date to it.status }, today)
                .copy(streak = currentStreak(entries, today, filter)),
        )
    }

    /**
     * The current streak: back from yesterday across month boundaries to the first gap,
     * skipping dates with nothing due, and never before the earliest export.
     */
    fun currentStreak(entries: List<ExportHistoryEntry>, today: LocalDate, filter: ArchiveProfile? = null): Int {
        val earliest = entries.minOfOrNull { it.dateRangeStart } ?: return 0
        val lanes = filter?.let(::listOf) ?: profiles(entries)
        var streak = 0
        var date = today.minusDays(1)
        while (!date.isBefore(earliest)) {
            val statuses = lanes.map { status(entries, it, date, today) }
            val status = if (filter != null) {
                statuses.firstOrNull() ?: CoverageStatus.NOT_DUE
            } else {
                aggregate(statuses, isToday = false)
            }
            when (status) {
                CoverageStatus.COMPLETE, CoverageStatus.PARTIAL -> streak += 1
                CoverageStatus.MISSING -> return streak
                CoverageStatus.NOT_DUE, CoverageStatus.IN_PROGRESS -> Unit
            }
            date = date.minusDays(1)
        }
        return streak
    }

    private fun isDue(status: CoverageStatus): Boolean = status != CoverageStatus.NOT_DUE

    private fun covering(
        entries: List<ExportHistoryEntry>,
        profile: ArchiveProfile,
        date: LocalDate,
    ): List<ExportHistoryEntry> = entries.filter { entry ->
        entry.profileName == profile.name &&
            !date.isBefore(entry.dateRangeStart) &&
            !date.isAfter(entry.dateRangeEnd)
    }

    private enum class Outcome(val status: CoverageStatus) {
        FAILED(CoverageStatus.MISSING),
        PARTIAL(CoverageStatus.PARTIAL),
        COMPLETE(CoverageStatus.COMPLETE),
    }

    private fun outcome(entry: ExportHistoryEntry, date: LocalDate): Outcome {
        val failure = entry.failedDateDetails.firstOrNull { it.date == date }
        return when {
            // A day without health data wrote nothing to fix; it is not a gap to backfill.
            failure?.reason == ExportFailureReason.NO_HEALTH_DATA -> Outcome.PARTIAL
            failure != null -> Outcome.FAILED
            entry.isFailure -> Outcome.FAILED
            // A partial run without per-date detail cannot say which dates were written.
            entry.isPartialSuccess && entry.failedDateDetails.isEmpty() -> Outcome.PARTIAL
            else -> Outcome.COMPLETE
        }
    }
}
