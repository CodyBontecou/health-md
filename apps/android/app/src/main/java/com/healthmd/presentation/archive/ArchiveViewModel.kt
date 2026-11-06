package com.healthmd.presentation.archive

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
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

/** One selected-day row: the lane's coverage plus where it writes and what it offers. */
data class ArchiveDayRow(
    val day: ArchiveProfileDay,
    /** The dated file, folder or endpoint line; null when it cannot be derived. */
    val path: String?,
    val action: ArchiveDayAction?,
)

data class ArchiveUiState(
    val isLoaded: Boolean = false,
    val hasHistory: Boolean = false,
    val today: LocalDate,
    val selection: ArchiveSelection,
    val month: ArchiveMonth,
    val selectedDay: List<ArchiveDayRow>,
    val canShowNextMonth: Boolean,
)

/** The Archive coverage calendar, fed from Android export history. */
@HiltViewModel
class ArchiveViewModel @Inject constructor(
    exportHistoryRepository: ExportHistoryRepository,
    exportProfileRepository: ExportProfileRepository,
    scheduledProfileEntryStore: ScheduledProfileEntryStore,
    settingsRepository: SettingsRepository,
    private val healthConnectManager: HealthConnectManager,
) : ViewModel() {
    private val clock: Clock = Clock.systemDefaultZone()
    private val today: LocalDate get() = LocalDate.now(clock)

    private val selection = MutableStateFlow(
        ArchiveSelection(month = YearMonth.from(today), selectedDate = today),
    )

    private val _healthConnectConnected = MutableStateFlow<Boolean?>(null)

    /** Whether Health Connect granted any read permission; null until checked. */
    val healthConnectConnected: StateFlow<Boolean?> = _healthConnectConnected.asStateFlow()

    private data class LaneSources(
        val profiles: List<ExportProfile>,
        val schedules: List<ScheduledProfileEntry>,
        val settings: ExportSettings?,
    )

    val uiState: StateFlow<ArchiveUiState> = combine(
        exportHistoryRepository.getAllEntries(),
        selection,
        combine(
            exportProfileRepository.profiles,
            scheduledProfileEntryStore.entries,
            settingsRepository.exportSettings,
        ) { profiles, schedules, settings -> LaneSources(profiles, schedules, settings) },
    ) { entries, current, sources -> buildState(entries, current, sources, isLoaded = true) }
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            buildState(emptyList(), selection.value, LaneSources(emptyList(), emptyList(), null), isLoaded = false),
        )

    /** Re-reads the Health Connect permission state, e.g. when the screen resumes. */
    fun refreshHealthConnect() {
        viewModelScope.launch {
            _healthConnectConnected.value = try {
                healthConnectManager.isAvailable() && healthConnectManager.hasAllPermissions()
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                false
            }
        }
    }

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
        sources: LaneSources,
        isLoaded: Boolean,
    ): ArchiveUiState {
        val day = today
        val profiles = ArchiveCoverage.profiles(entries)
        // A filter for a profile that no longer appears in history falls back to "All".
        val filter = current.filter?.takeIf { it in profiles }
        val laneInfo = profiles.associateWith { lane(it, sources) }
        val dueToday = laneInfo.filterValues { it.isDueToday }.keys
        val month = ArchiveCoverage.month(entries, current.month, day, filter, dueToday)
        val lanes = filter?.let(::listOf) ?: profiles
        val rows = ArchiveCoverage.profileDays(entries, lanes, current.selectedDate, day, dueToday).map { row ->
            val info = laneInfo[row.profile] ?: ArchiveLane()
            val path = ArchiveCoverage.pathLine(info.output, current.selectedDate, row.status)
            // The day page renders a per-date file, so Open needs one in a device folder.
            val canOpen = info.output is ArchiveOutput.DeviceFolder &&
                ArchiveCoverage.relativeFilePath(info.output.settings, current.selectedDate) != null
            ArchiveDayRow(
                day = row,
                path = path,
                action = ArchiveCoverage.action(row.status, info.hasTodayRefresh, canOpen),
            )
        }
        return ArchiveUiState(
            isLoaded = isLoaded,
            hasHistory = entries.isNotEmpty(),
            today = day,
            selection = current.copy(filter = filter),
            month = month,
            selectedDay = rows,
            canShowNextMonth = current.month.isBefore(YearMonth.from(day)),
        )
    }

    /** Resolves a history lane to its profile, schedule and output; unknown parts stay null. */
    private fun lane(profile: ArchiveProfile, sources: LaneSources): ArchiveLane {
        val settings = sources.settings
        val name = profile.name
        if (name == null) {
            return ArchiveLane(
                isDueToday = settings?.let(ArchiveCoverage::isDueToday) == true,
                output = settings?.let(::currentOutput),
            )
        }
        val exportProfile = ExportProfileRules.byName(sources.profiles, name) ?: return ArchiveLane()
        val schedule = sources.schedules.firstOrNull { it.profileId == exportProfile.id }
        return ArchiveLane(
            isDueToday = ArchiveCoverage.isDueToday(schedule),
            hasTodayRefresh = schedule?.isEnabled == true && schedule.todayRefreshEnabled,
            output = profileOutput(exportProfile, settings),
        )
    }

    private fun currentOutput(settings: ExportSettings): ArchiveOutput? = when (settings.exportTarget) {
        // The current folder's display name is not stored with settings; show the relative path.
        ExportTarget.DEVICE_FOLDER -> ArchiveOutput.DeviceFolder(folderName = null, settings = settings)
        ExportTarget.API_ENDPOINT -> ArchiveCoverage.endpointLine(settings.apiEndpointUrl)?.let(ArchiveOutput::Endpoint)
        ExportTarget.AGENT_DATA_GATEWAY -> null
    }

    private fun profileOutput(profile: ExportProfile, current: ExportSettings?): ArchiveOutput? = when (profile.target) {
        ExportTarget.DEVICE_FOLDER -> current?.let { base ->
            val restored = runCatching {
                AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)?.restoreOnto(base)
            }.getOrNull()
            restored?.let { ArchiveOutput.DeviceFolder(folderName = profile.folderDisplayName, settings = it) }
        }
        ExportTarget.API_ENDPOINT -> ArchiveCoverage.endpointLine(profile.apiEndpointUrl)?.let(ArchiveOutput::Endpoint)
        ExportTarget.AGENT_DATA_GATEWAY -> null
    }
}
