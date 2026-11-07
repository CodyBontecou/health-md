package com.healthmd.presentation.archive

import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.rawexport.ExportMode
import java.net.URI
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

    /** Today, for an automation that is due today: an export may still update this date. */
    IN_PROGRESS,
}

/** A selected-day row action, mirroring Apple `ArchiveAggregation.DayAction`. */
enum class ArchiveDayAction(
    /** Accent styling for actions that fix something. */
    val isProminent: Boolean,
) {
    OPEN(isProminent = false),
    REEXPORT(isProminent = true),
    RETRY(isProminent = true),
    BACKFILL(isProminent = true),
    REFRESH(isProminent = false),
}

/** Where one automation lane writes a date, for the selected-day rows. */
sealed interface ArchiveOutput {
    /** Dated files under a device folder, built from the lane's own output settings. */
    data class DeviceFolder(val folderName: String?, val settings: ExportSettings) : ArchiveOutput

    /** An HTTP destination; [line] is already `POST host/path`. */
    data class Endpoint(val line: String) : ArchiveOutput
}

/** What the Archive knows about one automation lane besides its export history. */
data class ArchiveLane(
    /** An enabled daily schedule or Today Refresh keeps today's file updating. */
    val isDueToday: Boolean = false,
    val hasTodayRefresh: Boolean = false,
    val output: ArchiveOutput? = null,
)

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
        /** Today is in progress only for an automation due today (Apple `CoverageProjection`). */
        isDueToday: Boolean = false,
    ): CoverageStatus {
        if (date.isAfter(today)) return CoverageStatus.NOT_DUE
        if (date == today && isDueToday) return CoverageStatus.IN_PROGRESS
        val covering = covering(entries, profile, date)
        if (covering.isEmpty()) return CoverageStatus.NOT_DUE
        val best = covering.maxOf { outcome(it, date) }
        // Today is never a gap yet: a written file shows, anything else is not due.
        if (date == today && best == Outcome.FAILED) return CoverageStatus.NOT_DUE
        return best.status
    }

    /**
     * "All": over profiles due for the date, missing > partial > complete. Today is in
     * progress while any profile is due, and a date nothing was due on is not due (today
     * included, so an on-demand-only setup does not read as updating).
     */
    fun aggregate(statuses: List<CoverageStatus>, isToday: Boolean): CoverageStatus {
        val due = statuses.filter(::isDue)
        return when {
            due.isEmpty() -> CoverageStatus.NOT_DUE
            isToday -> CoverageStatus.IN_PROGRESS
            CoverageStatus.MISSING in due -> CoverageStatus.MISSING
            CoverageStatus.PARTIAL in due -> CoverageStatus.PARTIAL
            else -> CoverageStatus.COMPLETE
        }
    }

    /** "All" for one date across every profile in [entries]. */
    fun aggregateDay(
        entries: List<ExportHistoryEntry>,
        date: LocalDate,
        today: LocalDate,
        dueToday: Set<ArchiveProfile> = emptySet(),
    ): CoverageStatus = aggregate(
        profiles(entries).map { status(entries, it, date, today, it in dueToday) },
        isToday = date == today,
    )

    /** "x of y on track" over due profiles; an update in progress counts as on track. */
    fun onTrack(days: List<ArchiveProfileDay>): Pair<Int, Int> {
        val due = days.map { it.status }.filter(::isDue)
        return due.count { it == CoverageStatus.COMPLETE || it == CoverageStatus.IN_PROGRESS } to due.size
    }

    /**
     * Days archived = complete + partial; gaps = missing. Today is excluded.
     */
    fun stats(days: List<Pair<LocalDate, CoverageStatus>>, today: LocalDate): ArchiveStats {
        var archived = 0
        var gaps = 0
        var earliestGap: LocalDate? = null
        days.filter { it.first.isBefore(today) }
            .sortedByDescending { it.first }
            .forEach { (date, status) ->
                when (status) {
                    CoverageStatus.COMPLETE, CoverageStatus.PARTIAL -> archived += 1
                    CoverageStatus.MISSING -> {
                        gaps += 1
                        earliestGap = date
                    }
                    CoverageStatus.NOT_DUE, CoverageStatus.IN_PROGRESS -> Unit
                }
            }
        return ArchiveStats(archived, gaps, earliestGap)
    }

    /** Per-profile rows for the selected day, in profile order. */
    fun profileDays(
        entries: List<ExportHistoryEntry>,
        profiles: List<ArchiveProfile>,
        date: LocalDate,
        today: LocalDate,
        dueToday: Set<ArchiveProfile> = emptySet(),
    ): List<ArchiveProfileDay> = profiles.map { profile ->
        ArchiveProfileDay(
            profile = profile,
            status = status(entries, profile, date, today, profile in dueToday),
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
        dueToday: Set<ArchiveProfile> = emptySet(),
    ): ArchiveMonth {
        val profiles = profiles(entries)
        val lanes = filter?.let(::listOf) ?: profiles
        val days = (1..month.lengthOfMonth()).map { dayOfMonth ->
            val date = month.atDay(dayOfMonth)
            val laneStatuses = lanes.map { it to status(entries, it, date, today, it in dueToday) }
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
            stats = stats(days.map { it.date to it.status }, today),
        )
    }

    /** The row action for a status (Apple `ArchiveAggregation.action`); Open needs the date's file. */
    fun action(status: CoverageStatus, hasTodayRefresh: Boolean, canOpen: Boolean): ArchiveDayAction? =
        when (status) {
            CoverageStatus.COMPLETE -> ArchiveDayAction.OPEN.takeIf { canOpen }
            CoverageStatus.PARTIAL -> if (hasTodayRefresh) ArchiveDayAction.RETRY else ArchiveDayAction.REEXPORT
            CoverageStatus.MISSING -> ArchiveDayAction.BACKFILL
            CoverageStatus.IN_PROGRESS -> ArchiveDayAction.REFRESH
            CoverageStatus.NOT_DUE -> null
        }

    /** An enabled per-automation schedule keeps today updating when it runs daily or refreshes today. */
    fun isDueToday(entry: ScheduledProfileEntry?): Boolean =
        entry != null && entry.isEnabled && (
            entry.todayRefreshEnabled ||
                (entry.cadenceUnit == ScheduledProfileCadenceUnit.DAY && entry.cadenceValue == 1)
            )

    /** The history lanes due today. A named lane resolves to its profile's schedule by name. */
    fun dueToday(
        lanes: List<ArchiveProfile>,
        profiles: List<ExportProfile>,
        schedules: List<ScheduledProfileEntry>,
        settings: ExportSettings?,
    ): Set<ArchiveProfile> = lanes.filter { lane ->
        val name = lane.name
        if (name == null) {
            settings?.let(::isDueToday) == true
        } else {
            val profile = ExportProfileRules.byName(profiles, name)
            isDueToday(profile?.let { found -> schedules.firstOrNull { it.profileId == found.id } })
        }
    }.toSet()

    /** The legacy app-wide schedule, which still drives the current-settings lane until migrated. */
    fun isDueToday(settings: ExportSettings): Boolean =
        settings.scheduleEnabled && (
            settings.scheduleDateWindow != ScheduleDateWindow.PAST_COMPLETE_DAYS ||
                settings.scheduleCadenceUnit == ScheduleCadenceUnit.MINUTES ||
                settings.scheduleCadenceUnit == ScheduleCadenceUnit.HOURS ||
                (settings.scheduleCadenceUnit == ScheduleCadenceUnit.DAYS && settings.scheduleCadenceValue == 1)
            )

    /**
     * The date's file relative to its folder, built the way the exporter names it, or null when
     * the output has no per-date file (raw snapshots, no file format).
     */
    fun relativeFilePath(settings: ExportSettings, date: LocalDate): String? {
        if (settings.exportMode == ExportMode.RAW_SNAPSHOT) return null
        val formats = settings.selectedExportFormats
        val format = ExportFormat.entries.firstOrNull { it in formats } ?: return null
        return settings.aggregateRelativePath(date, format)
    }

    /**
     * The row's path line (Apple `ArchiveOutputPath.display`): the dated file for written or due
     * dates, the folder alone otherwise, the endpoint line, or null when nothing is known.
     */
    fun pathLine(output: ArchiveOutput?, date: LocalDate, status: CoverageStatus): String? = when (output) {
        null -> null
        is ArchiveOutput.Endpoint -> output.line
        is ArchiveOutput.DeviceFolder -> {
            val root = output.folderName?.trimEnd('/')?.takeIf { it.isNotBlank() }
            val relative = if (status == CoverageStatus.NOT_DUE) null else relativeFilePath(output.settings, date)
            when {
                relative == null -> root
                root == null -> relative
                else -> "$root/$relative"
            }
        }
    }

    /** `POST api.example.com/health`. Scheme, credentials, query and fragment are left out. */
    fun endpointLine(url: String?): String? {
        val uri = url?.trim()?.takeIf { it.isNotEmpty() }?.let { runCatching { URI(it) }.getOrNull() } ?: return null
        val host = uri.host?.takeIf { it.isNotBlank() } ?: return null
        val port = if (uri.port >= 0) ":${uri.port}" else ""
        val path = uri.rawPath.orEmpty().takeUnless { it == "/" }.orEmpty()
        return "POST $host$port$path"
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
