package com.healthmd.presentation.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.scheduler.ExportScheduler
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
) : ViewModel() {

    private val _uiState = MutableStateFlow(ScheduleUiState())
    val uiState: StateFlow<ScheduleUiState> = _uiState.asStateFlow()

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
        }
    }

    fun setFrequency(frequency: ScheduleFrequency) {
        _uiState.update { it.copy(frequency = frequency) }
        if (_uiState.value.isEnabled) {
            toggleSchedule(true) // Reschedule with new frequency
        }
    }
}
