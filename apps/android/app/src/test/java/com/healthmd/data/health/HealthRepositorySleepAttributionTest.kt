package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepDayAttributionOverride
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.domain.repository.forCaptureOperation
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import java.time.LocalDate
import java.util.TimeZone
import kotlinx.coroutines.test.runTest
import org.junit.Test
import kotlin.time.Duration.Companion.minutes

class HealthRepositorySleepAttributionTest {
    @Test
    fun operationKeepsConnectedMembershipButRechecksRevokedReadPermission() = runTest {
        val date = LocalDate.of(2026, 7, 1)
        var selected = HealthDataMerger.ALL_CONNECTED_PROVIDER_ID
        val connected = mutableSetOf("health_connect")
        var permission = true
        val manager = mockk<HealthConnectManager>()
        coEvery { manager.isAvailable() } returns true
        coEvery { manager.hasAllPermissions() } answers { permission }
        coEvery { manager.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
            firstArg<List<LocalDate>>().map { HealthData(it, activity = ActivityData(steps = 10)) }
        }
        val alternate = mockk<HealthDataProvider>()
        io.mockk.every { alternate.providerId } returns "whoop"
        val preferences = mockk<SettingsRepository>()
        coEvery { preferences.getSelectedHealthProviderId() } answers { selected }
        coEvery { preferences.getConnectedHealthProviderIds() } answers { connected }
        val repository = HealthRepositoryImpl(HealthProviderRegistry(HealthConnectDataProvider(manager), listOf(alternate)), preferences)
        val accepted = repository.forCaptureOperation()
        connected += "whoop"
        selected = "whoop"
        val captured = accepted.fetchHealthDataRange(listOf(date),
            sleepDayAttributionOverride = SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS)).single()
        assertThat(captured.activity.steps).isEqualTo(10)
        assertThat(captured.compatibilityProvenance?.providerIdsAttempted).containsExactly("health_connect")
        permission = false
        val revoked = accepted.fetchHealthDataRange(listOf(date),
            sleepDayAttributionOverride = SleepDayAttributionOverride.Value(SleepDayAttribution.MORNING_ENDS)).single()
        assertThat(revoked.activity.steps).isNull()
        assertThat(revoked.compatibilityProvenance?.providerFailures?.single()?.errorType).isEqualTo("PermissionDenied")
        coVerify(exactly = 1) { manager.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) }
        coVerify(exactly = 0) { alternate.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) }
        coVerify(exactly = 1) { preferences.getSelectedHealthProviderId() }
        coVerify(exactly = 1) { preferences.getConnectedHealthProviderIds() }
    }

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
