package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepDayAttributionOverride
import io.mockk.coVerify
import java.util.TimeZone
import kotlinx.coroutines.test.runTest
import org.junit.Test
import kotlin.time.Duration.Companion.minutes

class HealthRepositorySleepAttributionTest {
    @Test
    fun singleDateReadsHonorShippedNightOwnerAndMatchRangeWithoutDuplicateNight() = runTest {
        val fixture = SleepAttributionCaptureFixture()
        fixture.storedAttribution = SleepDayAttribution.NIGHT_BEGINS
        val previousZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone(fixture.zone))
            val start = fixture.repository.fetchHealthData(fixture.startDay)
            val wake = fixture.repository.fetchHealthData(fixture.wakeDay)
            val range = fixture.repository.fetchHealthDataRange(
                dates = listOf(fixture.wakeDay, fixture.startDay),
                dataTypes = fixture.selection,
                includeGranularData = true,
                zoneId = fixture.zone,
            )

            assertThat(wake.hasAnyData).isFalse()
            assertThat(wake.sleep.sessions).isEmpty()
            assertThat(start.sleep.totalDuration).isEqualTo(495.minutes)
            assertThat(start.sleep.lightSleep).isEqualTo(465.minutes)
            assertThat(start.sleep.awakeTime).isEqualTo(30.minutes)
            assertThat(start.sleep.sessionStart).isEqualTo(fixture.start)
            assertThat(start.sleep.sessionEnd).isEqualTo(fixture.end)
            assertThat(start.sleep.sessions.single().identity?.nativeId).isEqualTo("synthetic-overnight")
            assertThat(range.map { it.date }).containsExactly(fixture.startDay)
            assertThat(range.single().sleep.totalDuration).isEqualTo(start.sleep.totalDuration)
            assertThat(range.single().sleep.stages.map { it.stage }).containsExactly("light", "awake", "light").inOrder()
            assertThat(range.single().sleep.stages[1].startTime).isEqualTo(fixture.startDay.atTime(23, 50))
            assertThat(range.single().sleep.stages[1].endTime).isEqualTo(fixture.wakeDay.atTime(0, 20))
            assertThat(fixture.singleDayReads).isEmpty()
            assertThat(fixture.observedContexts).containsExactly(
                fixture.zone to SleepDayAttribution.NIGHT_BEGINS,
                fixture.zone to SleepDayAttribution.NIGHT_BEGINS,
                fixture.zone to SleepDayAttribution.NIGHT_BEGINS,
            ).inOrder()
            coVerify(exactly = 3) { fixture.settings.getSleepDayAttribution() }
        } finally {
            TimeZone.setDefault(previousZone)
        }
    }

    @Test
    fun allConnectedSingleDateReadsKeepShippedSleepOnlyNightOnStartDate() = runTest {
        val fixture = SleepAttributionCaptureFixture(allConnected = true)
        fixture.storedAttribution = SleepDayAttribution.NIGHT_BEGINS
        val previousZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone(fixture.zone))
            val start = fixture.repository.fetchHealthData(fixture.startDay)
            val wake = fixture.repository.fetchHealthData(fixture.wakeDay)

            assertThat(wake.sleep.hasData).isFalse()
            assertThat(start.sleep.totalDuration).isEqualTo(495.minutes)
            assertThat(start.sleep.awakeTime).isEqualTo(30.minutes)
            assertThat(start.sleep.sessionStart).isEqualTo(fixture.start)
            assertThat(start.sleep.sessionEnd).isEqualTo(fixture.end)
            assertThat(fixture.singleDayReads).isEmpty()
            assertThat(fixture.observedContexts).containsExactly(
                fixture.zone to SleepDayAttribution.NIGHT_BEGINS,
                fixture.zone to SleepDayAttribution.NIGHT_BEGINS,
            ).inOrder()
        } finally {
            TimeZone.setDefault(previousZone)
        }
    }

    @Test
    fun explicitNightBeginsIsNotReinterpretedAsStoredMorningPreference() = runTest {
        val fixture = SleepAttributionCaptureFixture()
        val result = fixture.repository.fetchHealthDataRange(
            dates = listOf(fixture.startDay, fixture.wakeDay),
            dataTypes = fixture.selection,
            includeGranularData = true,
            zoneId = fixture.zone,
            sleepDayAttributionOverride = SleepDayAttributionOverride.Value(SleepDayAttribution.NIGHT_BEGINS),
        )

        assertThat(result.map { it.date }).containsExactly(fixture.startDay)
        assertThat(result.single().sleep.totalDuration).isEqualTo(495.minutes)
        assertThat(result.single().sleep.stages).hasSize(3)
        assertThat(fixture.observedContexts).containsExactly(fixture.zone to SleepDayAttribution.NIGHT_BEGINS)
        coVerify(exactly = 0) { fixture.settings.getSleepDayAttribution() }
    }
}
