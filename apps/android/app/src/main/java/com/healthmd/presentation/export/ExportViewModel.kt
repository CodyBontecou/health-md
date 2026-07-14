package com.healthmd.presentation.export

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportHeaders
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.scheduler.ExportScheduler
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
    val firstHealthPermissionGrantDate: LocalDate? = null,
    val allTimeSelected: Boolean = false,
    val freeExportsRemaining: Int = 3,
    val isPurchased: Boolean = false,
    val apiAuthorizationConfigured: Boolean = false,
    val apiRequestHeadersConfigured: Boolean = false,
    val apiConfigurationError: String? = null,
) {
    val requiresHistoricalReadPermission: Boolean
        get() = allTimeSelected || ExportHistoryAccess.requiresHistoricalReadPermission(
            startDate = startDate,
            endDate = endDate,
            firstPermissionGrantDate = firstHealthPermissionGrantDate,
        )

    val historyPermissionNeeded: Boolean
        get() = requiresHistoricalReadPermission && !hasHistoricalReadPermission

    val selectedTarget: ExportTarget
        get() = settings.exportTarget

    val apiEndpointConfigured: Boolean
        get() = APIExportEndpoint.isConfigured(settings.apiEndpointUrl)

    val destinationReady: Boolean
        get() = when (selectedTarget) {
            ExportTarget.DEVICE_FOLDER -> folderName != null
            ExportTarget.API_ENDPOINT -> apiEndpointConfigured
        }

    val destinationLabel: String?
        get() = when (selectedTarget) {
            ExportTarget.DEVICE_FOLDER -> folderName
            ExportTarget.API_ENDPOINT -> APIExportEndpoint.displayName(settings.apiEndpointUrl)
        }
}

@HiltViewModel
class ExportViewModel @Inject constructor(
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
    private val billingRepository: BillingRepository,
    private val exportHistoryRepository: ExportHistoryRepository,
    private val fileExportManager: FileExportManager,
    private val apiEndpointExportRunner: APIEndpointExportRunner? = null,
    private val apiCredentialStore: APIExportCredentialStore? = null,
    private val exportScheduler: ExportScheduler? = null,
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
                settingsRepository.firstHealthPermissionGrantDate,
            ) { settings, folderUri, freeExports, purchased, firstGrantDate ->
                _uiState.update {
                    it.copy(
                        exportFormat = settings.exportFormat,
                        exportFormats = settings.selectedExportFormats,
                        settings = settings,
                        folderName = folderUri?.let { uri -> fileExportManager.getFolderDisplayName(uri) },
                        freeExportsRemaining = freeExports,
                        isPurchased = purchased,
                        firstHealthPermissionGrantDate = firstGrantDate,
                    )
                }
            }.collect()
        }

        refreshAPIAuthorizationStatus()

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
            if (hasPerms) {
                settingsRepository.recordHealthPermissionGrantDateIfAbsent(LocalDate.now())
            }
            val hasHistoricalPerms = if (available) {
                try {
                    healthRepository.hasHistoricalReadPermission()
                } catch (_: Exception) {
                    false
                }
            } else false
            val firstGrantDate = settingsRepository.getFirstHealthPermissionGrantDate()
            _uiState.update {
                it.copy(
                    healthConnectAvailable = available,
                    hasPermissions = hasPerms,
                    hasHistoricalReadPermission = hasHistoricalPerms,
                    firstHealthPermissionGrantDate = firstGrantDate,
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
        _uiState.update { it.copy(startDate = startDate, endDate = endDate, allTimeSelected = false) }
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
        updateSettings { settings ->
            val newFormats = if (format in settings.selectedExportFormats) {
                settings.selectedExportFormats - format
            } else {
                settings.selectedExportFormats + format
            }
            settings.copy(
                exportFormats = newFormats,
                exportFormat = newFormats.firstOrNull() ?: settings.exportFormat,
            )
        }
    }

    fun updateWriteMode(mode: WriteMode) = updateSettings { it.copy(writeMode = mode) }
    fun updateFilenameFormat(format: String) = updateSettings { it.copy(filenameFormat = format) }
    fun updateSubfolder(subfolder: String) = updateSettings { it.copy(subfolder = subfolder) }
    fun updateFolderOrganization(org: FolderOrganization) = updateSettings { it.copy(folderOrganization = org) }
    fun updateFolderStructure(structure: String) = updateSettings { it.copy(folderStructure = structure) }
    fun updateIncludeMetadata(include: Boolean) = updateSettings { it.copy(includeMetadata = include) }
    fun updateGroupByCategory(group: Boolean) = updateSettings { it.copy(groupByCategory = group) }
    fun updateUseEmoji(use: Boolean) = updateFormatCustomization {
        it.copy(markdownTemplate = it.markdownTemplate.copy(useEmoji = use))
    }
    fun updateUnitPreference(pref: UnitPreference) = updateFormatCustomization { it.copy(unitPreference = pref) }

    fun setExportTarget(target: ExportTarget) = updateSettings { it.copy(exportTarget = target) }

    fun saveAPIExportConfiguration(
        endpointUrl: String,
        authorization: String?,
        requestHeaders: String?,
    ) {
        viewModelScope.launch {
            val normalized = APIExportEndpoint.normalizedOrNull(endpointUrl)
            if (normalized == null) {
                _uiState.update { it.copy(apiConfigurationError = "Enter a valid HTTP or HTTPS URL without a fragment or embedded username/password.") }
                return@launch
            }
            val headerError = requestHeaders
                ?.takeIf { it.isNotBlank() }
                ?.let { raw -> runCatching { APIExportHeaders.parse(raw) }.exceptionOrNull()?.message }
            if (headerError != null) {
                _uiState.update { it.copy(apiConfigurationError = headerError) }
                return@launch
            }
            try {
                authorization?.takeIf { it.isNotBlank() }?.let { apiCredentialStore?.saveAuthorization(it) }
                requestHeaders?.takeIf { it.isNotBlank() }?.let { apiCredentialStore?.saveRequestHeaders(it) }
                val current = settingsRepository.getExportSettings()
                settingsRepository.updateExportSettings(
                    current.copy(apiEndpointUrl = normalized, exportTarget = ExportTarget.API_ENDPOINT)
                )
                _uiState.update { it.copy(apiConfigurationError = null) }
                refreshAPIAuthorizationStatus()
                rescheduleAPIExportIfNeeded()
            } catch (error: IllegalArgumentException) {
                _uiState.update { it.copy(apiConfigurationError = error.message) }
            } catch (_: Exception) {
                _uiState.update { it.copy(apiConfigurationError = "Could not securely save API request settings.") }
            }
        }
    }

    fun clearAPIAuthorization() {
        viewModelScope.launch {
            apiCredentialStore?.clearAuthorization()
            refreshAPIAuthorizationStatus()
            rescheduleAPIExportIfNeeded()
        }
    }

    fun clearAPIRequestHeaders() {
        viewModelScope.launch {
            apiCredentialStore?.clearRequestHeaders()
            refreshAPIAuthorizationStatus()
            rescheduleAPIExportIfNeeded()
        }
    }

    fun clearAPIConfigurationError() {
        _uiState.update { it.copy(apiConfigurationError = null) }
    }

    fun resetSettings() {
        viewModelScope.launch {
            val current = settingsRepository.getExportSettings()
            settingsRepository.updateExportSettings(
                ExportSettings(
                    exportTarget = current.exportTarget,
                    scheduledExportTarget = current.scheduledExportTarget,
                    apiEndpointUrl = current.apiEndpointUrl,
                )
            )
        }
    }

    private fun updateSettings(transform: (ExportSettings) -> ExportSettings) {
        viewModelScope.launch {
            val current = settingsRepository.getExportSettings()
            settingsRepository.updateExportSettings(transform(current))
        }
    }

    private fun updateFormatCustomization(transform: (FormatCustomization) -> FormatCustomization) {
        updateSettings { it.copy(formatCustomization = transform(it.formatCustomization)) }
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
        if (!ExportTargetReadiness.canExport(
                hasHealthPermissions = currentState.hasPermissions,
                historicalPermissionNeeded = currentState.historyPermissionNeeded,
                hasSelectedFormat = currentState.exportFormats.isNotEmpty(),
                target = currentState.selectedTarget,
                hasExportFolder = currentState.folderName != null,
                apiEndpointConfigured = currentState.apiEndpointConfigured,
            )) return

        dismissJob?.cancel()
        exportJob = viewModelScope.launch {
            _uiState.update { it.copy(isExporting = true, lastResult = null, preview = null, exportedFolderUri = null) }

            val settings = settingsRepository.getExportSettings()
            val dates = ExportOrchestrator.dateRange(_uiState.value.startDate, _uiState.value.endDate)

            val progress: (Int, Int, String) -> Unit = { current, total, dateStr ->
                _uiState.update {
                    it.copy(exportProgress = current, exportTotal = total, exportProgressDate = dateStr)
                }
            }
            val result = when (settings.exportTarget) {
                ExportTarget.DEVICE_FOLDER -> ExportOrchestrator(healthRepository, exportRepository)
                    .exportDates(dates, settings, progress)
                    .copy(target = ExportTarget.DEVICE_FOLDER)
                ExportTarget.API_ENDPOINT -> apiEndpointExportRunner?.exportDates(dates, settings, progress)
                    ?: ExportResult(
                        successCount = 0,
                        totalCount = dates.size,
                        failedDateDetails = dates.map {
                            FailedDateDetail(it, ExportFailureReason.NETWORK_ERROR, "API export service unavailable")
                        },
                        target = ExportTarget.API_ENDPOINT,
                    )
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
                    target = settings.exportTarget,
                    targetLabel = when (settings.exportTarget) {
                        ExportTarget.DEVICE_FOLDER -> _uiState.value.folderName
                        ExportTarget.API_ENDPOINT -> APIExportEndpoint.redactedDescription(settings.apiEndpointUrl)
                    },
                    fileCount = if (settings.exportTarget == ExportTarget.DEVICE_FOLDER) {
                        estimatedFileCount(result.successCount, settings)
                    } else 0,
                    warningSummary = result.warningSummary(),
                )
            )

            // Successful manual export actions consume one free-tier use.
            if (ExportAccountingPolicy.shouldConsumeFreeExport(result, _uiState.value.isPurchased)) {
                settingsRepository.recordFreeExportUse()
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

            val folderUri = if (settings.exportTarget == ExportTarget.DEVICE_FOLDER) {
                settingsRepository.getExportFolderUri()
            } else null
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
        // Preview is a dry run. Like iOS, it only needs readable health data and at least
        // one format; users can inspect output before choosing or configuring a destination.
        if (!currentState.hasPermissions || currentState.historyPermissionNeeded ||
            currentState.exportFormats.isEmpty()) {
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
                val progress: (Int, Int, String) -> Unit = { current, total, dateStr ->
                    _uiState.update {
                        it.copy(exportProgress = current, exportTotal = total, exportProgressDate = dateStr)
                    }
                }
                val preview = when (settings.exportTarget) {
                    ExportTarget.DEVICE_FOLDER -> ExportOrchestrator(healthRepository, exportRepository)
                        .previewDates(dates, settings, onProgress = progress)
                    ExportTarget.API_ENDPOINT -> apiEndpointExportRunner?.previewDates(
                        dates = dates,
                        settings = settings,
                        onProgress = progress,
                    ) ?: ExportPreview(
                        requestedDateCount = dates.size,
                        previewedDateCount = 0,
                        isTruncated = false,
                        days = emptyList(),
                    )
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

    private suspend fun rescheduleAPIExportIfNeeded() {
        val settings = settingsRepository.getExportSettings()
        if (!settings.scheduleEnabled || settings.scheduledExportTarget != ExportTarget.API_ENDPOINT) return
        exportScheduler?.reconcile()
    }

    private fun refreshAPIAuthorizationStatus() {
        viewModelScope.launch {
            val authorizationConfigured = apiCredentialStore?.hasAuthorization() ?: false
            val requestHeadersConfigured = apiCredentialStore?.hasRequestHeaders() ?: false
            _uiState.update {
                it.copy(
                    apiAuthorizationConfigured = authorizationConfigured,
                    apiRequestHeadersConfigured = requestHeadersConfigured,
                )
            }
        }
    }

    fun refreshPermissions() {
        viewModelScope.launch {
            val hasPerms = try {
                healthRepository.hasPermissions()
            } catch (_: Exception) {
                _uiState.update { it.copy(healthConnectNeedsSetup = true) }
                return@launch
            }
            if (hasPerms) {
                settingsRepository.recordHealthPermissionGrantDateIfAbsent(LocalDate.now())
            }
            val hasHistoricalPerms = try {
                healthRepository.hasHistoricalReadPermission()
            } catch (_: Exception) {
                false
            }
            val firstGrantDate = settingsRepository.getFirstHealthPermissionGrantDate()
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
                    firstHealthPermissionGrantDate = firstGrantDate,
                )
            }
        }
    }
}
