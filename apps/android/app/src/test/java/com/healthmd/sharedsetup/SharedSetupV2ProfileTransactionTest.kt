package com.healthmd.sharedsetup

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.WriteMode
import io.mockk.mockk
import java.time.LocalDate
import java.time.ZoneId
import java.util.ArrayDeque
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class SharedSetupV2ProfileTransactionTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("shared-setup-v2.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = { file },
        )
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    @Test
    fun `add normalizes selection preserves existing order schedules and active then materializes blocked profiles`() = runTest {
        val existing = listOf(
            nativeProfile(EXISTING_ONE_ID, "Daily"),
            nativeProfile(EXISTING_TWO_ID, "Existing"),
        )
        val existingSchedule = ScheduledProfileEntry(
            profileId = EXISTING_TWO_ID,
            isEnabled = true,
            anchorEpochDay = LocalDate.parse("2025-01-01").toEpochDay(),
            hour = 9,
            zoneId = "UTC",
        )
        seed(existing, EXISTING_TWO_ID, listOf(existingSchedule))
        val plan = importPlan()
        val transaction = transaction(GENERATED_ONE_ID, GENERATED_TWO_ID)

        val result = transaction.apply(
            plan = plan,
            selectedBundleIds = listOf("profile-002", "profile-001"),
            mode = SharedSetupV2ProfileImportMode.ADD,
        ).getOrThrow()

        assertThat(result.selectedBundleIds).containsExactly("profile-001", "profile-002").inOrder()
        assertThat(result.nativeProfileIdsByBundleId)
            .containsExactly(
                "profile-001", GENERATED_ONE_ID,
                "profile-002", GENERATED_TWO_ID,
            ).inOrder()
        assertThat(result.activeProfileId).isEqualTo(EXISTING_TWO_ID)

        val profiles = storedProfiles()
        assertThat(profiles.map { it.id })
            .containsExactly(EXISTING_ONE_ID, EXISTING_TWO_ID, GENERATED_ONE_ID, GENERATED_TWO_ID)
            .inOrder()
        assertThat(profiles.map { it.name })
            .containsExactly("Daily", "Existing", "Daily 2", "Daily 2 2")
            .inOrder()
        profiles.takeLast(2).forEach { imported ->
            assertThat(imported.folderUri).isNull()
            assertThat(imported.folderDisplayName).isNull()
            assertThat(imported.apiEndpointUrl).isNull()
            assertThat(imported.isMigrationDefault).isFalse()
            assertThat(imported.createdAtEpochMillis).isEqualTo(NOW)
            assertThat(imported.updatedAtEpochMillis).isEqualTo(NOW)
        }
        assertThat(profiles.last().target).isEqualTo(ExportTarget.API_ENDPOINT)

        val firstSnapshot = requireNotNull(
            AndroidExportSettingsSnapshotCodec.decodeOrNull(profiles[2].settingsSnapshotJson),
        )
        assertThat(firstSnapshot.exportFormats).containsExactly(ExportFormat.JSON, ExportFormat.CSV)
        assertThat(firstSnapshot.includeMetadata).isFalse()
        assertThat(firstSnapshot.groupByCategory).isFalse()
        assertThat(firstSnapshot.filenameFormat).isEqualTo("daily-{date}")
        assertThat(firstSnapshot.writeMode).isEqualTo(WriteMode.UPDATE)
        assertThat(firstSnapshot.ianaTimeZone).isEqualTo("America/New_York")
        assertThat(firstSnapshot.enginePin).isNull()
        assertThat(firstSnapshot.apiEndpointIdentitySha256).isNull()
        assertThat(firstSnapshot.exportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)
        assertThat(firstSnapshot.scheduledExportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)

        val schedules = storedSchedules()
        assertThat(schedules.map { it.profileId })
            .containsExactly(EXISTING_TWO_ID, GENERATED_ONE_ID)
            .inOrder()
        assertThat(schedules.first()).isEqualTo(existingSchedule)
        val importedSchedule = schedules.last()
        assertThat(importedSchedule.isEnabled).isFalse()
        assertThat(importedSchedule.zoneId).isEqualTo("America/New_York")
        assertThat(importedSchedule.lastSuccessEpochMillis).isNull()
        assertThat(importedSchedule.lastRefreshSuccessEpochMillis).isNull()
        assertThat(importedSchedule.pendingExports).isEmpty()

        assertThat(storedActiveId()).isEqualTo(EXISTING_TWO_ID)
        assertThat(storedBlockedIds()).containsExactly(GENERATED_ONE_ID, GENERATED_TWO_ID)
        val sidecar = transaction.storedProfileState().getOrThrow()!!
        assertThat(sidecar.version).isEqualTo(1)
        assertThat(sidecar.profiles.map { it.profileId })
            .containsExactly(GENERATED_ONE_ID, GENERATED_TWO_ID)
            .inOrder()
        assertThat(sidecar.profiles.map { it.sourceBundleId })
            .containsExactly("profile-001", "profile-002")
            .inOrder()
        assertThat(sidecar.profiles[0].sourceProfile).isEqualTo(plan.profiles[0].source)
        assertThat(sidecar.profiles[1].sourceProfile.destination.kind).isEqualTo("api_endpoint")
        assertThat(sidecar.profiles.all { it.unsupportedSemanticIds == it.unsupportedSemanticIds.sorted() })
            .isTrue()
    }

    @Test
    fun `replace keeps selected source order chooses first when source active omitted and drops old schedules`() = runTest {
        seed(
            profiles = listOf(nativeProfile(EXISTING_ONE_ID, "Before")),
            activeProfileId = "missing-active",
            schedules = listOf(
                ScheduledProfileEntry(
                    profileId = EXISTING_ONE_ID,
                    isEnabled = true,
                    anchorEpochDay = 20_000,
                    zoneId = "UTC",
                ),
            ),
        )
        val plan = importPlan()
        val transaction = transaction(GENERATED_ONE_ID)

        val result = transaction.apply(
            plan = plan,
            selectedBundleIds = listOf("profile-001"),
            mode = SharedSetupV2ProfileImportMode.REPLACE,
        ).getOrThrow()

        assertThat(result.activeProfileId).isEqualTo(GENERATED_ONE_ID)
        assertThat(storedProfiles().map { it.id }).containsExactly(GENERATED_ONE_ID)
        assertThat(storedProfiles().single().name).isEqualTo("Daily")
        assertThat(storedActiveId()).isEqualTo(GENERATED_ONE_ID)
        assertThat(storedSchedules().map { it.profileId }).containsExactly(GENERATED_ONE_ID)
        assertThat(storedSchedules().single().isEnabled).isFalse()
        assertThat(storedBlockedIds()).containsExactly(GENERATED_ONE_ID)
        assertThat(transaction.storedProfileState().getOrThrow()!!.profiles.map { it.profileId })
            .containsExactly(GENERATED_ONE_ID)
    }

    @Test
    fun `unsupported schedule remains sidecar only`() = runTest {
        val original = importPlan()
        val first = original.source.profiles[0]
        val source = original.source.copy(
            profiles = listOf(
                first.copy(schedule = requireNotNull(first.schedule).copy(lookbackDays = 31)),
                original.source.profiles[1],
            ),
        )
        val plan = SharedSetupV2Mapper(EmptyRegistry).planImport(source)
        val transaction = transaction(GENERATED_ONE_ID)

        transaction.apply(
            plan,
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.REPLACE,
        ).getOrThrow()

        assertThat(storedSchedules()).isEmpty()
        assertThat(transaction.storedProfileState().getOrThrow()!!.profiles.single().sourceProfile.schedule)
            .isEqualTo(source.profiles[0].schedule)
    }

    @Test
    fun `empty duplicate unknown and stale-plan selections perform zero writes and preserve prior Undo`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Before")), EXISTING_ONE_ID, emptyList())
        dataStore.edit {
            it[SharedSetupV2ProfilePersistence.undoKey] = "prior-undo"
        }
        val before = dataStore.data.first().asMap()
        val plan = importPlan()
        val transaction = transaction(GENERATED_ONE_ID, GENERATED_TWO_ID)

        listOf(
            emptyList(),
            listOf("profile-001", "profile-001"),
            listOf("profile-999"),
            listOf(" profile-001"),
        ).forEach { selection ->
            val error = transaction.apply(
                plan,
                selection,
                SharedSetupV2ProfileImportMode.ADD,
            ).exceptionOrNull() as SharedSetupV2ProfileTransactionException
            assertThat(error.reason).isEqualTo(SharedSetupV2ProfileTransactionFailure.INVALID_SELECTION)
            assertThat(dataStore.data.first().asMap()).isEqualTo(before)
        }

        val stalePlan = plan.copy(profiles = plan.profiles.reversed())
        val staleError = transaction.apply(
            stalePlan,
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.ADD,
        ).exceptionOrNull() as SharedSetupV2ProfileTransactionException
        assertThat(staleError.reason).isEqualTo(SharedSetupV2ProfileTransactionFailure.INVALID_PLAN)
        assertThat(dataStore.data.first().asMap()).isEqualTo(before)
    }

    @Test
    fun `undo restores exact prior logical state and removes snapshot one shot`() = runTest {
        val previousProfiles = listOf(
            nativeProfile(EXISTING_ONE_ID, "Before One"),
            nativeProfile(EXISTING_TWO_ID, "Before Two"),
        )
        val previousSchedules = listOf(
            ScheduledProfileEntry(
                profileId = EXISTING_ONE_ID,
                isEnabled = true,
                anchorEpochDay = 19_000,
                hour = 3,
                zoneId = "UTC",
            ),
        )
        seed(previousProfiles, EXISTING_TWO_ID, previousSchedules)
        val transaction = transaction(GENERATED_ONE_ID)
        transaction.apply(
            importPlan(),
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.REPLACE,
        ).getOrThrow()

        transaction.undo().getOrThrow()

        assertThat(storedProfiles()).isEqualTo(previousProfiles)
        assertThat(storedActiveId()).isEqualTo(EXISTING_TWO_ID)
        assertThat(storedSchedules()).isEqualTo(previousSchedules)
        assertThat(storedBlockedIds()).isEmpty()
        assertThat(transaction.storedProfileState().getOrThrow()).isNull()
        assertThat(dataStore.data.first()[SharedSetupV2ProfilePersistence.undoKey]).isNull()

        val second = transaction.undo().exceptionOrNull() as SharedSetupV2ProfileTransactionException
        assertThat(second.reason).isEqualTo(SharedSetupV2ProfileTransactionFailure.NO_UNDO)
    }

    private fun importPlan(): SharedSetupV2ImportPlan {
        val firstSettings = baseSettings().copy(
            exportFormats = setOf(ExportFormat.JSON, ExportFormat.CSV),
            exportFormat = ExportFormat.JSON,
            includeMetadata = false,
            groupByCategory = false,
            filenameFormat = "daily-{date}",
            writeMode = WriteMode.UPDATE,
        )
        val secondSettings = baseSettings().copy(
            exportFormats = setOf(ExportFormat.MARKDOWN),
            exportFormat = ExportFormat.MARKDOWN,
        )
        val first = nativeProfile(
            id = SOURCE_ONE_ID,
            name = "Daily",
            settings = firstSettings,
        )
        val second = nativeProfile(
            id = SOURCE_TWO_ID,
            name = "Daily 2",
            settings = secondSettings,
            target = ExportTarget.API_ENDPOINT,
            endpoint = "https://setup.invalid/import",
        )
        val sourceSchedule = ScheduledProfileEntry(
            profileId = SOURCE_ONE_ID,
            isEnabled = true,
            anchorEpochDay = LocalDate.parse("2025-03-04").toEpochDay(),
            weekdayIso = 2,
            hour = 6,
            minute = 15,
            cadenceValue = 2,
            cadenceUnit = ScheduledProfileCadenceUnit.WEEK,
            lookbackDays = 7,
            zoneId = "Pacific/Auckland",
            lastSuccessEpochMillis = 1234,
        )
        val mapper = SharedSetupV2Mapper(EmptyRegistry)
        return mapper.planImport(
            mapper.export(
                profiles = listOf(first, second),
                activeProfileId = SOURCE_TWO_ID,
                schedules = listOf(sourceSchedule),
                appVersion = "test",
            ),
        )
    }

    private fun baseSettings(): ExportSettings = ExportSettings().copy(
        metricSelection = MetricSelectionState(emptySet()),
        individualTracking = IndividualTrackingSettings(),
    )

    private fun nativeProfile(
        id: String,
        name: String,
        settings: ExportSettings = baseSettings(),
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
        endpoint: String? = null,
    ): ExportProfile {
        val scoped = settings.copy(
            exportTarget = target,
            scheduledExportTarget = target,
            apiEndpointUrl = endpoint.orEmpty(),
        )
        val snapshot = AndroidExportSettingsSnapshot.capture(
            scoped,
            pin = null,
            zone = ZoneId.of("UTC"),
        )
        return ExportProfile(
            id = id,
            name = name,
            settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot),
            target = target,
            apiEndpointUrl = endpoint,
            createdAtEpochMillis = 10,
            updatedAtEpochMillis = 11,
        )
    }

    private fun transaction(vararg ids: String): SharedSetupV2ProfileTransaction {
        val queue = ArrayDeque(ids.toList())
        return SharedSetupV2ProfileTransaction(
            dataStore = dataStore,
            registry = EmptyRegistry,
            nativeId = { queue.removeFirst() },
            nowEpochMillis = { NOW },
            localZoneId = { ZoneId.of("America/New_York") },
            testing = Unit,
        )
    }

    private suspend fun seed(
        profiles: List<ExportProfile>,
        activeProfileId: String?,
        schedules: List<ScheduledProfileEntry>,
    ) {
        dataStore.edit { preferences ->
            preferences[SharedSetupV2ProfilePersistence.profilesKey] =
                SharedSetupV2ProfilePersistence.json.encodeToString(
                    SharedSetupV2ProfilePersistence.profileListSerializer,
                    profiles,
                )
            activeProfileId?.let {
                preferences[SharedSetupV2ProfilePersistence.activeProfileIdKey] = it
            }
            preferences[SharedSetupV2ProfilePersistence.scheduledProfileEntriesKey] =
                SharedSetupV2ProfilePersistence.json.encodeToString(
                    SharedSetupV2ProfilePersistence.scheduleListSerializer,
                    schedules,
                )
        }
    }

    private suspend fun storedProfiles(): List<ExportProfile> {
        val raw = dataStore.data.first()[SharedSetupV2ProfilePersistence.profilesKey]
            ?: return emptyList()
        return SharedSetupV2ProfilePersistence.json.decodeFromString(
            SharedSetupV2ProfilePersistence.profileListSerializer,
            raw,
        )
    }

    private suspend fun storedSchedules(): List<ScheduledProfileEntry> {
        val raw = dataStore.data.first()[SharedSetupV2ProfilePersistence.scheduledProfileEntriesKey]
            ?: return emptyList()
        return SharedSetupV2ProfilePersistence.json.decodeFromString(
            SharedSetupV2ProfilePersistence.scheduleListSerializer,
            raw,
        )
    }

    private suspend fun storedActiveId(): String? =
        dataStore.data.first()[SharedSetupV2ProfilePersistence.activeProfileIdKey]

    private suspend fun storedBlockedIds(): Set<String> =
        dataStore.data.first()[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()

    private object EmptyRegistry : SharedSetupMetricRegistry {
        override val version: Int = 1
        override val sha256: String = "0".repeat(64)
        override val bySemanticId: Map<String, SharedSetupRegistryBinding> = emptyMap()
        override val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding> = emptyMap()
    }

    private companion object {
        const val NOW = 1_800_000_000_000L
        const val EXISTING_ONE_ID = "10000000-0000-4000-8000-000000000001"
        const val EXISTING_TWO_ID = "10000000-0000-4000-8000-000000000002"
        const val SOURCE_ONE_ID = "20000000-0000-4000-8000-000000000001"
        const val SOURCE_TWO_ID = "20000000-0000-4000-8000-000000000002"
        const val GENERATED_ONE_ID = "30000000-0000-4000-8000-000000000001"
        const val GENERATED_TWO_ID = "30000000-0000-4000-8000-000000000002"
    }
}
