package com.healthmd.presentation.schedule

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.R
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportHeaders
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.domain.repository.BillingRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class ScheduleViewModel @Inject constructor(
    application: Application,
    private val exportScheduler: ExportScheduler,
    private val settingsRepository: SettingsRepository,
    private val billingRepository: BillingRepository,
    private val apiCredentialStore: APIExportCredentialStore? = null,
) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(ScheduleUiState())
    val uiState: StateFlow<ScheduleUiState> = _uiState.asStateFlow()

    init {
        billingRepository.startConnection()

        viewModelScope.launch {
            combine(
                settingsRepository.exportSettings,
                settingsRepository.exportFolderUri,
                settingsRepository.isPurchased,
                billingRepository.isUnlocked,
            ) { settings, folderUri, persistedPurchased, liveUnlocked ->
                ScheduleCombinedState(settings, folderUri, persistedPurchased, liveUnlocked)
            }.collect { combined ->
                val settings = combined.settings
                val persistedPurchased = combined.persistedPurchased
                val liveUnlocked = combined.liveUnlocked
                val purchased = persistedPurchased || liveUnlocked
                _uiState.update {
                    it.copy(
                        isEnabled = settings.scheduleEnabled && purchased,
                        cadenceValue = normalizeCadenceValue(settings.scheduleCadenceValue, settings.scheduleCadenceUnit),
                        cadenceUnit = settings.scheduleCadenceUnit,
                        hour = settings.scheduleHour,
                        minute = settings.scheduleMinute,
                        lookbackDays = settings.scheduleLookbackDays.coerceAtLeast(1),
                        dateWindow = settings.scheduleDateWindow,
                        isPurchased = purchased,
                        selectedTarget = settings.scheduledExportTarget,
                        apiEndpointUrl = settings.apiEndpointUrl,
                        apiEndpointConfigured = APIExportEndpoint.isConfigured(settings.apiEndpointUrl),
                        hasExportFolder = !combined.folderUri.isNullOrBlank(),
                    )
                }
                if (settings.scheduleEnabled && !purchased) {
                    val current = settingsRepository.getExportSettings()
                    settingsRepository.updateExportSettings(current.copy(scheduleEnabled = false))
                    exportScheduler.cancel()
                    _uiState.update { it.copy(requiresUpgrade = true) }
                }
                updateNextExportDescription()
            }
        }

        refreshAPIAuthorizationStatus()

        viewModelScope.launch {
            billingRepository.isUnlocked
                .filter { it }
                .collect { settingsRepository.setPurchased(true) }
        }
    }

    fun toggleSchedule(enabled: Boolean) {
        val state = _uiState.value
        if (enabled && !state.isPurchased) {
            _uiState.update { it.copy(isEnabled = false, requiresUpgrade = true) }
            return
        }
        if (enabled && state.selectedTarget == ExportTarget.DEVICE_FOLDER && !state.hasExportFolder) {
            _uiState.update { it.copy(isEnabled = false, configurationError = "Choose an export folder on the Export screen first.") }
            return
        }
        if (enabled && state.selectedTarget == ExportTarget.API_ENDPOINT && !state.apiEndpointConfigured) {
            _uiState.update { it.copy(isEnabled = false, configurationError = "Configure an API endpoint before enabling the schedule.") }
            return
        }
        _uiState.update { it.copy(isEnabled = enabled, configurationError = null) }
        persistAndRescheduleIfNeeded()
    }

    fun consumeUpgradeRequest() {
        _uiState.update { it.copy(requiresUpgrade = false) }
    }

    fun setScheduledExportTarget(target: ExportTarget) {
        _uiState.update { state ->
            val ready = when (target) {
                ExportTarget.DEVICE_FOLDER -> state.hasExportFolder
                ExportTarget.API_ENDPOINT -> state.apiEndpointConfigured
            }
            state.copy(
                selectedTarget = target,
                isEnabled = state.isEnabled && ready,
                configurationError = null,
            )
        }
        persistAndRescheduleIfNeeded()
    }

    fun saveAPIExportConfiguration(
        endpointUrl: String,
        authorization: String?,
        requestHeaders: String?,
    ) {
        viewModelScope.launch {
            val normalized = APIExportEndpoint.normalizedOrNull(endpointUrl)
            if (normalized == null) {
                _uiState.update { it.copy(configurationError = "Enter a valid HTTP or HTTPS URL without a fragment or embedded username/password.") }
                return@launch
            }
            val headerError = requestHeaders
                ?.takeIf { it.isNotBlank() }
                ?.let { raw -> runCatching { APIExportHeaders.parse(raw) }.exceptionOrNull()?.message }
            if (headerError != null) {
                _uiState.update { it.copy(configurationError = headerError) }
                return@launch
            }
            try {
                authorization?.takeIf { it.isNotBlank() }?.let { apiCredentialStore?.saveAuthorization(it) }
                requestHeaders?.takeIf { it.isNotBlank() }?.let { apiCredentialStore?.saveRequestHeaders(it) }
                _uiState.update {
                    it.copy(
                        selectedTarget = ExportTarget.API_ENDPOINT,
                        apiEndpointUrl = normalized,
                        apiEndpointConfigured = true,
                        configurationError = null,
                    )
                }
                val current = settingsRepository.getExportSettings()
                settingsRepository.updateExportSettings(
                    current.copy(
                        apiEndpointUrl = normalized,
                        scheduledExportTarget = ExportTarget.API_ENDPOINT,
                    )
                )
                refreshAPIAuthorizationStatus()
                persistAndRescheduleIfNeeded()
            } catch (error: IllegalArgumentException) {
                _uiState.update { it.copy(configurationError = error.message) }
            } catch (_: Exception) {
                _uiState.update { it.copy(configurationError = "Could not securely save API request settings.") }
            }
        }
    }

    fun clearAPIAuthorization() {
        viewModelScope.launch {
            apiCredentialStore?.clearAuthorization()
            refreshAPIAuthorizationStatus()
            persistAndRescheduleIfNeeded()
        }
    }

    fun clearAPIRequestHeaders() {
        viewModelScope.launch {
            apiCredentialStore?.clearRequestHeaders()
            refreshAPIAuthorizationStatus()
            persistAndRescheduleIfNeeded()
        }
    }

    fun clearConfigurationError() {
        _uiState.update { it.copy(configurationError = null) }
    }

    fun setCadenceValue(value: Int) {
        val unit = _uiState.value.cadenceUnit
        _uiState.update {
            it.copy(cadenceValue = normalizeCadenceValue(value, unit))
        }
        persistAndRescheduleIfNeeded()
    }

    fun setCadenceUnit(unit: ScheduleCadenceUnit) {
        _uiState.update {
            it.copy(
                cadenceUnit = unit,
                cadenceValue = normalizeCadenceValue(it.cadenceValue, unit),
            )
        }
        persistAndRescheduleIfNeeded()
    }

    fun setCadence(value: Int, unit: ScheduleCadenceUnit) {
        _uiState.update {
            it.copy(
                cadenceUnit = unit,
                cadenceValue = normalizeCadenceValue(value, unit),
            )
        }
        persistAndRescheduleIfNeeded()
    }

    fun setHour(hour: Int) {
        _uiState.update { it.copy(hour = hour.coerceIn(0, 23)) }
        persistAndRescheduleIfNeeded()
    }

    fun setMinute(minute: Int) {
        _uiState.update { it.copy(minute = minute.coerceIn(0, 59)) }
        persistAndRescheduleIfNeeded()
    }

    fun setLookbackDays(days: Int) {
        _uiState.update { it.copy(lookbackDays = days.coerceIn(1, MAX_LOOKBACK_DAYS)) }
        persistAndRescheduleIfNeeded()
    }

    fun setDateWindow(dateWindow: ScheduleDateWindow) {
        _uiState.update { it.copy(dateWindow = dateWindow) }
        persistAndRescheduleIfNeeded()
    }

    private fun persistAndRescheduleIfNeeded() {
        updateNextExportDescription()
        viewModelScope.launch {
            val state = _uiState.value
            val current = settingsRepository.getExportSettings()
            settingsRepository.updateExportSettings(
                current.copy(
                    scheduleEnabled = state.isEnabled,
                    scheduleCadenceValue = state.cadenceValue,
                    scheduleCadenceUnit = state.cadenceUnit,
                    scheduleHour = state.hour,
                    scheduleMinute = state.minute,
                    scheduleLookbackDays = state.lookbackDays,
                    scheduleDateWindow = state.dateWindow,
                    scheduledExportTarget = state.selectedTarget,
                )
            )

            if (state.isEnabled) {
                exportScheduler.schedule(
                    cadenceValue = state.cadenceValue,
                    cadenceUnit = state.cadenceUnit,
                    hour = state.hour,
                    minute = state.minute,
                    target = state.selectedTarget,
                    destinationFingerprint = if (state.selectedTarget == ExportTarget.API_ENDPOINT) {
                        apiCredentialStore?.destinationFingerprint(state.apiEndpointUrl)
                            ?: APIExportEndpoint.fingerprint(state.apiEndpointUrl)
                    } else null,
                )
            } else {
                exportScheduler.cancel()
            }
        }
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

    private fun normalizeCadenceValue(value: Int, unit: ScheduleCadenceUnit): Int = when (unit) {
        ScheduleCadenceUnit.MINUTES -> value.coerceIn(MIN_CADENCE_MINUTES, MAX_CADENCE_VALUE)
        else -> value.coerceIn(1, MAX_CADENCE_VALUE)
    }

    private fun updateNextExportDescription() {
        val state = _uiState.value
        if (!state.isEnabled) {
            _uiState.update { it.copy(nextExportDescription = "") }
            return
        }

        val nextExport = nextExportDateTime(state)
        val formatter = DateTimeFormatter.ofPattern("MMM d, yyyy 'at' h:mm a", Locale.getDefault())
        val description = getApplication<Application>().getString(
            R.string.schedule_next_export_at_datetime,
            nextExport.format(formatter),
        )

        _uiState.update { it.copy(nextExportDescription = description) }
    }

    private fun nextExportDateTime(state: ScheduleUiState): LocalDateTime {
        val now = LocalDateTime.now()
        val cadenceValue = normalizeCadenceValue(state.cadenceValue, state.cadenceUnit)
        return when (state.cadenceUnit) {
            ScheduleCadenceUnit.MINUTES -> now.plusMinutes(cadenceValue.toLong())
            ScheduleCadenceUnit.HOURS -> now.plusHours(cadenceValue.toLong())
            ScheduleCadenceUnit.DAYS,
            ScheduleCadenceUnit.WEEKS -> {
                var next = now
                    .withHour(state.hour.coerceIn(0, 23))
                    .withMinute(state.minute.coerceIn(0, 59))
                    .withSecond(0)
                    .withNano(0)

                if (!next.isAfter(now)) {
                    next = when (state.cadenceUnit) {
                        ScheduleCadenceUnit.DAYS -> next.plusDays(cadenceValue.toLong())
                        ScheduleCadenceUnit.WEEKS -> next.plusWeeks(cadenceValue.toLong())
                        else -> next
                    }
                }

                next
            }
        }
    }

    override fun onCleared() {
        super.onCleared()
        billingRepository.endConnection()
    }

    companion object {
        private const val MIN_CADENCE_MINUTES = 15
        private const val MAX_CADENCE_VALUE = 99_999
        private const val MAX_LOOKBACK_DAYS = 30
    }
}

data class ScheduleUiState(
    val isEnabled: Boolean = false,
    val cadenceValue: Int = 1,
    val cadenceUnit: ScheduleCadenceUnit = ScheduleCadenceUnit.DAYS,
    val hour: Int = 6,
    val minute: Int = 0,
    val lookbackDays: Int = 1,
    val dateWindow: ScheduleDateWindow = ScheduleDateWindow.PAST_COMPLETE_DAYS,
    val nextExportDescription: String = "",
    val isPurchased: Boolean = false,
    val requiresUpgrade: Boolean = false,
    val selectedTarget: ExportTarget = ExportTarget.DEVICE_FOLDER,
    val apiEndpointUrl: String = "",
    val apiEndpointConfigured: Boolean = false,
    val apiAuthorizationConfigured: Boolean = false,
    val apiRequestHeadersConfigured: Boolean = false,
    val hasExportFolder: Boolean = false,
    val configurationError: String? = null,
)

private data class ScheduleCombinedState(
    val settings: com.healthmd.domain.model.ExportSettings,
    val folderUri: String?,
    val persistedPurchased: Boolean,
    val liveUnlocked: Boolean,
)
