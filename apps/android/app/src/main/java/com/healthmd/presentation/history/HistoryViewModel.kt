package com.healthmd.presentation.history

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.ExportMode
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

@HiltViewModel
class HistoryViewModel @Inject constructor(
    private val exportHistoryRepository: ExportHistoryRepository,
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
    private val apiEndpointExportRunner: APIEndpointExportRunner? = null,
    private val rawSnapshotService: RawSnapshotService? = null,
) : ViewModel() {

    val entries: StateFlow<List<ExportHistoryEntry>> = exportHistoryRepository.getAllEntries()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    private val _uiState = MutableStateFlow(HistoryUiState())
    val uiState: StateFlow<HistoryUiState> = _uiState.asStateFlow()

    fun selectEntry(entry: ExportHistoryEntry) {
        _uiState.update { it.copy(selectedEntry = entry, retryMessage = null) }
    }

    fun dismissEntryDetails() {
        _uiState.update { it.copy(selectedEntry = null, retryMessage = null) }
    }

    fun requestClearHistory() {
        _uiState.update { it.copy(showClearConfirmation = true) }
    }

    fun dismissClearHistory() {
        _uiState.update { it.copy(showClearConfirmation = false) }
    }

    fun clearHistory() {
        viewModelScope.launch {
            exportHistoryRepository.clearAll()
            _uiState.update { it.copy(showClearConfirmation = false, selectedEntry = null) }
        }
    }

    fun retry(entry: ExportHistoryEntry) {
        if (_uiState.value.isRetrying) return

        viewModelScope.launch {
            _uiState.update { it.copy(isRetrying = true, retryMessage = null) }
            try {
                val settings = settingsRepository.getExportSettings().copy(exportMode = entry.exportMode)
                if (entry.target == ExportTarget.DEVICE_FOLDER && settingsRepository.getExportFolderUri() == null) {
                    _uiState.update { it.copy(retryMessage = "Select an export folder before retrying.") }
                    return@launch
                }
                if (entry.target == ExportTarget.API_ENDPOINT && !APIExportEndpoint.isConfigured(settings.apiEndpointUrl)) {
                    _uiState.update { it.copy(retryMessage = "Configure an API endpoint before retrying.") }
                    return@launch
                }
                if (!healthRepository.hasPermissions()) {
                    _uiState.update { it.copy(retryMessage = "Grant Health Connect permissions before retrying.") }
                    return@launch
                }

                val retryDates = if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                    ExportOrchestrator.dateRange(entry.dateRangeStart, entry.dateRangeEnd)
                } else {
                    retryDatesFor(entry)
                }
                val result = if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                    rawSnapshotService?.exportRange(
                        startDate = retryDates.first(),
                        endDate = retryDates.last(),
                        settings = settings,
                        target = entry.target,
                    ) ?: ExportResult(
                        successCount = 0,
                        totalCount = 1,
                        failedDateDetails = listOf(FailedDateDetail(retryDates.first(), ExportFailureReason.UNKNOWN, "Raw snapshot service unavailable")),
                        target = entry.target,
                        exportMode = ExportMode.RAW_SNAPSHOT,
                    )
                } else when (entry.target) {
                    ExportTarget.DEVICE_FOLDER -> ExportOrchestrator(healthRepository, exportRepository)
                        .exportDates(retryDates, settings)
                        .copy(target = ExportTarget.DEVICE_FOLDER)
                    ExportTarget.API_ENDPOINT -> apiEndpointExportRunner?.exportDates(
                        retryDates,
                        settings.copy(exportTarget = ExportTarget.API_ENDPOINT),
                    ) ?: ExportResult(
                        successCount = 0,
                        totalCount = retryDates.size,
                        failedDateDetails = retryDates.map {
                            FailedDateDetail(it, ExportFailureReason.NETWORK_ERROR, "API export service unavailable")
                        },
                        target = ExportTarget.API_ENDPOINT,
                    )
                }

                exportHistoryRepository.insertEntry(
                    ExportHistoryEntry(
                        timestamp = System.currentTimeMillis(),
                        source = ExportSource.RETRY,
                        dateRangeStart = retryDates.first(),
                        dateRangeEnd = retryDates.last(),
                        successCount = result.successCount,
                        totalCount = result.totalCount,
                        failureReason = result.primaryFailureReason,
                        failedDateDetails = result.failedDateDetails,
                        target = entry.target,
                        targetLabel = if (entry.target == ExportTarget.API_ENDPOINT) {
                            APIExportEndpoint.redactedDescription(settings.apiEndpointUrl)
                        } else entry.targetLabel,
                        fileCount = if (entry.target == ExportTarget.DEVICE_FOLDER) {
                            if (settings.exportMode == ExportMode.RAW_SNAPSHOT) result.successCount else estimatedFileCount(result.successCount, settings)
                        } else 0,
                        warningSummary = result.warningSummary(),
                        exportMode = result.exportMode,
                    )
                )
                _uiState.update {
                    it.copy(
                        selectedEntry = null,
                        retryMessage = if (result.isFullSuccess) {
                            "Retry completed."
                        } else if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                            "Raw snapshot retry failed. Review export history for details."
                        } else {
                            "Retry finished with ${result.failedDateDetails.size} failed date(s)."
                        },
                    )
                }
            } catch (e: Exception) {
                _uiState.update { it.copy(retryMessage = e.message ?: "Retry failed.") }
            } finally {
                _uiState.update { it.copy(isRetrying = false) }
            }
        }
    }

    private fun retryDatesFor(entry: ExportHistoryEntry): List<LocalDate> {
        val failedDates = entry.failedDateDetails.map { it.date }.distinct().sorted()
        if (failedDates.isNotEmpty()) return failedDates
        return ExportOrchestrator.dateRange(entry.dateRangeStart, entry.dateRangeEnd)
    }

    private fun estimatedFileCount(successCount: Int, settings: ExportSettings): Int =
        successCount * settings.selectedExportFormats.size

    private fun ExportResult.warningSummary(): String? = when {
        isPartialSuccess -> "${failedDateDetails.size} failed date(s)"
        wasCancelled -> "Export cancelled"
        else -> null
    }
}

data class HistoryUiState(
    val selectedEntry: ExportHistoryEntry? = null,
    val showClearConfirmation: Boolean = false,
    val isRetrying: Boolean = false,
    val retryMessage: String? = null,
)
