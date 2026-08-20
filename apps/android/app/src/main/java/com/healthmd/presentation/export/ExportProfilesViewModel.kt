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
import com.healthmd.domain.exportengine.ExportProfileOverlapDetector
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportSettingsSnapshotView
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

data class ExportProfilesUiState(
    val rows: List<ExportProfileRow> = emptyList(),
    val activeProfileName: String? = null,
    val detailProfileId: String? = null,
    val editingScheduleProfileId: String? = null,
    val renamingProfileId: String? = null,
    val pendingDeleteProfileId: String? = null,
)

/**
 * Dedicated export-profiles management surface (cross-platform parity with the iOS
 * `ExportProfilesView`): every profile at a glance with destination, schedule status,
 * formats, and metric count; detail inspection with the stable profile id used by
 * automation references; and activate / rename / duplicate / delete management.
 *
 * Activation applies the profile's frozen snapshot onto live settings through
 * [ExportProfileCoordinator] (editing-authority decision 1): the Export screen edits the
 * active profile, and edits flush back into it.
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
                profiles.map { profile ->
                    ExportProfileRow(
                        profile = profile,
                        isActive = profile.id == activeProfile?.id,
                        entry = entries.firstOrNull { it.profileId == profile.id },
                        snapshot = ExportProfileRules.decodeSnapshot(profile),
                        overlappingProfileNames = ExportProfileOverlapDetector
                            .overlappingProfileNames(profile.id, identities),
                    )
                }
            }.collect { rows ->
                _uiState.update { state ->
                    state.copy(
                        rows = rows,
                        activeProfileName = rows.firstOrNull { it.isActive }?.profile?.name,
                    )
                }
            }
        }
        // Bootstrap migration + initial arming, matching the schedule surface.
        viewModelScope.launch { runCatching { profileScheduler.reconcile() } }
    }

    /** Creates a profile duplicating current settings and activates the copy (iOS parity). */
    fun addFromCurrentSettings() {
        viewModelScope.launch {
            runCatching {
                val current = settingsRepository.getExportSettings()
                val target = current.scheduledExportTarget
                val endpointUrl = current.apiEndpointUrl.takeIf { it.isNotBlank() }
                // Duplicates inherit the active profile's folder binding (when set).
                val activeFolder = profileRepository.getActiveProfile()
                    ?.folderUri?.takeIf { it.isNotBlank() }
                    ?.let { uri -> uri to profileRepository.getActiveProfile()?.folderDisplayName }
                val profile = profileRepository.add(
                    name = defaultProfileName(),
                    settingsSnapshotJson = snapshotFactory.captureFromCurrent(
                        current = current,
                        target = target,
                        apiEndpointUrl = endpointUrl,
                    ),
                    target = target,
                    apiEndpointUrl = endpointUrl,
                    folderUri = activeFolder?.first,
                    folderDisplayName = activeFolder?.second,
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
        }
    }

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
                val deleted = profileRepository.delete(profileId)
                if (deleted || profileRepository.profileById(profileId) == null) {
                    entryStore.delete(profileId)
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

    private suspend fun defaultProfileName(): String {
        val count = profileRepository.getProfiles().size
        return if (count == 0) "Default" else "Profile ${count + 1}"
    }
}
