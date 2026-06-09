package com.healthmd.presentation.schedule

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.R
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.repository.BillingRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
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
) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(ScheduleUiState())
    val uiState: StateFlow<ScheduleUiState> = _uiState.asStateFlow()

    init {
        billingRepository.startConnection()

        viewModelScope.launch {
            combine(
                settingsRepository.exportSettings,
                settingsRepository.isPurchased,
                billingRepository.isUnlocked,
            ) { settings, persistedPurchased, liveUnlocked ->
                Triple(settings, persistedPurchased, liveUnlocked)
            }.collect { (settings, persistedPurchased, liveUnlocked) ->
                val purchased = persistedPurchased || liveUnlocked
                _uiState.update {
                    it.copy(
                        isEnabled = settings.scheduleEnabled && purchased,
                        cadenceValue = normalizeCadenceValue(settings.scheduleCadenceValue, settings.scheduleCadenceUnit),
                        cadenceUnit = settings.scheduleCadenceUnit,
                        hour = settings.scheduleHour,
                        minute = settings.scheduleMinute,
                        lookbackDays = settings.scheduleLookbackDays.coerceAtLeast(1),
                        isPurchased = purchased,
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

        viewModelScope.launch {
            billingRepository.isUnlocked
                .filter { it }
                .collect { settingsRepository.setPurchased(true) }
        }
    }

    fun toggleSchedule(enabled: Boolean) {
        if (enabled && !_uiState.value.isPurchased) {
            _uiState.update { it.copy(isEnabled = false, requiresUpgrade = true) }
            return
        }
        _uiState.update { it.copy(isEnabled = enabled) }
        persistAndRescheduleIfNeeded()
    }

    fun consumeUpgradeRequest() {
        _uiState.update { it.copy(requiresUpgrade = false) }
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
                )
            )

            if (state.isEnabled) {
                exportScheduler.schedule(
                    cadenceValue = state.cadenceValue,
                    cadenceUnit = state.cadenceUnit,
                    hour = state.hour,
                    minute = state.minute,
                )
            } else {
                exportScheduler.cancel()
            }
        }
    }

    private fun normalizeCadenceValue(value: Int, unit: ScheduleCadenceUnit): Int = when (unit) {
        ScheduleCadenceUnit.MINUTES -> value.coerceAtLeast(MIN_CADENCE_MINUTES)
        else -> value.coerceAtLeast(1)
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
    val nextExportDescription: String = "",
    val isPurchased: Boolean = false,
    val requiresUpgrade: Boolean = false,
)
