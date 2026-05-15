package com.healthmd.presentation.export

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.BillingRepository
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import timber.log.Timber
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
    private val billingRepository: BillingRepository,
    private val exportHistoryRepository: ExportHistoryRepository,
    private val fileExportManager: FileExportManager,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ExportUiState())
    val uiState: StateFlow<ExportUiState> = _uiState.asStateFlow()

    private val _requestReview = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val requestReview: SharedFlow<Unit> = _requestReview.asSharedFlow()

    private var exportJob: Job? = null
    private var dismissJob: Job? = null

    init {
        // Ensure billing client is connected so isUnlocked reflects real purchase state
        billingRepository.startConnection()

        viewModelScope.launch {
            // Combine persisted purchase state with live billing state — user is considered
            // purchased if either source confirms it (handles offline / just-purchased cases)
            val isPurchasedFlow = combine(
                settingsRepository.isPurchased,
                billingRepository.isUnlocked,
            ) { persisted, live -> persisted || live }

            combine(
                settingsRepository.exportSettings,
                settingsRepository.exportFolderUri,
                settingsRepository.freeExportsRemaining,
                isPurchasedFlow,
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

        // Persist confirmed purchases to DataStore so the state survives offline / app restarts
        viewModelScope.launch {
            billingRepository.isUnlocked
                .filter { it }
                .collect { settingsRepository.setPurchased(true) }
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
        // Block export if free tier is exhausted
        if (!_uiState.value.isPurchased && _uiState.value.freeExportsRemaining <= 0) return

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

            // Only a complete manual export consumes a free export.
            if (!_uiState.value.isPurchased && result.isFullSuccess) {
                settingsRepository.decrementFreeExports()
            }

            // Track complete exports and request review after 2nd success
            if (result.isFullSuccess) {
                settingsRepository.incrementSuccessfulExportCount()
                val count = settingsRepository.getSuccessfulExportCount()
                if (count >= 2 && !settingsRepository.hasRequestedReview()) {
                    settingsRepository.setReviewRequested()
                    _requestReview.tryEmit(Unit)
                    Timber.d("In-app review requested after $count successful exports")
                }
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
