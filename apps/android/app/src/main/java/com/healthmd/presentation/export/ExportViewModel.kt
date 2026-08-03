package com.healthmd.presentation.export

import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportHeaders
import com.healthmd.data.export.ExportAwakeCoordinator
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.billing.FreemiumPolicy
import com.healthmd.domain.export.ExportAccountingPolicy
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.BillingRepository
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawSnapshotScope
import com.healthmd.presentation.common.HealthConnectActionError
import com.healthmd.util.runCatchingCancellable
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import timber.log.Timber
import java.net.URI
import java.time.LocalDate
import javax.inject.Inject

enum class APIConfigurationIssue {
    INVALID_ENDPOINT,
    INVALID_HEADERS,
    SECURE_SAVE_FAILED,
}

private val RAW_SNAPSHOT_PROVIDER_IDS = setOf(
    "health_connect",
    "fitbit",
    "withings",
    "oura",
    "whoop",
    "all_connected",
)

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
    val exportProgressDate: LocalDate? = null,
    val lastResult: ExportResult? = null,
    val preview: ExportPreview? = null,
    val exportedFolderUri: String? = null,
    val healthConnectAvailable: Boolean = false,
    val healthConnectNeedsSetup: Boolean = false,
    val hasPermissions: Boolean = false,
    val hasHistoricalReadPermission: Boolean = false,
    val healthConnectActionError: HealthConnectActionError? = null,
    val firstHealthPermissionGrantDate: LocalDate? = null,
    val allTimeSelected: Boolean = false,
    val freeExportsRemaining: Int = FreemiumPolicy.FREE_EXPORT_LIMIT,
    val isPurchased: Boolean = false,
    val apiAuthorizationConfigured: Boolean = false,
    val apiRequestHeadersConfigured: Boolean = false,
    val apiConfigurationError: APIConfigurationIssue? = null,
    val selectedHealthProviderId: String = "health_connect",
) {
    val requiresHistoricalReadPermission: Boolean
        get() = ExportHistoryAccess.requiresHistoricalReadPermission(
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

    val rawApiEndpointConfigured: Boolean
        get() = APIExportEndpoint.normalizedOrNull(settings.apiEndpointUrl)
            ?.let { runCatching { URI(it).scheme.equals("https", ignoreCase = true) }.getOrDefault(false) }
            ?: false

    val rawProviderSupported: Boolean
        get() = settings.exportMode != ExportMode.RAW_SNAPSHOT ||
            selectedHealthProviderId in RAW_SNAPSHOT_PROVIDER_IDS

    val hasSelectedFormat: Boolean
        get() = settings.exportMode == ExportMode.RAW_SNAPSHOT || exportFormats.isNotEmpty()

    val rawSelectionReady: Boolean
        get() = settings.exportMode != ExportMode.RAW_SNAPSHOT ||
            settings.rawSnapshot.scope == RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA ||
            settings.metricSelection.enabledMetrics.isNotEmpty()

    val previewEnabled: Boolean
        get() = settings.exportMode == ExportMode.COMPATIBILITY ||
            (rawProviderSupported && rawSelectionReady)

    val destinationReady: Boolean
        get() = when (selectedTarget) {
            ExportTarget.DEVICE_FOLDER -> folderName != null
            ExportTarget.API_ENDPOINT -> if (settings.exportMode == ExportMode.RAW_SNAPSHOT) rawApiEndpointConfigured else apiEndpointConfigured
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
    private val rawSnapshotExportRunner: RawSnapshotService? = null,
    private val apiCredentialStore: APIExportCredentialStore? = null,
    private val exportScheduler: ExportScheduler? = null,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ExportUiState())
    val uiState: StateFlow<ExportUiState> = _uiState.asStateFlow()

    private val _requestReview = MutableSharedFlow<Unit>(extraBufferCapacity = 1)
    val requestReview: SharedFlow<Unit> = _requestReview.asSharedFlow()

    private var exportJob: Job? = null
    private var dismissJob: Job? = null
    private var healthRefreshJob: Job? = null

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

        viewModelScope.launch {
            settingsRepository.selectedHealthProviderId.collect { providerId ->
                _uiState.update { it.copy(selectedHealthProviderId = providerId) }
            }
        }

        refreshAPIAuthorizationStatus()

        // Persist confirmed purchases to DataStore so the state survives offline / app restarts
        viewModelScope.launch {
            billingRepository.isUnlocked
                .filter { it }
                .collect { settingsRepository.setPurchased(true) }
        }

        refreshPermissions()
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

    fun setExportMode(mode: ExportMode) = updateSettings { it.copy(exportMode = mode) }
    fun setRawExportFormat(format: RawExportFormat) = updateSettings {
        it.copy(rawSnapshot = it.rawSnapshot.copy(format = format))
    }
    fun setRawSnapshotScope(scope: RawSnapshotScope) = updateSettings {
        it.copy(rawSnapshot = it.rawSnapshot.copy(scope = scope))
    }
    fun setRawIncludeExerciseRoutes(include: Boolean) = updateSettings {
        it.copy(rawSnapshot = it.rawSnapshot.copy(includeExerciseRoutes = include))
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
                _uiState.update { it.copy(apiConfigurationError = APIConfigurationIssue.INVALID_ENDPOINT) }
                return@launch
            }
            val headersInvalid = requestHeaders
                ?.takeIf { it.isNotBlank() }
                ?.let { raw -> runCatching { APIExportHeaders.parse(raw) }.isFailure }
                ?: false
            if (headersInvalid) {
                _uiState.update { it.copy(apiConfigurationError = APIConfigurationIssue.INVALID_HEADERS) }
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
            } catch (_: IllegalArgumentException) {
                _uiState.update { it.copy(apiConfigurationError = APIConfigurationIssue.INVALID_HEADERS) }
            } catch (_: Exception) {
                _uiState.update { it.copy(apiConfigurationError = APIConfigurationIssue.SECURE_SAVE_FAILED) }
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
                ExportSettings.newInstallDefaults().copy(
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
        val currentState = _uiState.value
        if (currentState.isExporting || currentState.isPreviewing || exportJob?.isActive == true) return

        // Block export if free tier is exhausted
        if (!currentState.isPurchased && currentState.freeExportsRemaining <= 0) return

        if (!ExportTargetReadiness.canExport(
                hasHealthPermissions = currentState.hasPermissions,
                historicalPermissionNeeded = currentState.historyPermissionNeeded,
                hasSelectedFormat = currentState.hasSelectedFormat,
                target = currentState.selectedTarget,
                hasExportFolder = currentState.folderName != null,
                apiEndpointConfigured = if (currentState.settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                    currentState.rawApiEndpointConfigured
                } else {
                    currentState.apiEndpointConfigured
                },
                exportMode = currentState.settings.exportMode,
                rawProviderSupported = currentState.rawProviderSupported,
                rawSelectionReady = currentState.rawSelectionReady,
            )) return

        dismissJob?.cancel()
        val awakeActivityId = ExportAwakeCoordinator.shared.beginActivity()
        exportJob = viewModelScope.launch {
            _uiState.update { it.copy(isExporting = true, lastResult = null, preview = null, exportedFolderUri = null) }

            val settings = settingsRepository.getExportSettings()
            val dates = ExportOrchestrator.dateRange(_uiState.value.startDate, _uiState.value.endDate)

            val progress: (Int, Int, String) -> Unit = { current, total, dateStr ->
                _uiState.update {
                    it.copy(
                        exportProgress = current,
                        exportTotal = total,
                        exportProgressDate = dateStr.toLocalDateOrNull(),
                    )
                }
            }
            val result = if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                _uiState.update { it.copy(exportProgress = 0, exportTotal = 1, exportProgressDate = _uiState.value.startDate) }
                (rawSnapshotExportRunner?.exportRange(
                    startDate = _uiState.value.startDate,
                    endDate = _uiState.value.endDate,
                    settings = settings,
                ) ?: ExportResult(
                    successCount = 0,
                    totalCount = 1,
                    failedDateDetails = listOf(FailedDateDetail(_uiState.value.startDate, ExportFailureReason.UNKNOWN, "Raw snapshot service unavailable")),
                    target = settings.exportTarget,
                    exportMode = ExportMode.RAW_SNAPSHOT,
                )).also { _uiState.update { state -> state.copy(exportProgress = 1) } }
            } else when (settings.exportTarget) {
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

            // UI and local history consume typed failure reasons, never arbitrary producer text.
            // The original result remains available above for canonical API envelope/accounting work.
            val presentationResult = result.withoutProducerDiagnostics()

            // Record in history
            exportHistoryRepository.insertEntry(
                ExportHistoryEntry(
                    timestamp = System.currentTimeMillis(),
                    source = ExportSource.MANUAL,
                    dateRangeStart = _uiState.value.startDate,
                    dateRangeEnd = _uiState.value.endDate,
                    successCount = presentationResult.successCount,
                    totalCount = presentationResult.totalCount,
                    failureReason = presentationResult.primaryFailureReason,
                    failedDateDetails = presentationResult.failedDateDetails,
                    target = settings.exportTarget,
                    targetLabel = when (settings.exportTarget) {
                        ExportTarget.DEVICE_FOLDER -> _uiState.value.folderName
                        ExportTarget.API_ENDPOINT -> APIExportEndpoint.redactedDescription(settings.apiEndpointUrl)
                    },
                    fileCount = if (settings.exportTarget == ExportTarget.DEVICE_FOLDER) {
                        if (settings.exportMode == ExportMode.RAW_SNAPSHOT) presentationResult.artifactCount else estimatedFileCount(presentationResult.successCount, settings)
                    } else 0,
                    warningSummary = null,
                    exportMode = presentationResult.exportMode,
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
                    lastResult = presentationResult,
                    exportedFolderUri = if (presentationResult.artifactCount > 0) folderUri else null,
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
        }.also { job ->
            job.invokeOnCompletion {
                ExportAwakeCoordinator.shared.endActivity(awakeActivityId)
            }
        }
    }

    fun buildPreview() {
        dismissJob?.cancel()
        val currentState = _uiState.value
        if (!currentState.previewEnabled) return
        // Preview is a dry run. Like iOS, it only needs readable health data and at least
        // one format; users can inspect output before choosing or configuring a destination.
        if (!currentState.hasPermissions || currentState.historyPermissionNeeded ||
            !currentState.hasSelectedFormat || !currentState.rawProviderSupported ||
            !currentState.rawSelectionReady) {
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
                        it.copy(
                            exportProgress = current,
                            exportTotal = total,
                            exportProgressDate = dateStr.toLocalDateOrNull(),
                        )
                    }
                }
                val preview = if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                    _uiState.update {
                        it.copy(
                            exportProgress = 0,
                            exportTotal = 1,
                            exportProgressDate = _uiState.value.startDate,
                        )
                    }
                    (rawSnapshotExportRunner?.previewRange(
                        startDate = _uiState.value.startDate,
                        endDate = _uiState.value.endDate,
                        settings = settings,
                    ) ?: ExportPreview(
                        requestedDateCount = dates.size,
                        previewedDateCount = 0,
                        isTruncated = false,
                        days = listOf(
                            ExportPreviewDay(
                                date = _uiState.value.startDate,
                                failureReason = ExportFailureReason.UNKNOWN,
                                issues = listOf(
                                    ExportPreviewIssue(ExportPreviewIssueKind.RAW_PREVIEW_SERVICE_UNAVAILABLE),
                                ),
                                requestedDates = dates,
                            ),
                        ),
                        isRangeArtifact = true,
                    )).also { _uiState.update { state -> state.copy(exportProgress = 1) } }
                } else when (settings.exportTarget) {
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
        val state = _uiState.value
        if (!state.isExporting && !state.isPreviewing) return
        exportJob?.cancel()
        if (state.isPreviewing) {
            _uiState.update { it.copy(isPreviewing = false, preview = null) }
            return
        }
        val isRaw = state.settings.exportMode == ExportMode.RAW_SNAPSHOT
        val reason = if (isRaw) ExportFailureReason.RAW_CANCELLED else ExportFailureReason.UNKNOWN
        val total = if (isRaw) 1 else ExportOrchestrator.dateRange(state.startDate, state.endDate).size
        val cancelled = ExportResult(
            successCount = 0,
            totalCount = total,
            failedDateDetails = listOf(FailedDateDetail(state.startDate, reason)),
            wasCancelled = true,
            target = state.selectedTarget,
            exportMode = state.settings.exportMode,
        )
        _uiState.update { it.copy(isExporting = false, lastResult = cancelled) }
        viewModelScope.launch {
            exportHistoryRepository.insertEntry(
                ExportHistoryEntry(
                    timestamp = System.currentTimeMillis(),
                    source = ExportSource.MANUAL,
                    dateRangeStart = state.startDate,
                    dateRangeEnd = state.endDate,
                    successCount = 0,
                    totalCount = total,
                    failureReason = reason,
                    failedDateDetails = cancelled.failedDateDetails,
                    target = state.selectedTarget,
                    targetLabel = state.destinationLabel,
                    fileCount = 0,
                    warningSummary = null,
                    exportMode = state.settings.exportMode,
                ),
            )
        }
    }

    private fun estimatedFileCount(successCount: Int, settings: ExportSettings): Int =
        successCount * settings.selectedExportFormats.size

    private fun ExportResult.withoutProducerDiagnostics(): ExportResult = copy(
        failedDateDetails = failedDateDetails.map { it.copy(errorDetails = null) },
    )

    private fun String.toLocalDateOrNull(): LocalDate? =
        runCatching { LocalDate.parse(this) }.getOrNull()

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
        healthRefreshJob?.cancel()
        healthRefreshJob = viewModelScope.launch {
            val available = runCatchingCancellable { healthRepository.isAvailable() }
                .getOrElse {
                    _uiState.update { state ->
                        state.copy(
                            hasPermissions = false,
                            healthConnectActionError = HealthConnectActionError.ACCESS_CHECK_FAILED,
                        )
                    }
                    return@launch
                }

            if (!available) {
                _uiState.update {
                    it.copy(
                        healthConnectAvailable = false,
                        healthConnectNeedsSetup = false,
                        hasPermissions = false,
                        hasHistoricalReadPermission = false,
                        healthConnectActionError = it.healthConnectActionError
                            .takeUnless { error -> error == HealthConnectActionError.ACCESS_CHECK_FAILED },
                    )
                }
                return@launch
            }

            val hasPerms = runCatchingCancellable { healthRepository.hasPermissions() }
                .getOrElse {
                    _uiState.update { state ->
                        state.copy(
                            healthConnectAvailable = true,
                            healthConnectNeedsSetup = true,
                            hasPermissions = false,
                            healthConnectActionError = HealthConnectActionError.ACCESS_CHECK_FAILED,
                        )
                    }
                    return@launch
                }
            if (hasPerms) {
                settingsRepository.recordHealthPermissionGrantDateIfAbsent(LocalDate.now())
            }

            val historicalResult = runCatchingCancellable {
                healthRepository.hasHistoricalReadPermission()
            }
            val hasHistoricalPerms = historicalResult.getOrDefault(false)
            val firstGrantDate = settingsRepository.getFirstHealthPermissionGrantDate()
            val refreshedAllTimeStart = if (hasHistoricalPerms && _uiState.value.allTimeSelected) {
                runCatchingCancellable { healthRepository.getEarliestDataDate() }.getOrNull()
            } else {
                null
            }
            _uiState.update {
                it.copy(
                    startDate = refreshedAllTimeStart ?: it.startDate,
                    healthConnectAvailable = true,
                    healthConnectNeedsSetup = false,
                    hasPermissions = hasPerms,
                    hasHistoricalReadPermission = hasHistoricalPerms,
                    healthConnectActionError = if (historicalResult.isFailure) {
                        HealthConnectActionError.ACCESS_CHECK_FAILED
                    } else {
                        it.healthConnectActionError
                            .takeUnless { error -> error == HealthConnectActionError.ACCESS_CHECK_FAILED }
                    },
                    firstHealthPermissionGrantDate = firstGrantDate,
                )
            }
        }
    }

    fun reportHealthConnectActionError(error: HealthConnectActionError) {
        _uiState.update { it.copy(healthConnectActionError = error) }
    }

    fun clearHealthConnectActionError() {
        _uiState.update { it.copy(healthConnectActionError = null) }
    }
}
