package com.healthmd.presentation.schedule

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.presentation.archive.CoverageStatus
import dagger.hilt.android.lifecycle.HiltViewModel
import java.time.LocalDate
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn

/**
 * The Automations cards' 14-day strips: each automation's coverage of the completed days
 * before today, from the same export history and rules as the Archive.
 */
@HiltViewModel
class AutomationRecentViewModel @Inject constructor(
    historyRepository: ExportHistoryRepository,
    profileRepository: ExportProfileRepository,
) : ViewModel() {
    /** Statuses keyed by profile ID, oldest first. */
    val recentDays: StateFlow<Map<String, List<CoverageStatus>>> = combine(
        historyRepository.getAllEntries(),
        profileRepository.profiles,
    ) { entries, profiles ->
        val today = LocalDate.now()
        profiles.associate { it.id to AutomationFacts.recentDays(entries, it.name, today) }
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())
}
