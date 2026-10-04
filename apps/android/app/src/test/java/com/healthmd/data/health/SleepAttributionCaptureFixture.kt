package com.healthmd.data.health

import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.SleepStageEntry
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

/** Synthetic sleep-only capture through the real repository, provider and reducer. */
internal class SleepAttributionCaptureFixture(allConnected: Boolean = false) {
    val startDay: LocalDate = LocalDate.of(2026, 7, 1)
    val wakeDay: LocalDate = startDay.plusDays(1)
    val zone: ZoneId = ZoneId.of("Asia/Kathmandu")
    val start: LocalDateTime = startDay.atTime(22, 30)
    val end: LocalDateTime = wakeDay.atTime(6, 45)
    val selection: DataTypeSelection = DataTypeSelection().deselectAll().copy(sleep = true)
    var storedAttribution: SleepDayAttribution = SleepDayAttribution.MORNING_ENDS
    val observedContexts = mutableListOf<Pair<ZoneId, SleepDayAttribution>>()
    val singleDayReads = mutableListOf<LocalDate>()
    val settings = mockk<SettingsRepository>()
    private val manager = mockk<HealthConnectManager>()
    val repository: HealthRepositoryImpl

    init {
        val awakeStart = startDay.atTime(23, 50)
        val awakeEnd = wakeDay.atTime(0, 20)
        fun stage(from: LocalDateTime, to: LocalDateTime, name: String) = SourceStage(
            start = from.atZone(zone).toInstant(),
            end = to.atZone(zone).toInstant(),
            entry = SleepStageEntry(
                startTime = from,
                endTime = to,
                stage = name,
                exactStartTime = ExactSourceTimestamp.from(from.atZone(zone).toInstant()),
                exactEndTime = ExactSourceTimestamp.from(to.atZone(zone).toInstant()),
            ),
        )
        val sessions = listOf(SourceSession(
            start = start.atZone(zone).toInstant(),
            end = end.atZone(zone).toInstant(),
            entry = SleepSessionEntry(
                startTime = start,
                endTime = end,
                identity = ExactSourceIdentity(nativeId = "synthetic-overnight"),
            ),
            stages = listOf(
                stage(start, awakeStart, "light"),
                stage(awakeStart, awakeEnd, "awake"),
                stage(awakeEnd, end, "light"),
            ),
        ))
        coEvery { settings.getSelectedHealthProviderId() } returns
            if (allConnected) HealthDataMerger.ALL_CONNECTED_PROVIDER_ID else "health_connect"
        coEvery { settings.getConnectedHealthProviderIds() } returns setOf("health_connect")
        coEvery { settings.getSleepDayAttribution() } answers { storedAttribution }
        coEvery { manager.isAvailable() } returns true
        coEvery { manager.hasAllPermissions() } returns true
        every { manager.isBeforeFirstUnlock() } returns false
        // Deliberately retain the stale provider-native behavior as a trap for
        // consumers that reintroduce a second read after an empty range result.
        coEvery { manager.fetchHealthData(any()) } answers {
            val date = firstArg<LocalDate>()
            singleDayReads += date
            HealthData(date, sleep = SleepJournalSummary.summarize(
                sessions, listOf(date), zone, true, SleepDayAttribution.NIGHT_BEGINS,
            ).getValue(date))
        }
        coEvery { manager.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
            val dates = firstArg<List<LocalDate>>()
            val types = arg<DataTypeSelection>(1)
            val granular = arg<Boolean>(2)
            val capturedZone = arg<ZoneId>(3)
            val attribution = arg<SleepDayAttribution>(5)
            observedContexts += capturedZone to attribution
            SleepJournalSummary.summarize(sessions, dates, capturedZone, granular, attribution)
                .map { (date, sleep) -> HealthData(date, sleep = sleep).filtered(types) }
                .filter(HealthData::hasAnyData)
        }
        repository = HealthRepositoryImpl(
            HealthProviderRegistry(HealthConnectDataProvider(manager)),
            settings,
        )
    }
}
