package com.healthmd.data.health

import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.SleepStageEntry
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.nanoseconds
import kotlin.time.Duration.Companion.seconds

/**
 * Pure compatibility projection for Health Connect sleep sessions.
 *
 * With the default night-begins attribution ([SleepDayAttribution.NIGHT_BEGINS], rule
 * `noon-to-noon-sleep-window-v1`), the exported journal date owns the half-open local
 * interval from noon on that date to noon on the following date. Summary intervals are
 * clipped to that window, while detailed source entries retain their original timestamps
 * and offsets.
 *
 * With wake-up-date attribution ([SleepDayAttribution.MORNING_ENDS], rule
 * `wake-date-sleep-window-v1`, issue #104), the journal date owns every source session
 * that ENDS on that date, matching the Health Connect UI. Owned sessions are kept whole:
 * they are never clipped at a noon boundary or split between two journal days, and
 * afternoon naps stay on the day they end. The read interval in [queryInterval] is
 * unchanged because Health Connect interval reads are overlap-based; its prior-day
 * noon start already covers overnight sessions ending on the first requested date.
 *
 * Aggregation remains additive: valid owned source sessions and recognized stages contribute
 * independently, without principal-cluster selection or provider de-duplication. Historical
 * Night begins retains the frozen v4/v5 Light aliases; Morning ends counts native Light only,
 * never treating an unclassified sleeping stage as Light.
 */
internal object SleepJournalSummary {
    const val WINDOW_RULE_ID = "noon-to-noon-sleep-window-v1"
    const val WAKE_DATE_WINDOW_RULE_ID = "wake-date-sleep-window-v1"

    data class QueryInterval(
        val start: Instant,
        val endExclusive: Instant,
    )

    /**
     * Health Connect interval reads are overlap-based, but the extra prior journal day also
     * protects against provider implementations that only return records by start time. The end
     * reaches the following noon so the final requested night's wake is available.
     */
    fun queryInterval(requestedDates: Collection<LocalDate>, zone: ZoneId): QueryInterval {
        require(requestedDates.isNotEmpty()) { "At least one sleep journal date is required" }
        val first = requestedDates.minOrNull()!!
        val last = requestedDates.maxOrNull()!!
        return QueryInterval(
            start = first.minusDays(1).atTime(JOURNAL_BOUNDARY).atZone(zone).toInstant(),
            endExclusive = last.plusDays(1).atTime(JOURNAL_BOUNDARY).atZone(zone).toInstant(),
        )
    }

    fun summarize(
        sourceSessions: List<SourceSession>,
        requestedDates: Collection<LocalDate>,
        zone: ZoneId,
        includeGranularData: Boolean,
        attribution: SleepDayAttribution = SleepDayAttribution.DEFAULT,
    ): Map<LocalDate, SleepData> = requestedDates
        .distinct()
        .sorted()
        .associateWith { date ->
            summarizeDay(sourceSessions, date, zone, includeGranularData, attribution)
        }

    private fun summarizeDay(
        sourceSessions: List<SourceSession>,
        date: LocalDate,
        zone: ZoneId,
        includeGranularData: Boolean,
        attribution: SleepDayAttribution,
    ): SleepData {
        val window = journalWindow(date, zone)
        val rawSessions = sourceSessions
            .filter { it.belongsToDay(attribution, window, date, zone) }
            .sortedWith(SOURCE_SESSION_ORDER)
        if (rawSessions.isEmpty()) return SleepData()

        val rawStages = if (includeGranularData) {
            rawSessions
                .flatMap { it.stages }
                .sortedWith(SOURCE_STAGE_ORDER)
                .map { it.entry }
        } else {
            emptyList()
        }
        val detailedSessions = rawSessions.map { it.entry }
        val slices = when (attribution) {
            SleepDayAttribution.NIGHT_BEGINS -> rawSessions.mapNotNull { it.clippedTo(window) }
            // Wake-up-date ownership keeps each session whole; no noon clipping.
            SleepDayAttribution.MORNING_ENDS -> rawSessions.mapNotNull { it.wholeSessionSlice() }
        }
        if (slices.isEmpty()) {
            return SleepData(stages = rawStages, sessions = detailedSessions)
        }

        val totalDuration = when (attribution) {
            SleepDayAttribution.NIGHT_BEGINS -> slices.sumOf { slice ->
                Duration.between(slice.start, slice.end).toMillis()
            }.milliseconds
            SleepDayAttribution.MORNING_ENDS -> slices.fold(Duration.ZERO) { total, slice ->
                total.plus(Duration.between(slice.start, slice.end))
            }.toExactSleepDuration()
        }
        // Night-begins keeps clipping stages to the journal window. Wake-up-date
        // mode clips only to the owned sessions' own span, which is a no-op guard
        // because stages already sit inside their parent session.
        val stageClipWindow = when (attribution) {
            SleepDayAttribution.NIGHT_BEGINS -> window
            SleepDayAttribution.MORNING_ENDS -> InstantInterval(
                start = slices.minOf { it.start },
                end = slices.maxOf { it.end },
            )
        }
        val stageDurations = additiveStageDurations(slices, stageClipWindow, attribution)

        return SleepData(
            totalDuration = totalDuration,
            deepSleep = stageDurations[StageBucket.DEEP] ?: kotlin.time.Duration.ZERO,
            remSleep = stageDurations[StageBucket.REM] ?: kotlin.time.Duration.ZERO,
            lightSleep = stageDurations[StageBucket.LIGHT] ?: kotlin.time.Duration.ZERO,
            awakeTime = stageDurations[StageBucket.AWAKE] ?: kotlin.time.Duration.ZERO,
            inBedTime = totalDuration,
            stages = rawStages,
            sessions = detailedSessions,
            sessionStart = LocalDateTime.ofInstant(slices.minOf { it.start }, zone),
            sessionEnd = LocalDateTime.ofInstant(slices.maxOf { it.end }, zone),
        )
    }

    /** Preserves the shipped Android behavior: overlapping stage sources remain additive. */
    private fun additiveStageDurations(
        slices: List<SessionSlice>,
        window: InstantInterval,
        attribution: SleepDayAttribution,
    ): Map<StageBucket, kotlin.time.Duration> {
        val legacyMilliseconds = mutableMapOf<StageBucket, Long>()
        val exactDurations = mutableMapOf<StageBucket, Duration>()
        for (slice in slices) {
            for (stage in slice.source.stages) {
                if (!stage.start.isBefore(stage.end)) continue
                val start = maxOf(stage.start, slice.start, window.start)
                val end = minOf(stage.end, slice.end, window.end)
                if (!start.isBefore(end)) continue
                val bucket = stageBucket(stage.entry.stage, attribution) ?: continue
                val duration = Duration.between(start, end)
                when (attribution) {
                    SleepDayAttribution.NIGHT_BEGINS -> legacyMilliseconds[bucket] =
                        legacyMilliseconds.getOrDefault(bucket, 0L) + duration.toMillis()
                    SleepDayAttribution.MORNING_ENDS -> exactDurations[bucket] =
                        exactDurations.getOrDefault(bucket, Duration.ZERO).plus(duration)
                }
            }
        }
        return when (attribution) {
            SleepDayAttribution.NIGHT_BEGINS -> legacyMilliseconds.mapValues { it.value.milliseconds }
            SleepDayAttribution.MORNING_ENDS -> exactDurations.mapValues { it.value.toExactSleepDuration() }
        }
    }

    private fun journalWindow(date: LocalDate, zone: ZoneId): InstantInterval = InstantInterval(
        start = date.atTime(JOURNAL_BOUNDARY).atZone(zone).toInstant(),
        end = date.plusDays(1).atTime(JOURNAL_BOUNDARY).atZone(zone).toInstant(),
    )

    private fun SourceSession.belongsToDay(
        attribution: SleepDayAttribution,
        window: InstantInterval,
        date: LocalDate,
        zone: ZoneId,
    ): Boolean = when (attribution) {
        SleepDayAttribution.NIGHT_BEGINS -> belongsToDetailedDay(window, date, zone)
        // Wake-up-date ownership: the calendar date of the session end decides the
        // note. Malformed zero/negative-length records also land on their end date.
        SleepDayAttribution.MORNING_ENDS -> end.atZone(zone).toLocalDate() == date
    }

    private fun SourceSession.belongsToDetailedDay(
        window: InstantInterval,
        date: LocalDate,
        zone: ZoneId,
    ): Boolean {
        if (start.isBefore(end) && start < window.end && end > window.start) return true
        // Preserve malformed source records on their start-owned journal day without allowing
        // them into the summary calculation.
        val localStart = start.atZone(zone)
        val ownerDate = if (localStart.toLocalTime() < JOURNAL_BOUNDARY) {
            localStart.toLocalDate().minusDays(1)
        } else {
            localStart.toLocalDate()
        }
        return ownerDate == date
    }

    private fun SourceSession.clippedTo(window: InstantInterval): SessionSlice? {
        if (!start.isBefore(end)) return null
        val clippedStart = maxOf(start, window.start)
        val clippedEnd = minOf(end, window.end)
        if (!clippedStart.isBefore(clippedEnd)) return null
        return SessionSlice(this, clippedStart, clippedEnd)
    }

    /** Wake-up-date attribution keeps the session whole; the session is the ownership unit. */
    private fun SourceSession.wholeSessionSlice(): SessionSlice? {
        if (!start.isBefore(end)) return null
        return SessionSlice(this, start, end)
    }

    private fun stageBucket(stageName: String, attribution: SleepDayAttribution): StageBucket? = when (stageName.lowercase()) {
        "deep" -> StageBucket.DEEP
        "rem" -> StageBucket.REM
        "light" -> StageBucket.LIGHT
        // Retain the shipped v4/v5 alias calculation, never invent Light in the successor.
        // Unclassified sleeping still contributes to its whole session's total duration.
        "core", "sleeping" -> if (attribution == SleepDayAttribution.NIGHT_BEGINS) StageBucket.LIGHT else null
        "awake", "wake" -> StageBucket.AWAKE
        else -> null
    }

    private fun Duration.toExactSleepDuration(): kotlin.time.Duration {
        val value = seconds.seconds + nano.nanoseconds
        require(value.isFinite() && value.toComponents { seconds, nanoseconds ->
            seconds == this.seconds && nanoseconds == nano
        }) { "wake-date sleep duration precision is unavailable" }
        return value
    }

    private val JOURNAL_BOUNDARY: LocalTime = LocalTime.NOON

    private val SOURCE_SESSION_ORDER = compareBy<SourceSession>(
        { it.start },
        { it.end },
        { it.stableSortKey },
    )
    private val SOURCE_STAGE_ORDER = compareBy<SourceStage>(
        { it.start },
        { it.end },
        { it.entry.stage },
        { it.entry.identity?.nativeId.orEmpty() },
        { it.entry.identity?.syntheticId.orEmpty() },
    )

    private enum class StageBucket { DEEP, REM, LIGHT, AWAKE }

    private data class InstantInterval(
        val start: Instant,
        val end: Instant,
    )

    private data class SessionSlice(
        val source: SourceSession,
        val start: Instant,
        val end: Instant,
    )
}

internal data class SourceSession(
    val start: Instant,
    val end: Instant,
    val entry: SleepSessionEntry,
    val stages: List<SourceStage> = emptyList(),
) {
    val stableSortKey: String by lazy(LazyThreadSafetyMode.NONE) {
        listOf(
            entry.identity?.nativeId.orEmpty(),
            entry.identity?.clientRecordId.orEmpty(),
            entry.identity?.clientRecordVersion?.toString().orEmpty(),
            entry.identity?.origin.orEmpty(),
            entry.identity?.syntheticId.orEmpty(),
            entry.identity?.lastModified?.let {
                "${it.epochSecond}:${it.nano}:${it.offset.orEmpty()}"
            }.orEmpty(),
            entry.exactStartTime?.let {
                "${it.epochSecond}:${it.nano}:${it.offset.orEmpty()}"
            }.orEmpty(),
            entry.exactEndTime?.let {
                "${it.epochSecond}:${it.nano}:${it.offset.orEmpty()}"
            }.orEmpty(),
            entry.source.orEmpty(),
            entry.title.orEmpty(),
            entry.notes.orEmpty(),
            entry.metadata.toSortedMap().entries.joinToString("\u001d") { (key, value) ->
                "${key.length}:$key=${value.length}:$value"
            },
        ).joinToString("\u001f")
    }
}

internal data class SourceStage(
    val start: Instant,
    val end: Instant,
    val entry: SleepStageEntry,
)
