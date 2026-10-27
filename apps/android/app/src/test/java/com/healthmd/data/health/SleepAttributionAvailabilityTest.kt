package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepDayAttributionOverride
import kotlinx.coroutines.test.runTest
import org.junit.Test

class SleepAttributionAvailabilityTest {
    @Test
    fun storedMorningEndsCannotReachAnyShippedWriterCapture() = runTest {
        val fixture = SleepAttributionCaptureFixture()
        val result = runCatching {
            fixture.repository.fetchHealthDataRange(
                dates = listOf(fixture.startDay, fixture.wakeDay),
                dataTypes = fixture.selection,
                zoneId = fixture.zone,
            )
        }
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
        assertThat(result.exceptionOrNull()?.message).isEqualTo(
            "Morning ends is unavailable for current export profiles. Choose Night begins for a new export.",
        )
        assertThat(fixture.observedContexts).isEmpty()
        assertThat(fixture.singleDayReads).isEmpty()
        assertThat(fixture.storedAttribution).isEqualTo(SleepDayAttribution.MORNING_ENDS)
    }

    @Test
    fun unavailableExplicitPendingContextIsNotCoercedWhenPreferenceChangesToNight() = runTest {
        val fixture = SleepAttributionCaptureFixture()
        fixture.storedAttribution = SleepDayAttribution.NIGHT_BEGINS
        val result = runCatching {
            fixture.repository.fetchHealthDataRange(
                dates = listOf(fixture.startDay, fixture.wakeDay),
                dataTypes = fixture.selection,
                zoneId = fixture.zone,
                sleepDayAttributionOverride = SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS),
            )
        }
        assertThat(result.exceptionOrNull()).isInstanceOf(IllegalStateException::class.java)
        assertThat(fixture.observedContexts).isEmpty()
        assertThat(fixture.storedAttribution).isEqualTo(SleepDayAttribution.NIGHT_BEGINS)
    }
}
