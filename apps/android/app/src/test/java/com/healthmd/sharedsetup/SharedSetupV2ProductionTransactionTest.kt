package com.healthmd.sharedsetup

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.WriteMode
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import java.time.LocalDate
import java.time.ZoneId
import java.util.ArrayDeque
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertThrows
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Production adapter over the real profile transaction and profile repository: explicit apply and
 * one-shot Undo delegation, the mandatory per-profile Apple-extension sidecar loader, blocked
 * imported-profile visibility, and folder rebinding through the existing clearing rules.
 */
class SharedSetupV2ProductionTransactionTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var profileRepository: ExportProfileRepository
    private lateinit var coordinator: ExportProfileCoordinator
    private lateinit var adapter: SharedSetupV2ProductionTransaction

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("v2-production.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = { file },
        )
        profileRepository = ExportProfileRepository(
            dataStore = dataStore,
            context = mockk<Context>(relaxed = true),
        )
        coordinator = mockk(relaxed = true)
        adapter = SharedSetupV2ProductionTransaction(
            transaction = transaction(GENERATED_ONE_ID, GENERATED_TWO_ID),
            profileRepository = profileRepository,
            profileCoordinator = coordinator,
        )
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    @Test
    fun `apply delegates to the transaction with mapped add mode and materializes blocked profiles`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Daily")), EXISTING_ONE_ID)

        val result = adapter.apply(
            SharedSetupV2ApplyRequest(
                plan = importPlan(),
                selectedBundleIds = listOf("profile-002", "profile-001"),
                mode = SharedSetupV2ApplyMode.ADD,
            ),
        )

        assertThat(result.isSuccess).isTrue()
        val profiles = profileRepository.getProfiles()
        assertThat(profiles.map { it.id })
            .containsExactly(EXISTING_ONE_ID, GENERATED_ONE_ID, GENERATED_TWO_ID)
            .inOrder()
        // ADD retains the valid existing active profile; the source active was not selected.
        assertThat(profileRepository.getActiveProfileId()).isEqualTo(EXISTING_ONE_ID)
        val blocked = adapter.blockedImportedProfiles()
        assertThat(blocked.map { it.profileId })
            .containsExactly(GENERATED_ONE_ID, GENERATED_TWO_ID)
            .inOrder()
        assertThat(blocked.map { it.name }).containsExactly("Daily 2", "Daily 2 2").inOrder()
        assertThat(blocked.map { it.sourceDestinationKind })
            .containsExactly("device_folder", "api_endpoint")
            .inOrder()
    }

    @Test
    fun `apply maps replace mode and undo is one shot`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Daily")), EXISTING_ONE_ID)

        val applied = adapter.apply(
            SharedSetupV2ApplyRequest(
                plan = importPlan(),
                selectedBundleIds = listOf("profile-002"),
                mode = SharedSetupV2ApplyMode.REPLACE,
            ),
        )
        assertThat(applied.isSuccess).isTrue()
        // Fresh native ids are assigned in normalized selection order, so the sole selected
        // source profile receives the first generated id.
        assertThat(profileRepository.getProfiles().map { it.id })
            .containsExactly(GENERATED_ONE_ID)
            .inOrder()
        assertThat(profileRepository.getActiveProfileId()).isEqualTo(GENERATED_ONE_ID)
        assertThat(adapter.blockedImportedProfiles().map { it.profileId })
            .containsExactly(GENERATED_ONE_ID)

        assertThat(adapter.undo().isSuccess).isTrue()
        assertThat(profileRepository.getProfiles().map { it.id }).containsExactly(EXISTING_ONE_ID)
        assertThat(profileRepository.getActiveProfileId()).isEqualTo(EXISTING_ONE_ID)
        assertThat(adapter.blockedImportedProfiles()).isEmpty()

        val secondUndo = adapter.undo()
        assertThat(secondUndo.isFailure).isTrue()
        assertThat(secondUndo.exceptionOrNull())
            .isInstanceOf(SharedSetupV2ProfileTransactionException::class.java)
        assertThat(
            (secondUndo.exceptionOrNull() as SharedSetupV2ProfileTransactionException).reason,
        ).isEqualTo(SharedSetupV2ProfileTransactionFailure.NO_UNDO)
    }

    @Test
    fun `mandatory apple extension loader preserves foreign typed extensions by native id`() = runTest {
        assertThat(adapter.preservedAppleExtensionsByProfileId()).isEmpty()

        val applied = adapter.apply(
            SharedSetupV2ApplyRequest(
                plan = importPlan(preservedAppleExtension = APPLE_ARCHIVE_EXTENSION),
                selectedBundleIds = listOf("profile-001"),
                mode = SharedSetupV2ApplyMode.ADD,
            ),
        )
        assertThat(applied.isSuccess).isTrue()

        val preserved = adapter.preservedAppleExtensionsByProfileId()
        assertThat(preserved.keys).containsExactly(GENERATED_ONE_ID)
        assertThat(preserved[GENERATED_ONE_ID]).isEqualTo(APPLE_ARCHIVE_EXTENSION)

        // The loader feeds the explicit repository export source unchanged.
        val scheduleStore = mockk<ScheduledProfileEntryStore>()
        coEvery { scheduleStore.getEntries() } returns emptyList()
        val exportContext = RepositorySharedSetupV2ExportSource(
            profileRepository = profileRepository,
            scheduledProfileEntryStore = scheduleStore,
            appVersion = "test",
            preservedAppleExtensions = adapter::preservedAppleExtensionsByProfileId,
        ).load()
        assertThat(exportContext.preservedAppleExtensionsByProfileId)
            .containsExactly(GENERATED_ONE_ID, APPLE_ARCHIVE_EXTENSION)
    }

    @Test
    fun `apple extension loader and blocked visibility fail closed on an unreadable sidecar`() = runTest {
        dataStore.edit { preferences ->
            preferences[SharedSetupV2ProfilePersistence.profileStateKey] = "{not-json"
            // A blocked id forces the visibility read to consult the sidecar.
            preferences[SharedSetupV2ProfilePersistence.blockedProfileIdsKey] =
                setOf(GENERATED_ONE_ID)
        }

        assertThrows(Throwable::class.java) {
            kotlinx.coroutines.runBlocking { adapter.preservedAppleExtensionsByProfileId() }
        }
        assertThrows(Throwable::class.java) {
            kotlinx.coroutines.runBlocking { adapter.blockedImportedProfiles() }
        }
    }

    @Test
    fun `folder rebind clears a non active device folder import through the repository`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Daily")), EXISTING_ONE_ID)
        adapter.apply(
            SharedSetupV2ApplyRequest(
                plan = importPlan(),
                selectedBundleIds = listOf("profile-001"),
                mode = SharedSetupV2ApplyMode.ADD,
            ),
        ).getOrThrow()
        assertThat(profileRepository.getActiveProfileId()).isEqualTo(EXISTING_ONE_ID)

        val rebound = adapter.rebindBlockedFolder(
            profileId = GENERATED_ONE_ID,
            folderUri = "content://primary/tree/synthetic-docs",
            folderDisplayName = "Docs",
        )

        assertThat(rebound).isTrue()
        assertThat(profileRepository.isSharedSetupV2Blocked(GENERATED_ONE_ID)).isFalse()
        assertThat(
            profileRepository.profileById(GENERATED_ONE_ID)?.folderUri,
        ).isEqualTo("content://primary/tree/synthetic-docs")
        // The active profile rebind path was not taken.
        coVerify(exactly = 0) { coordinator.folderWasSelected(any(), any()) }
    }

    @Test
    fun `folder rebind routes the active profile through the coordinator staged rebind`() = runTest {
        // Emulate the coordinator's staged rebind: explicit picker binding via the repository.
        coEvery { coordinator.folderWasSelected(any(), any()) } coAnswers {
            profileRepository.bindFolder(
                id = GENERATED_ONE_ID,
                folderUri = firstArg(),
                folderDisplayName = secondArg(),
            )
            Unit
        }
        adapter.apply(
            SharedSetupV2ApplyRequest(
                plan = importPlan(),
                selectedBundleIds = listOf("profile-001"),
                mode = SharedSetupV2ApplyMode.REPLACE,
            ),
        ).getOrThrow()
        assertThat(profileRepository.getActiveProfileId()).isEqualTo(GENERATED_ONE_ID)

        val rebound = adapter.rebindBlockedFolder(
            profileId = GENERATED_ONE_ID,
            folderUri = "content://primary/tree/synthetic-docs",
            folderDisplayName = "Docs",
        )

        assertThat(rebound).isTrue()
        coVerify(exactly = 1) { coordinator.folderWasSelected("content://primary/tree/synthetic-docs", "Docs") }
        assertThat(profileRepository.isSharedSetupV2Blocked(GENERATED_ONE_ID)).isFalse()
    }

    @Test
    fun `api endpoint intent never clears through a folder rebind`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Daily")), EXISTING_ONE_ID)
        adapter.apply(
            SharedSetupV2ApplyRequest(
                plan = importPlan(),
                selectedBundleIds = listOf("profile-002"),
                mode = SharedSetupV2ApplyMode.ADD,
            ),
        ).getOrThrow()
        // The sole selection (the api_endpoint source profile) holds the first generated id.
        val apiImportId = GENERATED_ONE_ID

        val rebound = adapter.rebindBlockedFolder(
            profileId = apiImportId,
            folderUri = "content://primary/tree/synthetic-docs",
            folderDisplayName = "Docs",
        )

        assertThat(rebound).isFalse()
        assertThat(profileRepository.isSharedSetupV2Blocked(apiImportId)).isTrue()
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

    private fun importPlan(
        preservedAppleExtension: SharedSetupV2AppleExtension? = null,
    ): SharedSetupV2ImportPlan {
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
                preservedAppleExtensionsByProfileId = if (preservedAppleExtension == null) {
                    emptyMap()
                } else {
                    mapOf(SOURCE_ONE_ID to preservedAppleExtension)
                },
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

    private suspend fun seed(profiles: List<ExportProfile>, activeProfileId: String?) {
        dataStore.edit { preferences ->
            preferences[SharedSetupV2ProfilePersistence.profilesKey] =
                SharedSetupV2ProfilePersistence.json.encodeToString(
                    SharedSetupV2ProfilePersistence.profileListSerializer,
                    profiles,
                )
            activeProfileId?.let {
                preferences[SharedSetupV2ProfilePersistence.activeProfileIdKey] = it
            }
        }
    }

    private object EmptyRegistry : SharedSetupMetricRegistry {
        override val version: Int = 1
        override val sha256: String = "0".repeat(64)
        override val bySemanticId: Map<String, SharedSetupRegistryBinding> = emptyMap()
        override val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding> = emptyMap()
    }

    private companion object {
        const val NOW = 1_800_000_000_000L
        const val EXISTING_ONE_ID = "10000000-0000-4000-8000-000000000001"
        const val SOURCE_ONE_ID = "20000000-0000-4000-8000-000000000001"
        const val SOURCE_TWO_ID = "20000000-0000-4000-8000-000000000002"
        const val GENERATED_ONE_ID = "30000000-0000-4000-8000-000000000001"
        const val GENERATED_TWO_ID = "30000000-0000-4000-8000-000000000002"
        val APPLE_ARCHIVE_EXTENSION = SharedSetupV2AppleExtension(
            extensionVersion = SHARED_SETUP_V2_VERSION,
            export = SharedSetupV2AppleExport(
                organizeFormatsIntoFolders = true,
                archiveFiles = false,
                includeDataDictionary = true,
                summaryOnly = false,
                healthkitSourceArchive = "canonical_v1",
                generateRangeSummary = true,
            ),
            dailyNotes = SharedSetupV2AppleDailyNotes(only = false),
            schedule = null,
        )
    }
}
