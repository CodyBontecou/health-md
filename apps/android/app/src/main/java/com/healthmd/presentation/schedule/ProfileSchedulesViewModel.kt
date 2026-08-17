package com.healthmd.presentation.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileUsageProjection
import com.healthmd.data.scheduler.ScheduledProfileScheduler
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
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

/** One row in the profile-schedules section. */
data class ProfileScheduleRow(
    val profile: ExportProfile,
    val entry: ScheduledProfileEntry?,
)

data class ProfileSchedulesUiState(
    val rows: List<ProfileScheduleRow> = emptyList(),
    val projectedMonthlyRequests: Int = 0,
    val editingProfileId: String? = null,
)

/**
 * Phase-6 QA slice: per-profile schedule management on the Schedule screen. Profile creation
 * duplicates current settings (captured through the frozen snapshot factory); edits go through
 * [ScheduledProfileEntryStore] and every mutation re-arms alarms via [ScheduledProfileScheduler].
 */
@HiltViewModel
class ProfileSchedulesViewModel @Inject constructor(
    private val profileRepository: ExportProfileRepository,
    private val entryStore: ScheduledProfileEntryStore,
    private val profileScheduler: ScheduledProfileScheduler,
    private val snapshotFactory: ScheduledProfileSnapshotFactory,
    private val settingsRepository: SettingsRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ProfileSchedulesUiState())
    val uiState: StateFlow<ProfileSchedulesUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            combine(
                profileRepository.profiles,
                profileRepository.activeProfileId,
                entryStore.entries,
            ) { profiles, _, entries ->
                profiles.map { profile ->
                    ProfileScheduleRow(profile, entries.firstOrNull { it.profileId == profile.id })
                }
            }.collect { rows ->
                _uiState.update { state ->
                    state.copy(
                        rows = rows,
                        projectedMonthlyRequests = rows.sumOf { row ->
                            if (row.entry?.isEnabled == true) {
                                ScheduledProfileUsageProjection.projectedMonthlyRequests(row.entry)
                            } else 0
                        },
                    )
                }
            }
        }
        // Bootstrap migration + initial arming.
        viewModelScope.launch { runCatching { profileScheduler.reconcile() } }
    }

    /** Creates a profile duplicating current settings, bound to the current target/endpoint. */
    fun addProfileFromCurrentSettings() {
        viewModelScope.launch {
            runCatching {
                val current: ExportSettings = settingsRepository.getExportSettings()
                val profile = profileRepository.add(
                    name = defaultProfileName(),
                    settingsSnapshotJson = snapshotFactory.captureFromCurrent(
                        current = current,
                        target = current.scheduledExportTarget,
                        apiEndpointUrl = current.apiEndpointUrl.takeIf { it.isNotBlank() },
                    ),
                    target = current.scheduledExportTarget,
                    apiEndpointUrl = current.apiEndpointUrl.takeIf { it.isNotBlank() },
                )
                // Seed the new profile's entry from the legacy preferred time.
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
            }.onFailure { Timber.e(it, "Could not create profile") }
        }
    }

    fun setEnabled(profileId: String, enabled: Boolean) {
        viewModelScope.launch {
            val existing = entryStore.entry(profileId)
            if (existing == null) {
                val settings = settingsRepository.getExportSettings()
                entryStore.upsert(
                    ScheduledProfileEntry(
                        profileId = profileId,
                        isEnabled = enabled,
                        anchorEpochDay = java.time.LocalDate.now().toEpochDay(),
                        hour = settings.scheduleHour.coerceIn(0, 23),
                        minute = settings.scheduleMinute.coerceIn(0, 59),
                        cadenceUnit = ScheduledProfileCadenceUnit.DAY,
                        lookbackDays = 1,
                        zoneId = java.time.ZoneId.systemDefault().id,
                    ),
                )
            } else {
                entryStore.update(profileId) { it.copy(isEnabled = enabled) }
            }
            profileScheduler.reconcile()
        }
    }

    fun saveEntry(entry: ScheduledProfileEntry) {
        viewModelScope.launch {
            entryStore.upsert(entry)
            profileScheduler.reconcile()
            _uiState.update { it.copy(editingProfileId = null) }
        }
    }

    fun openEditor(profileId: String?) {
        _uiState.update { it.copy(editingProfileId = profileId) }
    }

    fun deleteProfile(profileId: String) {
        viewModelScope.launch {
            runCatching {
                profileRepository.delete(profileId)
                entryStore.delete(profileId)
                profileScheduler.reconcile()
            }.onFailure { Timber.e(it, "Could not delete profile") }
        }
    }

    private suspend fun defaultProfileName(): String {
        val count = profileRepository.getProfiles().size
        return if (count == 0) "Default" else "Profile ${count + 1}"
    }
}
