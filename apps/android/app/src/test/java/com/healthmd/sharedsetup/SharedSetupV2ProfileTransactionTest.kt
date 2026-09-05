package com.healthmd.sharedsetup

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.mutablePreferencesOf
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.WriteMode
import io.mockk.mockk
import java.time.LocalDate
import java.time.ZoneId
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
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
    fun `Add with no valid native active chooses selected source active`() = runTest {
        seed(
            profiles = listOf(nativeProfile(EXISTING_ONE_ID, "Existing")),
            activeProfileId = "missing-active",
            schedules = emptyList(),
        )
        val result = transaction(GENERATED_ONE_ID, GENERATED_TWO_ID).apply(
            plan = importPlan(),
            selectedBundleIds = listOf("profile-001", "profile-002"),
            mode = SharedSetupV2ProfileImportMode.ADD,
        ).getOrThrow()

        assertThat(result.activeProfileId).isEqualTo(GENERATED_TWO_ID)
        assertThat(storedActiveId()).isEqualTo(GENERATED_TWO_ID)
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
    fun `Add enforces the native profile cap before writing any key`() = runTest {
        val profiles = (1..ExportProfileRules.MAX_PROFILES).map { index ->
            nativeProfile(
                id = "10000000-0000-4000-8000-${index.toString().padStart(12, '0')}",
                name = "Existing $index",
            )
        }
        seed(profiles, profiles.first().id, emptyList())
        dataStore.edit { it[SharedSetupV2ProfilePersistence.undoKey] = "prior-undo" }
        val before = snapshotBytes()

        val error = transaction(GENERATED_ONE_ID).apply(
            importPlan(),
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.ADD,
        ).exceptionOrNull() as SharedSetupV2ProfileTransactionException

        assertThat(error.reason)
            .isEqualTo(SharedSetupV2ProfileTransactionFailure.PROFILE_LIMIT_EXCEEDED)
        assertThat(snapshotBytes()).isEqualTo(before)
    }

    @Test
    fun `oversized preservation sidecar fails closed before mutation`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Before")), EXISTING_ONE_ID, emptyList())
        dataStore.edit {
            it[SharedSetupV2ProfilePersistence.profileStateKey] =
                "x".repeat(4 * 1024 * 1024 + 1)
            it[SharedSetupV2ProfilePersistence.undoKey] = "prior-undo"
        }
        val before = snapshotBytes()

        val error = transaction(GENERATED_ONE_ID).apply(
            importPlan(),
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.REPLACE,
        ).exceptionOrNull() as SharedSetupV2ProfileTransactionException

        assertThat(error.reason)
            .isEqualTo(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE)
        assertThat(snapshotBytes()).isEqualTo(before)
    }

    @Test
    fun `previous logical state over eight MiB cannot become Undo and no key changes`() = runTest {
        val oversizedProfile = nativeProfile(EXISTING_ONE_ID, "Before").copy(
            settingsSnapshotJson = "x".repeat(SHARED_SETUP_V2_UNDO_MAX_BYTES),
        )
        seed(listOf(oversizedProfile), EXISTING_ONE_ID, emptyList())
        dataStore.edit { it[SharedSetupV2ProfilePersistence.undoKey] = "prior-undo" }
        val before = snapshotBytes()

        val error = transaction(GENERATED_ONE_ID).apply(
            importPlan(),
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.REPLACE,
        ).exceptionOrNull() as SharedSetupV2ProfileTransactionException

        assertThat(error.reason)
            .isEqualTo(SharedSetupV2ProfileTransactionFailure.UNDO_LIMIT_EXCEEDED)
        assertThat(snapshotBytes()).isEqualTo(before)
    }

    @Test
    fun `candidate preservation sidecar over four MiB fails before mutation`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Before")), EXISTING_ONE_ID, emptyList())
        val source = importPlan().profiles.first().source
        fun sidecar(customText: String) = SharedSetupV2StoredProfileState(
            profiles = listOf(
                SharedSetupV2StoredProfileStateRow(
                    profileId = EXISTING_ONE_ID,
                    sourceBundleId = source.bundleId,
                    sourceProfile = source.copy(
                        presentation = source.presentation.copy(
                            markdown = source.presentation.markdown.copy(
                                style = "custom",
                                customText = customText,
                            ),
                        ),
                    ),
                    unsupportedSemanticIds = emptyList(),
                ),
            ),
        )
        val emptyBytes = checkNotNull(
            SharedSetupV2ProfilePersistence.encodeProfileState(sidecar("")),
        ).encodeToByteArray().size
        val retainedRaw = checkNotNull(
            SharedSetupV2ProfilePersistence.encodeProfileState(
                sidecar(
                    "x".repeat(
                        SHARED_SETUP_V2_PROFILE_STATE_MAX_BYTES - emptyBytes - 16,
                    ),
                ),
            ),
        )
        dataStore.edit {
            it[SharedSetupV2ProfilePersistence.profileStateKey] = retainedRaw
            it[SharedSetupV2ProfilePersistence.blockedProfileIdsKey] = setOf(EXISTING_ONE_ID)
            it[SharedSetupV2ProfilePersistence.undoKey] = "prior-undo"
        }
        val before = snapshotBytes()

        val error = transaction(GENERATED_ONE_ID).apply(
            importPlan(),
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.ADD,
        ).exceptionOrNull() as SharedSetupV2ProfileTransactionException

        assertThat(error.reason)
            .isEqualTo(SharedSetupV2ProfileTransactionFailure.SIDECAR_LIMIT_EXCEEDED)
        assertThat(snapshotBytes()).isEqualTo(before)
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
    fun `central gate clears only for explicit exact folder or credential-confirmed API rebind`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Before")), EXISTING_ONE_ID, emptyList())
        val transaction = transaction(GENERATED_ONE_ID, GENERATED_TWO_ID)
        transaction.apply(
            importPlan(),
            listOf("profile-001", "profile-002"),
            SharedSetupV2ProfileImportMode.ADD,
        ).getOrThrow()
        val repository = ExportProfileRepository(dataStore, mockk<Context>(relaxed = true))

        assertThat(repository.isSharedSetupV2Blocked(GENERATED_ONE_ID)).isTrue()
        assertThat(repository.isSharedSetupV2Blocked(GENERATED_TWO_ID)).isTrue()
        assertThat(repository.activeSharedSetupV2ExecutionAccess())
            .isEqualTo(SharedSetupV2ProfileExecutionAccess.Allowed)
        assertThat(repository.activate(GENERATED_ONE_ID)).isFalse()
        assertThat(storedActiveId()).isEqualTo(EXISTING_ONE_ID)

        val importedSource = checkNotNull(repository.profileById(GENERATED_ONE_ID))
        val duplicate = repository.add(
            name = importedSource.name,
            settingsSnapshotJson = importedSource.settingsSnapshotJson,
            target = importedSource.target,
            apiEndpointUrl = importedSource.apiEndpointUrl,
            folderUri = importedSource.folderUri,
            folderDisplayName = importedSource.folderDisplayName,
            derivedFromProfileId = importedSource.id,
        )
        assertThat(repository.isSharedSetupV2Blocked(duplicate.id)).isTrue()
        assertThat(repository.activate(duplicate.id)).isFalse()
        assertThat(transaction.storedProfileState().getOrThrow()!!.profiles.map { it.profileId })
            .containsExactly(GENERATED_ONE_ID, GENERATED_TWO_ID, duplicate.id)
            .inOrder()

        assertThat(
            repository.bindFolder(
                GENERATED_ONE_ID,
                "content://local.provider/tree/health",
                "Local Health",
            ),
        ).isTrue()
        assertThat(repository.isSharedSetupV2Blocked(GENERATED_ONE_ID)).isFalse()
        assertThat(repository.activeSharedSetupV2ExecutionAccess())
            .isEqualTo(SharedSetupV2ProfileExecutionAccess.Allowed)
        assertThat(repository.activate(GENERATED_ONE_ID)).isTrue()

        val endpoint = "https://local.invalid/confirmed"
        val apiSnapshot = AndroidExportSettingsSnapshot.capture(
            baseSettings().copy(
                exportTarget = ExportTarget.API_ENDPOINT,
                scheduledExportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = endpoint,
            ),
            pin = null,
            zone = ZoneId.of("UTC"),
        )
        assertThat(
            repository.applyEditorUpdate(
                id = GENERATED_TWO_ID,
                rawName = "Daily 2 2",
                settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(apiSnapshot),
                target = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = endpoint,
                folderUri = null,
                folderDisplayName = null,
            ),
        ).isNotNull()
        // URL/editor persistence alone is deliberately insufficient.
        assertThat(repository.isSharedSetupV2Blocked(GENERATED_TWO_ID)).isTrue()
        assertThat(repository.activate(GENERATED_TWO_ID)).isFalse()

        assertThat(
            repository.clearSharedSetupV2BlockAfterApiCredentialConfirmation(GENERATED_TWO_ID),
        ).isTrue()
        assertThat(repository.isSharedSetupV2Blocked(GENERATED_TWO_ID)).isFalse()
        assertThat(repository.activate(GENERATED_TWO_ID)).isTrue()
    }

    @Test
    fun `folder selection cannot reinterpret connected Mac intent or clear its block`() = runTest {
        val original = importPlan()
        val connectedSource = original.source.copy(
            profiles = original.source.profiles.mapIndexed { index, profile ->
                if (index == 0) {
                    profile.copy(
                        destination = SharedSetupV2Destination(
                            kind = "connected_mac",
                            apiEndpoint = null,
                        ),
                    )
                } else {
                    profile
                }
            },
        )
        val plan = SharedSetupV2Mapper(EmptyRegistry).planImport(connectedSource)
        val transaction = transaction(GENERATED_ONE_ID)
        transaction.apply(
            plan,
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.REPLACE,
        ).getOrThrow()
        val repository = ExportProfileRepository(dataStore, mockk<Context>(relaxed = true))

        assertThat(
            repository.bindFolder(
                GENERATED_ONE_ID,
                "content://local.provider/tree/health",
                "Local Health",
            ),
        ).isTrue()

        assertThat(repository.isSharedSetupV2Blocked(GENERATED_ONE_ID)).isTrue()
        assertThat(repository.activeSharedSetupV2ExecutionAccess())
            .isEqualTo(SharedSetupV2ProfileExecutionAccess.DestinationRebindRequired)
        assertThat(repository.activate(GENERATED_ONE_ID)).isFalse()
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
    fun `post-commit verification failure compare-and-set rolls back all keys and prior Undo`() = runTest {
        val previousProfiles = listOf(nativeProfile(EXISTING_ONE_ID, "Before"))
        seed(previousProfiles, EXISTING_ONE_ID, emptyList())
        dataStore.edit { it[SharedSetupV2ProfilePersistence.undoKey] = "prior-undo" }
        val faulting = OneReadVerificationFaultDataStore(dataStore)
        val transaction = transactionWithStore(faulting, GENERATED_ONE_ID)

        val error = transaction.apply(
            importPlan(),
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.REPLACE,
        ).exceptionOrNull() as SharedSetupV2ProfileTransactionException

        assertThat(error.reason)
            .isEqualTo(SharedSetupV2ProfileTransactionFailure.COMMIT_VERIFICATION_FAILED)
        assertThat(storedProfiles()).isEqualTo(previousProfiles)
        assertThat(storedActiveId()).isEqualTo(EXISTING_ONE_ID)
        assertThat(storedSchedules()).isEmpty()
        assertThat(storedBlockedIds()).isEmpty()
        assertThat(dataStore.data.first()[SharedSetupV2ProfilePersistence.profileStateKey]).isNull()
        assertThat(dataStore.data.first()[SharedSetupV2ProfilePersistence.undoKey])
            .isEqualTo("prior-undo")
    }

    @Test
    fun `concurrent post-commit change makes rollback fail explicitly without overwriting it`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Before")), EXISTING_ONE_ID, emptyList())
        val concurrentlyMutating = ConcurrentMutationAfterCommitDataStore(dataStore)
        val transaction = transactionWithStore(concurrentlyMutating, GENERATED_ONE_ID)

        val error = transaction.apply(
            importPlan(),
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.REPLACE,
        ).exceptionOrNull() as SharedSetupV2ProfileTransactionException

        assertThat(error.reason)
            .isEqualTo(SharedSetupV2ProfileTransactionFailure.ROLLBACK_NOT_VERIFIED)
        assertThat(storedActiveId()).isEqualTo(CONCURRENT_ACTIVE_ID)
        assertThat(storedProfiles().map { it.id }).containsExactly(GENERATED_ONE_ID)
    }

    @Test
    fun `apply finishes its one-edit commit and verification after caller cancellation`() = runTest {
        seed(listOf(nativeProfile(EXISTING_ONE_ID, "Before")), EXISTING_ONE_ID, emptyList())
        val commitStarted = CompletableDeferred<Unit>()
        val releaseCommit = CompletableDeferred<Unit>()
        val blocking = BlockingAfterCommitDataStore(dataStore, commitStarted, releaseCommit)
        val transaction = transactionWithStore(blocking, GENERATED_ONE_ID)
        var outcome: Result<SharedSetupV2ProfileApplyResult>? = null
        val apply = launch {
            outcome = transaction.apply(
                importPlan(),
                listOf("profile-001"),
                SharedSetupV2ProfileImportMode.REPLACE,
            )
        }
        commitStarted.await()

        apply.cancel()
        releaseCommit.complete(Unit)
        apply.join()

        assertThat(outcome?.isSuccess).isTrue()
        assertThat(storedProfiles().map { it.id }).containsExactly(GENERATED_ONE_ID)
        assertThat(storedBlockedIds()).containsExactly(GENERATED_ONE_ID)
        assertThat(dataStore.data.first()[SharedSetupV2ProfilePersistence.undoKey]).isNotNull()
    }

    @Test
    fun `undo completes restoration and one-shot removal after caller cancellation`() = runTest {
        val previous = listOf(nativeProfile(EXISTING_ONE_ID, "Before"))
        seed(previous, EXISTING_ONE_ID, emptyList())
        val restoreStarted = CompletableDeferred<Unit>()
        val releaseRestore = CompletableDeferred<Unit>()
        val blocking = BlockingAfterCommitDataStore(
            delegate = dataStore,
            commitStarted = restoreStarted,
            releaseCommit = releaseRestore,
            blockedUpdateNumber = 2,
        )
        val transaction = transactionWithStore(blocking, GENERATED_ONE_ID)
        transaction.apply(
            importPlan(),
            listOf("profile-001"),
            SharedSetupV2ProfileImportMode.REPLACE,
        ).getOrThrow()
        var outcome: Result<Unit>? = null
        val undo = launch { outcome = transaction.undo() }
        restoreStarted.await()

        undo.cancel()
        releaseRestore.complete(Unit)
        undo.join()

        assertThat(outcome?.isSuccess).isTrue()
        assertThat(storedProfiles()).isEqualTo(previous)
        assertThat(storedActiveId()).isEqualTo(EXISTING_ONE_ID)
        assertThat(dataStore.data.first()[SharedSetupV2ProfilePersistence.undoKey]).isNull()
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

    private fun transaction(vararg ids: String): SharedSetupV2ProfileTransaction =
        transactionWithStore(dataStore, *ids)

    private fun transactionWithStore(
        store: DataStore<Preferences>,
        vararg ids: String,
    ): SharedSetupV2ProfileTransaction {
        val queue = ArrayDeque(ids.toList())
        return SharedSetupV2ProfileTransaction(
            dataStore = store,
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

    private suspend fun snapshotBytes(): Map<Preferences.Key<*>, Any> =
        dataStore.data.first().asMap()

    private suspend fun storedActiveId(): String? =
        dataStore.data.first()[SharedSetupV2ProfilePersistence.activeProfileIdKey]

    private suspend fun storedBlockedIds(): Set<String> =
        dataStore.data.first()[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()

    private class OneReadVerificationFaultDataStore(
        private val delegate: DataStore<Preferences>,
    ) : DataStore<Preferences> {
        private val updates = AtomicInteger(0)
        private val faultNextRead = AtomicBoolean(false)

        override val data: Flow<Preferences> = delegate.data.map { preferences ->
            if (faultNextRead.compareAndSet(true, false)) {
                preferences.mutableCopy().apply {
                    this[SharedSetupV2ProfilePersistence.activeProfileIdKey] =
                        "verification-corrupt"
                }
            } else {
                preferences
            }
        }

        override suspend fun updateData(
            transform: suspend (t: Preferences) -> Preferences,
        ): Preferences = delegate.updateData(transform).also {
            if (updates.incrementAndGet() == 1) faultNextRead.set(true)
        }
    }

    private class ConcurrentMutationAfterCommitDataStore(
        private val delegate: DataStore<Preferences>,
    ) : DataStore<Preferences> {
        private val updates = AtomicInteger(0)
        override val data: Flow<Preferences> = delegate.data

        override suspend fun updateData(
            transform: suspend (t: Preferences) -> Preferences,
        ): Preferences {
            val result = delegate.updateData(transform)
            if (updates.incrementAndGet() == 1) {
                delegate.updateData { preferences ->
                    preferences.mutableCopy().apply {
                        this[SharedSetupV2ProfilePersistence.activeProfileIdKey] =
                            CONCURRENT_ACTIVE_ID
                    }
                }
            }
            return result
        }
    }

    private class BlockingAfterCommitDataStore(
        private val delegate: DataStore<Preferences>,
        private val commitStarted: CompletableDeferred<Unit>,
        private val releaseCommit: CompletableDeferred<Unit>,
        private val blockedUpdateNumber: Int = 1,
    ) : DataStore<Preferences> {
        private val updates = AtomicInteger(0)
        override val data: Flow<Preferences> = delegate.data

        override suspend fun updateData(
            transform: suspend (t: Preferences) -> Preferences,
        ): Preferences = delegate.updateData(transform).also {
            if (updates.incrementAndGet() == blockedUpdateNumber) {
                commitStarted.complete(Unit)
                releaseCommit.await()
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
        const val EXISTING_TWO_ID = "10000000-0000-4000-8000-000000000002"
        const val SOURCE_ONE_ID = "20000000-0000-4000-8000-000000000001"
        const val SOURCE_TWO_ID = "20000000-0000-4000-8000-000000000002"
        const val GENERATED_ONE_ID = "30000000-0000-4000-8000-000000000001"
        const val GENERATED_TWO_ID = "30000000-0000-4000-8000-000000000002"
        const val CONCURRENT_ACTIVE_ID = "concurrent-change"
    }
}

@Suppress("UNCHECKED_CAST")
private fun Preferences.mutableCopy(): MutablePreferences = mutablePreferencesOf().also { copy ->
    asMap().forEach { (key, value) ->
        copy[key as Preferences.Key<Any>] = value
    }
}
