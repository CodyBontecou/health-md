package com.healthmd.presentation.export

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import java.time.LocalDate
import javax.inject.Inject

data class ExportUiState(
    val startDate: LocalDate = LocalDate.now(),
    val endDate: LocalDate = LocalDate.now(),
    val exportFormat: ExportFormat = ExportFormat.MARKDOWN,
    val folderName: String? = null,
    val isExporting: Boolean = false,
    val exportProgress: Int = 0,
    val exportTotal: Int = 0,
    val exportProgressDate: String = "",
    val lastResult: ExportResult? = null,
    val exportedFolderUri: String? = null,
    val healthConnectAvailable: Boolean = true,
    val healthConnectNeedsSetup: Boolean = false,
    val hasPermissions: Boolean = false,
    val freeExportsRemaining: Int = 3,
    val isPurchased: Boolean = false,
)

@HiltViewModel
class ExportViewModel @Inject constructor(
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
    private val exportHistoryRepository: ExportHistoryRepository,
    private val fileExportManager: FileExportManager,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ExportUiState())
    val uiState: StateFlow<ExportUiState> = _uiState.asStateFlow()

    private var exportJob: Job? = null
    private var dismissJob: Job? = null

    init {
        viewModelScope.launch {
            combine(
                settingsRepository.exportSettings,
                settingsRepository.exportFolderUri,
                settingsRepository.freeExportsRemaining,
                settingsRepository.isPurchased,
            ) { settings, folderUri, freeExports, purchased ->
                _uiState.update {
                    it.copy(
                        exportFormat = settings.exportFormat,
                        folderName = folderUri?.let { uri -> fileExportManager.getFolderDisplayName(uri) },
                        freeExportsRemaining = freeExports,
                        isPurchased = purchased,
                    )
                }
            }.collect()
        }

        viewModelScope.launch {
            val available = healthRepository.isAvailable()
            val hasPerms = if (available) {
                try {
                    healthRepository.hasPermissions()
                } catch (_: Exception) {
                    // SDK_AVAILABLE but client init failed — Health Connect not set up yet
                    _uiState.update {
                        it.copy(healthConnectAvailable = true, healthConnectNeedsSetup = true)
                    }
                    return@launch
                }
            } else false
            _uiState.update {
                it.copy(healthConnectAvailable = available, hasPermissions = hasPerms)
            }
        }
    }

    fun setStartDate(date: LocalDate) {
        _uiState.update { it.copy(startDate = date) }
    }

    fun setEndDate(date: LocalDate) {
        _uiState.update { it.copy(endDate = date) }
    }

    fun selectAllTime() {
        viewModelScope.launch {
            val earliest = healthRepository.getEarliestDataDate()
                ?: LocalDate.now().minusDays(365)
            val end = LocalDate.now()
            _uiState.update { it.copy(startDate = earliest, endDate = end) }
        }
    }

    fun setExportFormat(format: ExportFormat) {
        viewModelScope.launch {
            val settings = settingsRepository.getExportSettings()
            settingsRepository.updateExportSettings(settings.copy(exportFormat = format))
        }
    }

    fun onFolderSelected(uri: Uri) {
        fileExportManager.takePersistablePermission(uri)
        viewModelScope.launch {
            settingsRepository.saveExportFolderUri(uri.toString())
            _uiState.update {
                it.copy(folderName = fileExportManager.getFolderDisplayName(uri.toString()))
            }
        }
    }

    fun startExport() {
        dismissJob?.cancel()
        exportJob = viewModelScope.launch {
            _uiState.update { it.copy(isExporting = true, lastResult = null, exportedFolderUri = null) }

            val settings = settingsRepository.getExportSettings()
            val dates = ExportOrchestrator.dateRange(_uiState.value.startDate, _uiState.value.endDate)

            val orchestrator = ExportOrchestrator(healthRepository, exportRepository)
            val result = orchestrator.exportDates(dates, settings) { current, total, dateStr ->
                _uiState.update {
                    it.copy(exportProgress = current, exportTotal = total, exportProgressDate = dateStr)
                }
            }

            // Record in history
            exportHistoryRepository.insertEntry(
                ExportHistoryEntry(
                    timestamp = System.currentTimeMillis(),
                    source = ExportSource.MANUAL,
                    dateRangeStart = _uiState.value.startDate,
                    dateRangeEnd = _uiState.value.endDate,
                    successCount = result.successCount,
                    totalCount = result.totalCount,
                    failureReason = result.primaryFailureReason,
                    failedDateDetails = result.failedDateDetails,
                )
            )

            // Decrement free export counter if not purchased
            if (!_uiState.value.isPurchased && result.successCount > 0) {
                settingsRepository.decrementFreeExports()
            }

            val folderUri = settingsRepository.getExportFolderUri()
            _uiState.update {
                it.copy(
                    isExporting = false,
                    lastResult = result,
                    exportedFolderUri = if (result.successCount > 0) folderUri else null,
                )
            }

            // Auto-dismiss the result toast after 5 seconds
            dismissJob = viewModelScope.launch {
                delay(5_000)
                _uiState.update { it.copy(lastResult = null, exportedFolderUri = null) }
            }
        }
    }

    fun dismissResult() {
        dismissJob?.cancel()
        _uiState.update { it.copy(lastResult = null, exportedFolderUri = null) }
    }

    fun cancelExport() {
        exportJob?.cancel()
    }

    fun refreshPermissions() {
        viewModelScope.launch {
            val hasPerms = try {
                healthRepository.hasPermissions()
            } catch (_: Exception) {
                _uiState.update { it.copy(healthConnectNeedsSetup = true) }
                return@launch
            }
            _uiState.update { it.copy(hasPermissions = hasPerms) }
        }
    }
}
