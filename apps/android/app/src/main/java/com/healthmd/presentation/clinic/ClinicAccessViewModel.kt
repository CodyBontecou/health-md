package com.healthmd.presentation.clinic

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.billing.ClinicSponsorshipManager
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.ExportMode
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class ClinicAccessViewModel @Inject constructor(
    private val manager: ClinicSponsorshipManager,
    private val settings: SettingsRepository,
    private val profiles: ExportProfileRepository,
    private val coordinator: ExportProfileCoordinator,
    private val snapshots: ScheduledProfileSnapshotFactory,
    entitlements: com.healthmd.domain.repository.EntitlementRepository,
    private val syncRequests: com.healthmd.data.clinicsync.ClinicSyncDoorbellManager,
) : ViewModel() {
    val syncRequestState = syncRequests.state
    val syncRequestsAvailable: Boolean get() = syncRequests.pushAvailable

    val status = manager.status
    val independentAccess = entitlements.isUnlocked
    private val mutableBusy = MutableStateFlow(false)
    val busy = mutableBusy.asStateFlow()
    private val mutableError = MutableStateFlow(false)
    val error = mutableError.asStateFlow()

    fun enroll(code: String) = run { manager.enroll(code.trim()) }
    fun refresh() = run { manager.refresh() }
    fun resumeEnrollment() = run { manager.resumeEnrollment() }
    fun disconnect() = run { manager.disconnect() }
    fun setSharing(authorized: Boolean) = run { manager.setSharingAuthorized(authorized) }
    fun setSyncRequests(enabled: Boolean) {
        viewModelScope.launch { if (enabled) syncRequests.enable() else syncRequests.disable() }
    }

    fun useDestination(uploadToken: String, onDone: () -> Unit) = run {
        val state = status.value
        val endpoint = checkNotNull(state.endpoint)
        check(manager.authorizeCached(endpoint).isAllowed)
        if (uploadToken.isNotEmpty()) manager.setUploadAuthorization("Bearer $uploadToken")
        coordinator.flushEdits()
        val existing = profiles.getProfiles().firstOrNull {
            it.target == ExportTarget.API_ENDPOINT && it.apiEndpointUrl == endpoint
        }
        val profile = existing ?: kotlin.run {
            val current = settings.getExportSettings()
            val clinicSettings = current.copy(exportTarget = ExportTarget.API_ENDPOINT,
                scheduledExportTarget = ExportTarget.API_ENDPOINT, apiEndpointUrl = endpoint,
                exportMode = ExportMode.COMPATIBILITY, exportFormat = ExportFormat.JSON,
                exportFormats = setOf(ExportFormat.JSON),
                dailyNoteInjection = current.dailyNoteInjection.copy(enabled = false))
            profiles.add(state.clinicName ?: "Clinic", snapshots.captureFromCurrent(clinicSettings,
                ExportTarget.API_ENDPOINT, endpoint), ExportTarget.API_ENDPOINT, apiEndpointUrl = endpoint)
        }
        check(coordinator.activate(profile.id))
        onDone()
    }

    private fun run(action: suspend () -> Unit) {
        if (mutableBusy.value) return
        mutableBusy.value = true; mutableError.value = false
        viewModelScope.launch {
            try { action() }
            catch (error: Exception) { if (error is CancellationException) throw error; mutableError.value = true }
            finally { mutableBusy.value = false }
        }
    }
}
