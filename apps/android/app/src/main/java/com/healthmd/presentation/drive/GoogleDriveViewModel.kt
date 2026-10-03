package com.healthmd.presentation.drive

import android.content.Context
import android.content.Intent
import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.drive.DriveApiResult
import com.healthmd.data.drive.GoogleDriveAuthorizationAction
import com.healthmd.data.drive.GoogleDriveAuthorizationGrant
import com.healthmd.data.drive.GoogleDriveAuthorizationManager
import com.healthmd.data.drive.GoogleDriveDestination
import com.healthmd.data.drive.GoogleDriveDestinationStore
import com.healthmd.data.drive.GoogleDriveErrorId
import com.healthmd.data.drive.GoogleDriveReadiness
import com.healthmd.data.drive.GoogleDriveRecoveryWorker
import com.healthmd.data.drive.GoogleDriveSelectionStore
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

data class GoogleDriveUiState(
    val readiness: GoogleDriveReadiness = GoogleDriveReadiness.Unavailable(GoogleDriveErrorId.CONFIGURATION_MISSING),
    val destination: GoogleDriveDestination? = null,
    val busy: Boolean = false,
    val error: GoogleDriveErrorId? = null,
)

@HiltViewModel
class GoogleDriveViewModel @Inject constructor(
    private val authorization: GoogleDriveAuthorizationManager,
    private val destinationStore: GoogleDriveDestinationStore,
    private val selectionStore: GoogleDriveSelectionStore,
    private val settingsRepository: SettingsRepository,
    private val savedStateHandle: SavedStateHandle,
    @ApplicationContext private val context: Context,
) : ViewModel() {
    private val mutableState = MutableStateFlow(GoogleDriveUiState(readiness = authorization.readiness()))
    val state: StateFlow<GoogleDriveUiState> = mutableState.asStateFlow()
    private var expectedDestinationId: String?
        get() = savedStateHandle[EXPECTED_DESTINATION_ID]
        set(value) { savedStateHandle[EXPECTED_DESTINATION_ID] = value }
    private var pendingOperationId: String?
        get() = savedStateHandle[PENDING_OPERATION_ID]
        set(value) { savedStateHandle[PENDING_OPERATION_ID] = value }

    init { refresh() }

    fun setPendingOperation(operationId: String?) {
        pendingOperationId = operationId?.takeIf { it.matches(Regex("[A-Za-z0-9._-]{1,128}")) }
    }

    fun begin(onAction: (GoogleDriveAuthorizationAction) -> Unit) {
        if (mutableState.value.busy) return
        mutableState.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            if (configurationProtected()) return@launch
            expectedDestinationId = mutableState.value.destination?.id
            val action = authorization.beginPicker(expectedDestinationId)
            if (configurationProtected()) return@launch
            if (action is GoogleDriveAuthorizationAction.Authorized) {
                bind(action.grant)
            } else {
                if (action !is GoogleDriveAuthorizationAction.Launch) {
                    mutableState.update { it.copy(busy = false, error = (action as GoogleDriveAuthorizationAction.Failed).error) }
                }
                onAction(action)
            }
        }
    }

    fun finish(data: Intent?) {
        when (val action = authorization.finishPicker(data, expectedDestinationId)) {
            is GoogleDriveAuthorizationAction.Authorized -> viewModelScope.launch { bind(action.grant) }
            is GoogleDriveAuthorizationAction.Launch -> mutableState.update {
                it.copy(busy = false, error = GoogleDriveErrorId.REAUTHORIZATION_REQUIRED)
            }
            is GoogleDriveAuthorizationAction.Failed -> mutableState.update { it.copy(busy = false, error = action.error) }
        }
    }

    fun disconnect() {
        val id = mutableState.value.destination?.id ?: return
        mutableState.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            if (configurationProtected()) return@launch
            // Revocation may suspend. The service admits every local removal in one protected
            // edit afterwards; denial leaves local bindings/schedules/selection/authority intact.
            if (!authorization.disconnect(id)) {
                mutableState.update { it.copy(busy = false, error = GoogleDriveErrorId.PERMISSION_DENIED) }
                return@launch
            }
            expectedDestinationId = null
            mutableState.value = GoogleDriveUiState(readiness = authorization.readiness())
        }
    }

    fun clearError() = mutableState.update { it.copy(error = null) }

    private suspend fun configurationProtected(): Boolean {
        if (!settingsRepository.preventAccidentalChanges.first()) return false
        mutableState.update { it.copy(busy = false, error = GoogleDriveErrorId.PERMISSION_DENIED) }
        return true
    }

    private suspend fun bind(grant: GoogleDriveAuthorizationGrant) {
        // Includes results delivered after Activity recreation or after protection changed.
        if (configurationProtected()) return
        when (val result = authorization.bind(grant, expectedDestinationId)) {
            is DriveApiResult.Success -> {
                if (configurationProtected() || !selectionStore.selectIfAllowed(result.value.id)) {
                    mutableState.update { it.copy(busy = false, error = GoogleDriveErrorId.PERMISSION_DENIED) }
                    return
                }
                mutableState.update { it.copy(destination = result.value, busy = false, error = null) }
                pendingOperationId?.let { operationId ->
                    GoogleDriveRecoveryWorker.enqueue(context, operationId)
                    pendingOperationId = null
                }
            }
            is DriveApiResult.Failure -> mutableState.update { it.copy(busy = false, error = result.error) }
        }
    }

    private fun refresh() {
        viewModelScope.launch {
            val id = selectionStore.get()
            mutableState.update {
                it.copy(
                    readiness = authorization.readiness(),
                    destination = id?.let { selected -> destinationStore.find(selected) },
                )
            }
        }
    }

    private companion object {
        const val EXPECTED_DESTINATION_ID = "google_drive_expected_destination_id"
        const val PENDING_OPERATION_ID = "google_drive_pending_operation_id"
    }
}
