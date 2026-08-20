package com.healthmd.presentation.drive

import android.content.Context
import android.content.Intent
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
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
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
    @ApplicationContext private val context: Context,
) : ViewModel() {
    private val mutableState = MutableStateFlow(GoogleDriveUiState(readiness = authorization.readiness()))
    val state: StateFlow<GoogleDriveUiState> = mutableState.asStateFlow()
    private var expectedDestinationId: String? = null
    private var pendingOperationId: String? = null

    init { refresh() }

    fun setPendingOperation(operationId: String?) {
        pendingOperationId = operationId?.takeIf { it.matches(Regex("[A-Za-z0-9._-]{1,128}")) }
    }

    fun begin(onAction: (GoogleDriveAuthorizationAction) -> Unit) {
        if (mutableState.value.busy) return
        mutableState.update { it.copy(busy = true, error = null) }
        viewModelScope.launch {
            expectedDestinationId = mutableState.value.destination?.id
            val action = authorization.beginPicker(expectedDestinationId)
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
            authorization.disconnect(id)
            selectionStore.select(null)
            mutableState.value = GoogleDriveUiState(readiness = authorization.readiness())
        }
    }

    fun clearError() = mutableState.update { it.copy(error = null) }

    private suspend fun bind(grant: GoogleDriveAuthorizationGrant) {
        when (val result = authorization.bind(grant, expectedDestinationId)) {
            is DriveApiResult.Success -> {
                selectionStore.select(result.value.id)
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
}
