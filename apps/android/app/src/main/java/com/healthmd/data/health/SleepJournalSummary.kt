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
 * Product rule `principal-overnight-sleep-v1`:
 * - a journal day is the half-open local interval [noon, following noon);
 * - valid sessions separated by at most [SPLIT_SLEEP_CONTINUITY_GAP] form one cluster;
 * - an overnight cluster outranks a daytime cluster, then the greatest de-duplicated session
 *   coverage wins, with stable timestamp/source tie-breakers;
 * - overlapping session and stage time is counted once. A longer source session supplies the
 *   stage label when a shorter duplicate fragment disagrees.
 *
 * Source entries are never clipped or rewritten. Clipping and validity limits apply only to the
 * compatibility headline so detailed exports retain exact source timestamps and offsets.
 */
internal object SleepJournalSummary {
    const val PRODUCT_RULE_ID = "principal-overnight-sleep-v1"

    val SPLIT_SLEEP_CONTINUITY_GAP: Duration = Duration.ofMinutes(90)
    val MAX_SUMMARY_SESSION_DURATION: Duration = Duration.ofHours(24)

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

        val slices = rawSessions.mapNotNull { source ->
            if (!source.isSummaryEligible()) return@mapNotNull null
            val start = maxOf(source.start, window.start)
            val end = minOf(source.end, window.end)
            if (!start.isBefore(end)) return@mapNotNull null
            SessionSlice(source, start, end)
        }
        val principal = principalCluster(slices, date, zone)
            ?: return SleepData(stages = rawStages, sessions = detailedSessions)

        val coverage = mergeIntervals(principal.slices.map { InstantInterval(it.start, it.end) })
        val stageDurations = resolveStageDurations(principal.slices, window)
        val totalMilliseconds = coverage.totalMilliseconds()

        return SleepData(
            totalDuration = totalMilliseconds.milliseconds,
            deepSleep = stageDurations[StageBucket.DEEP].orZero().milliseconds,
            remSleep = stageDurations[StageBucket.REM].orZero().milliseconds,
            lightSleep = stageDurations[StageBucket.LIGHT].orZero().milliseconds,
            awakeTime = stageDurations[StageBucket.AWAKE].orZero().milliseconds,
            inBedTime = totalMilliseconds.milliseconds,
            stages = rawStages,
            sessions = detailedSessions,
            sessionStart = LocalDateTime.ofInstant(coverage.first().start, zone),
            sessionEnd = LocalDateTime.ofInstant(coverage.last().end, zone),
        )
    }

    private fun principalCluster(
        slices: List<SessionSlice>,
        date: LocalDate,
        zone: ZoneId,
    ): SessionCluster? {
        if (slices.isEmpty()) return null
        val sorted = slices.sortedWith(SESSION_SLICE_ORDER)
        val clusters = mutableListOf<MutableList<SessionSlice>>()
        var current = mutableListOf(sorted.first())
        var currentEnd = sorted.first().end

        for (slice in sorted.drop(1)) {
            val gap = Duration.between(currentEnd, slice.start)
            if (gap.isNegative || gap.isZero || gap <= SPLIT_SLEEP_CONTINUITY_GAP) {
                current += slice
                if (slice.end > currentEnd) currentEnd = slice.end
            } else {
                clusters += current
                current = mutableListOf(slice)
                currentEnd = slice.end
            }
        }
        clusters += current

        val midnight = date.plusDays(1).atStartOfDay(zone).toInstant()
        return clusters
            .map { SessionCluster(it) }
            .sortedWith(
                compareByDescending<SessionCluster> { cluster -> cluster.spans(midnight) }
                    .thenByDescending { cluster -> cluster.coverageMilliseconds }
                    .thenBy { cluster -> cluster.start }
                    .thenByDescending { cluster -> cluster.end }
                    .thenBy { cluster -> cluster.stableKey },
            )
            .first()
    }

    /**
     * Resolves an atomic timeline so duplicate or conflicting stage fragments cannot add time.
     * The longest parent session is authoritative; exact ties use stable source identity and then
     * an explicit stage order that prefers awake/specific stages over generic sleeping.
     */
    private fun resolveStageDurations(
        slices: List<SessionSlice>,
        window: InstantInterval,
    ): Map<StageBucket, Long> {
        val candidates = slices.flatMap { slice ->
            slice.source.stages.mapNotNull { stage ->
                if (!stage.start.isBefore(stage.end)) return@mapNotNull null
                val start = maxOf(stage.start, slice.start, window.start)
                val end = minOf(stage.end, slice.end, window.end)
                if (!start.isBefore(end)) return@mapNotNull null
                val bucket = stageBucket(stage.entry.stage) ?: return@mapNotNull null
                StageCandidate(
                    start = start,
                    end = end,
                    bucket = bucket,
                    parentDurationMilliseconds = Duration.between(slice.start, slice.end).toMillis(),
                    parentStart = slice.start,
                    parentEnd = slice.end,
                    sourceKey = slice.source.stableKey(),
                    stageName = stage.entry.stage.lowercase(),
                )
            }
        }
        if (candidates.isEmpty()) return emptyMap()

        val boundaries = candidates.flatMap { listOf(it.start, it.end) }.distinct().sorted()
        val totals = mutableMapOf<StageBucket, Long>()
        for (index in 0 until boundaries.lastIndex) {
            val start = boundaries[index]
            val end = boundaries[index + 1]
            if (!start.isBefore(end)) continue
            val winner = candidates
                .asSequence()
                .filter { it.start < end && it.end > start }
                .minWithOrNull(STAGE_CANDIDATE_ORDER)
                ?: continue
            totals[winner.bucket] = totals.getOrDefault(winner.bucket, 0L) +
                Duration.between(start, end).toMillis()
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

    private fun SourceSession.isSummaryEligible(): Boolean {
        if (!start.isBefore(end)) return false
        return Duration.between(start, end) <= MAX_SUMMARY_SESSION_DURATION
    }

    private fun mergeIntervals(intervals: List<InstantInterval>): List<InstantInterval> {
        if (intervals.isEmpty()) return emptyList()
        val sorted = intervals.sortedWith(compareBy<InstantInterval>({ it.start }, { it.end }))
        val merged = mutableListOf<InstantInterval>()
        var current = sorted.first()
        for (next in sorted.drop(1)) {
            if (next.start <= current.end) {
                if (next.end > current.end) current = current.copy(end = next.end)
            } else {
                merged += current
                current = next
            }
        }
        merged += current
        return merged
    }

    private fun List<InstantInterval>.totalMilliseconds(): Long = sumOf { interval ->
        Duration.between(interval.start, interval.end).toMillis()
    }

    private fun stageBucket(stageName: String): StageBucket? = when (stageName.lowercase()) {
        "deep" -> StageBucket.DEEP
        "rem" -> StageBucket.REM
        "light", "core", "sleeping" -> StageBucket.LIGHT
        "awake", "wake" -> StageBucket.AWAKE
        else -> null
    }

    private fun stagePriority(stageName: String): Int = when (stageName) {
        "awake", "wake" -> 0
        "deep" -> 1
        "rem" -> 2
        "light", "core" -> 3
        "sleeping" -> 4
        else -> 5
    }

    private fun SourceSession.stableKey(): String = listOf(
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

    private fun Long?.orZero(): Long = this ?: 0L

    private val JOURNAL_BOUNDARY: LocalTime = LocalTime.NOON

    private val SOURCE_SESSION_ORDER = compareBy<SourceSession>(
        { it.start },
        { it.end },
        { it.stableKey() },
    )
    private val SOURCE_STAGE_ORDER = compareBy<SourceStage>(
        { it.start },
        { it.end },
        { it.entry.stage },
        { it.entry.identity?.nativeId.orEmpty() },
        { it.entry.identity?.syntheticId.orEmpty() },
    )
    private val SESSION_SLICE_ORDER = compareBy<SessionSlice>(
        { it.start },
        { it.end },
        { it.source.stableKey() },
    )
    private val STAGE_CANDIDATE_ORDER =
        compareByDescending<StageCandidate> { it.parentDurationMilliseconds }
            .thenBy { it.parentStart }
            .thenByDescending { it.parentEnd }
            .thenBy { it.sourceKey }
            .thenBy { stagePriority(it.stageName) }
            .thenBy { it.stageName }

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

    private data class SessionCluster(
        val slices: List<SessionSlice>,
    ) {
        val coverage: List<InstantInterval> = mergeIntervals(slices.map { InstantInterval(it.start, it.end) })
        val coverageMilliseconds: Long = coverage.totalMilliseconds()
        val start: Instant = coverage.first().start
        val end: Instant = coverage.last().end
        val stableKey: String = slices.map { it.source.stableKey() }.sorted().joinToString("\u001e")

        fun spans(instant: Instant): Boolean = start < instant && end > instant
    }

    private data class StageCandidate(
        val start: Instant,
        val end: Instant,
        val bucket: StageBucket,
        val parentDurationMilliseconds: Long,
        val parentStart: Instant,
        val parentEnd: Instant,
        val sourceKey: String,
        val stageName: String,
    )
}

internal data class SourceSession(
    val start: Instant,
    val end: Instant,
    val entry: SleepSessionEntry,
    val stages: List<SourceStage> = emptyList(),
)

internal data class SourceStage(
    val start: Instant,
    val end: Instant,
    val entry: SleepStageEntry,
)
