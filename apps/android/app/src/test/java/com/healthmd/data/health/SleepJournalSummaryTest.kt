package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.SleepStageEntry
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZoneOffset
import org.junit.Test

class SleepJournalSummaryTest {
    private val utc = ZoneId.of("UTC")
    private val journalDay = LocalDate.of(2026, 1, 10)

    @Test
    fun `issue 96 full overnight boundaries survive a nested fragment`() {
        val main = session(
            id = "main",
            start = local(journalDay, 22, 0),
            end = local(journalDay.plusDays(1), 5, 30),
            stages = listOf(
                stage(local(journalDay, 22, 0), local(journalDay.plusDays(1), 1, 0), "deep"),
                stage(local(journalDay.plusDays(1), 1, 0), local(journalDay.plusDays(1), 3, 0), "rem"),
                stage(local(journalDay.plusDays(1), 3, 0), local(journalDay.plusDays(1), 5, 30), "light"),
            ),
        )
        val fragment = session(
            id = "fragment",
            start = local(journalDay, 23, 8),
            end = local(journalDay, 23, 48),
            stages = listOf(stage(local(journalDay, 23, 8), local(journalDay, 23, 48), "deep")),
        )

        val sleep = summarize(journalDay, listOf(fragment, main))

        assertThat(sleep.sessionStart).isEqualTo(local(journalDay, 22, 0))
        assertThat(sleep.sessionEnd).isEqualTo(local(journalDay.plusDays(1), 5, 30))
        assertThat(sleep.sessions.map { it.identity?.nativeId }).containsExactly("main", "fragment")
        assertThat(sleep.stages).hasSize(4)
    }

    @Test
    fun `nested sessions retain frozen additive summary aggregation`() {
        val parent = session(
            id = "parent",
            start = local(journalDay, 22, 0),
            end = local(journalDay.plusDays(1), 5, 30),
            stages = listOf(
                stage(local(journalDay, 22, 0), local(journalDay.plusDays(1), 1, 0), "deep"),
            ),
        )
        val fragment = session(
            id = "fragment",
            start = local(journalDay, 23, 8),
            end = local(journalDay, 23, 48),
            stages = listOf(stage(local(journalDay, 23, 8), local(journalDay, 23, 48), "deep")),
        )

        val sleep = summarize(journalDay, listOf(parent, fragment))

        assertThat(sleep.totalDuration.inWholeMinutes).isEqualTo(490)
        assertThat(sleep.inBedTime.inWholeMinutes).isEqualTo(490)
        assertThat(sleep.deepSleep.inWholeMinutes).isEqualTo(220)
    }

    @Test
    fun `sleep query looks back one journal day and reaches following noon`() {
        val interval = SleepJournalSummary.queryInterval(listOf(journalDay), utc)

        assertThat(SleepJournalSummary.WINDOW_RULE_ID)
            .isEqualTo("noon-to-noon-sleep-window-v1")
        assertThat(interval.start).isEqualTo(
            journalDay.minusDays(1).atTime(LocalTime.NOON).atZone(utc).toInstant(),
        )
        assertThat(interval.endExclusive).isEqualTo(
            journalDay.plusDays(1).atTime(LocalTime.NOON).atZone(utc).toInstant(),
        )
    }

    @Test
    fun `disconnected sessions retain additive summary and full boundaries`() {
        val nap = session(
            id = "nap",
            start = local(journalDay, 14, 0),
            end = local(journalDay, 15, 30),
            stages = listOf(stage(local(journalDay, 14, 0), local(journalDay, 15, 30), "deep")),
        )
        val overnight = session(
            id = "overnight",
            start = local(journalDay, 22, 0),
            end = local(journalDay.plusDays(1), 5, 30),
            stages = listOf(
                stage(local(journalDay, 22, 0), local(journalDay.plusDays(1), 5, 30), "light"),
            ),
        )

        val sleep = summarize(journalDay, listOf(nap, overnight))

        assertThat(sleep.sessionStart).isEqualTo(local(journalDay, 14, 0))
        assertThat(sleep.sessionEnd).isEqualTo(local(journalDay.plusDays(1), 5, 30))
        assertThat(sleep.totalDuration.inWholeMinutes).isEqualTo(540)
        assertThat(sleep.deepSleep.inWholeMinutes).isEqualTo(90)
        assertThat(sleep.lightSleep.inWholeMinutes).isEqualTo(450)
    }

    @Test
    fun `split sessions do not add the gap to total duration`() {
        val first = session(
            id = "split-1",
            start = local(journalDay, 22, 0),
            end = local(journalDay.plusDays(1), 1, 0),
        )
        val second = session(
            id = "split-2",
            start = local(journalDay.plusDays(1), 1, 45),
            end = local(journalDay.plusDays(1), 5, 0),
        )

        val sleep = summarize(journalDay, listOf(second, first))

        assertThat(sleep.sessionStart).isEqualTo(local(journalDay, 22, 0))
        assertThat(sleep.sessionEnd).isEqualTo(local(journalDay.plusDays(1), 5, 0))
        assertThat(sleep.totalDuration.inWholeMinutes).isEqualTo(375)
    }

    @Test
    fun `overlapping sessions remain additive and detail ordering is deterministic`() {
        val first = session(
            id = "source-a",
            start = local(journalDay, 22, 0),
            end = local(journalDay.plusDays(1), 2, 0),
            stages = listOf(stage(local(journalDay, 22, 0), local(journalDay.plusDays(1), 2, 0), "light")),
        )
        val second = session(
            id = "source-b",
            start = local(journalDay.plusDays(1), 1, 0),
            end = local(journalDay.plusDays(1), 5, 0),
            stages = listOf(stage(local(journalDay.plusDays(1), 1, 0), local(journalDay.plusDays(1), 5, 0), "rem")),
        )
        val duplicateFragment = session(
            id = "duplicate",
            start = local(journalDay, 23, 0),
            end = local(journalDay.plusDays(1), 3, 0),
            stages = listOf(stage(local(journalDay, 23, 0), local(journalDay.plusDays(1), 3, 0), "deep")),
        )

        val forward = summarize(journalDay, listOf(first, second, duplicateFragment))
        val reversed = summarize(journalDay, listOf(duplicateFragment, second, first))

        assertThat(forward).isEqualTo(reversed)
        assertThat(forward.totalDuration.inWholeHours).isEqualTo(12)
        assertThat(forward.deepSleep.inWholeHours).isEqualTo(4)
        assertThat(forward.remSleep.inWholeHours).isEqualTo(4)
        assertThat(forward.lightSleep.inWholeHours).isEqualTo(4)
        assertThat(forward.sessions).hasSize(3)
    }

    @Test
    fun `empty journal day produces empty sleep data`() {
        val sleep = summarize(journalDay, emptyList())

        assertThat(sleep.hasData).isFalse()
        assertThat(sleep.sessionStart).isNull()
        assertThat(sleep.sessions).isEmpty()
    }

    @Test
    fun `stage-less session still produces a valid headline`() {
        val sleep = summarize(
            journalDay,
            listOf(
                session(
                    id = "stage-less",
                    start = local(journalDay, 21, 30),
                    end = local(journalDay.plusDays(1), 4, 30),
                ),
            ),
        )

        assertThat(sleep.totalDuration.inWholeHours).isEqualTo(7)
        assertThat(sleep.deepSleep.inWholeMilliseconds).isEqualTo(0)
        assertThat(sleep.stages).isEmpty()
    }

    @Test
    fun `noon boundary is half open on adjacent journal days`() {
        val previousDay = journalDay.minusDays(1)
        val endingAtNoon = session(
            id = "ending-at-noon",
            start = local(journalDay, 10, 0),
            end = local(journalDay, 12, 0),
        )
        val startingAtNoon = session(
            id = "starting-at-noon",
            start = local(journalDay, 12, 0),
            end = local(journalDay, 13, 0),
        )

        val result = SleepJournalSummary.summarize(
            sourceSessions = listOf(startingAtNoon, endingAtNoon),
            requestedDates = listOf(previousDay, journalDay),
            zone = utc,
            includeGranularData = true,
        )

        assertThat(result.getValue(previousDay).sessions.map { it.identity?.nativeId })
            .containsExactly("ending-at-noon")
        assertThat(result.getValue(journalDay).sessions.map { it.identity?.nativeId })
            .containsExactly("starting-at-noon")
        assertThat(result.getValue(previousDay).sessionEnd).isEqualTo(local(journalDay, 12, 0))
        assertThat(result.getValue(journalDay).sessionStart).isEqualTo(local(journalDay, 12, 0))
    }

    @Test
    fun `summary intervals are clipped at opening noon without rewriting detail`() {
        val acrossNoon = session(
            id = "across-noon",
            start = local(journalDay, 10, 0),
            end = local(journalDay, 13, 0),
            stages = listOf(stage(local(journalDay, 10, 0), local(journalDay, 13, 0), "deep")),
        )
        val afterNoon = session(
            id = "after-noon",
            start = local(journalDay, 12, 0),
            end = local(journalDay, 13, 30),
            stages = listOf(stage(local(journalDay, 12, 0), local(journalDay, 13, 30), "rem")),
        )

        val sleep = summarize(journalDay, listOf(afterNoon, acrossNoon))

        assertThat(sleep.totalDuration.inWholeMinutes).isEqualTo(150)
        assertThat(sleep.deepSleep.inWholeMinutes).isEqualTo(60)
        assertThat(sleep.remSleep.inWholeMinutes).isEqualTo(90)
        assertThat(sleep.sessions.first { it.identity?.nativeId == "across-noon" }.startTime)
            .isEqualTo(local(journalDay, 10, 0))
    }

    @Test
    fun `spring DST uses elapsed duration while retaining local bedtime and wake`() {
        val zone = ZoneId.of("America/Los_Angeles")
        val day = LocalDate.of(2026, 3, 7)
        val sleep = summarize(
            date = day,
            sessions = listOf(
                session(
                    id = "spring",
                    start = local(day, 22, 0),
                    end = local(day.plusDays(1), 6, 0),
                    exportZone = zone,
                ),
            ),
            zone = zone,
        )

        assertThat(sleep.totalDuration.inWholeHours).isEqualTo(7)
        assertThat(sleep.sessionStart).isEqualTo(local(day, 22, 0))
        assertThat(sleep.sessionEnd).isEqualTo(local(day.plusDays(1), 6, 0))
    }

    @Test
    fun `fall DST uses elapsed duration while retaining local bedtime and wake`() {
        val zone = ZoneId.of("America/Los_Angeles")
        val day = LocalDate.of(2026, 10, 31)
        val sleep = summarize(
            date = day,
            sessions = listOf(
                session(
                    id = "fall",
                    start = local(day, 22, 0),
                    end = local(day.plusDays(1), 6, 0),
                    exportZone = zone,
                ),
            ),
            zone = zone,
        )

        assertThat(sleep.totalDuration.inWholeHours).isEqualTo(9)
        assertThat(sleep.sessionStart).isEqualTo(local(day, 22, 0))
        assertThat(sleep.sessionEnd).isEqualTo(local(day.plusDays(1), 6, 0))
    }

    @Test
    fun `source offsets differing from export zone remain exact in granular sessions`() {
        val exportZone = ZoneId.of("America/Los_Angeles")
        val sourceOffset = ZoneOffset.ofHours(9)
        val source = session(
            id = "travel",
            start = local(journalDay, 22, 0),
            end = local(journalDay.plusDays(1), 5, 0),
            exportZone = exportZone,
            exactOffset = sourceOffset,
        )

        val sleep = summarize(journalDay, listOf(source), exportZone)
        val detailed = sleep.sessions.single()

        assertThat(sleep.sessionStart).isEqualTo(local(journalDay, 22, 0))
        assertThat(detailed.exactStartTime?.offset).isEqualTo("+09:00")
        assertThat(detailed.exactEndTime?.offset).isEqualTo("+09:00")
        assertThat(detailed.exactStartTime?.instant()).isEqualTo(source.start)
        assertThat(detailed.startTime).isEqualTo(LocalDateTime.ofInstant(source.start, exportZone))
    }

    @Test
    fun `negative session and invalid stage remain detailed but cannot corrupt summary`() {
        val valid = session(
            id = "valid",
            start = local(journalDay, 22, 0),
            end = local(journalDay.plusDays(1), 5, 0),
            stages = listOf(
                stage(local(journalDay, 22, 0), local(journalDay, 23, 0), "deep"),
                stage(local(journalDay, 23, 30), local(journalDay, 23, 0), "rem"),
            ),
        )
        val negative = session(
            id = "negative",
            start = local(journalDay.plusDays(1), 1, 0),
            end = local(journalDay, 23, 0),
        )

        val sleep = summarize(journalDay, listOf(negative, valid))

        assertThat(sleep.totalDuration.inWholeHours).isEqualTo(7)
        assertThat(sleep.deepSleep.inWholeHours).isEqualTo(1)
        assertThat(sleep.remSleep.inWholeMilliseconds).isEqualTo(0)
        assertThat(sleep.sessions.map { it.identity?.nativeId }).containsExactly("negative", "valid")
        assertThat(sleep.stages).hasSize(2)
    }

    @Test
    fun `rejected detailed session has no explicit session boundaries`() {
        val invalid = session(
            id = "negative",
            start = local(journalDay.plusDays(1), 1, 0),
            end = local(journalDay, 23, 0),
            stages = listOf(stage(local(journalDay, 22, 0), local(journalDay, 23, 0), "deep")),
        )

        val sleep = summarize(journalDay, listOf(invalid))

        assertThat(sleep.sessions).hasSize(1)
        assertThat(sleep.stages).hasSize(1)
        assertThat(sleep.sessionStart).isNull()
        assertThat(sleep.sessionEnd).isNull()
    }

    @Test
    fun `single-day and range projections return identical sleep summary`() {
        val sessions = listOf(
            session(
                id = "overnight",
                start = local(journalDay, 22, 0),
                end = local(journalDay.plusDays(1), 5, 30),
                stages = listOf(
                    stage(local(journalDay, 22, 0), local(journalDay.plusDays(1), 5, 30), "sleeping"),
                ),
            ),
            session(
                id = "next-night",
                start = local(journalDay.plusDays(1), 22, 30),
                end = local(journalDay.plusDays(2), 6, 0),
            ),
        )

        val single = SleepJournalSummary.summarize(sessions, listOf(journalDay), utc, true)
            .getValue(journalDay)
        val range = SleepJournalSummary.summarize(
            sessions,
            listOf(journalDay, journalDay.plusDays(1)),
            utc,
            false,
        ).getValue(journalDay)

        assertThat(single.copy(stages = emptyList())).isEqualTo(range)
        assertThat(single.stages).hasSize(1)
        assertThat(range.stages).isEmpty()
    }

    // MARK: Wake-up-date attribution (issue #104)

    @Test
    fun `wake date rule id is versioned alongside the shipped noon window`() {
        assertThat(SleepJournalSummary.WAKE_DATE_WINDOW_RULE_ID)
            .isEqualTo("wake-date-sleep-window-v1")
    }

    @Test
    fun `night begins default keeps late night session on its start day`() {
        val lateNight = session(
            id = "late-night",
            start = local(journalDay, 23, 45),
            end = local(journalDay.plusDays(1), 7, 30),
            stages = listOf(stage(local(journalDay, 23, 45), local(journalDay.plusDays(1), 7, 30), "light")),
        )

        val startDay = summarize(journalDay, listOf(lateNight))
        val wakeDay = summarize(journalDay.plusDays(1), listOf(lateNight))

        assertThat(startDay.totalDuration.inWholeMinutes).isEqualTo(465)
        assertThat(startDay.sessionStart).isEqualTo(local(journalDay, 23, 45))
        assertThat(startDay.sessionEnd).isEqualTo(local(journalDay.plusDays(1), 7, 30))
        assertThat(wakeDay.hasData).isFalse()
    }

    @Test
    fun `morning ends attributes late night session to its wake day whole`() {
        val lateNight = session(
            id = "late-night",
            start = local(journalDay, 23, 45),
            end = local(journalDay.plusDays(1), 7, 30),
            stages = listOf(stage(local(journalDay, 23, 45), local(journalDay.plusDays(1), 7, 30), "light")),
        )

        val startDay = summarize(journalDay, listOf(lateNight), attribution = SleepDayAttribution.MORNING_ENDS)
        val wakeDay = summarize(journalDay.plusDays(1), listOf(lateNight), attribution = SleepDayAttribution.MORNING_ENDS)

        assertThat(startDay.hasData).isFalse()
        // The whole session stays together: never clipped at midnight or a noon boundary.
        assertThat(wakeDay.totalDuration.inWholeMinutes).isEqualTo(465)
        assertThat(wakeDay.inBedTime.inWholeMinutes).isEqualTo(465)
        assertThat(wakeDay.lightSleep.inWholeMinutes).isEqualTo(465)
        assertThat(wakeDay.sessionStart).isEqualTo(local(journalDay, 23, 45))
        assertThat(wakeDay.sessionEnd).isEqualTo(local(journalDay.plusDays(1), 7, 30))
        assertThat(wakeDay.sessions.map { it.identity?.nativeId }).containsExactly("late-night")
        assertThat(wakeDay.stages).hasSize(1)
    }

    @Test
    fun `morning ends keeps an afternoon nap on the day it ends`() {
        val nap = session(
            id = "nap",
            start = local(journalDay, 14, 0),
            end = local(journalDay, 15, 30),
            stages = listOf(stage(local(journalDay, 14, 0), local(journalDay, 15, 30), "deep")),
        )

        val sameDay = summarize(journalDay, listOf(nap), attribution = SleepDayAttribution.MORNING_ENDS)
        val nextDay = summarize(journalDay.plusDays(1), listOf(nap), attribution = SleepDayAttribution.MORNING_ENDS)

        assertThat(sameDay.totalDuration.inWholeMinutes).isEqualTo(90)
        assertThat(sameDay.sessionStart).isEqualTo(local(journalDay, 14, 0))
        assertThat(sameDay.sessionEnd).isEqualTo(local(journalDay, 15, 30))
        assertThat(nextDay.hasData).isFalse()
    }

    @Test
    fun `morning ends keeps a single-day evening nap on its start day`() {
        val eveningNap = session(
            id = "evening-nap",
            start = local(journalDay, 20, 0),
            end = local(journalDay, 22, 0),
        )

        val sameDay = summarize(journalDay, listOf(eveningNap), attribution = SleepDayAttribution.MORNING_ENDS)
        val nextDay = summarize(journalDay.plusDays(1), listOf(eveningNap), attribution = SleepDayAttribution.MORNING_ENDS)

        assertThat(sameDay.totalDuration.inWholeHours).isEqualTo(2)
        assertThat(nextDay.hasData).isFalse()
    }

    @Test
    fun `morning ends separates two nights by wake day without duplication`() {
        val nap = session(
            id = "nap",
            start = local(journalDay, 14, 0),
            end = local(journalDay, 15, 0),
        )
        val firstNight = session(
            id = "night-one",
            start = local(journalDay, 23, 0),
            end = local(journalDay.plusDays(1), 6, 0),
        )
        val secondNight = session(
            id = "night-two",
            start = local(journalDay.plusDays(1), 23, 30),
            end = local(journalDay.plusDays(2), 7, 0),
        )
        val sessions = listOf(nap, firstNight, secondNight)

        val result = SleepJournalSummary.summarize(
            sourceSessions = sessions,
            requestedDates = listOf(journalDay, journalDay.plusDays(1), journalDay.plusDays(2)),
            zone = utc,
            includeGranularData = false,
            attribution = SleepDayAttribution.MORNING_ENDS,
        )

        assertThat(result.getValue(journalDay).sessions.map { it.identity?.nativeId })
            .containsExactly("nap")
        assertThat(result.getValue(journalDay).totalDuration.inWholeMinutes).isEqualTo(60)
        assertThat(result.getValue(journalDay.plusDays(1)).sessions.map { it.identity?.nativeId })
            .containsExactly("night-one")
        assertThat(result.getValue(journalDay.plusDays(1)).totalDuration.inWholeHours).isEqualTo(7)
        assertThat(result.getValue(journalDay.plusDays(2)).sessions.map { it.identity?.nativeId })
            .containsExactly("night-two")
        assertThat(result.getValue(journalDay.plusDays(2)).totalDuration.inWholeMinutes).isEqualTo(450)
    }

    @Test
    fun `morning ends retains additive overlapping aggregation`() {
        val first = session(
            id = "source-a",
            start = local(journalDay, 23, 0),
            end = local(journalDay.plusDays(1), 3, 0),
            stages = listOf(stage(local(journalDay, 23, 0), local(journalDay.plusDays(1), 3, 0), "deep")),
        )
        val second = session(
            id = "source-b",
            start = local(journalDay.plusDays(1), 1, 0),
            end = local(journalDay.plusDays(1), 5, 0),
            stages = listOf(stage(local(journalDay.plusDays(1), 1, 0), local(journalDay.plusDays(1), 5, 0), "rem")),
        )

        val wakeDay = summarize(
            journalDay.plusDays(1),
            listOf(first, second),
            attribution = SleepDayAttribution.MORNING_ENDS,
        )

        assertThat(wakeDay.totalDuration.inWholeHours).isEqualTo(8)
        assertThat(wakeDay.deepSleep.inWholeHours).isEqualTo(4)
        assertThat(wakeDay.remSleep.inWholeHours).isEqualTo(4)
        assertThat(wakeDay.sessions).hasSize(2)
    }

    @Test
    fun `morning ends lands a before-noon malformed session on its end date`() {
        val malformed = session(
            id = "zero-length",
            start = local(journalDay, 9, 30),
            end = local(journalDay, 9, 30),
        )

        val nightBegins = summarize(journalDay, listOf(malformed))
        val morningEnds = summarize(journalDay, listOf(malformed), attribution = SleepDayAttribution.MORNING_ENDS)

        // Night-begins keeps the shipped malformed fallback: a 9:30 AM zero-length
        // record stays on the PREVIOUS journal day (start before noon).
        assertThat(nightBegins.sessions).isEmpty()
        assertThat(summarize(journalDay.minusDays(1), listOf(malformed)).sessions.map { it.identity?.nativeId })
            .containsExactly("zero-length")
        // Wake-date ownership uses the end date directly: same calendar day.
        assertThat(morningEnds.sessions.map { it.identity?.nativeId }).containsExactly("zero-length")
        assertThat(morningEnds.sessionStart).isNull()
    }

    private fun summarize(
        date: LocalDate,
        sessions: List<SourceSession>,
        zone: ZoneId = utc,
        attribution: SleepDayAttribution = SleepDayAttribution.DEFAULT,
    ) = SleepJournalSummary.summarize(
        sourceSessions = sessions,
        requestedDates = listOf(date),
        zone = zone,
        includeGranularData = true,
        attribution = attribution,
    ).getValue(date)

    private fun session(
        id: String,
        start: LocalDateTime,
        end: LocalDateTime,
        stages: List<StageSpec> = emptyList(),
        exportZone: ZoneId = utc,
        exactOffset: ZoneOffset? = null,
    ): SourceSession {
        val startInstant = start.atZone(exportZone).toInstant()
        val endInstant = end.atZone(exportZone).toInstant()
        val offset = exactOffset ?: start.atZone(exportZone).offset
        val entry = SleepSessionEntry(
            startTime = LocalDateTime.ofInstant(startInstant, exportZone),
            endTime = LocalDateTime.ofInstant(endInstant, exportZone),
            source = "test.source.$id",
            exactStartTime = ExactSourceTimestamp.from(startInstant, offset),
            exactEndTime = ExactSourceTimestamp.from(endInstant, exactOffset ?: end.atZone(exportZone).offset),
            identity = ExactSourceIdentity(nativeId = id),
        )
        return SourceSession(
            start = startInstant,
            end = endInstant,
            entry = entry,
            stages = stages.mapIndexed { index, stage ->
                val stageStart = stage.start.atZone(exportZone).toInstant()
                val stageEnd = stage.end.atZone(exportZone).toInstant()
                SourceStage(
                    start = stageStart,
                    end = stageEnd,
                    entry = SleepStageEntry(
                        startTime = LocalDateTime.ofInstant(stageStart, exportZone),
                        endTime = LocalDateTime.ofInstant(stageEnd, exportZone),
                        stage = stage.name,
                        exactStartTime = ExactSourceTimestamp.from(stageStart),
                        exactEndTime = ExactSourceTimestamp.from(stageEnd),
                        identity = ExactSourceIdentity(nativeId = "$id-stage-$index"),
                    ),
                )
            },
        )
    }

    private fun stage(start: LocalDateTime, end: LocalDateTime, name: String) =
        StageSpec(start, end, name)

    private fun local(date: LocalDate, hour: Int, minute: Int): LocalDateTime =
        date.atTime(hour, minute)

    private data class StageSpec(
        val start: LocalDateTime,
        val end: LocalDateTime,
        val name: String,
    )
}
