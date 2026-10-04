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
    fun singleDateReadsHonorStoredMorningOwnerAndMatchRangeWithoutDuplicateNight() = runTest {
        val fixture = SleepAttributionCaptureFixture()
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

            assertThat(start.hasAnyData).isFalse()
            assertThat(start.sleep.sessions).isEmpty()
            assertThat(wake.sleep.totalDuration).isEqualTo(495.minutes)
            assertThat(wake.sleep.lightSleep).isEqualTo(465.minutes)
            assertThat(wake.sleep.awakeTime).isEqualTo(30.minutes)
            assertThat(wake.sleep.sessionStart).isEqualTo(fixture.start)
            assertThat(wake.sleep.sessionEnd).isEqualTo(fixture.end)
            assertThat(wake.sleep.sessions.single().identity?.nativeId).isEqualTo("synthetic-overnight")
            assertThat(range.map { it.date }).containsExactly(fixture.wakeDay)
            assertThat(range.single().sleep.totalDuration).isEqualTo(wake.sleep.totalDuration)
            assertThat(range.single().sleep.stages.map { it.stage }).containsExactly("light", "awake", "light").inOrder()
            assertThat(range.single().sleep.stages[1].startTime).isEqualTo(fixture.startDay.atTime(23, 50))
            assertThat(range.single().sleep.stages[1].endTime).isEqualTo(fixture.wakeDay.atTime(0, 20))
            assertThat(fixture.singleDayReads).isEmpty()
            assertThat(fixture.observedContexts).containsExactly(
                fixture.zone to SleepDayAttribution.MORNING_ENDS,
                fixture.zone to SleepDayAttribution.MORNING_ENDS,
                fixture.zone to SleepDayAttribution.MORNING_ENDS,
            ).inOrder()
            coVerify(exactly = 3) { fixture.settings.getSleepDayAttribution() }
        } finally {
            TimeZone.setDefault(previousZone)
        }
    }

    @Test
    fun allConnectedSingleDateReadsAlsoKeepSleepOnlyNightOnWakeDate() = runTest {
        val fixture = SleepAttributionCaptureFixture(allConnected = true)
        val previousZone = TimeZone.getDefault()
        try {
            TimeZone.setDefault(TimeZone.getTimeZone(fixture.zone))
            val start = fixture.repository.fetchHealthData(fixture.startDay)
            val wake = fixture.repository.fetchHealthData(fixture.wakeDay)

            assertThat(start.sleep.hasData).isFalse()
            assertThat(wake.sleep.totalDuration).isEqualTo(495.minutes)
            assertThat(wake.sleep.awakeTime).isEqualTo(30.minutes)
            assertThat(wake.sleep.sessionStart).isEqualTo(fixture.start)
            assertThat(wake.sleep.sessionEnd).isEqualTo(fixture.end)
            assertThat(fixture.singleDayReads).isEmpty()
            assertThat(fixture.observedContexts).containsExactly(
                fixture.zone to SleepDayAttribution.MORNING_ENDS,
                fixture.zone to SleepDayAttribution.MORNING_ENDS,
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
