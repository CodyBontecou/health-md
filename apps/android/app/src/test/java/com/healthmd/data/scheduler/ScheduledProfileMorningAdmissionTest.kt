package com.healthmd.data.scheduler

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.RestorableHealthRepository
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.mockk
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.*
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class ScheduledProfileMorningAdmissionTest {
    @get:Rule val temporary = TemporaryFolder()
    private val zone = ZoneId.of("UTC")
    private val endpoint = "https://profile.example.invalid/health"
    private var preference = SleepDayAttribution.MORNING_ENDS
    private var grant = "00000000-0000-4000-8000-000000000201"
    private var acceptances = 0
    private val settingsRepository = mockk<SettingsRepository>()
    private val source = object : HealthRepository by mockk(relaxed = true), RestorableHealthRepository {
        override suspend fun captureProviderAuthority(): HealthProviderCaptureAuthority {
            acceptances++
            return HealthProviderCaptureAuthority(selectedProviderId = "whoop", providerIds = listOf("whoop"),
                connectionIds = mapOf("whoop" to grant)).validatedCopy()
        }
        override suspend fun restoreProviderAuthority(authority: HealthProviderCaptureAuthority): HealthRepository =
            error("No health read is needed for profile acceptance")
    }
    private lateinit var scope: CoroutineScope
    private lateinit var store: ScheduledProfileEntryStore
    private lateinit var dataStore: androidx.datastore.core.DataStore<androidx.datastore.preferences.core.Preferences>
    private val factory get() = ScheduledProfileSnapshotFactory(ExportEnginePinPlanner(), settingsRepository)
    private val live = ExportSettings(exportFormat = ExportFormat.CSV, exportFormats = setOf(ExportFormat.CSV), subfolder = "live")

    @Before fun setup() {
        val library = System.getenv("HEALTHMD_HOST_CORE_LIBRARY")
        org.junit.Assume.assumeTrue(!library.isNullOrBlank())
        System.setProperty("uniffi.component.healthmd_core_uniffi.libraryOverride", library!!)
        coEvery { settingsRepository.getSleepDayAttribution() } answers { preference }
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporary.newFolder().resolve("entries.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(scope = scope, produceFile = { file })
        store = ScheduledProfileEntryStore(dataStore, mockk<Context>(relaxed = true))
    }
    @After fun teardown() { if (::scope.isInitialized) scope.cancel() }

    private fun definition(): ExportProfile {
        val settings = ExportSettings(exportFormat = ExportFormat.JSON, exportFormats = setOf(ExportFormat.JSON),
            subfolder = "frozen", filenameFormat = "sleep-{date}", exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.API_ENDPOINT, apiEndpointUrl = endpoint)
        return ExportProfile(id = "profile-morning", name = "Frozen profile", target = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = endpoint, settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
                AndroidExportSettingsSnapshot.capture(settings, null, zone)), createdAtEpochMillis = 1L, updatedAtEpochMillis = 1L)
    }

    @Test fun freshOccurrencesPreserveProfileOutputAndAcceptIndependentSources() = runTest {
        val definition = definition()
        val original = definition.settingsSnapshotJson
        val first = requireNotNull(factory.captureForNewOccurrence(definition, live, zone, source))
        val firstSettings = requireNotNull(factory.restoreForRun(first, live, 2))
        assertThat(firstSettings.exportFormats).containsExactly(ExportFormat.JSON)
        assertThat(firstSettings.subfolder).isEqualTo("frozen")
        assertThat(firstSettings.filenameFormat).isEqualTo("sleep-{date}")
        assertThat(firstSettings.executionProviderCaptureAuthority?.connectionIds).containsEntry("whoop", grant)
        grant = "00000000-0000-4000-8000-000000000202"
        val second = requireNotNull(factory.captureForNewOccurrence(definition, live, zone, source))
        assertThat(requireNotNull(factory.restoreForRun(second, live, 2)).executionProviderCaptureAuthority?.connectionIds)
            .containsEntry("whoop", grant)
        assertThat(factory.restoreForRun(first, live, 2)?.executionProviderCaptureAuthority)
            .isEqualTo(firstSettings.executionProviderCaptureAuthority)
        assertThat(definition.settingsSnapshotJson).isEqualTo(original)
        assertThat(acceptances).isEqualTo(2)
        preference = SleepDayAttribution.NIGHT_BEGINS
        assertThat(factory.captureForNewOccurrence(definition, live, zone, source)).isEqualTo(definition)
        assertThat(acceptances).isEqualTo(2)
        val night = requireNotNull(factory.captureForNewOccurrence(first, live, zone, source))
        val restoredNight = requireNotNull(factory.restoreForRun(night, live, 2))
        assertThat(restoredNight.executionSleepCaptureContext?.sleepDayAttribution).isEqualTo(SleepDayAttribution.NIGHT_BEGINS)
        assertThat(restoredNight.executionProviderCaptureAuthority).isNull()
        assertThat(restoredNight.executionEnginePin?.profile).isNotEqualTo(com.healthmd.domain.exportengine.AndroidExportProfile.android_sleep_v6)
        assertThat(firstSettings.executionSleepCaptureContext?.sleepDayAttribution).isEqualTo(SleepDayAttribution.MORNING_ENDS)
        assertThat(acceptances).isEqualTo(2)
    }

    @Test fun acceptedRefreshReopensWithExactScopeAndCannotBeReplacedAfterDiscard() = runTest {
        val now = Instant.parse("2026-07-02T00:01:00Z").toEpochMilli()
        val today = LocalDate.of(2026, 7, 2)
        val entry = ScheduledProfileEntry(profileId = "profile-morning", isEnabled = true,
            anchorEpochDay = today.toEpochDay(), hour = 0, zoneId = zone.id, todayRefreshEnabled = true,
            lastSuccessEpochMillis = today.atStartOfDay(zone).toInstant().toEpochMilli())
        assertThat(store.upsert(entry)).isTrue()
        val due = requireNotNull(ScheduledProfileOccurrenceMath.dueOccurrence(entry, now))
        val profile = requireNotNull(factory.captureForNewOccurrence(definition(), live, zone, source))
        val pending = ScheduledProfilePendingExport(id = "accepted", ownerEpochDays = due.exportDates.map(LocalDate::toEpochDay),
            fireAtMillis = due.fireAtMillis, settingsSnapshotJson = profile.settingsSnapshotJson,
            target = profile.target, profileName = profile.name, apiEndpointUrl = endpoint,
            refreshSlotMillis = due.refreshSlotMillis)
        assertThat(store.admitOccurrence(entry, pending)).isTrue()
        val other = pending.copy(id = "replacement", settingsSnapshotJson = pending.settingsSnapshotJson.replace(grant,
            "00000000-0000-4000-8000-000000000202"))
        assertThat(store.admitOccurrence(entry, other)).isFalse()
        val reopened = ScheduledProfileEntryStore(dataStore, mockk<Context>(relaxed = true))
        val recovered = requireNotNull(reopened.entry(entry.profileId))
        preference = SleepDayAttribution.NIGHT_BEGINS
        grant = "00000000-0000-4000-8000-000000000203"
        val retry = requireNotNull(ScheduledProfileOccurrenceMath.dueOccurrence(recovered.copy(zoneId = "America/Los_Angeles"), now + 3_600_000))
        assertThat(retry.pendingExport).isEqualTo(pending)
        assertThat(retry.exportDates).containsExactly(today)
        assertThat(retry.refreshSlotMillis).isEqualTo(due.refreshSlotMillis)
        assertThat(factory.restoreForRun(profile, live, 1)?.executionProviderCaptureAuthority?.connectionIds)
            .containsEntry("whoop", "00000000-0000-4000-8000-000000000201")
        assertThat(acceptances).isEqualTo(1)
        assertThat(store.discardPendingRecovery(entry.profileId)).isTrue()
        assertThat(store.admitOccurrence(entry, other)).isFalse()
        assertThat(store.entry(entry.profileId)?.pendingExports).isEmpty()
    }

    @Test fun competingAdmissionsPublishOnlyOneImmutableSnapshot() = runTest {
        val entry = ScheduledProfileEntry(profileId = "profile-morning", isEnabled = true,
            anchorEpochDay = LocalDate.of(2026, 7, 2).toEpochDay(), zoneId = zone.id)
        store.upsert(entry)
        val profile = requireNotNull(factory.captureForNewOccurrence(definition(), live, zone, source))
        val first = ScheduledProfilePendingExport(id = "first", ownerEpochDays = listOf(LocalDate.of(2026, 7, 1).toEpochDay()),
            fireAtMillis = 1L, settingsSnapshotJson = profile.settingsSnapshotJson, target = profile.target, profileName = profile.name)
        val second = first.copy(id = "second", settingsSnapshotJson = first.settingsSnapshotJson.replace(grant,
            "00000000-0000-4000-8000-000000000202"))
        val outcomes = listOf(first, second).map { candidate -> async(Dispatchers.IO) { store.admitOccurrence(entry, candidate) } }.awaitAll()
        assertThat(outcomes.count { it }).isEqualTo(1)
        assertThat(store.entry(entry.profileId)?.pendingExports?.single()).isEqualTo(if (outcomes.first()) first else second)
    }

    @Test fun profileDefinitionsDoNotPersistExecutionGrantIdentity() = runTest {
        val supplied = HealthProviderCaptureAuthority(selectedProviderId = "whoop", providerIds = listOf("whoop"), connectionIds = mapOf("whoop" to grant))
        val json = factory.captureFromCurrent(live.copy(exportFormat = ExportFormat.JSON, exportFormats = setOf(ExportFormat.JSON),
            executionProviderCaptureAuthority = supplied, executionProviderCaptureAuthorityIsFrozen = true), ExportTarget.API_ENDPOINT, endpoint)
        assertThat(AndroidExportSettingsSnapshotCodec.decode(json).providerCaptureAuthority).isNull()
        assertThat(json).doesNotContain(grant)
    }
}
