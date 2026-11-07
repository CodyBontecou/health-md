package com.healthmd.presentation.archive

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import java.time.LocalDate
import javax.inject.Inject
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn

/** One automation tab of the day page. */
data class DayPageLane(
    val row: ArchiveDayRow,
    /** Position among the Archive's lanes, for the identity colour. */
    val colorIndex: Int,
    val isPaused: Boolean,
)

data class DayPageUiState(
    val date: LocalDate,
    val today: LocalDate = date,
    val isLoaded: Boolean = false,
    val lanes: List<DayPageLane> = emptyList(),
    val selected: ArchiveProfile? = null,
    val currentSettingsName: String? = null,
) {
    val lane: DayPageLane?
        get() = lanes.firstOrNull { it.row.day.profile == selected } ?: lanes.firstOrNull()

    /** What to read for the selected tab; null when the date has no file of its own. */
    val fileKey: ArchiveDayFileKey?
        get() = lane?.let { ArchiveLanes.fileKey(it.row, date) }

    /**
     * The date's fix (Backfill, Retry, Refresh), or Re-export for a written day (iOS
     * `secondaryAction`).
     */
    val secondaryAction: ArchiveDayAction?
        get() {
            val row = lane?.row ?: return null
            row.action?.takeIf { it != ArchiveDayAction.OPEN }?.let { return it }
            return when (row.day.status) {
                CoverageStatus.COMPLETE, CoverageStatus.PARTIAL -> ArchiveDayAction.REEXPORT
                else -> null
            }
        }
}

/**
 * The day page (iOS `ArchiveDayPage`): one tab per automation, its status for the date, and the
 * file that automation wrote, read from the export folder. Nothing is rendered or written here.
 */
@HiltViewModel
class DayPageViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    exportHistoryRepository: ExportHistoryRepository,
    exportProfileRepository: ExportProfileRepository,
    scheduledProfileEntryStore: ScheduledProfileEntryStore,
    settingsRepository: SettingsRepository,
    private val dayFileReader: ArchiveDayFileReader,
) : ViewModel() {
    private val date: LocalDate = savedStateHandle.get<String>(DATE_ARGUMENT)
        ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        ?: LocalDate.now()

    /** The tab chosen here, else the one the route asked for; null leads with the Archive's lead lane. */
    private val selection = MutableStateFlow(decodeLane(savedStateHandle.get<String>(LANE_ARGUMENT)))

    private val sources = combine(
        exportProfileRepository.profiles,
        exportProfileRepository.activeProfileId,
        scheduledProfileEntryStore.entries,
        settingsRepository.exportSettings,
        settingsRepository.exportFolderUri,
    ) { profiles, activeId, schedules, settings, folder ->
        ArchiveLaneSources(
            profiles = profiles,
            schedules = schedules,
            settings = settings,
            activeProfileName = ExportProfileRules.active(profiles, activeId)?.name,
            appFolderUri = folder?.takeIf { it.isNotBlank() },
        )
    }

    val uiState: StateFlow<DayPageUiState> = combine(
        exportHistoryRepository.getAllEntries(),
        sources,
        selection,
    ) { entries, sources, selected -> state(entries, sources, selected, date, LocalDate.now()) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DayPageUiState(date = date))

    /** The selected tab's written file; compare its key with [DayPageUiState.fileKey]. */
    @OptIn(ExperimentalCoroutinesApi::class)
    val file: StateFlow<ArchiveLoadedFile?> = uiState
        .map { it.fileKey }
        .distinctUntilChanged()
        .mapLatest { key -> key?.let { ArchiveLoadedFile(it, dayFileReader.read(it.ref)) } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun select(lane: ArchiveProfile) {
        selection.value = lane
    }

    companion object {
        const val DATE_ARGUMENT = "date"
        const val LANE_ARGUMENT = "lane"

        private const val CURRENT_SETTINGS_LANE = "c"
        private const val NAMED_LANE_PREFIX = "n:"

        /** A lane as a route argument: the current-settings lane has no name of its own. */
        fun encodeLane(lane: ArchiveProfile): String = lane.name?.let { NAMED_LANE_PREFIX + it } ?: CURRENT_SETTINGS_LANE

        fun decodeLane(value: String?): ArchiveProfile? = when {
            value == null -> null
            value == CURRENT_SETTINGS_LANE -> ArchiveProfile(null)
            value.startsWith(NAMED_LANE_PREFIX) -> ArchiveProfile(value.removePrefix(NAMED_LANE_PREFIX))
            else -> null
        }

        internal fun state(
            entries: List<ExportHistoryEntry>,
            sources: ArchiveLaneSources,
            selected: ArchiveProfile?,
            date: LocalDate,
            today: LocalDate,
        ): DayPageUiState {
            val lanes = ArchiveCoverage.profiles(entries)
            val automations = ArchiveLanes.automations(sources)
            val rows = ArchiveLanes.dayRows(entries, lanes, date, today, sources, automations = automations)
            val pages = rows.mapIndexed { index, row ->
                DayPageLane(
                    row = row,
                    colorIndex = index,
                    isPaused = ArchiveLanes.automationFor(row.day.profile, automations, sources)?.isPaused == true,
                )
            }
            // iOS `leadProfile`: the asked-for lane, else the first running one, else the first.
            val lead = selected?.takeIf { wanted -> pages.any { it.row.day.profile == wanted } }
                ?: pages.firstOrNull { !it.isPaused }?.row?.day?.profile
                ?: pages.firstOrNull()?.row?.day?.profile
            return DayPageUiState(
                date = date,
                today = today,
                isLoaded = true,
                lanes = pages,
                selected = lead,
                currentSettingsName = sources.activeProfileName,
            )
        }
    }
}
