package com.healthmd.presentation.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class ScheduleViewModel @Inject constructor(
    private val exportScheduler: ExportScheduler,
    private val settingsRepository: SettingsRepository,
) : ViewModel() {

    private val _uiState = MutableStateFlow(ScheduleUiState())
    val uiState: StateFlow<ScheduleUiState> = _uiState.asStateFlow()

    init {
        viewModelScope.launch {
            val settings = settingsRepository.getExportSettings()
            _uiState.update {
                it.copy(
                    hour = settings.scheduleHour,
                    minute = settings.scheduleMinute,
                )
            }
            updateNextExportDescription()
        }
    }

    fun toggleSchedule(enabled: Boolean) {
        _uiState.update { it.copy(isEnabled = enabled) }
        viewModelScope.launch {
            if (enabled) {
                when (_uiState.value.frequency) {
                    ScheduleFrequency.DAILY -> exportScheduler.scheduleDaily()
                    ScheduleFrequency.WEEKLY -> exportScheduler.scheduleWeekly()
                }
            } else {
                exportScheduler.cancel()
            }
            updateNextExportDescription()
        }
    }

    fun setFrequency(frequency: ScheduleFrequency) {
        _uiState.update { it.copy(frequency = frequency) }
        if (_uiState.value.isEnabled) {
            toggleSchedule(true)
        }
        updateNextExportDescription()
    }

    fun setHour(hour: Int) {
        _uiState.update { it.copy(hour = hour) }
        viewModelScope.launch {
            val current = settingsRepository.getExportSettings()
            settingsRepository.updateExportSettings(current.copy(scheduleHour = hour))
        }
        updateNextExportDescription()
    }

    fun setMinute(minute: Int) {
        _uiState.update { it.copy(minute = minute) }
        viewModelScope.launch {
            val current = settingsRepository.getExportSettings()
            settingsRepository.updateExportSettings(current.copy(scheduleMinute = minute))
        }
        updateNextExportDescription()
    }

    private fun updateNextExportDescription() {
        val state = _uiState.value
        if (!state.isEnabled) {
            _uiState.update { it.copy(nextExportDescription = "") }
            return
        }
        val timeStr = String.format("%02d:%02d", state.hour, state.minute)
        val freqStr = when (state.frequency) {
            ScheduleFrequency.DAILY -> "daily"
            ScheduleFrequency.WEEKLY -> "weekly"
        }
        _uiState.update { it.copy(nextExportDescription = "Next export: $freqStr at $timeStr") }
    }
}
