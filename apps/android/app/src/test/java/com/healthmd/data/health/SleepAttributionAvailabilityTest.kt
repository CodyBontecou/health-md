package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepDayAttributionOverride
import kotlinx.coroutines.test.runTest
import org.junit.Test

class SleepAttributionAvailabilityTest {
    @Test
    fun storedMorningEndsCapturesOnlyTheWakeDateWithoutALegacySecondRead() = runTest {
        val fixture = SleepAttributionCaptureFixture()
        val result = fixture.repository.fetchHealthDataRange(
            dates = listOf(fixture.startDay, fixture.wakeDay),
            dataTypes = fixture.selection,
            zoneId = fixture.zone,
        )
        assertThat(result.map { it.date }).containsExactly(fixture.wakeDay)
        assertThat(result.single().sleep.sessionStart).isEqualTo(fixture.start)
        assertThat(result.single().sleep.sessionEnd).isEqualTo(fixture.end)
        assertThat(fixture.observedContexts).containsExactly(fixture.zone to SleepDayAttribution.MORNING_ENDS)
        assertThat(fixture.singleDayReads).isEmpty()
    }

    @Test
    fun explicitMorningContextIsNotCoercedWhenPreferenceChangesToNight() = runTest {
        val fixture = SleepAttributionCaptureFixture()
        fixture.storedAttribution = SleepDayAttribution.NIGHT_BEGINS
        val result = fixture.repository.fetchHealthDataRange(
            dates = listOf(fixture.startDay, fixture.wakeDay),
            dataTypes = fixture.selection,
            zoneId = fixture.zone,
            sleepDayAttributionOverride = SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS),
        )
        assertThat(result.map { it.date }).containsExactly(fixture.wakeDay)
        assertThat(fixture.observedContexts).containsExactly(fixture.zone to SleepDayAttribution.MORNING_ENDS)
        assertThat(fixture.storedAttribution).isEqualTo(SleepDayAttribution.NIGHT_BEGINS)
    }
}
