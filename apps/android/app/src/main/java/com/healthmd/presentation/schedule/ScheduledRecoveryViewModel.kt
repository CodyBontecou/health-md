package com.healthmd.presentation.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.scheduler.ScheduledExportRecoveryBlocker
import com.healthmd.data.scheduler.ScheduledExportRecoveryManager
import com.healthmd.data.scheduler.ScheduledExportRecoveryRunStatus
import com.healthmd.domain.model.ExportResult
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

@HiltViewModel
class ScheduledRecoveryViewModel @Inject constructor(
    private val recoveryManager: ScheduledExportRecoveryManager,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ScheduledRecoveryUiState())
    val uiState: StateFlow<ScheduledRecoveryUiState> = _uiState.asStateFlow()

    private var dismissedPendingSignature: String? = null

    fun refresh(autoPrompt: Boolean = false, forcePrompt: Boolean = false) {
        if (_uiState.value.isRunning) return

        viewModelScope.launch {
            val status = recoveryManager.inspectPendingRecovery()
            val signature = status.pendingDates.signature()
            val shouldPrompt = status.pendingDates.isNotEmpty() && when {
                forcePrompt -> true
                autoPrompt && status.canRecover -> dismissedPendingSignature != signature
                else -> false
            }

            _uiState.update {
                it.copy(
                    pendingDates = status.pendingDates,
                    blocker = status.blocker,
                    showPrompt = shouldPrompt || (it.showPrompt && status.pendingDates.isNotEmpty()),
                    lastResult = null,
                )
            }
        }
    }

    fun requestPromptFromNotification() {
        dismissedPendingSignature = null
        refresh(autoPrompt = true, forcePrompt = true)
    }

    fun dismissPrompt() {
        dismissedPendingSignature = _uiState.value.pendingDates.signature()
        _uiState.update { it.copy(showPrompt = false, lastResult = null) }
    }

    fun recoverNow() {
        if (_uiState.value.isRunning) return

        viewModelScope.launch {
            _uiState.update { it.copy(isRunning = true, lastResult = null) }
            val runResult = recoveryManager.recoverPendingDates()
            val latestStatus = recoveryManager.inspectPendingRecovery()
            val shouldKeepPromptOpen = when (runResult.status) {
                ScheduledExportRecoveryRunStatus.COMPLETED -> runResult.pendingDates.isNotEmpty()
                ScheduledExportRecoveryRunStatus.BLOCKED,
                ScheduledExportRecoveryRunStatus.ALREADY_RUNNING -> true
            }

            if (latestStatus.pendingDates.isEmpty()) {
                dismissedPendingSignature = null
            }

            _uiState.update {
                it.copy(
                    pendingDates = latestStatus.pendingDates,
                    blocker = latestStatus.blocker,
                    showPrompt = shouldKeepPromptOpen && latestStatus.pendingDates.isNotEmpty(),
                    isRunning = false,
                    lastResult = ScheduledRecoveryResultMessage(
                        status = runResult.status,
                        blocker = runResult.blocker,
                        exportResult = runResult.exportResult,
                    ),
                )
            }
        }
    }

    private fun List<LocalDate>.signature(): String = joinToString("|") { it.toString() }
}

data class ScheduledRecoveryUiState(
    val pendingDates: List<LocalDate> = emptyList(),
    val blocker: ScheduledExportRecoveryBlocker? = null,
    val showPrompt: Boolean = false,
    val isRunning: Boolean = false,
    val lastResult: ScheduledRecoveryResultMessage? = null,
) {
    val canRecover: Boolean get() = pendingDates.isNotEmpty() && blocker == null
}

data class ScheduledRecoveryResultMessage(
    val status: ScheduledExportRecoveryRunStatus,
    val blocker: ScheduledExportRecoveryBlocker?,
    val exportResult: ExportResult?,
)
