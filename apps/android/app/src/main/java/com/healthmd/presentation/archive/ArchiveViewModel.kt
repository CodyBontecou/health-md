package com.healthmd.presentation.archive

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.repository.ExportHistoryRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import java.time.Clock
import java.time.LocalDate
import java.time.YearMonth
import javax.inject.Inject

data class ArchiveSelection(
    val month: YearMonth,
    val selectedDate: LocalDate,
    /** Null shows "All". */
    val filter: ArchiveProfile? = null,
)

data class ArchiveUiState(
    val isLoaded: Boolean = false,
    val hasHistory: Boolean = false,
    val today: LocalDate,
    val selection: ArchiveSelection,
    val month: ArchiveMonth,
    val selectedDay: List<ArchiveProfileDay>,
    val canShowNextMonth: Boolean,
)

/** The Archive coverage calendar, fed from Android export history. */
@HiltViewModel
class ArchiveViewModel @Inject constructor(
    exportHistoryRepository: ExportHistoryRepository,
) : ViewModel() {
    private val clock: Clock = Clock.systemDefaultZone()
    private val today: LocalDate get() = LocalDate.now(clock)

    private val selection = MutableStateFlow(
        ArchiveSelection(month = YearMonth.from(today), selectedDate = today),
    )

    val uiState: StateFlow<ArchiveUiState> = combine(
        exportHistoryRepository.getAllEntries(),
        selection,
    ) { entries, current -> buildState(entries, current, isLoaded = true) }
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            buildState(emptyList(), selection.value, isLoaded = false),
        )

    fun selectDate(date: LocalDate) {
        selection.update { it.copy(selectedDate = date, month = YearMonth.from(date)) }
    }

    fun selectFilter(profile: ArchiveProfile?) {
        selection.update { it.copy(filter = profile) }
    }

    fun showPreviousMonth() {
        selection.update { current ->
            val month = current.month.minusMonths(1)
            current.copy(month = month, selectedDate = month.atEndOfMonth())
        }
    }

    fun showNextMonth() {
        selection.update { current ->
            val month = current.month.plusMonths(1)
            if (month.isAfter(YearMonth.from(today))) return@update current
            val date = if (month == YearMonth.from(today)) today else month.atDay(1)
            current.copy(month = month, selectedDate = date)
        }
    }

    /** Selects the earliest gap of the visible month, if any. */
    fun jumpToGap() {
        val gap = uiState.value.month.stats.earliestGap ?: return
        selectDate(gap)
    }

    private fun buildState(
        entries: List<ExportHistoryEntry>,
        current: ArchiveSelection,
        isLoaded: Boolean,
    ): ArchiveUiState {
        val day = today
        val profiles = ArchiveCoverage.profiles(entries)
        // A filter for a profile that no longer appears in history falls back to "All".
        val filter = current.filter?.takeIf { it in profiles }
        val month = ArchiveCoverage.month(entries, current.month, day, filter)
        val lanes = filter?.let(::listOf) ?: profiles
        return ArchiveUiState(
            isLoaded = isLoaded,
            hasHistory = entries.isNotEmpty(),
            today = day,
            selection = current.copy(filter = filter),
            month = month,
            selectedDay = ArchiveCoverage.profileDays(entries, lanes, current.selectedDate, day),
            canShowNextMonth = current.month.isBefore(YearMonth.from(day)),
        )
    }
}
