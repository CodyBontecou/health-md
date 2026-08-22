package com.healthmd.presentation.export

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import android.net.Uri
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileScheduler
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportProfileOverlapDetector
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSettingsSnapshotView
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import timber.log.Timber

/** One row in the export profiles management screen. */
data class ExportProfileRow(
    val profile: ExportProfile,
    val isActive: Boolean,
    val entry: ScheduledProfileEntry?,
    val snapshot: ExportSettingsSnapshotView?,
    /** Names of other profiles whose exports write the same files (same destination root
     * and matching rendered paths). Empty when there is no overlap. */
    val overlappingProfileNames: List<String> = emptyList(),
)

/**
 * Draft state for the unified full-field profile editor (creation + editing parity with the
 * iOS `ExportProfileEditorSheet`): identity, destination binding, and the editable settings
 * projection all live here until Create/Save persists them.
 */
data class ExportProfileEditorDraft(
    val name: String,
    val target: ExportTarget,
    /** Bound SAF tree URI for DEVICE_FOLDER targets; null follows the live Export-tab folder. */
    val folderUri: String? = null,
    val folderDisplayName: String? = null,
    /** Raw endpoint URL for API_ENDPOINT targets (validated on save). */
    val apiEndpointUrl: String = "",
    val settings: ExportSettings = ExportSettings(),
)

data class ExportProfilesUiState(
    val rows: List<ExportProfileRow> = emptyList(),
    val activeProfileName: String? = null,
    val detailProfileId: String? = null,
    val editingScheduleProfileId: String? = null,
    val renamingProfileId: String? = null,
    val pendingDeleteProfileId: String? = null,
    /** Profile being edited in the full-field editor; null when closed. */
    val editingProfileId: String? = null,
    /** True while the creation form (seeded from current settings) is open. */
    val creatingProfile: Boolean = false,
    /** Live device folder / settings the editor drafts resolve against (overlap preview, restore base). */
    val currentFolderUri: String? = null,
    val currentSettings: ExportSettings = ExportSettings(),
)

/** Inputs the draft overlap preview resolves against, refreshed with the row stream. */
private data class OverlapPreviewContext(
    val identities: List<ExportProfileOverlapDetector.ProfilePathIdentity> = emptyList(),
    val currentFolderUri: String? = null,
)

/**
 * Dedicated export-profiles management surface (cross-platform parity with the iOS
 * `ExportProfilesView`): every profile at a glance with destination, schedule status,
 * formats, and metric count; detail inspection with the stable profile id used by
 * automation references; and activate / rename / duplicate / delete management.
 *
 * Activation applies the profile's frozen snapshot onto live settings through
 * [ExportProfileCoordinator] (editing-authority decision 1): the Export screen edits the
 * active profile, and edits flush back into it. The full-field editor additionally edits a
 * frozen profile in place — saving an edit to the ACTIVE profile re-applies the new snapshot
 * onto live settings and adopts the new destination binding, while a NON-active profile
 * edit never touches live state.
 */
@HiltViewModel
class ExportProfilesViewModel @Inject constructor(
    private val profileRepository: ExportProfileRepository,
    private val entryStore: ScheduledProfileEntryStore,
    private val profileScheduler: ScheduledProfileScheduler,
    private val snapshotFactory: ScheduledProfileSnapshotFactory,
    private val settingsRepository: SettingsRepository,
    private val profileCoordinator: ExportProfileCoordinator,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ExportProfilesUiState())
    val uiState: StateFlow<ExportProfilesUiState> = _uiState.asStateFlow()

    private var overlapContext = OverlapPreviewContext()

    init {
        viewModelScope.launch {
            combine(
                profileRepository.profiles,
                profileRepository.activeProfileId,
                entryStore.entries,
                settingsRepository.exportFolderUri,
                settingsRepository.exportSettings,
            ) { profiles, activeId, entries, currentFolderUri, currentSettings ->
                val activeProfile = ExportProfileRules.active(profiles, activeId)
                val identities = ExportProfileOverlapDetector.identities(
                    profiles = profiles,
                    currentFolderUri = currentFolderUri,
                    currentSettings = currentSettings,
                )
                Triple(
                    profiles.map { profile ->
                        ExportProfileRow(
                            profile = profile,
                            isActive = profile.id == activeProfile?.id,
                            entry = entries.firstOrNull { it.profileId == profile.id },
                            snapshot = ExportProfileRules.decodeSnapshot(profile),
                            overlappingProfileNames = ExportProfileOverlapDetector
                                .overlappingProfileNames(profile.id, identities),
                        )
                    },
                    OverlapPreviewContext(identities, currentFolderUri),
                    currentSettings,
                )
            }.collect { (rows, context, currentSettings) ->
                overlapContext = context
                _uiState.update { state ->
                    state.copy(
                        rows = rows,
                        activeProfileName = rows.firstOrNull { it.isActive }?.profile?.name,
                        currentFolderUri = context.currentFolderUri,
                        currentSettings = currentSettings,
                    )
                }
            }
        }
        // Bootstrap migration + initial arming, matching the schedule surface.
        viewModelScope.launch { runCatching { profileScheduler.reconcile() } }
    }

    // MARK: - Creation form

    /** Opens the creation form seeded from the current live settings snapshot. */
    fun startCreation() {
        _uiState.update { it.copy(creatingProfile = true) }
    }

    fun dismissCreation() {
        _uiState.update { it.copy(creatingProfile = false) }
    }

    /**
     * Creates a profile from the creation form's draft: name, target, destination binding,
     * and a frozen snapshot captured from the draft settings. Seeds the schedule entry
     * (disabled) and activates the new profile, matching the previous instant-create behavior
     * (iOS parity).
     */
    fun createProfile(draft: ExportProfileEditorDraft) {
        viewModelScope.launch {
            runCatching {
                val current = settingsRepository.getExportSettings()
                val snapshotJson = encodeDraftSnapshot(draft)
                val profile = profileRepository.add(
                    name = draft.name.trim(),
                    settingsSnapshotJson = snapshotJson,
                    target = draft.target,
                    apiEndpointUrl = endpointBinding(draft),
                    folderUri = folderBinding(draft)?.first,
                    folderDisplayName = folderBinding(draft)?.second,
                )
                // Seed the new profile's entry (disabled) so the schedule surface
                // and the row toggle have a cadence to edit immediately.
                entryStore.upsert(
                    ScheduledProfileEntry(
                        profileId = profile.id,
                        isEnabled = false,
                        anchorEpochDay = java.time.LocalDate.now().toEpochDay(),
                        hour = current.scheduleHour.coerceIn(0, 23),
                        minute = current.scheduleMinute.coerceIn(0, 59),
                        cadenceUnit = ScheduledProfileCadenceUnit.DAY,
                        lookbackDays = 1,
                        zoneId = java.time.ZoneId.systemDefault().id,
                    ),
                )
                profileCoordinator.activate(profile.id)
                openDetail(profile.id)
            }.onFailure { Timber.e(it, "Could not create profile") }
            _uiState.update { it.copy(creatingProfile = false) }
        }
    }

    // MARK: - Full-field editor

    fun openEditor(profileId: String?) {
        _uiState.update { it.copy(editingProfileId = profileId, detailProfileId = null) }
    }

    /**
     * Saves a full-field edit: name, target, destination bindings, and a new frozen snapshot
     * in one atomic repository update. When the edited profile is ACTIVE, the new snapshot is
     * re-applied onto live settings and the new destination binding is adopted (iOS parity);
     * editing a NON-active profile never touches live state.
     */
    fun updateProfile(profileId: String, draft: ExportProfileEditorDraft) {
        viewModelScope.launch {
            runCatching {
                val snapshotJson = encodeDraftSnapshot(draft)
                val storedName = profileRepository.applyEditorUpdate(
                    id = profileId,
                    rawName = draft.name.trim(),
                    settingsSnapshotJson = snapshotJson,
                    target = draft.target,
                    apiEndpointUrl = endpointBinding(draft),
                    folderUri = folderBinding(draft)?.first,
                    folderDisplayName = folderBinding(draft)?.second,
                )
                require(storedName != null) { "Profile $profileId could not be updated." }
                if (uiState.value.rows.firstOrNull { it.isActive }?.profile?.id == profileId) {
                    // Re-activation applies the new snapshot onto live settings and
                    // adopts the new folder binding (same-profile activate path).
                    profileCoordinator.activate(profileId)
                }
            }.onFailure { Timber.e(it, "Could not update profile") }
            _uiState.update { it.copy(editingProfileId = null) }
        }
    }

    /**
     * Live draft overlap preview: names of existing profiles whose exports would write the
     * same files as the draft's target, folder binding, and settings. While editing a
     * profile its own stored identity is excluded so an unchanged draft never flags itself.
     */
    fun draftOverlapPreview(
        editingProfileId: String?,
        target: ExportTarget,
        folderUri: String?,
        settings: ExportSettings,
    ): List<String> {
        val context = overlapContext
        val identities = if (editingProfileId == null) {
            context.identities
        } else {
            context.identities.filter { it.profileId != editingProfileId }
        }
        return ExportProfileOverlapDetector.overlapPreviewNames(
            identities = identities,
            currentFolderUri = context.currentFolderUri,
            candidateTarget = target,
            candidateFolderUri = folderUri,
            candidateSettings = settings,
        )
    }

    // MARK: - Existing management actions

    /** Applies the profile onto live settings and makes it the active editing surface. */
    fun activate(profileId: String) {
        viewModelScope.launch {
            runCatching { profileCoordinator.activate(profileId) }
                .onFailure { Timber.e(it, "Could not activate profile") }
        }
    }

    fun openDetail(profileId: String?) {
        _uiState.update { it.copy(detailProfileId = profileId) }
    }

    fun openScheduleEditor(profileId: String?) {
        _uiState.update { it.copy(editingScheduleProfileId = profileId) }
    }

    fun startRename(profileId: String?) {
        _uiState.update { it.copy(renamingProfileId = profileId) }
    }

    fun askDelete(profileId: String?) {
        _uiState.update { it.copy(pendingDeleteProfileId = profileId) }
    }

    /** Rename with trim + unique suffixing; invalid names are rejected by the repository. */
    fun rename(profileId: String, rawName: String) {
        viewModelScope.launch {
            runCatching { profileRepository.rename(profileId, rawName) }
                .onFailure { Timber.e(it, "Could not rename profile") }
            _uiState.update { it.copy(renamingProfileId = null) }
        }
    }

    /** Duplicates a profile (frozen snapshot, target, endpoint, folder binding) under a unique name. */
    fun duplicate(profileId: String) {
        viewModelScope.launch {
            runCatching {
                val source = profileRepository.profileById(profileId) ?: return@launch
                val copy = profileRepository.add(
                    name = source.name,
                    settingsSnapshotJson = source.settingsSnapshotJson,
                    target = source.target,
                    apiEndpointUrl = source.apiEndpointUrl,
                    folderUri = source.folderUri,
                    folderDisplayName = source.folderDisplayName,
                )
                openDetail(copy.id)
            }.onFailure { Timber.e(it, "Could not duplicate profile") }
        }
    }

    /**
     * Binds a profile to a newly picked SAF folder (persistable grant already taken by the UI).
     * When the profile is active the live device folder follows the binding so manual exports
     * write to it immediately.
     */
    fun bindProfileFolder(profileId: String, uri: Uri, displayName: String?) {
        viewModelScope.launch {
            runCatching {
                profileRepository.bindFolder(profileId, uri.toString(), displayName)
                if (uiState.value.rows.firstOrNull { it.isActive }?.profile?.id == profileId) {
                    profileCoordinator.activate(profileId)
                }
            }.onFailure { Timber.e(it, "Could not bind profile folder") }
        }
    }

    /** Deletes a profile and its schedule entry; the last remaining profile is never deleted. */
    fun delete(profileId: String) {
        viewModelScope.launch {
            runCatching {
                // Atomic order matters: the last-profile guard can refuse the profile
                // deletion, and then its scheduled entry must survive too.
                val deleted = profileCoordinator.delete(profileId)
                if (deleted || profileRepository.profileById(profileId) == null) {
                    // Keep the id long enough to remove alarms and both unique WorkManager chains;
                    // reconcile cannot discover runtime artifacts after the entry row is gone.
                    profileScheduler.removeEntry(profileId)
                }
                profileScheduler.reconcile()
            }.onFailure { Timber.e(it, "Could not delete profile") }
            _uiState.update {
                it.copy(pendingDeleteProfileId = null, detailProfileId = null)
            }
        }
    }

    fun saveEntry(entry: ScheduledProfileEntry) {
        viewModelScope.launch {
            runCatching {
                entryStore.upsert(entry)
                profileScheduler.reconcile()
            }.onFailure { Timber.e(it, "Could not save schedule entry") }
            _uiState.update { it.copy(editingScheduleProfileId = null) }
        }
    }

    // MARK: - Draft helpers

    /** Endpoint URL persisted for API targets; null keeps the profile unbound for folders. */
    private fun endpointBinding(draft: ExportProfileEditorDraft): String? = when (draft.target) {
        ExportTarget.API_ENDPOINT -> APIExportEndpoint.normalizedOrNull(draft.apiEndpointUrl)
            ?: throw IllegalArgumentException("API target requires a configured endpoint URL.")
        ExportTarget.DEVICE_FOLDER -> null
    }

    /** Folder binding persisted for folder targets; null for API targets. */
    private fun folderBinding(draft: ExportProfileEditorDraft): Pair<String?, String?>? =
        when (draft.target) {
            ExportTarget.DEVICE_FOLDER -> draft.folderUri to draft.folderDisplayName
            ExportTarget.API_ENDPOINT -> null
        }

    /**
     * Freezes the draft's editable settings into a canonical snapshot scoped to the chosen
     * target and endpoint. Capture also freezes the currently planned engine authority, matching
     * every other profile creation path; a null frozen pin remains reserved for explicit legacy.
     */
    private fun encodeDraftSnapshot(draft: ExportProfileEditorDraft): String {
        val scoped = draft.settings.copy(
            exportTarget = draft.target,
            scheduledExportTarget = draft.target,
            apiEndpointUrl = when (draft.target) {
                ExportTarget.API_ENDPOINT -> endpointBinding(draft)
                    ?: throw IllegalArgumentException("API target requires a configured endpoint URL.")
                ExportTarget.DEVICE_FOLDER -> draft.settings.apiEndpointUrl
            },
        )
        return snapshotFactory.captureFromCurrent(
            current = scoped,
            target = draft.target,
            apiEndpointUrl = scoped.apiEndpointUrl.takeIf {
                draft.target == ExportTarget.API_ENDPOINT
            },
        )
    }

    companion object {
        /**
         * Prefill suggestion for the creation form: "Profile", then "Profile 2", "Profile 3", …
         * skipping names already taken (case-insensitive).
         */
        fun suggestedProfileName(profiles: List<ExportProfile>): String =
            ExportProfileRules.uniquifyName("Profile", profiles)

        /**
         * Creation-form seed: name suggestion, the live target, the active profile's
         * destination binding, and the current live settings the form starts from.
         */
        fun initialCreationDraft(
            rows: List<ExportProfileRow>,
            currentSettings: ExportSettings,
        ): ExportProfileEditorDraft {
            val profiles = rows.map { it.profile }
            val active = rows.firstOrNull { it.isActive }?.profile
            return ExportProfileEditorDraft(
                name = suggestedProfileName(profiles),
                target = currentSettings.scheduledExportTarget,
                folderUri = active?.folderUri,
                folderDisplayName = active?.folderDisplayName,
                apiEndpointUrl = active?.apiEndpointUrl?.takeIf { it.isNotBlank() }
                    ?: currentSettings.apiEndpointUrl,
                settings = currentSettings,
            )
        }

        /**
         * Editor seed: the profile's frozen snapshot restored onto current plumbing (the
         * same restore path activation uses); a corrupt or mismatched snapshot falls back
         * to current live settings so the editor still opens.
         */
        fun initialEditDraft(
            profile: ExportProfile,
            currentSettings: ExportSettings,
        ): ExportProfileEditorDraft {
            val withProfileEndpoint = currentSettings.copy(
                apiEndpointUrl = profile.apiEndpointUrl ?: currentSettings.apiEndpointUrl,
            )
            val restored = AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)
                ?.let { snapshot ->
                    runCatching { snapshot.restoreOnto(withProfileEndpoint) }.getOrNull()
                }
                ?: currentSettings
            return ExportProfileEditorDraft(
                name = profile.name,
                target = profile.target,
                folderUri = profile.folderUri,
                folderDisplayName = profile.folderDisplayName,
                apiEndpointUrl = profile.apiEndpointUrl ?: currentSettings.apiEndpointUrl,
                settings = restored,
            )
        }
    }
}
