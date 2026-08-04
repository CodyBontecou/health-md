package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
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
    fun `issue 96 fragment cannot replace or inflate principal overnight session`() {
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
        assertThat(sleep.totalDuration.inWholeMinutes).isEqualTo(450)
        assertThat(sleep.inBedTime.inWholeMinutes).isEqualTo(450)
        assertThat(sleep.deepSleep.inWholeMinutes).isEqualTo(180)
        assertThat(sleep.remSleep.inWholeMinutes).isEqualTo(120)
        assertThat(sleep.lightSleep.inWholeMinutes).isEqualTo(150)
        assertThat(sleep.sessions.map { it.identity?.nativeId }).containsExactly("main", "fragment")
        assertThat(sleep.stages).hasSize(4)
    }

    @Test
    fun `tiny midnight crossing cannot beat disconnected seven hour sleep`() {
        val midnightFragment = session(
            id = "midnight-fragment",
            start = local(journalDay, 23, 50),
            end = local(journalDay.plusDays(1), 0, 10),
        )
        val sevenHourSleep = session(
            id = "seven-hour-sleep",
            start = local(journalDay.plusDays(1), 2, 0),
            end = local(journalDay.plusDays(1), 9, 0),
        )

        val sleep = summarize(journalDay, listOf(midnightFragment, sevenHourSleep))

        assertThat(sleep.sessionStart).isEqualTo(local(journalDay.plusDays(1), 2, 0))
        assertThat(sleep.sessionEnd).isEqualTo(local(journalDay.plusDays(1), 9, 0))
        assertThat(sleep.totalDuration.inWholeMinutes).isEqualTo(420)
        assertThat(sleep.sessions.map { it.identity?.nativeId })
            .containsExactly("midnight-fragment", "seven-hour-sleep")
    }

    @Test
    fun `sleep query looks back one journal day and reaches following noon`() {
        val interval = SleepJournalSummary.queryInterval(listOf(journalDay), utc)

        assertThat(interval.start).isEqualTo(
            journalDay.minusDays(1).atTime(LocalTime.NOON).atZone(utc).toInstant(),
        )
        assertThat(interval.endExclusive).isEqualTo(
            journalDay.plusDays(1).atTime(LocalTime.NOON).atZone(utc).toInstant(),
        )

        val overnight = session(
            id = "first-day-overnight",
            start = local(journalDay, 22, 0),
            end = local(journalDay.plusDays(1), 5, 30),
        )
        val sleep = summarize(journalDay, listOf(overnight))
        assertThat(sleep.totalDuration.inWholeMinutes).isEqualTo(450)
    }

    @Test
    fun `disconnected daytime nap does not pull headline bedtime earlier`() {
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

        assertThat(sleep.sessionStart).isEqualTo(local(journalDay, 22, 0))
        assertThat(sleep.sessionEnd).isEqualTo(local(journalDay.plusDays(1), 5, 30))
        assertThat(sleep.totalDuration.inWholeMinutes).isEqualTo(450)
        assertThat(sleep.deepSleep.inWholeMinutes).isEqualTo(0)
        assertThat(sleep.lightSleep.inWholeMinutes).isEqualTo(450)
        assertThat(sleep.sessions).hasSize(2)
        assertThat(sleep.stages).hasSize(2)
    }

    @Test
    fun `named continuity rule joins split sleep without counting its gap`() {
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

        assertThat(SleepJournalSummary.PRODUCT_RULE_ID).isEqualTo("principal-overnight-sleep-v1")
        assertThat(sleep.sessionStart).isEqualTo(local(journalDay, 22, 0))
        assertThat(sleep.sessionEnd).isEqualTo(local(journalDay.plusDays(1), 5, 0))
        assertThat(sleep.totalDuration.inWholeMinutes).isEqualTo(375)
    }

    @Test
    fun `overlapping and duplicate sessions use union coverage and deterministic stages`() {
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
        assertThat(forward.totalDuration.inWholeHours).isEqualTo(7)
        assertThat(
            forward.deepSleep + forward.remSleep + forward.lightSleep + forward.awakeTime,
        ).isAtMost(forward.totalDuration)
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
        assertThat(sleep.remSleep.inWholeMilliseconds).isEqualTo(0)
        assertThat(sleep.lightSleep.inWholeMilliseconds).isEqualTo(0)
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
    fun `negative implausible and invalid stage intervals cannot corrupt summary`() {
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
        val implausible = session(
            id = "implausible",
            start = local(journalDay, 12, 0),
            end = local(journalDay.plusDays(1), 13, 0),
        )

        val sleep = summarize(journalDay, listOf(negative, implausible, valid))

        assertThat(sleep.totalDuration.inWholeHours).isEqualTo(7)
        assertThat(sleep.deepSleep.inWholeHours).isEqualTo(1)
        assertThat(sleep.remSleep.inWholeMilliseconds).isEqualTo(0)
        assertThat(sleep.sessions.map { it.identity?.nativeId })
            .containsExactly("implausible", "negative", "valid")
        assertThat(sleep.stages).hasSize(2)
    }

    @Test
    fun `rejected detailed session cannot regain a headline through stage fallback`() {
        val invalid = session(
            id = "too-long",
            start = local(journalDay, 12, 0),
            end = local(journalDay.plusDays(1), 13, 0),
            stages = listOf(stage(local(journalDay, 22, 0), local(journalDay, 23, 0), "deep")),
        )

        val sleep = summarize(journalDay, listOf(invalid))

        assertThat(sleep.sessions).hasSize(1)
        assertThat(sleep.stages).hasSize(1)
        assertThat(sleep.sessionStart).isNull()
        assertThat(sleep.sessionEnd).isNull()
        assertThat(sleep.headlineStart).isNull()
        assertThat(sleep.headlineEnd).isNull()
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

    private fun summarize(
        date: LocalDate,
        sessions: List<SourceSession>,
        zone: ZoneId = utc,
    ) = SleepJournalSummary.summarize(
        sourceSessions = sessions,
        requestedDates = listOf(date),
        zone = zone,
        includeGranularData = true,
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
