package com.healthmd.presentation.schedule

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.R
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.Locale
import javax.inject.Inject

@HiltViewModel
class ScheduleViewModel @Inject constructor(
    application: Application,
    private val exportScheduler: ExportScheduler,
    private val settingsRepository: SettingsRepository,
) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(ScheduleUiState())
    val uiState: StateFlow<ScheduleUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val settings = settingsRepository.getExportSettings()
            _uiState.update {
                it.copy(
                    isEnabled = settings.scheduleEnabled,
                    cadenceValue = normalizeCadenceValue(settings.scheduleCadenceValue, settings.scheduleCadenceUnit),
                    cadenceUnit = settings.scheduleCadenceUnit,
                    hour = settings.scheduleHour,
                    minute = settings.scheduleMinute,
                )
            }
            updateNextExportDescription()
        }
    }

    fun toggleSchedule(enabled: Boolean) {
        _uiState.update { it.copy(isEnabled = enabled) }
        persistAndRescheduleIfNeeded()
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

    fun setHour(hour: Int) {
        _uiState.update { it.copy(hour = hour.coerceIn(0, 23)) }
        persistAndRescheduleIfNeeded()
    }

    fun setMinute(minute: Int) {
        _uiState.update { it.copy(minute = minute.coerceIn(0, 59)) }
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

        val resources = getApplication<Application>().resources
        val cadenceText = when (state.cadenceUnit) {
            ScheduleCadenceUnit.MINUTES -> resources.getQuantityString(
                R.plurals.schedule_cadence_minutes_count,
                state.cadenceValue,
                state.cadenceValue,
            )
            ScheduleCadenceUnit.HOURS -> resources.getQuantityString(
                R.plurals.schedule_cadence_hours_count,
                state.cadenceValue,
                state.cadenceValue,
            )
            ScheduleCadenceUnit.DAYS -> resources.getQuantityString(
                R.plurals.schedule_cadence_days_count,
                state.cadenceValue,
                state.cadenceValue,
            )
            ScheduleCadenceUnit.WEEKS -> resources.getQuantityString(
                R.plurals.schedule_cadence_weeks_count,
                state.cadenceValue,
                state.cadenceValue,
            )
        }

        val description = if (state.cadenceUnit == ScheduleCadenceUnit.DAYS || state.cadenceUnit == ScheduleCadenceUnit.WEEKS) {
            val timeStr = String.format(Locale.getDefault(), "%02d:%02d", state.hour, state.minute)
            getApplication<Application>().getString(
                R.string.schedule_next_export_every_at,
                cadenceText,
                timeStr,
            )
        } else {
            getApplication<Application>().getString(
                R.string.schedule_next_export_every,
                cadenceText,
            )
        }

        _uiState.update { it.copy(nextExportDescription = description) }
    }

    companion object {
        private const val MIN_CADENCE_MINUTES = 15
    }
}
