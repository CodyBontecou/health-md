package com.healthmd.sharedsetup

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.mutablePreferencesOf
import androidx.datastore.preferences.core.stringPreferencesKey
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
import java.io.File
import java.time.ZoneId
import java.util.ArrayDeque
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Cross-platform transaction conformance: drives the native Android Add/Replace/Undo
 * transaction against the frozen language-neutral scenario fixture
 * `packages/contracts/shared-setup/v2/fixtures/transaction-scenarios-v1.json` and asserts the
 * fixture's expected logical states exactly.
 *
 * Sentinel mapping: the scenario names synthetic native identities
 * (`native-import-profile-101`, ...). Native tests must not copy those strings into persisted
 * native identity; instead each sentinel maps to one deterministic canonical native UUID minted
 * by the injectable ID factory in normalized document order. Expected states are compared by
 * translating their sentinels through the same mapping, so minted IDs stay fresh, distinct, and
 * stable across the comparison exactly as the contract's scenario rules define. Schedule rows
 * carry no native ID on Android; `native-import-schedule-101` identifies the disabled row of the
 * profile that `generated_schedule_ids` maps it to.
 */
class SharedSetupV2TransactionScenariosTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>

    private val destinationMarkerKey = stringPreferencesKey("conformance_destination_store_marker")
    private val secureMarkerKey = stringPreferencesKey("conformance_secure_store_marker")

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("shared-setup-v2-scenarios.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = { file },
        )
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    // ---------------------------------------------------------------------------------------------
    // Frozen scenario fixture access
    // ---------------------------------------------------------------------------------------------

    private val scenario: JsonObject by lazy {
        val fixture = contractFileOrNull(
            "packages/contracts/shared-setup/v2/fixtures/transaction-scenarios-v1.json",
        )
        if (fixture == null) {
            throw org.junit.AssumptionViolatedException(
                "transaction-scenarios-v1.json is absent; skipping frozen scenario conformance",
            )
        }
        Json.parseToJsonElement(fixture.readText()).jsonObject.let { root ->
            root.jsonObject("scenario").also { scenario ->
                check(scenario.string("name") == "selection-normalized-add-replace-undo")
                check(scenario.string("scope") == "synthetic_local_transaction_test_only")
            }
        }
    }

    private fun contractFileOrNull(path: String): File? {
        var directory = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (true) {
            val candidate = File(directory, path)
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: return null
        }
    }

    // ---------------------------------------------------------------------------------------------
    // Sentinel -> native identity mapping (proven against the fixture itself)
    // ---------------------------------------------------------------------------------------------

    private val sentinelToNativeId: Map<String, String> = mapOf(
        "native-existing-profile-001" to EXISTING_ONE_ID,
        "native-existing-profile-002" to EXISTING_TWO_ID,
        "native-import-profile-101" to GENERATED_ONE_ID,
        "native-import-profile-103" to GENERATED_TWO_ID,
    )

    private fun nativeIdOf(sentinel: String?): String = sentinelToNativeId.getValue(sentinel!!)

    private fun requireSentinelMappingMatchesFixture() {
        val generatedProfiles = scenario.jsonObject("generated_profile_ids")
        assertThat(generatedProfiles.string("profile-001"))
            .isEqualTo("native-import-profile-101")
        assertThat(generatedProfiles.string("profile-003"))
            .isEqualTo("native-import-profile-103")
        val generatedSchedules = scenario.jsonObject("generated_schedule_ids")
        assertThat(generatedSchedules.string("profile-001"))
            .isEqualTo("native-import-schedule-101")
        assertThat(generatedSchedules.keys).containsExactly("profile-001")
    }

    // ---------------------------------------------------------------------------------------------
    // Scenario-driven plan construction
    // ---------------------------------------------------------------------------------------------

    private val scenarioRegistry: SharedSetupMetricRegistry = object : SharedSetupMetricRegistry {
        override val version: Int = 1
        override val sha256: String = "b".repeat(64)
        override val bySemanticId: Map<String, SharedSetupRegistryBinding> = listOf(
            SharedSetupRegistryBinding(
                semanticId = "steps",
                appleSelectionId = "steps",
                androidSelectionId = "steps",
                equivalence = "platform_exact_or_unavailable",
            ),
            SharedSetupRegistryBinding(
                semanticId = "active_energy",
                appleSelectionId = "active_energy",
                androidSelectionId = "active_calories",
                equivalence = "mapped_alias",
            ),
        ).associateBy { it.semanticId }
        override val byAndroidSelectionId: Map<String, SharedSetupRegistryBinding> =
            bySemanticId.values.mapNotNull { binding ->
                binding.androidSelectionId?.let { it to binding }
            }.toMap()
    }

    private val scenarioCodec: SharedSetupV2Codec by lazy { SharedSetupV2Codec(scenarioRegistry) }
    private val scenarioMapper: SharedSetupV2Mapper by lazy { SharedSetupV2Mapper(scenarioRegistry) }

    private fun scenarioDocument(): SharedSetupV2 {
        val bytes = Json.encodeToString(
            JsonObject.serializer(),
            scenario.jsonObject("source_document"),
        ).encodeToByteArray()
        return when (val decoded = scenarioCodec.decode(bytes)) {
            is SharedSetupVersionedDecodeResult.Valid -> when (val document = decoded.document) {
                is SharedSetupDecodedDocument.V2 -> document.document
                else -> error("Frozen scenario source document is not a v2 document")
            }
            is SharedSetupVersionedDecodeResult.Invalid ->
                error("Frozen scenario source document failed native decode: ${decoded.message}")
        }
    }

    private fun scenarioPlan(): SharedSetupV2ImportPlan = scenarioMapper.planImport(scenarioDocument())

    // ---------------------------------------------------------------------------------------------
    // Scenario-driven seeding of the existing native state
    // ---------------------------------------------------------------------------------------------

    private fun existingState(): JsonObject = scenario.jsonObject("existing_state")

    private fun existingProfiles(): List<ExportProfile> =
        existingState().jsonArray("profiles").map { row ->
            val profile = row.jsonObject
            val target = androidTarget(profile.string("destination_intent"))
            ExportProfile(
                id = nativeIdOf(profile.string("profile_id")),
                name = profile.string("name"),
                settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
                    AndroidExportSettingsSnapshot.capture(
                        baseSettings(),
                        pin = null,
                        zone = ZoneId.of("UTC"),
                    ),
                ),
                target = target,
                apiEndpointUrl = profile.stringOrNull("api_endpoint_binding_id")
                    ?.let { "https://synthetic.invalid/$it" },
                folderUri = profile.stringOrNull("folder_binding_id")
                    ?.let { "content://synthetic/local/$it" },
                folderDisplayName = null,
                isMigrationDefault = false,
                createdAtEpochMillis = 10,
                updatedAtEpochMillis = 11,
            )
        }

    private fun existingSchedules(): List<ScheduledProfileEntry> =
        existingState().jsonArray("schedules").map { row ->
            val schedule = row.jsonObject
            ScheduledProfileEntry(
                profileId = nativeIdOf(schedule.string("profile_id")),
                isEnabled = schedule.boolean("is_enabled"),
                anchorEpochDay = 20_001,
                weekdayIso = 5,
                hour = 7,
                minute = 30,
                cadenceValue = 3,
                cadenceUnit = ScheduledProfileCadenceUnit.MONTH,
                lookbackDays = 5,
                zoneId = "UTC",
                lastSuccessEpochMillis = 1_234_567L,
                lastRefreshSuccessEpochMillis = 2_345_678L,
                pendingExports = emptyList(),
            )
        }

    private suspend fun seedExistingState() {
        val sidecar = SharedSetupV2StoredProfileState(
            profiles = existingState().jsonObject("sidecar").jsonArray("profiles").map { row ->
                val sidecarRow = row.jsonObject
                SharedSetupV2StoredProfileStateRow(
                    profileId = nativeIdOf(sidecarRow.string("profile_id")),
                    sourceBundleId = sidecarRow.string("source_bundle_id"),
                    sourceProfile = scenarioDocument().profiles.first {
                        it.bundleId == sidecarRow.string("source_bundle_id")
                    },
                    unsupportedSemanticIds = sidecarRow.jsonArray("unsupported_semantic_ids")
                        .map { it.jsonPrimitive.content },
                )
            },
        )
        dataStore.edit { preferences ->
            preferences[SharedSetupV2ProfilePersistence.profilesKey] =
                SharedSetupV2ProfilePersistence.json.encodeToString(
                    SharedSetupV2ProfilePersistence.profileListSerializer,
                    existingProfiles(),
                )
            preferences[SharedSetupV2ProfilePersistence.activeProfileIdKey] =
                nativeIdOf(existingState().string("active_profile_id"))
            preferences[SharedSetupV2ProfilePersistence.scheduledProfileEntriesKey] =
                SharedSetupV2ProfilePersistence.json.encodeToString(
                    SharedSetupV2ProfilePersistence.scheduleListSerializer,
                    existingSchedules(),
                )
            preferences[SharedSetupV2ProfilePersistence.profileStateKey] =
                requireNotNull(SharedSetupV2ProfilePersistence.encodeProfileState(sidecar))
            // A full scenario re-seed must also reset the v2 transaction keys: a prior apply in
            // this test leaves blocked IDs and a one-shot Undo snapshot that would otherwise
            // fail the transaction's stored-state validation fail-closed.
            preferences.remove(SharedSetupV2ProfilePersistence.blockedProfileIdsKey)
            preferences.remove(SharedSetupV2ProfilePersistence.undoKey)
            val environment = scenario.jsonObject("local_environment")
            preferences[destinationMarkerKey] = environment.string("destination_store_marker")
            preferences[secureMarkerKey] = environment.string("secure_store_marker")
        }
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
            registry = scenarioRegistry,
            nativeId = { queue.removeFirst() },
            nowEpochMillis = { NOW },
            localZoneId = { ZoneId.of("America/New_York") },
            testing = Unit,
        )
    }

    private fun androidTarget(destinationIntent: String): ExportTarget = when (destinationIntent) {
        "api_endpoint" -> ExportTarget.API_ENDPOINT
        else -> ExportTarget.DEVICE_FOLDER
    }

    // ---------------------------------------------------------------------------------------------
    // Shared expected-state assertions
    // ---------------------------------------------------------------------------------------------

    private suspend fun assertProfilesMatchExpectedState(stateName: String) {
        val state = scenario.jsonObject("expected_$stateName")
        val expectedRows = state.jsonArray("profiles").map { it.jsonObject }
        val profiles = storedProfiles()

        assertThat(profiles.map { it.id })
            .containsExactlyElementsIn(expectedRows.map { nativeIdOf(it.string("profile_id")) })
            .inOrder()
        assertThat(profiles.map { it.name })
            .containsExactlyElementsIn(expectedRows.map { it.string("name") })
            .inOrder()
        profiles.zip(expectedRows).forEach { (native, expected) ->
            assertThat(native.target).isEqualTo(androidTarget(expected.string("destination_intent")))
            val isImported = expected.stringOrNull("settings_source_bundle_id") != null
            if (isImported) {
                // Imported destination intent is inert: no folder or API binding is inherited.
                assertThat(native.folderUri).isNull()
                assertThat(native.folderDisplayName).isNull()
                assertThat(native.apiEndpointUrl).isNull()
            } else {
                expected.stringOrNull("folder_binding_id")?.let { sentinel ->
                    assertThat(native.folderUri).isEqualTo("content://synthetic/local/$sentinel")
                }
                expected.stringOrNull("api_endpoint_binding_id")?.let { sentinel ->
                    assertThat(native.apiEndpointUrl).isEqualTo("https://synthetic.invalid/$sentinel")
                }
            }
        }
        assertThat(storedActiveId())
            .isEqualTo(nativeIdOf(state.string("active_profile_id")))
    }

    private suspend fun assertBlockedAndSidecarMatchExpectedState(stateName: String) {
        val state = scenario.jsonObject("expected_$stateName")
        assertThat(storedBlockedIds()).containsExactlyElementsIn(
            state.jsonArray("blocked_profile_ids").map { nativeIdOf(it.jsonPrimitive.content) },
        )
        assertThat(dataStore.data.first()[SharedSetupV2ProfilePersistence.undoKey]).isNotNull()

        val document = scenarioDocument()
        val expectedRows = state.jsonObject("sidecar").jsonArray("profiles").map { it.jsonObject }
        val sidecar = requireNotNull(
            transactionWithStore(dataStore).storedProfileState().getOrThrow(),
        )
        assertThat(sidecar.version).isEqualTo(1)
        assertThat(sidecar.profiles.map { it.profileId })
            .containsExactlyElementsIn(expectedRows.map { nativeIdOf(it.string("profile_id")) })
            .inOrder()
        sidecar.profiles.zip(expectedRows).forEach { (row, expected) ->
            assertThat(row.sourceBundleId).isEqualTo(expected.string("source_bundle_id"))
            assertThat(row.unsupportedSemanticIds)
                .isEqualTo(
                    expected.jsonArray("unsupported_semantic_ids").map { it.jsonPrimitive.content },
                )
            // The complete closed source v2 DTO is preserved per profile, including any
            // foreign typed extension and unsupported semantic meaning.
            assertThat(row.sourceProfile)
                .isEqualTo(document.profiles.first { it.bundleId == row.sourceBundleId })
        }
    }

    private suspend fun assertImportedScheduleRowsMatchExpectedState(stateName: String) {
        val state = scenario.jsonObject("expected_$stateName")
        val expectedRows = state.jsonArray("schedules").map { it.jsonObject }
        val schedules = storedSchedules()
        val existingByProfile = existingSchedules().associateBy { it.profileId }

        assertThat(schedules.map { it.profileId })
            .containsExactlyElementsIn(expectedRows.map { nativeIdOf(it.string("profile_id")) })
            .inOrder()
        schedules.zip(expectedRows).forEach { (native, expected) ->
            assertThat(native.isEnabled).isEqualTo(expected.boolean("is_enabled"))
            if (expected.string("schedule_id").startsWith("native-import-")) {
                // Imported schedules are always disabled with empty runtime-local state.
                assertThat(native.lastSuccessEpochMillis).isNull()
                assertThat(native.lastRefreshSuccessEpochMillis).isNull()
                assertThat(native.pendingExports).isEmpty()
            } else {
                // Existing schedule rows are preserved exactly, runtime state included.
                assertThat(native).isEqualTo(existingByProfile.getValue(native.profileId))
            }
        }
    }

    private suspend fun assertExistingStateFullyRestored() {
        assertThat(storedProfiles()).isEqualTo(existingProfiles())
        assertThat(storedActiveId()).isEqualTo(nativeIdOf(existingState().string("active_profile_id")))
        assertThat(storedSchedules()).isEqualTo(existingSchedules())
        assertThat(storedBlockedIds()).isEmpty()
        assertThat(
            transactionWithStore(dataStore).storedProfileState().getOrThrow(),
        ).isEqualTo(
            SharedSetupV2StoredProfileState(
                profiles = existingState().jsonObject("sidecar").jsonArray("profiles").map { row ->
                    val sidecarRow = row.jsonObject
                    SharedSetupV2StoredProfileStateRow(
                        profileId = nativeIdOf(sidecarRow.string("profile_id")),
                        sourceBundleId = sidecarRow.string("source_bundle_id"),
                        sourceProfile = scenarioDocument().profiles.first {
                            it.bundleId == sidecarRow.string("source_bundle_id")
                        },
                        unsupportedSemanticIds = sidecarRow.jsonArray("unsupported_semantic_ids")
                            .map { it.jsonPrimitive.content },
                    )
                },
            ),
        )
    }

    private suspend fun assertLocalEnvironmentUnchanged() {
        val environment = scenario.jsonObject("expected_unmodified_local_environment")
        val preferences = dataStore.data.first()
        assertThat(preferences[destinationMarkerKey])
            .isEqualTo(environment.string("destination_store_marker"))
        assertThat(preferences[secureMarkerKey])
            .isEqualTo(environment.string("secure_store_marker"))
    }

    // ---------------------------------------------------------------------------------------------
    // Tests
    // ---------------------------------------------------------------------------------------------

    @Test
    fun `add reproduces the frozen scenario expected state`() = runTest {
        requireSentinelMappingMatchesFixture()
        seedExistingState()
        val callerSelection = scenario.jsonArray("caller_selection").map { it.jsonPrimitive.content }
        val normalizedSelection = scenario.jsonArray("normalized_selection")
            .map { it.jsonPrimitive.content }
        assertThat(callerSelection).isNotEqualTo(normalizedSelection)

        val result = transaction(GENERATED_ONE_ID, GENERATED_TWO_ID).apply(
            plan = scenarioPlan(),
            selectedBundleIds = callerSelection,
            mode = SharedSetupV2ProfileImportMode.ADD,
        ).getOrThrow()

        // Caller order never determines persistence order: selection is normalized into
        // source document order.
        assertThat(result.selectedBundleIds).isEqualTo(normalizedSelection)
        assertThat(result.nativeProfileIdsByBundleId)
            .containsExactly("profile-001", GENERATED_ONE_ID, "profile-003", GENERATED_TWO_ID)
            .inOrder()

        // Existing schedule row is preserved byte-for-byte in Add mode.
        val existingSchedule = existingSchedules().single()
        assertThat(storedSchedules().first()).isEqualTo(existingSchedule)

        assertProfilesMatchExpectedState("add_state")
        assertBlockedAndSidecarMatchExpectedState("add_state")
        assertLocalEnvironmentUnchanged()
    }

    @Test
    fun `replace reproduces the frozen scenario expected state`() = runTest {
        requireSentinelMappingMatchesFixture()
        seedExistingState()
        val callerSelection = scenario.jsonArray("caller_selection").map { it.jsonPrimitive.content }

        val result = transaction(GENERATED_ONE_ID, GENERATED_TWO_ID).apply(
            plan = scenarioPlan(),
            selectedBundleIds = callerSelection,
            mode = SharedSetupV2ProfileImportMode.REPLACE,
        ).getOrThrow()

        assertThat(result.selectedBundleIds)
            .isEqualTo(scenario.jsonArray("normalized_selection").map { it.jsonPrimitive.content })
        assertThat(result.activeProfileId).isEqualTo(GENERATED_TWO_ID)

        assertProfilesMatchExpectedState("replace_state")
        assertBlockedAndSidecarMatchExpectedState("replace_state")
        assertLocalEnvironmentUnchanged()
    }

    @Test
    fun `imported schedules materialize disabled with empty runtime state per the frozen scenario`() = runTest {
        requireSentinelMappingMatchesFixture()
        seedExistingState()
        val callerSelection = scenario.jsonArray("caller_selection").map { it.jsonPrimitive.content }

        transaction(GENERATED_ONE_ID, GENERATED_TWO_ID).apply(
            plan = scenarioPlan(),
            selectedBundleIds = callerSelection,
            mode = SharedSetupV2ProfileImportMode.ADD,
        ).getOrThrow()
        assertImportedScheduleRowsMatchExpectedState("add_state")

        seedExistingState()
        transaction(GENERATED_ONE_ID, GENERATED_TWO_ID).apply(
            plan = scenarioPlan(),
            selectedBundleIds = callerSelection,
            mode = SharedSetupV2ProfileImportMode.REPLACE,
        ).getOrThrow()
        assertImportedScheduleRowsMatchExpectedState("replace_state")
    }

    @Test
    fun `failed apply restores and verifies the exact existing state and prior undo`() = runTest {
        requireSentinelMappingMatchesFixture()
        seedExistingState()
        dataStore.edit { it[SharedSetupV2ProfilePersistence.undoKey] = PRIOR_UNDO }
        val rollback = scenario.jsonObject("expected_failed_apply_rollback")
        assertThat(rollback.boolean("verification_required")).isTrue()
        assertThat(rollback.boolean("previous_undo_restored")).isTrue()
        val faulting = OneReadVerificationFaultDataStore(dataStore)

        val error = transactionWithStore(faulting, GENERATED_ONE_ID, GENERATED_TWO_ID).apply(
            scenarioPlan(),
            scenario.jsonArray("caller_selection").map { it.jsonPrimitive.content },
            SharedSetupV2ProfileImportMode.ADD,
        ).exceptionOrNull() as SharedSetupV2ProfileTransactionException

        assertThat(error.reason)
            .isEqualTo(SharedSetupV2ProfileTransactionFailure.COMMIT_VERIFICATION_FAILED)
        assertExistingStateFullyRestored()
        assertThat(dataStore.data.first()[SharedSetupV2ProfilePersistence.undoKey])
            .isEqualTo(PRIOR_UNDO)
        assertLocalEnvironmentUnchanged()
    }

    @Test
    fun `undo restores the existing state once and then reports no undo`() = runTest {
        requireSentinelMappingMatchesFixture()
        seedExistingState()
        val transaction = transaction(GENERATED_ONE_ID, GENERATED_TWO_ID)
        transaction.apply(
            plan = scenarioPlan(),
            selectedBundleIds = scenario.jsonArray("caller_selection").map { it.jsonPrimitive.content },
            mode = SharedSetupV2ProfileImportMode.ADD,
        ).getOrThrow()
        assertThat(dataStore.data.first()[SharedSetupV2ProfilePersistence.undoKey]).isNotNull()

        transaction.undo().getOrThrow()

        assertExistingStateFullyRestored()
        assertThat(dataStore.data.first()[SharedSetupV2ProfilePersistence.undoKey]).isNull()
        assertLocalEnvironmentUnchanged()

        val second = transaction.undo().exceptionOrNull() as SharedSetupV2ProfileTransactionException
        assertThat(second.reason).isEqualTo(SharedSetupV2ProfileTransactionFailure.NO_UNDO)
        assertThat(scenario.jsonObject("expected_undo").string("second_attempt"))
            .isEqualTo("no_undo_snapshot")
    }

    @Test
    fun `invalid selections are rejected before any write`() = runTest {
        requireSentinelMappingMatchesFixture()
        seedExistingState()
        val before = dataStore.data.first().asMap()
        val transaction = transaction(GENERATED_ONE_ID, GENERATED_TWO_ID)

        listOf(emptyList(), listOf("profile-001", "profile-001"), listOf("profile-999"), listOf(" "))
            .forEach { selection ->
                val error = transaction.apply(
                    scenarioPlan(),
                    selection,
                    SharedSetupV2ProfileImportMode.ADD,
                ).exceptionOrNull() as SharedSetupV2ProfileTransactionException
                assertThat(error.reason)
                    .isEqualTo(SharedSetupV2ProfileTransactionFailure.INVALID_SELECTION)
                assertThat(dataStore.data.first().asMap()).isEqualTo(before)
            }
    }

    // ---------------------------------------------------------------------------------------------
    // Stored-state helpers and fault injection
    // ---------------------------------------------------------------------------------------------

    private fun baseSettings(): ExportSettings = ExportSettings().copy(
        exportFormats = setOf(ExportFormat.CSV),
        filenameFormat = "existing-{date}",
        metricSelection = MetricSelectionState(emptySet()),
        individualTracking = IndividualTrackingSettings(),
    )

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

    /** Faults the first post-commit readback so verified rollback must engage. */
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

    private companion object {
        const val NOW = 1_800_000_000_000L
        const val PRIOR_UNDO = "prior-undo"
        const val EXISTING_ONE_ID = "10000000-0000-4000-8000-000000000001"
        const val EXISTING_TWO_ID = "10000000-0000-4000-8000-000000000002"
        const val GENERATED_ONE_ID = "30000000-0000-4000-8000-000000000101"
        const val GENERATED_TWO_ID = "30000000-0000-4000-8000-000000000103"
    }
}

private fun JsonObject.jsonObject(key: String): JsonObject =
    requireNotNull(this[key]) { "Missing object $key" }.jsonObject

private fun JsonObject.jsonArray(key: String): JsonArray =
    requireNotNull(this[key]) { "Missing array $key" }.jsonArray

private fun JsonObject.string(key: String): String =
    stringOrNull(key) ?: error("Missing string $key")

private fun JsonObject.stringOrNull(key: String): String? =
    (this[key] as? JsonPrimitive)?.takeIf { it !is JsonNull }?.contentOrNull

private fun JsonObject.boolean(key: String): Boolean =
    requireNotNull(this[key]) { "Missing boolean $key" }.jsonPrimitive.boolean

@Suppress("UNCHECKED_CAST")
private fun Preferences.mutableCopy(): MutablePreferences = mutablePreferencesOf().also { copy ->
    asMap().forEach { (key, value) ->
        copy[key as Preferences.Key<Any>] = value
    }
}
