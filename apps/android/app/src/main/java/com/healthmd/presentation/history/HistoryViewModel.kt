package com.healthmd.presentation.history

import androidx.annotation.PluralsRes
import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.R
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.ExportAwakeCoordinator
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.data.drive.GoogleDriveDestinationRunner
import com.healthmd.data.drive.GoogleDriveRunResult
import com.healthmd.data.drive.toFailureReason
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
import timber.log.Timber

@HiltViewModel
class HistoryViewModel @Inject constructor(
    private val exportHistoryRepository: ExportHistoryRepository,
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
    private val apiEndpointExportRunner: APIEndpointExportRunner? = null,
    private val rawSnapshotService: RawSnapshotService? = null,
    private val googleDriveDestinationRunner: GoogleDriveDestinationRunner,
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
            val awakeActivityId = ExportAwakeCoordinator.shared.beginActivity()
            _uiState.update { it.copy(isRetrying = true, retryMessage = null) }
            try {
                val settings = settingsRepository.getExportSettings().copy(exportMode = entry.exportMode)
                if (entry.target == ExportTarget.DEVICE_FOLDER && settingsRepository.getExportFolderUri() == null) {
                    _uiState.update {
                        it.copy(retryMessage = HistoryUiMessage.Text(R.string.history_retry_folder_required))
                    }
                    return@launch
                }
                if (entry.target == ExportTarget.API_ENDPOINT && !APIExportEndpoint.isConfigured(settings.apiEndpointUrl)) {
                    _uiState.update {
                        it.copy(retryMessage = HistoryUiMessage.Text(R.string.history_retry_api_required))
                    }
                    return@launch
                }
                val resumesDriveJournal = entry.target == ExportTarget.GOOGLE_DRIVE && entry.driveOperationId != null
                if (!resumesDriveJournal && !healthRepository.hasPermissions()) {
                    _uiState.update {
                        it.copy(retryMessage = HistoryUiMessage.Text(R.string.history_retry_permissions_required))
                    }
                    return@launch
                }

                val retryDates = if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                    ExportOrchestrator.dateRange(entry.dateRangeStart, entry.dateRangeEnd)
                } else {
                    retryDatesFor(entry)
                }
                val result = if (resumesDriveJournal) {
                    when (val resumed = googleDriveDestinationRunner.resume(requireNotNull(entry.driveOperationId))) {
                        is GoogleDriveRunResult.Complete -> ExportResult(
                            successCount = retryDates.size,
                            totalCount = retryDates.size,
                            target = ExportTarget.GOOGLE_DRIVE,
                            exportMode = entry.exportMode,
                            artifactCount = resumed.artifactCount,
                        )
                        is GoogleDriveRunResult.Stopped -> ExportResult(
                            successCount = 0,
                            totalCount = retryDates.size,
                            failedDateDetails = retryDates.map {
                                FailedDateDetail(it, resumed.error.toFailureReason())
                            },
                            target = ExportTarget.GOOGLE_DRIVE,
                            exportMode = entry.exportMode,
                            artifactCount = resumed.completedArtifactCount,
                            retryDriveOperationIds = retryDates.associateWith {
                                requireNotNull(entry.driveOperationId)
                            },
                        )
                    }
                } else if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                    rawSnapshotService?.exportRange(
                        startDate = retryDates.first(),
                        endDate = retryDates.last(),
                        settings = settings,
                        target = entry.target,
                    ) ?: ExportResult(
                        successCount = 0,
                        totalCount = 1,
                        failedDateDetails = listOf(
                            FailedDateDetail(retryDates.first(), ExportFailureReason.UNKNOWN),
                        ),
                        target = entry.target,
                        exportMode = ExportMode.RAW_SNAPSHOT,
                    ).also {
                        Timber.w("Raw snapshot service unavailable while retrying export history")
                    }
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
                            FailedDateDetail(it, ExportFailureReason.NETWORK_ERROR)
                        },
                        target = ExportTarget.API_ENDPOINT,
                    ).also {
                        Timber.w("API export service unavailable while retrying export history")
                    }
                    ExportTarget.GOOGLE_DRIVE -> ExportResult(
                        0,
                        retryDates.size,
                        retryDates.map { FailedDateDetail(it, ExportFailureReason.FILE_WRITE_ERROR) },
                        target = ExportTarget.GOOGLE_DRIVE,
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
                        fileCount = when (entry.target) {
                            ExportTarget.DEVICE_FOLDER -> if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                                result.artifactCount
                            } else {
                                estimatedFileCount(result.successCount, settings)
                            }
                            ExportTarget.GOOGLE_DRIVE -> result.artifactCount
                            ExportTarget.API_ENDPOINT -> 0
                        },
                        // The UI derives a localized warning from the typed result fields.
                        warningSummary = null,
                        exportMode = result.exportMode,
                        driveOperationId = result.retryDriveOperationIds.values.firstOrNull(),
                    )
                )
                if (result.isFullSuccess && entry.target == ExportTarget.GOOGLE_DRIVE) {
                    entry.driveOperationId?.let { googleDriveDestinationRunner.acknowledgeAfterHistory(it) }
                }
                _uiState.update {
                    it.copy(
                        selectedEntry = null,
                        retryMessage = if (result.isFullSuccess) {
                            HistoryUiMessage.Text(R.string.history_retry_complete)
                        } else if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                            HistoryUiMessage.Text(R.string.history_retry_raw_failed)
                        } else {
                            HistoryUiMessage.Plural(
                                resourceId = R.plurals.history_retry_failed_dates,
                                quantity = result.failedDateDetails.size,
                                arguments = listOf(result.failedDateDetails.size),
                            )
                        },
                    )
                }
            } catch (error: Exception) {
                Timber.e(error, "Export history retry failed")
                _uiState.update {
                    it.copy(retryMessage = HistoryUiMessage.Text(R.string.history_retry_failed))
                }
            } finally {
                ExportAwakeCoordinator.shared.endActivity(awakeActivityId)
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
}

sealed interface HistoryUiMessage {
    data class Text(
        @StringRes val resourceId: Int,
        val arguments: List<Any> = emptyList(),
    ) : HistoryUiMessage

    data class Plural(
        @PluralsRes val resourceId: Int,
        val quantity: Int,
        val arguments: List<Any> = emptyList(),
    ) : HistoryUiMessage
}

data class HistoryUiState(
    val selectedEntry: ExportHistoryEntry? = null,
    val showClearConfirmation: Boolean = false,
    val isRetrying: Boolean = false,
    val retryMessage: HistoryUiMessage? = null,
)
