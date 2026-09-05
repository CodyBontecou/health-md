package com.healthmd.sharedsetup

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.core.stringSetPreferencesKey
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileDateWindow
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.BulletStyle
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.DateFormatPreference
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.FrontmatterKeyStyle
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MarkdownTemplateConfig
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.MetricTrackingConfig
import com.healthmd.domain.model.RawSnapshotSettings
import com.healthmd.domain.model.TimeFormatPreference
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WriteMode
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawSnapshotScope
import java.net.URI
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Explicit mutation mode for one validated Shared Setup v2 profile import. */
enum class SharedSetupV2ProfileImportMode {
    ADD,
    REPLACE,
}

/** Bounded, non-secret failure classification for profile transaction callers. */
enum class SharedSetupV2ProfileTransactionFailure {
    INVALID_PLAN,
    INVALID_SELECTION,
    INVALID_STORED_STATE,
    PROFILE_LIMIT_EXCEEDED,
    INVALID_GENERATED_ID,
    SIDECAR_LIMIT_EXCEEDED,
    UNDO_LIMIT_EXCEEDED,
    COMMIT_VERIFICATION_FAILED,
    ROLLBACK_NOT_VERIFIED,
    NO_UNDO,
    UNDO_VERIFICATION_FAILED,
}

class SharedSetupV2ProfileTransactionException(
    val reason: SharedSetupV2ProfileTransactionFailure,
    cause: Throwable? = null,
) : IllegalStateException(
    when (reason) {
        SharedSetupV2ProfileTransactionFailure.INVALID_PLAN ->
            "The reviewed Shared Setup v2 import plan is no longer valid."
        SharedSetupV2ProfileTransactionFailure.INVALID_SELECTION ->
            "Select one or more unambiguous Shared Setup v2 profiles."
        SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE ->
            "The saved export-profile state is invalid and was not changed."
        SharedSetupV2ProfileTransactionFailure.PROFILE_LIMIT_EXCEEDED ->
            "The export-profile limit would be exceeded."
        SharedSetupV2ProfileTransactionFailure.INVALID_GENERATED_ID ->
            "A fresh native profile identity could not be created safely."
        SharedSetupV2ProfileTransactionFailure.SIDECAR_LIMIT_EXCEEDED ->
            "The preserved Shared Setup v2 profile state exceeds 4 MiB."
        SharedSetupV2ProfileTransactionFailure.UNDO_LIMIT_EXCEEDED ->
            "The Shared Setup v2 Undo snapshot exceeds 8 MiB."
        SharedSetupV2ProfileTransactionFailure.COMMIT_VERIFICATION_FAILED ->
            "Shared Setup v2 persistence verification failed."
        SharedSetupV2ProfileTransactionFailure.ROLLBACK_NOT_VERIFIED ->
            "Shared Setup v2 failed and the previous profile state could not be verified as restored."
        SharedSetupV2ProfileTransactionFailure.NO_UNDO ->
            "No Shared Setup v2 profile import is available to undo."
        SharedSetupV2ProfileTransactionFailure.UNDO_VERIFICATION_FAILED ->
            "Shared Setup v2 Undo could not be verified safely."
    },
    cause,
)

/** Frozen aggregate sidecar shape. Rows are ordered as a subsequence of native profile order. */
@Serializable
data class SharedSetupV2StoredProfileState(
    val version: Int = SHARED_SETUP_V2_PROFILE_STATE_VERSION,
    val profiles: List<SharedSetupV2StoredProfileStateRow>,
)

@Serializable
data class SharedSetupV2StoredProfileStateRow(
    @SerialName("profile_id") val profileId: String,
    @SerialName("source_bundle_id") val sourceBundleId: String,
    @SerialName("source_profile") val sourceProfile: SharedSetupV2Profile,
    @SerialName("unsupported_semantic_ids") val unsupportedSemanticIds: List<String>,
)

/** Gate result deliberately carries no profile name, endpoint, URI, or other user-authored text. */
sealed interface SharedSetupV2ProfileExecutionAccess {
    data object Allowed : SharedSetupV2ProfileExecutionAccess
    data object DestinationRebindRequired : SharedSetupV2ProfileExecutionAccess
}

class SharedSetupV2ProfileBlockedException : IllegalStateException(
    "This imported profile requires an explicit local destination rebind before it can run.",
)

data class SharedSetupV2ProfileApplyResult(
    val mode: SharedSetupV2ProfileImportMode,
    val selectedBundleIds: List<String>,
    val nativeProfileIdsByBundleId: Map<String, String>,
    val activeProfileId: String,
    val canUndo: Boolean = true,
)

@Serializable
private data class SharedSetupV2LogicalProfileState(
    val profiles: List<ExportProfile>,
    @SerialName("active_profile_id") val activeProfileId: String?,
    @SerialName("scheduled_profile_entries") val scheduledProfileEntries: List<ScheduledProfileEntry>,
    @SerialName("profile_state") val profileState: SharedSetupV2StoredProfileState?,
    @SerialName("blocked_profile_ids") val blockedProfileIds: List<String>,
)

@Serializable
private data class SharedSetupV2UndoPayload(
    val version: Int = SHARED_SETUP_V2_UNDO_VERSION,
    val previous: SharedSetupV2LogicalProfileState,
)

private data class StoredSnapshot(
    val logical: SharedSetupV2LogicalProfileState,
    val undoRaw: String?,
)

private data class EncodedLogicalProfileState(
    val profiles: String,
    val activeProfileId: String?,
    val scheduledProfileEntries: String,
    val profileState: String?,
    val blockedProfileIds: Set<String>,
)

/**
 * Shared persistence names and strict sidecar helpers used by the transaction and profile gates.
 * Existing profile/schedule repositories deliberately keep their shipped public APIs.
 */
internal object SharedSetupV2ProfilePersistence {
    val profilesKey = stringPreferencesKey("export_profiles")
    val activeProfileIdKey = stringPreferencesKey("export_profiles_active_id")
    val scheduledProfileEntriesKey = stringPreferencesKey("scheduled_profile_entries")
    val profileStateKey = stringPreferencesKey("shared_setup_v2_profile_state")
    val blockedProfileIdsKey = stringSetPreferencesKey("shared_setup_v2_blocked_profile_ids")
    val undoKey = stringPreferencesKey("shared_setup_v2_undo")

    val json = Json {
        ignoreUnknownKeys = false
        encodeDefaults = true
        explicitNulls = true
        prettyPrint = false
    }
    val profileListSerializer = ListSerializer(ExportProfile.serializer())
    val scheduleListSerializer = ListSerializer(ScheduledProfileEntry.serializer())

    fun decodeProfileStateOrNull(raw: String?): SharedSetupV2StoredProfileState? {
        if (raw == null) return null
        require(raw.isNotBlank())
        require(raw.encodeToByteArray().size <= SHARED_SETUP_V2_PROFILE_STATE_MAX_BYTES)
        return json.decodeFromString(SharedSetupV2StoredProfileState.serializer(), raw).also(::validateProfileState)
    }

    fun encodeProfileState(state: SharedSetupV2StoredProfileState?): String? = state?.let {
        validateProfileState(it)
        json.encodeToString(SharedSetupV2StoredProfileState.serializer(), it).also { encoded ->
            require(encoded.encodeToByteArray().size <= SHARED_SETUP_V2_PROFILE_STATE_MAX_BYTES)
        }
    }

    fun sourceDestinationKind(raw: String?, profileId: String): String? =
        runCatching {
            decodeProfileStateOrNull(raw)
                ?.profiles
                ?.singleOrNull { it.profileId == profileId }
                ?.sourceProfile
                ?.destination
                ?.kind
        }.getOrNull()

    /**
     * The imported API endpoint URL retained in the bounded sidecar for one profile, normalized
     * through the same [APIExportEndpoint] gate the profile editor uses. The sidecar endpoint
     * hint is descriptive-only (queries never travel in it), so the reconstruction is exactly
     * the retained scheme, effective port, and path — never a derived or guessed identity.
     * Null for any non-API row, absent row, or unnormalizable reconstruction (fail closed).
     */
    fun retainedApiEndpointUrl(raw: String?, profileId: String): String? = runCatching {
        retainedApiEndpointUrl(decodeProfileStateOrNull(raw), profileId)
    }.getOrNull()

    /** Typed-state variant of [retainedApiEndpointUrl] for callers holding decoded state. */
    fun retainedApiEndpointUrl(
        state: SharedSetupV2StoredProfileState?,
        profileId: String,
    ): String? = runCatching {
        val endpoint = state
            ?.profiles
            ?.singleOrNull { it.profileId == profileId }
            ?.sourceProfile
            ?.destination
            ?.takeIf { it.kind == "api_endpoint" }
            ?.apiEndpoint
            ?: return null
        APIExportEndpoint.normalizedOrNull(
            URI(endpoint.scheme, null, endpoint.host, endpoint.port ?: -1, endpoint.path, null, null)
                .toASCIIString(),
        )
    }.getOrNull()

    private fun validateProfileState(state: SharedSetupV2StoredProfileState) {
        require(state.version == SHARED_SETUP_V2_PROFILE_STATE_VERSION)
        require(state.profiles.size <= ExportProfileRules.MAX_PROFILES)
        require(state.profiles.map { it.profileId }.distinct().size == state.profiles.size)
        state.profiles.forEach { row ->
            require(isCanonicalUuid(row.profileId))
            require(row.sourceBundleId == row.sourceProfile.bundleId)
            require(row.sourceBundleId.matches(SOURCE_BUNDLE_ID))
            require(row.unsupportedSemanticIds == row.unsupportedSemanticIds.sorted())
            require(row.unsupportedSemanticIds.distinct().size == row.unsupportedSemanticIds.size)
        }
    }

    fun isCanonicalUuid(value: String): Boolean = runCatching {
        UUID.fromString(value).toString() == value
    }.getOrDefault(false)

    private val SOURCE_BUNDLE_ID = Regex("profile-[0-9]{3}")
}

/**
 * One-edit Add/Replace materialization plus verified compare-and-set rollback and one-shot Undo.
 * This class never touches live settings, SAF grants, credential/header stores, schedulers, or
 * destination network state. A service adapter supplies only an already validated import plan.
 */
@Singleton
class SharedSetupV2ProfileTransaction private constructor(
    private val dataStore: DataStore<Preferences>,
    private val registry: SharedSetupMetricRegistry,
    private val nativeId: () -> String,
    private val nowEpochMillis: () -> Long,
    private val localZoneId: () -> ZoneId,
) {
    @Inject
    constructor(dataStore: DataStore<Preferences>) : this(
        dataStore = dataStore,
        registry = AndroidSharedSetupMetricRegistry(),
        nativeId = { UUID.randomUUID().toString() },
        nowEpochMillis = System::currentTimeMillis,
        localZoneId = ZoneId::systemDefault,
    )

    internal constructor(
        dataStore: DataStore<Preferences>,
        registry: SharedSetupMetricRegistry,
        nativeId: () -> String,
        nowEpochMillis: () -> Long,
        localZoneId: () -> ZoneId,
        @Suppress("UNUSED_PARAMETER") testing: Unit = Unit,
    ) : this(dataStore, registry, nativeId, nowEpochMillis, localZoneId)

    private val codec = SharedSetupV2Codec(registry)
    private val mapper = SharedSetupV2Mapper(registry)
    private val mutex = Mutex()

    suspend fun apply(
        plan: SharedSetupV2ImportPlan,
        selectedBundleIds: List<String>,
        mode: SharedSetupV2ProfileImportMode,
    ): Result<SharedSetupV2ProfileApplyResult> = mutex.withLock {
        withContext(NonCancellable) {
            runCatching { applyLocked(plan, selectedBundleIds, mode) }
        }
    }

    suspend fun undo(): Result<Unit> = mutex.withLock {
        withContext(NonCancellable) {
            runCatching { undoLocked() }
        }
    }

    suspend fun storedProfileState(): Result<SharedSetupV2StoredProfileState?> = runCatching {
        val snapshot = readStoredSnapshot()
        snapshot.logical.profileState
    }

    suspend fun blockedProfileIds(): Set<String> =
        dataStore.data.first()[SharedSetupV2ProfilePersistence.blockedProfileIdsKey].orEmpty()

    private suspend fun applyLocked(
        plan: SharedSetupV2ImportPlan,
        selectedBundleIds: List<String>,
        mode: SharedSetupV2ProfileImportMode,
    ): SharedSetupV2ProfileApplyResult {
        val validatedPlan = validatePlan(plan)
        val selected = normalizeSelection(validatedPlan, selectedBundleIds)
        val before = readStoredSnapshot()
        val existing = before.logical

        if (
            mode == SharedSetupV2ProfileImportMode.ADD &&
            existing.profiles.size + selected.size > ExportProfileRules.MAX_PROFILES
        ) {
            fail(SharedSetupV2ProfileTransactionFailure.PROFILE_LIMIT_EXCEEDED)
        }

        val zone = runCatching { ZoneId.of(localZoneId().id) }
            .getOrElse { fail(SharedSetupV2ProfileTransactionFailure.INVALID_PLAN, it) }
        val now = nowEpochMillis()
        if (now < 0) fail(SharedSetupV2ProfileTransactionFailure.INVALID_PLAN)
        val generatedIds = selected.map { nativeId() }
        if (
            generatedIds.any { !SharedSetupV2ProfilePersistence.isCanonicalUuid(it) } ||
            generatedIds.distinct().size != generatedIds.size ||
            generatedIds.any { generated -> existing.profiles.any { it.id == generated } }
        ) {
            fail(SharedSetupV2ProfileTransactionFailure.INVALID_GENERATED_ID)
        }
        val generatedByBundle = selected.mapIndexed { index, profile ->
            profile.bundleId to generatedIds[index]
        }.toMap(LinkedHashMap())

        val importedProfiles = mutableListOf<ExportProfile>()
        selected.forEachIndexed { index, profilePlan ->
            val id = generatedIds[index]
            val name = if (mode == SharedSetupV2ProfileImportMode.ADD) {
                ExportProfileRules.uniquifyName(
                    profilePlan.name,
                    existing.profiles + importedProfiles,
                )
            } else {
                profilePlan.name
            }
            importedProfiles += materializeProfile(profilePlan, id, name, now, zone)
        }

        val importedSchedules = selected.mapIndexedNotNull { index, profile ->
            materializeSchedule(
                plan = validatedPlan,
                profile = profile,
                nativeProfileId = generatedIds[index],
                zone = zone,
            )
        }
        val importedSidecarRows = selected.mapIndexed { index, profile ->
            SharedSetupV2StoredProfileStateRow(
                profileId = generatedIds[index],
                sourceBundleId = profile.bundleId,
                sourceProfile = profile.source,
                unsupportedSemanticIds = profile.unavailableMetricIds.sorted(),
            )
        }

        val candidateProfiles = when (mode) {
            SharedSetupV2ProfileImportMode.ADD -> existing.profiles + importedProfiles
            SharedSetupV2ProfileImportMode.REPLACE -> importedProfiles
        }
        val candidateSchedules = when (mode) {
            SharedSetupV2ProfileImportMode.ADD -> existing.scheduledProfileEntries + importedSchedules
            SharedSetupV2ProfileImportMode.REPLACE -> importedSchedules
        }
        val retainedSidecar = when (mode) {
            SharedSetupV2ProfileImportMode.ADD -> existing.profileState?.profiles.orEmpty()
            SharedSetupV2ProfileImportMode.REPLACE -> emptyList()
        }
        val candidateSidecar = SharedSetupV2StoredProfileState(
            profiles = retainedSidecar + importedSidecarRows,
        )
        val candidateBlocked = when (mode) {
            SharedSetupV2ProfileImportMode.ADD -> existing.blockedProfileIds.toSet() + generatedIds
            SharedSetupV2ProfileImportMode.REPLACE -> generatedIds.toSet()
        }
        val sourceActiveNativeId = generatedByBundle[validatedPlan.activeProfile]
        val candidateActive = when (mode) {
            SharedSetupV2ProfileImportMode.ADD -> existing.activeProfileId
                ?.takeIf { active -> existing.profiles.any { it.id == active } }
                ?: sourceActiveNativeId
                ?: generatedIds.first()
            SharedSetupV2ProfileImportMode.REPLACE -> sourceActiveNativeId ?: generatedIds.first()
        }
        val candidate = SharedSetupV2LogicalProfileState(
            profiles = candidateProfiles,
            activeProfileId = candidateActive,
            scheduledProfileEntries = candidateSchedules,
            profileState = candidateSidecar,
            blockedProfileIds = candidateBlocked.sorted(),
        )
        validateLogicalState(candidate)

        // Encode every candidate component and the complete previous-state Undo before mutation.
        val encodedBefore = encodeLogicalState(existing)
        val encodedCandidate = encodeLogicalState(candidate)
        val undoRaw = encodeUndo(existing)
        before.undoRaw?.let { priorUndo ->
            if (priorUndo.encodeToByteArray().size > SHARED_SETUP_V2_UNDO_MAX_BYTES) {
                fail(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE)
            }
        }

        var committed = false
        dataStore.edit { preferences ->
            val current = decodeLogicalState(preferences)
            if (current != existing || preferences[SharedSetupV2ProfilePersistence.undoKey] != before.undoRaw) {
                return@edit
            }
            writeLogicalState(preferences, encodedCandidate)
            preferences[SharedSetupV2ProfilePersistence.undoKey] = undoRaw
            committed = true
        }
        if (!committed) fail(SharedSetupV2ProfileTransactionFailure.COMMIT_VERIFICATION_FAILED)

        val verified = runCatching { readStoredSnapshot() }
            .getOrNull()
            ?.let { it.logical == candidate && it.undoRaw == undoRaw }
            ?: false
        if (!verified) {
            val restored = rollbackApply(
                expectedCandidate = candidate,
                expectedUndoRaw = undoRaw,
                previous = encodedBefore,
                previousLogical = existing,
                previousUndoRaw = before.undoRaw,
            )
            if (!restored) {
                fail(SharedSetupV2ProfileTransactionFailure.ROLLBACK_NOT_VERIFIED)
            }
            fail(SharedSetupV2ProfileTransactionFailure.COMMIT_VERIFICATION_FAILED)
        }

        return SharedSetupV2ProfileApplyResult(
            mode = mode,
            selectedBundleIds = selected.map { it.bundleId },
            nativeProfileIdsByBundleId = generatedByBundle,
            activeProfileId = candidateActive,
        )
    }

    private suspend fun undoLocked() {
        val before = readStoredSnapshot()
        val undoRaw = before.undoRaw ?: fail(SharedSetupV2ProfileTransactionFailure.NO_UNDO)
        val undo = decodeUndo(undoRaw)
        val restoredLogical = undo.previous
        validateLogicalState(restoredLogical)
        val encodedRestored = encodeLogicalState(restoredLogical)
        val encodedBefore = encodeLogicalState(before.logical)

        var restored = false
        dataStore.edit { preferences ->
            if (preferences[SharedSetupV2ProfilePersistence.undoKey] != undoRaw) return@edit
            writeLogicalState(preferences, encodedRestored)
            // Verification happens while the one-shot snapshot remains available.
            preferences[SharedSetupV2ProfilePersistence.undoKey] = undoRaw
            restored = true
        }
        if (!restored || !matchesStored(restoredLogical, undoRaw)) {
            val rollbackVerified = rollbackUndoRestore(
                expectedRestored = restoredLogical,
                undoRaw = undoRaw,
                previous = encodedBefore,
                previousLogical = before.logical,
            )
            if (!rollbackVerified) {
                fail(SharedSetupV2ProfileTransactionFailure.ROLLBACK_NOT_VERIFIED)
            }
            fail(SharedSetupV2ProfileTransactionFailure.UNDO_VERIFICATION_FAILED)
        }

        var removed = false
        dataStore.edit { preferences ->
            if (
                preferences[SharedSetupV2ProfilePersistence.undoKey] != undoRaw ||
                decodeLogicalState(preferences) != restoredLogical
            ) {
                return@edit
            }
            preferences.remove(SharedSetupV2ProfilePersistence.undoKey)
            removed = true
        }
        val removalVerified = removed && runCatching { readStoredSnapshot() }
            .getOrNull()
            ?.let { it.logical == restoredLogical && it.undoRaw == null }
            ?: false
        if (!removalVerified) {
            // Keep failed Undo retryable when the logical restore is present but snapshot removal
            // cannot be attested.
            runCatching {
                dataStore.edit { preferences ->
                    if (
                        preferences[SharedSetupV2ProfilePersistence.undoKey] == null &&
                        decodeLogicalState(preferences) == restoredLogical
                    ) {
                        preferences[SharedSetupV2ProfilePersistence.undoKey] = undoRaw
                    }
                }
            }
            fail(SharedSetupV2ProfileTransactionFailure.UNDO_VERIFICATION_FAILED)
        }
    }

    private fun validatePlan(plan: SharedSetupV2ImportPlan): SharedSetupV2ImportPlan {
        val recalculated = runCatching {
            codec.encode(plan.source)
            mapper.planImport(plan.source)
        }.getOrElse { fail(SharedSetupV2ProfileTransactionFailure.INVALID_PLAN, it) }
        if (recalculated != plan) fail(SharedSetupV2ProfileTransactionFailure.INVALID_PLAN)
        return recalculated
    }

    private fun normalizeSelection(
        plan: SharedSetupV2ImportPlan,
        selectedBundleIds: List<String>,
    ): List<SharedSetupV2ProfileImportPlan> {
        if (
            selectedBundleIds.isEmpty() ||
            selectedBundleIds.any { it.isBlank() || it != it.trim() } ||
            selectedBundleIds.distinct().size != selectedBundleIds.size
        ) {
            fail(SharedSetupV2ProfileTransactionFailure.INVALID_SELECTION)
        }
        val rowsById = plan.profiles.groupBy { it.bundleId }
        if (rowsById.values.any { it.size != 1 }) {
            fail(SharedSetupV2ProfileTransactionFailure.INVALID_PLAN)
        }
        if (selectedBundleIds.any { rowsById[it]?.size != 1 }) {
            fail(SharedSetupV2ProfileTransactionFailure.INVALID_SELECTION)
        }
        val selected = selectedBundleIds.toSet()
        return plan.profiles.filter { it.bundleId in selected }.also {
            if (it.size != selectedBundleIds.size) {
                fail(SharedSetupV2ProfileTransactionFailure.INVALID_SELECTION)
            }
        }
    }

    private fun materializeProfile(
        plan: SharedSetupV2ProfileImportPlan,
        profileId: String,
        name: String,
        now: Long,
        zone: ZoneId,
    ): ExportProfile {
        val source = plan.source
        val baseline = ExportSettings()
        val android = source.platformExtensions.android?.export
        val supportedSelections = plan.supportedMetricIds.map { semanticId ->
            registry.bySemanticId[semanticId]?.androidSelectionId
                ?: fail(SharedSetupV2ProfileTransactionFailure.INVALID_PLAN)
        }.toSortedSet()
        val individualConfigs = source.individualEntries.metrics.entries
            .mapNotNull { (semanticId, row) ->
                registry.bySemanticId[semanticId]?.androidSelectionId?.let { selectionId ->
                    selectionId to MetricTrackingConfig(
                        trackIndividually = row.enabled,
                        customFolder = row.customFolder,
                    )
                }
            }
            .toMap(java.util.TreeMap())
        val presentation = source.presentation
        val frontmatter = presentation.frontmatter
        val markdown = presentation.markdown
        val baselineMarkdown = baseline.formatCustomization.markdownTemplate
        val materializedMarkdown = if (templateIsExactlySupported(markdown)) {
            MarkdownTemplateConfig(
                style = MarkdownTemplateStyle.valueOf(markdown.style.uppercase()),
                customTemplate = markdown.customText,
                sectionHeaderLevel = markdown.headerLevel,
                useEmoji = markdown.useEmoji,
                includeSummary = markdown.includeSummary,
                bulletStyle = BulletStyle.valueOf(markdown.bulletStyle.uppercase()),
            )
        } else {
            // Preserve supported presentation knobs, but never install or execute an unresolved
            // custom template. The complete source text remains only in the bounded sidecar.
            baselineMarkdown.copy(
                sectionHeaderLevel = markdown.headerLevel,
                useEmoji = markdown.useEmoji,
                includeSummary = markdown.includeSummary,
                bulletStyle = BulletStyle.valueOf(markdown.bulletStyle.uppercase()),
            )
        }
        val selectedFormats = source.export.formats.map(::formatFromWire).toSet()
        val legacyPrimary = android?.legacyPrimaryFormat?.let(::formatFromWire)
            ?: selectedFormats.firstOrNull()
            ?: baseline.exportFormat
        val compatibilityProfile = when (android?.compatibilityProfile) {
            "analytical_v5" -> CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5
            else -> CompatibilitySchemaProfile.IOS_V4_FROZEN
        }
        val settings = baseline.copy(
            exportMode = when (android?.mode) {
                "raw_snapshot" -> ExportMode.RAW_SNAPSHOT
                else -> ExportMode.COMPATIBILITY
            },
            rawSnapshot = android?.rawSnapshot?.let { raw ->
                RawSnapshotSettings(
                    format = if (raw.format == "json") RawExportFormat.JSON else RawExportFormat.NDJSON,
                    scope = if (raw.scope == "all_authorized_supported_data") {
                        RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA
                    } else {
                        RawSnapshotScope.SELECTED_RECORD_TYPES
                    },
                    includeExerciseRoutes = raw.includeExerciseRoutes,
                    pageSize = raw.pageSize,
                )
            } ?: baseline.rawSnapshot,
            dataTypes = android?.legacyDataTypes?.toNative() ?: baseline.dataTypes,
            exportFormat = legacyPrimary,
            exportFormats = selectedFormats,
            includeMetadata = source.export.includeMetadata,
            groupByCategory = source.export.groupByCategory,
            filenameFormat = source.export.filenameTemplate,
            folderStructure = source.export.folderTemplate,
            writeMode = WriteMode.valueOf(source.export.writeMode.uppercase()),
            formatCustomization = FormatCustomization(
                dateFormat = DateFormatPreference.valueOf(presentation.dateFormat.uppercase()),
                timeFormat = TimeFormatPreference.valueOf(presentation.timeFormat.uppercase()),
                unitPreference = if (presentation.units == "imperial") UnitPreference.IMPERIAL else UnitPreference.METRIC,
                includeLegacyAndroidAliases = android?.includeLegacyAliases ?: false,
                includeAndroidNativeFields = android?.includeAndroidNativeFields ?: false,
                compatibilitySchemaProfile = compatibilityProfile,
                frontmatterConfig = FrontmatterConfiguration(
                    fields = frontmatter.fields.map { field ->
                        CustomFrontmatterField(
                            originalKey = field.sourceKey,
                            customKey = field.outputKey,
                            isEnabled = field.enabled,
                        )
                    },
                    customFields = frontmatter.customValues.toSortedMap(),
                    placeholderFields = frontmatter.placeholders.toList(),
                    includeDate = frontmatter.includeDate,
                    includeType = frontmatter.includeType,
                    customDateKey = frontmatter.dateKey,
                    customTypeKey = frontmatter.typeKey,
                    customTypeValue = frontmatter.typeValue,
                    keyStyle = if (frontmatter.keyStyle == "camel_case") {
                        FrontmatterKeyStyle.CAMEL_CASE
                    } else {
                        FrontmatterKeyStyle.SNAKE_CASE
                    },
                ),
                markdownTemplate = materializedMarkdown,
            ),
            metricSelection = MetricSelectionState(supportedSelections),
            dailyNoteInjection = DailyNoteInjectionSettings(
                enabled = source.dailyNotes.enabled,
                folderPath = source.dailyNotes.folder,
                filenamePattern = source.dailyNotes.filenameTemplate,
                createIfMissing = source.dailyNotes.createIfMissing,
                injectMarkdownSections = source.dailyNotes.injectSections,
            ),
            individualTracking = IndividualTrackingSettings(
                globalEnabled = source.individualEntries.enabled,
                enabledMetrics = individualConfigs.filterValues { it.trackIndividually }.keys,
                metricConfigs = individualConfigs,
                entriesFolder = source.individualEntries.entriesFolder,
                organizeByCategory = source.individualEntries.organizeByCategory,
                filenameTemplate = source.individualEntries.filenameTemplate,
            ),
            includeGranularData = source.export.compatibilityDetail == "selected_time_series",
            // Destination intent is carried by ExportProfile + sidecar. The snapshot remains an
            // inert folder-scoped value so no sender endpoint fingerprint or local API binding is
            // fabricated. A later credential-safe API rebind replaces this local snapshot.
            exportTarget = ExportTarget.DEVICE_FOLDER,
            scheduledExportTarget = ExportTarget.DEVICE_FOLDER,
            apiEndpointUrl = "",
            subfolder = android?.subfolder ?: baseline.subfolder,
            folderOrganization = android?.folderOrganization?.let {
                FolderOrganization.valueOf(it.uppercase())
            } ?: baseline.folderOrganization,
            scheduleEnabled = false,
            pendingScheduledRetryDates = emptyList(),
            pendingScheduledExportRequests = emptyList(),
            executionEnginePin = null,
            executionEngineAuthorityIsFrozen = false,
        )
        val snapshot = AndroidExportSettingsSnapshot.capture(settings, pin = null, zone = zone)
        val target = if (source.destination.kind == "api_endpoint") {
            ExportTarget.API_ENDPOINT
        } else {
            ExportTarget.DEVICE_FOLDER
        }
        return ExportProfile(
            id = profileId,
            name = name,
            settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot),
            target = target,
            apiEndpointUrl = null,
            folderUri = null,
            folderDisplayName = null,
            isMigrationDefault = false,
            createdAtEpochMillis = now,
            updatedAtEpochMillis = now,
        )
    }

    private fun materializeSchedule(
        plan: SharedSetupV2ImportPlan,
        profile: SharedSetupV2ProfileImportPlan,
        nativeProfileId: String,
        zone: ZoneId,
    ): ScheduledProfileEntry? {
        val source = profile.scheduleIntent?.source ?: return null
        if (profile.source.destination.kind !in setOf("device_folder", "api_endpoint")) return null
        if (source.lookbackDays !in 1..30) return null
        return ScheduledProfileEntry(
            profileId = nativeProfileId,
            isEnabled = false,
            anchorEpochDay = LocalDate.parse(source.cadence.anchorDate).toEpochDay(),
            weekdayIso = source.weekday,
            hour = source.localTime.hour,
            minute = source.localTime.minute,
            cadenceValue = source.cadence.value,
            cadenceUnit = when (source.cadence.unit) {
                "days" -> ScheduledProfileCadenceUnit.DAY
                "weeks" -> ScheduledProfileCadenceUnit.WEEK
                else -> ScheduledProfileCadenceUnit.MONTH
            },
            dateWindow = ScheduledProfileDateWindow.PAST_COMPLETE_DAYS,
            lookbackDays = source.lookbackDays,
            zoneId = zone.id,
            lastSuccessEpochMillis = null,
            lastRefreshSuccessEpochMillis = null,
            pendingExports = emptyList(),
        )
    }

    private fun templateIsExactlySupported(markdown: SharedSetupV2Markdown): Boolean {
        if (markdown.style != "custom") return true
        if (SharedSetupTemplateSyntax.templateSyntaxProblem(markdown.customText) != null) return false
        return Regex("\\{\\{([#/]?)([A-Za-z0-9_]+)\\}\\}")
            .findAll(markdown.customText)
            .none { match ->
                val marker = match.groupValues[1]
                val name = match.groupValues[2]
                if (marker.isEmpty()) name !in ANDROID_TEMPLATE_TOKENS else name !in ANDROID_TEMPLATE_SECTIONS
            }
    }

    private fun SharedSetupV2AndroidLegacyDataTypes.toNative(): DataTypeSelection = DataTypeSelection(
        sleep = sleep,
        activity = activity,
        heart = heart,
        vitals = vitals,
        body = body,
        nutrition = nutrition,
        mobility = mobility,
        reproductiveHealth = reproductiveHealth,
        mindfulness = mindfulness,
        workouts = workouts,
        plannedWorkouts = plannedWorkouts,
        medicalResources = medicalResources,
    )

    private fun formatFromWire(value: String): ExportFormat = when (value) {
        "markdown" -> ExportFormat.MARKDOWN
        "obsidian_bases" -> ExportFormat.OBSIDIAN_BASES
        "json" -> ExportFormat.JSON
        else -> ExportFormat.CSV
    }

    private suspend fun readStoredSnapshot(): StoredSnapshot = try {
        val preferences = dataStore.data.first()
        StoredSnapshot(
            logical = decodeLogicalState(preferences),
            undoRaw = preferences[SharedSetupV2ProfilePersistence.undoKey],
        )
    } catch (error: SharedSetupV2ProfileTransactionException) {
        throw error
    } catch (error: Throwable) {
        fail(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE, error)
    }

    private fun decodeLogicalState(preferences: Preferences): SharedSetupV2LogicalProfileState = try {
        val profilesRaw = preferences[SharedSetupV2ProfilePersistence.profilesKey]
        val schedulesRaw = preferences[SharedSetupV2ProfilePersistence.scheduledProfileEntriesKey]
        val state = SharedSetupV2LogicalProfileState(
            profiles = if (profilesRaw.isNullOrBlank()) {
                emptyList()
            } else {
                SharedSetupV2ProfilePersistence.json.decodeFromString(
                    SharedSetupV2ProfilePersistence.profileListSerializer,
                    profilesRaw,
                )
            },
            activeProfileId = preferences[SharedSetupV2ProfilePersistence.activeProfileIdKey],
            scheduledProfileEntries = if (schedulesRaw.isNullOrBlank()) {
                emptyList()
            } else {
                SharedSetupV2ProfilePersistence.json.decodeFromString(
                    SharedSetupV2ProfilePersistence.scheduleListSerializer,
                    schedulesRaw,
                )
            },
            profileState = SharedSetupV2ProfilePersistence.decodeProfileStateOrNull(
                preferences[SharedSetupV2ProfilePersistence.profileStateKey],
            ),
            blockedProfileIds = preferences[SharedSetupV2ProfilePersistence.blockedProfileIdsKey]
                .orEmpty()
                .sorted(),
        )
        validateLogicalState(state)
        state
    } catch (error: SharedSetupV2ProfileTransactionException) {
        throw error
    } catch (error: Throwable) {
        fail(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE, error)
    }

    private fun validateLogicalState(state: SharedSetupV2LogicalProfileState) {
        if (state.profiles.size > ExportProfileRules.MAX_PROFILES) {
            fail(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE)
        }
        if (
            state.profiles.any { !ExportProfileRules.isValidName(it.name) || it.id.isBlank() } ||
            state.profiles.map { it.id }.distinct().size != state.profiles.size ||
            state.profiles.map { it.name.trim().lowercase() }.distinct().size != state.profiles.size
        ) {
            fail(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE)
        }
        val profileIds = state.profiles.map { it.id }
        val sidecarRows = state.profileState?.profiles.orEmpty()
        val sidecarIds = sidecarRows.map { it.profileId }
        if (
            sidecarIds.any { it !in profileIds } ||
            sidecarIds.map(profileIds::indexOf) != sidecarIds.map(profileIds::indexOf).sorted() ||
            state.blockedProfileIds.any { it !in sidecarIds }
        ) {
            fail(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE)
        }
    }

    private fun encodeLogicalState(state: SharedSetupV2LogicalProfileState): EncodedLogicalProfileState = try {
        validateLogicalState(state)
        EncodedLogicalProfileState(
            profiles = SharedSetupV2ProfilePersistence.json.encodeToString(
                SharedSetupV2ProfilePersistence.profileListSerializer,
                state.profiles,
            ),
            activeProfileId = state.activeProfileId,
            scheduledProfileEntries = SharedSetupV2ProfilePersistence.json.encodeToString(
                SharedSetupV2ProfilePersistence.scheduleListSerializer,
                state.scheduledProfileEntries,
            ),
            profileState = SharedSetupV2ProfilePersistence.encodeProfileState(state.profileState),
            blockedProfileIds = state.blockedProfileIds.toSet(),
        )
    } catch (error: SharedSetupV2ProfileTransactionException) {
        throw error
    } catch (error: Throwable) {
        val reason = if (error is IllegalArgumentException && error.message?.contains("4 MiB") == true) {
            SharedSetupV2ProfileTransactionFailure.SIDECAR_LIMIT_EXCEEDED
        } else if (state.profileState != null) {
            SharedSetupV2ProfileTransactionFailure.SIDECAR_LIMIT_EXCEEDED
        } else {
            SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE
        }
        fail(reason, error)
    }

    private fun encodeUndo(previous: SharedSetupV2LogicalProfileState): String = try {
        SharedSetupV2ProfilePersistence.json.encodeToString(
            SharedSetupV2UndoPayload.serializer(),
            SharedSetupV2UndoPayload(previous = previous),
        ).also { encoded ->
            if (encoded.encodeToByteArray().size > SHARED_SETUP_V2_UNDO_MAX_BYTES) {
                fail(SharedSetupV2ProfileTransactionFailure.UNDO_LIMIT_EXCEEDED)
            }
        }
    } catch (error: SharedSetupV2ProfileTransactionException) {
        throw error
    } catch (error: Throwable) {
        fail(SharedSetupV2ProfileTransactionFailure.UNDO_LIMIT_EXCEEDED, error)
    }

    private fun decodeUndo(raw: String): SharedSetupV2UndoPayload {
        if (raw.encodeToByteArray().size > SHARED_SETUP_V2_UNDO_MAX_BYTES) {
            fail(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE)
        }
        return runCatching {
            SharedSetupV2ProfilePersistence.json.decodeFromString(SharedSetupV2UndoPayload.serializer(), raw)
        }.getOrElse { fail(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE, it) }.also {
            if (it.version != SHARED_SETUP_V2_UNDO_VERSION) {
                fail(SharedSetupV2ProfileTransactionFailure.INVALID_STORED_STATE)
            }
        }
    }

    private fun writeLogicalState(
        preferences: MutablePreferences,
        state: EncodedLogicalProfileState,
    ) {
        preferences[SharedSetupV2ProfilePersistence.profilesKey] = state.profiles
        state.activeProfileId?.let {
            preferences[SharedSetupV2ProfilePersistence.activeProfileIdKey] = it
        } ?: preferences.remove(SharedSetupV2ProfilePersistence.activeProfileIdKey)
        preferences[SharedSetupV2ProfilePersistence.scheduledProfileEntriesKey] =
            state.scheduledProfileEntries
        state.profileState?.let {
            preferences[SharedSetupV2ProfilePersistence.profileStateKey] = it
        } ?: preferences.remove(SharedSetupV2ProfilePersistence.profileStateKey)
        if (state.blockedProfileIds.isEmpty()) {
            preferences.remove(SharedSetupV2ProfilePersistence.blockedProfileIdsKey)
        } else {
            preferences[SharedSetupV2ProfilePersistence.blockedProfileIdsKey] = state.blockedProfileIds
        }
    }

    private suspend fun rollbackApply(
        expectedCandidate: SharedSetupV2LogicalProfileState,
        expectedUndoRaw: String,
        previous: EncodedLogicalProfileState,
        previousLogical: SharedSetupV2LogicalProfileState,
        previousUndoRaw: String?,
    ): Boolean = runCatching {
        var restored = false
        dataStore.edit { preferences ->
            if (
                decodeLogicalState(preferences) != expectedCandidate ||
                preferences[SharedSetupV2ProfilePersistence.undoKey] != expectedUndoRaw
            ) {
                return@edit
            }
            writeLogicalState(preferences, previous)
            previousUndoRaw?.let {
                preferences[SharedSetupV2ProfilePersistence.undoKey] = it
            } ?: preferences.remove(SharedSetupV2ProfilePersistence.undoKey)
            restored = true
        }
        restored && matchesStored(previousLogical, previousUndoRaw)
    }.getOrDefault(false)

    private suspend fun rollbackUndoRestore(
        expectedRestored: SharedSetupV2LogicalProfileState,
        undoRaw: String,
        previous: EncodedLogicalProfileState,
        previousLogical: SharedSetupV2LogicalProfileState,
    ): Boolean = runCatching {
        var rolledBack = false
        dataStore.edit { preferences ->
            if (
                decodeLogicalState(preferences) != expectedRestored ||
                preferences[SharedSetupV2ProfilePersistence.undoKey] != undoRaw
            ) {
                return@edit
            }
            writeLogicalState(preferences, previous)
            preferences[SharedSetupV2ProfilePersistence.undoKey] = undoRaw
            rolledBack = true
        }
        rolledBack && matchesStored(previousLogical, undoRaw)
    }.getOrDefault(false)

    private suspend fun matchesStored(
        expected: SharedSetupV2LogicalProfileState,
        expectedUndoRaw: String?,
    ): Boolean = runCatching { readStoredSnapshot() }
        .getOrNull()
        ?.let { it.logical == expected && it.undoRaw == expectedUndoRaw }
        ?: false

    private fun fail(
        reason: SharedSetupV2ProfileTransactionFailure,
        cause: Throwable? = null,
    ): Nothing = throw SharedSetupV2ProfileTransactionException(reason, cause)

    private companion object {
        val ANDROID_TEMPLATE_TOKENS = setOf(
            "date",
            "metrics",
            "sleep_metrics",
            "activity_metrics",
            "heart_metrics",
            "vitals_metrics",
            "body_metrics",
            "nutrition_metrics",
            "mobility_metrics",
            "reproductive_health_metrics",
            "mindfulness_metrics",
            "planned_workout_list",
            "medical_resources_metrics",
            "workout_list",
        )
        val ANDROID_TEMPLATE_SECTIONS = setOf(
            "sleep",
            "activity",
            "heart",
            "vitals",
            "body",
            "nutrition",
            "mobility",
            "reproductive_health",
            "mindfulness",
            "workouts",
            "planned_workouts",
            "medical_resources",
        )
    }
}

const val SHARED_SETUP_V2_PROFILE_STATE_VERSION: Int = 1
const val SHARED_SETUP_V2_UNDO_VERSION: Int = 1
const val SHARED_SETUP_V2_PROFILE_STATE_MAX_BYTES: Int = 4 * 1024 * 1024
const val SHARED_SETUP_V2_UNDO_MAX_BYTES: Int = 8 * 1024 * 1024
