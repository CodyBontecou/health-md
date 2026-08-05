package com.healthmd.data.health

import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.SleepStageEntry
import java.time.Duration
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import kotlin.time.Duration.Companion.milliseconds

/**
 * Pure compatibility projection for Health Connect sleep sessions.
 *
 * The exported journal date owns the half-open local interval from noon on that date to noon on
 * the following date. Summary intervals are clipped to that window, while detailed source entries
 * retain their original timestamps and offsets.
 *
 * Frozen Android v4/v5 aggregation remains additive: every valid source session and stage that
 * overlaps the journal window contributes independently. This object deliberately does not choose
 * a principal cluster or de-duplicate provider records because doing so would change the meaning
 * of shipped summary fields and require a new public schema profile.
 */
internal object SleepJournalSummary {
    const val WINDOW_RULE_ID = "noon-to-noon-sleep-window-v1"

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
    ): Map<LocalDate, SleepData> = requestedDates
        .distinct()
        .sorted()
        .associateWith { date ->
            summarizeDay(sourceSessions, date, zone, includeGranularData)
        }

    private fun summarizeDay(
        sourceSessions: List<SourceSession>,
        date: LocalDate,
        zone: ZoneId,
        includeGranularData: Boolean,
    ): SleepData {
        val window = journalWindow(date, zone)
        val rawSessions = sourceSessions
            .filter { it.belongsToDetailedDay(window, date, zone) }
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
        val slices = rawSessions.mapNotNull { source -> source.clippedTo(window) }
        if (slices.isEmpty()) {
            return SleepData(stages = rawStages, sessions = detailedSessions)
        }

        val totalMilliseconds = slices.sumOf { slice ->
            Duration.between(slice.start, slice.end).toMillis()
        }
        val stageDurations = additiveStageDurations(slices, window)

        return SleepData(
            totalDuration = totalMilliseconds.milliseconds,
            deepSleep = stageDurations[StageBucket.DEEP].orZero().milliseconds,
            remSleep = stageDurations[StageBucket.REM].orZero().milliseconds,
            lightSleep = stageDurations[StageBucket.LIGHT].orZero().milliseconds,
            awakeTime = stageDurations[StageBucket.AWAKE].orZero().milliseconds,
            inBedTime = totalMilliseconds.milliseconds,
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
    ): Map<StageBucket, Long> {
        val totals = mutableMapOf<StageBucket, Long>()
        for (slice in slices) {
            for (stage in slice.source.stages) {
                if (!stage.start.isBefore(stage.end)) continue
                val start = maxOf(stage.start, slice.start, window.start)
                val end = minOf(stage.end, slice.end, window.end)
                if (!start.isBefore(end)) continue
                val bucket = stageBucket(stage.entry.stage) ?: continue
                totals[bucket] = totals.getOrDefault(bucket, 0L) +
                    Duration.between(start, end).toMillis()
            }
        }
        return totals
    }

    private fun journalWindow(date: LocalDate, zone: ZoneId): InstantInterval = InstantInterval(
        start = date.atTime(JOURNAL_BOUNDARY).atZone(zone).toInstant(),
        end = date.plusDays(1).atTime(JOURNAL_BOUNDARY).atZone(zone).toInstant(),
    )

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

    private fun stageBucket(stageName: String): StageBucket? = when (stageName.lowercase()) {
        "deep" -> StageBucket.DEEP
        "rem" -> StageBucket.REM
        "light", "core", "sleeping" -> StageBucket.LIGHT
        "awake", "wake" -> StageBucket.AWAKE
        else -> null
    }

    private fun Long?.orZero(): Long = this ?: 0L

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
