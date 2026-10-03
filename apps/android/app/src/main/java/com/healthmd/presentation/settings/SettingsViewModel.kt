package com.healthmd.presentation.settings

import android.content.Intent
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.health.HealthProviderDiagnosticsReporter
import com.healthmd.data.health.providers.HealthProviderCatalog
import com.healthmd.data.health.providers.HealthProviderConnectionManager
import com.healthmd.data.health.providers.HealthProviderId
import com.healthmd.data.health.providers.HealthProviderState
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

data class HealthProviderUiState(
    val provider: HealthProviderState,
    val isSelected: Boolean,
    val isConnected: Boolean,
    val isDirectConnectionConfigured: Boolean,
)

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsRepository: SettingsRepository,
    private val healthProviderCatalog: HealthProviderCatalog,
    private val providerConnectionManager: HealthProviderConnectionManager,
    private val diagnosticsReporter: HealthProviderDiagnosticsReporter,
    private val entitlementRepository: EntitlementRepository,
    val distributionPolicy: DistributionPolicy,
) : ViewModel() {

    val settings: StateFlow<ExportSettings> = settingsRepository.exportSettings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ExportSettings())

    val isPurchased: StateFlow<Boolean> = combine(
        settingsRepository.isPurchased,
        entitlementRepository.isUnlocked,
    ) { persisted, live -> distributionPolicy.fullAccessIncluded || persisted || live }
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5000),
            distributionPolicy.fullAccessIncluded,
        )

    private val _preventAccidentalChanges = MutableStateFlow<Boolean?>(null)
    val preventAccidentalChanges: StateFlow<Boolean?> = _preventAccidentalChanges.asStateFlow()

    private val _blockedChangeToastId = MutableStateFlow<Long?>(null)
    val blockedChangeToastId: StateFlow<Long?> = _blockedChangeToastId.asStateFlow()

    private val _protectionSettingsRequestId = MutableStateFlow<Long?>(null)
    val protectionSettingsRequestId: StateFlow<Long?> = _protectionSettingsRequestId.asStateFlow()

    private val providerRefreshSignal = MutableStateFlow(0)

    init {
        entitlementRepository.refresh()
        viewModelScope.launch {
            settingsRepository.preventAccidentalChanges.collect(_preventAccidentalChanges)
        }
        if (!distributionPolicy.fullAccessIncluded) {
            viewModelScope.launch {
                entitlementRepository.isUnlocked
                    .filter { it }
                    .collect { settingsRepository.setPurchased(true) }
            }
        }
    }

    val healthProviderStates: StateFlow<List<HealthProviderUiState>> = combine(
        providerRefreshSignal,
        settingsRepository.selectedHealthProviderId,
        settingsRepository.connectedHealthProviderIds,
    ) { _, selectedProviderId, connectedProviderIds ->
        healthProviderCatalog.providerStates().map { providerState ->
            val providerId = providerState.definition.id.wireId
            HealthProviderUiState(
                provider = providerState,
                isSelected = selectedProviderId == providerId,
                isConnected = providerId in connectedProviderIds,
                isDirectConnectionConfigured = providerConnectionManager.isConfigured(providerId),
            )
        }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), emptyList())

    fun refreshHealthProviders() {
        providerRefreshSignal.value += 1
    }

    fun setPreventAccidentalChanges(enabled: Boolean) {
        // Enabling fails closed immediately. Disabling remains protected until DataStore confirms
        // the write, so a slow or failed persistence operation cannot expose configuration edits.
        if (enabled) _preventAccidentalChanges.value = true
        viewModelScope.launch {
            runCatching { settingsRepository.setPreventAccidentalChanges(enabled) }
                .onSuccess {
                    _preventAccidentalChanges.value = enabled
                    if (!enabled) dismissBlockedChangeToast()
                }
                .onFailure {
                    _preventAccidentalChanges.value = settingsRepository.preventAccidentalChanges.first()
                }
        }
    }

    fun showBlockedChangeToast() {
        _blockedChangeToastId.value = System.nanoTime()
    }

    fun dismissBlockedChangeToast() {
        _blockedChangeToastId.value = null
    }

    fun openProtectionSetting() {
        _protectionSettingsRequestId.value = System.nanoTime()
        dismissBlockedChangeToast()
    }

    /** Guards callbacks owned by this shared settings ViewModel. Feature screens also use the
     * shared UI overlay so their user-initiated mutations cannot reach their ViewModels. */
    fun performConfigurationChange(action: () -> Unit) {
        // Treat the brief DataStore-loading state as protected rather than exposing saved settings.
        if (preventAccidentalChanges.value != false) showBlockedChangeToast() else action()
    }

    fun getHealthProviderSetupIntent(providerId: HealthProviderId) =
        healthProviderCatalog.setupIntentFor(providerId)

    suspend fun getHealthProviderConnectionIntent(providerId: HealthProviderId): Intent? =
        providerConnectionManager.buildConnectionIntent(providerId.wireId)

    suspend fun buildRedactedDiagnosticsShareText(): String =
        diagnosticsReporter.buildReport().toShareText()

    fun selectHealthProvider(providerId: HealthProviderId) {
        viewModelScope.launch {
            settingsRepository.setSelectedHealthProviderId(providerId.wireId)
            settingsRepository.setHealthProviderConnected(providerId.wireId, true)
        }
    }

    fun disconnectHealthProvider(providerId: HealthProviderId) {
        viewModelScope.launch {
            providerConnectionManager.disconnect(providerId.wireId)
            settingsRepository.setHealthProviderConnected(providerId.wireId, false)
            if (settingsRepository.getSelectedHealthProviderId() == providerId.wireId) {
                settingsRepository.setSelectedHealthProviderId(HealthProviderId.HEALTH_CONNECT.wireId)
            }
        }
    }

    fun updateFormat(format: ExportFormat) = update { it.copy(exportFormat = format, exportFormats = setOf(format)) }
    fun toggleExportFormat(format: ExportFormat) = update { settings ->
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
    fun updateWriteMode(mode: WriteMode) = update { it.copy(writeMode = mode) }
    fun updateFilenameFormat(format: String) = update { it.copy(filenameFormat = format) }
    fun updateFolderStructure(structure: String) = update { it.copy(folderStructure = structure) }
    fun updateIncludeMetadata(include: Boolean) = update { it.copy(includeMetadata = include) }
    fun updateGroupByCategory(group: Boolean) = update { it.copy(groupByCategory = group) }
    fun updateSubfolder(subfolder: String) = update { it.copy(subfolder = subfolder) }
    fun updateFolderOrganization(org: FolderOrganization) = update { it.copy(folderOrganization = org) }
    fun updateIncludeGranularData(include: Boolean) = update { it.copy(includeGranularData = include) }

    fun updateMetricSelection(selection: MetricSelectionState) = update { it.copy(metricSelection = selection) }
    fun updateDailyNoteInjection(settings: DailyNoteInjectionSettings) = update { it.copy(dailyNoteInjection = settings) }
    fun updateIndividualTracking(settings: IndividualTrackingSettings) = update { it.copy(individualTracking = settings) }
    fun updateFormatCustomization(customization: FormatCustomization) = update { it.copy(formatCustomization = customization) }

    fun updateScheduleHour(hour: Int) = update { it.copy(scheduleHour = hour) }
    fun updateScheduleMinute(minute: Int) = update { it.copy(scheduleMinute = minute) }

    fun updateDateFormat(format: DateFormatPreference) = updateCustomization {
        it.copy(dateFormat = format)
    }

    fun updateTimeFormat(format: TimeFormatPreference) = updateCustomization {
        it.copy(timeFormat = format)
    }

    fun updateUnitPreference(pref: UnitPreference) = updateCustomization {
        it.copy(unitPreference = pref)
    }

    fun updateBulletStyle(style: BulletStyle) = updateCustomization {
        it.copy(markdownTemplate = it.markdownTemplate.copy(bulletStyle = style))
    }

    fun updateUseEmoji(use: Boolean) = updateCustomization {
        it.copy(markdownTemplate = it.markdownTemplate.copy(useEmoji = use))
    }

    fun updateHeaderLevel(level: Int) = updateCustomization {
        it.copy(markdownTemplate = it.markdownTemplate.copy(sectionHeaderLevel = level))
    }

    fun updateFrontmatterKeyStyle(style: FrontmatterKeyStyle) = updateCustomization {
        it.copy(frontmatterConfig = it.frontmatterConfig.withKeyStyle(style))
    }

    fun resetSettings() {
        viewModelScope.launch {
            settingsRepository.updateExportSettings(ExportSettings.newInstallDefaults())
        }
    }

    private fun update(transform: (ExportSettings) -> ExportSettings) {
        viewModelScope.launch {
            settingsRepository.updateExportSettingsAtomically(transform)
        }
    }

    private fun updateCustomization(transform: (FormatCustomization) -> FormatCustomization) {
        update { it.copy(formatCustomization = transform(it.formatCustomization)) }
    }
}
