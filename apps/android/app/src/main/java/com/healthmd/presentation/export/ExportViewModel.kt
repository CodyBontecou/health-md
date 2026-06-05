package com.healthmd.presentation.export

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.export.ExportAccountingPolicy
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
    val exportFormats: Set<ExportFormat> = setOf(ExportFormat.MARKDOWN),
    val settings: ExportSettings = ExportSettings(),
    val folderName: String? = null,
    val isExporting: Boolean = false,
    val isPreviewing: Boolean = false,
    val exportProgress: Int = 0,
    val exportTotal: Int = 0,
    val exportProgressDate: String = "",
    val lastResult: ExportResult? = null,
    val preview: ExportPreview? = null,
    val exportedFolderUri: String? = null,
    val healthConnectAvailable: Boolean = true,
    val healthConnectNeedsSetup: Boolean = false,
    val hasPermissions: Boolean = false,
    val hasHistoricalReadPermission: Boolean = false,
    val allTimeSelected: Boolean = false,
    val freeExportsRemaining: Int = 3,
    val isPurchased: Boolean = false,
) {
    val requiresHistoricalReadPermission: Boolean
        get() = allTimeSelected || ExportHistoryAccess.requiresHistoricalReadPermission(startDate, endDate)

    val historyPermissionNeeded: Boolean
        get() = requiresHistoricalReadPermission && !hasHistoricalReadPermission
}

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
                        exportFormats = settings.selectedExportFormats,
                        settings = settings,
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
            val hasHistoricalPerms = if (available) {
                try {
                    healthRepository.hasHistoricalReadPermission()
                } catch (_: Exception) {
                    false
                }
            } else false
            _uiState.update {
                it.copy(
                    healthConnectAvailable = available,
                    hasPermissions = hasPerms,
                    hasHistoricalReadPermission = hasHistoricalPerms,
                )
            }
        }
    }

    fun setStartDate(date: LocalDate) {
        _uiState.update { it.copy(startDate = date, allTimeSelected = false) }
    }

    fun setEndDate(date: LocalDate) {
        _uiState.update { it.copy(endDate = date, allTimeSelected = false) }
    }

    fun setDateRange(startDate: LocalDate, endDate: LocalDate) {
        _uiState.update { it.copy(startDate = startDate, endDate = endDate) }
    }

    fun selectAllTime() {
        viewModelScope.launch {
            val earliest = healthRepository.getEarliestDataDate()
                ?: LocalDate.now().minusDays(365)
            val end = LocalDate.now()
            _uiState.update { it.copy(startDate = earliest, endDate = end, allTimeSelected = true) }
        }
    }

    fun setExportFormat(format: ExportFormat) {
        viewModelScope.launch {
            val settings = settingsRepository.getExportSettings()
            settingsRepository.updateExportSettings(settings.copy(exportFormat = format, exportFormats = setOf(format)))
        }
    }

    fun toggleExportFormat(format: ExportFormat) {
        viewModelScope.launch {
            val settings = settingsRepository.getExportSettings()
            val newFormats = if (format in settings.selectedExportFormats) {
                settings.selectedExportFormats - format
            } else {
                settings.selectedExportFormats + format
            }
            settingsRepository.updateExportSettings(
                settings.copy(
                    exportFormats = newFormats,
                    exportFormat = newFormats.firstOrNull() ?: settings.exportFormat,
                )
            )
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

        val currentState = _uiState.value
        if (!currentState.hasPermissions || currentState.folderName == null ||
            currentState.historyPermissionNeeded || currentState.exportFormats.isEmpty()) {
            return
        }

        dismissJob?.cancel()
        exportJob = viewModelScope.launch {
            _uiState.update { it.copy(isExporting = true, lastResult = null, preview = null, exportedFolderUri = null) }

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
                    targetLabel = _uiState.value.folderName,
                    fileCount = estimatedFileCount(result.successCount, settings),
                    warningSummary = result.warningSummary(),
                )
            )

            // Only complete manual exports consume free-tier quota.
            if (ExportAccountingPolicy.shouldConsumeFreeExport(result, _uiState.value.isPurchased)) {
                settingsRepository.decrementFreeExports()
            }

            // Review prompts use their own counter, separate from free-tier quota.
            if (ExportAccountingPolicy.shouldCountForReviewPrompt(result)) {
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

            if (result.toDiagnosticsSummary().shouldAutoDismiss) {
                // Auto-dismiss successful result badges after 5 seconds. Partial and failed
                // exports stay visible so users can inspect the diagnostics.
                dismissJob = viewModelScope.launch {
                    delay(5_000)
                    _uiState.update { it.copy(lastResult = null, exportedFolderUri = null) }
                }
            }
        }
    }

    fun buildPreview() {
        dismissJob?.cancel()
        val currentState = _uiState.value
        if (!currentState.hasPermissions || currentState.folderName == null ||
            currentState.historyPermissionNeeded || currentState.exportFormats.isEmpty()) {
            return
        }

        exportJob = viewModelScope.launch {
            _uiState.update {
                it.copy(
                    isPreviewing = true,
                    preview = null,
                    lastResult = null,
                    exportedFolderUri = null,
                )
            }

            try {
                val settings = settingsRepository.getExportSettings()
                val dates = ExportOrchestrator.dateRange(_uiState.value.startDate, _uiState.value.endDate)
                val orchestrator = ExportOrchestrator(healthRepository, exportRepository)
                val preview = orchestrator.previewDates(dates, settings) { current, total, dateStr ->
                    _uiState.update {
                        it.copy(exportProgress = current, exportTotal = total, exportProgressDate = dateStr)
                    }
                }

                _uiState.update { it.copy(preview = preview) }
            } finally {
                _uiState.update { it.copy(isPreviewing = false) }
            }
        }
    }

    fun dismissPreview() {
        _uiState.update { it.copy(preview = null) }
    }

    fun dismissResult() {
        dismissJob?.cancel()
        _uiState.update { it.copy(lastResult = null, exportedFolderUri = null) }
    }

    fun cancelExport() {
        exportJob?.cancel()
    }

    private fun estimatedFileCount(successCount: Int, settings: ExportSettings): Int =
        successCount * settings.selectedExportFormats.size

    private fun ExportResult.warningSummary(): String? = when {
        isPartialSuccess -> "${failedDateDetails.size} failed date(s)"
        wasCancelled -> "Export cancelled"
        else -> null
    }

    fun refreshPermissions() {
        viewModelScope.launch {
            val hasPerms = try {
                healthRepository.hasPermissions()
            } catch (_: Exception) {
                _uiState.update { it.copy(healthConnectNeedsSetup = true) }
                return@launch
            }
            val hasHistoricalPerms = try {
                healthRepository.hasHistoricalReadPermission()
            } catch (_: Exception) {
                false
            }
            val refreshedAllTimeStart = if (hasHistoricalPerms && _uiState.value.allTimeSelected) {
                try {
                    healthRepository.getEarliestDataDate()
                } catch (_: Exception) {
                    null
                }
            } else {
                null
            }
            _uiState.update {
                it.copy(
                    startDate = refreshedAllTimeStart ?: it.startDate,
                    hasPermissions = hasPerms,
                    hasHistoricalReadPermission = hasHistoricalPerms,
                )
            }
        }
    }
}
