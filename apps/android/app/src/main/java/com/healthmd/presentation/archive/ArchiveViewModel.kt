package com.healthmd.presentation.archive

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.data.scheduler.ScheduledProfileOccurrenceMath
import com.healthmd.data.scheduler.ScheduledProfileScheduler
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Clock
import java.time.LocalDate
import java.time.YearMonth
import java.time.temporal.WeekFields
import java.util.Locale
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
    /** The date's own file in a chosen folder, when the lane writes one. */
    val file: ArchiveFileRef? = null,
    /** The saved automation the lane maps to; fixes preset Export now to it. */
    val automationId: String? = null,
    /** False for endpoints and gateways: no file on this device to read. */
    val writesFilesOnDevice: Boolean = false,
)

/** One tile of the week strip. Future dates are shown but cannot be selected. */
data class ArchiveWeekDay(val date: LocalDate, val status: CoverageStatus, val isFuture: Boolean)

/** The earliest upcoming run: the automation's name, or null for the app-wide schedule. */
data class ArchiveNextRun(val profileName: String?, val atMillis: Long)

/** A saved automation as the Archive's sentence card and paused note read it. */
data class ArchiveAutomation(val profile: ExportProfile, val entry: ScheduledProfileEntry?) {
    val isRunning: Boolean get() = entry?.isEnabled == true
    val isPaused: Boolean get() = entry != null && !entry.isEnabled
}

data class ArchiveUiState(
    val isLoaded: Boolean = false,
    val hasHistory: Boolean = false,
    val today: LocalDate,
    val selection: ArchiveSelection,
    val month: ArchiveMonth,
    val selectedDay: List<ArchiveDayRow>,
    val canShowNextMonth: Boolean,
    /**
     * The name for the lane exported from the app's current settings: the active profile, whose
     * settings those are. Null when no profile exists yet.
     */
    val currentSettingsName: String? = null,
    /** False leads with the week strip and readable day (the iOS default); true shows the month. */
    val showsMonth: Boolean = false,
    val week: List<ArchiveWeekDay> = emptyList(),
    val canShowPreviousWeek: Boolean = true,
    val canShowNextWeek: Boolean = false,
    val nextRun: ArchiveNextRun? = null,
    val automations: List<ArchiveAutomation> = emptyList(),
    /** The selected lane's automation, when the lane is a saved profile. */
    val filteredAutomation: ArchiveAutomation? = null,
    /** Lanes whose automation is paused. */
    val pausedLanes: Set<ArchiveProfile> = emptySet(),
    /** The app's export folder is chosen (setup step two). */
    val hasFolder: Boolean = false,
) {
    /** iOS `needsSetup`: nothing exported, scheduled or pointed at a folder yet. */
    val needsSetup: Boolean
        get() = isLoaded && !hasHistory && automations.none { it.isRunning } && !hasFolder

    /** The readable day's lead lane: the filter, else the first lane that is not paused. */
    val leadRow: ArchiveDayRow?
        get() = selectedDay.firstOrNull { it.day.profile !in pausedLanes } ?: selectedDay.firstOrNull()

    /** What the readable day card reads: the lead lane's own file for the selected date. */
    val leadFileKey: ArchiveDayFileKey?
        get() = leadRow?.let { ArchiveLanes.fileKey(it, selection.selectedDate) }
}

/** The Archive coverage calendar, fed from Android export history. */
@HiltViewModel
class ArchiveViewModel @Inject constructor(
    exportHistoryRepository: ExportHistoryRepository,
    exportProfileRepository: ExportProfileRepository,
    private val scheduledProfileEntryStore: ScheduledProfileEntryStore,
    settingsRepository: SettingsRepository,
    private val healthConnectManager: HealthConnectManager,
    private val exportScheduler: ExportScheduler,
    private val profileScheduler: ScheduledProfileScheduler,
    private val dayFileReader: ArchiveDayFileReader,
    @ApplicationContext context: Context,
) : ViewModel() {
    private val preferences = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
    private val showsMonth = MutableStateFlow(preferences.getBoolean(KEY_SHOWS_MONTH, false))

    private val clock: Clock = Clock.systemDefaultZone()
    private val today: LocalDate get() = LocalDate.now(clock)

    private val selection = MutableStateFlow(
        ArchiveSelection(month = YearMonth.from(today), selectedDate = today),
    )

    private val _healthConnectConnected = MutableStateFlow<Boolean?>(null)

    /** Whether Health Connect granted any read permission; null until checked. */
    val healthConnectConnected: StateFlow<Boolean?> = _healthConnectConnected.asStateFlow()

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

    private val entries = exportHistoryRepository.getAllEntries()

    val uiState: StateFlow<ArchiveUiState> = combine(
        entries,
        combine(selection, showsMonth) { current, month -> current to month },
        sources,
    ) { entries, (current, month), sources -> buildState(entries, current, sources, isLoaded = true, showsMonth = month) }
        .stateIn(
            viewModelScope,
            SharingStarted.WhileSubscribed(5_000),
            buildState(
                emptyList(),
                selection.value,
                ArchiveLaneSources(),
                isLoaded = false,
                showsMonth = showsMonth.value,
            ),
        )

    /**
     * The lead lane's written file for the selected date, read through SAF (iOS `loadLeadFile`).
     * Compare its key with [ArchiveUiState.leadFileKey] so a stale read never shows.
     */
    @OptIn(ExperimentalCoroutinesApi::class)
    val leadFile: StateFlow<ArchiveLoadedFile?> = uiState
        .map { it.leadFileKey }
        .distinctUntilChanged()
        .mapLatest { key -> key?.let { ArchiveLoadedFile(it, dayFileReader.read(it.ref)) } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    /** Re-checked on resume: a grant can be revoked while the app is away. */
    private val environmentTick = MutableStateFlow(0)

    /** Needs attention: the heart's count and the sheet's items. */
    val attention: StateFlow<List<ArchiveAttentionItem>> = combine(
        entries,
        sources,
        _healthConnectConnected,
        environmentTick,
    ) { entries, sources, connected, _ ->
        val folder = sources.appFolderUri
        ArchiveAttention.items(
            ArchiveAttentionInputs(
                entries = entries,
                sources = sources,
                healthConnected = connected,
                appFolderAccessible = folder == null || dayFileReader.hasFolderAccess(folder),
                appFolderName = sources.profiles.firstOrNull { it.folderUri == folder }?.folderDisplayName
                    ?: folder?.let(dayFileReader::folderDisplayName),
            ),
        )
    }
        .flowOn(Dispatchers.IO)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    /** Re-reads the Health Connect permission state, e.g. when the screen resumes. */
    fun refreshHealthConnect() {
        environmentTick.update { it + 1 }
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

    /** Switches between the week strip and the month calendar; the choice is remembered. */
    fun setShowsMonth(value: Boolean) {
        preferences.edit().putBoolean(KEY_SHOWS_MONTH, value).apply()
        showsMonth.value = value
    }

    /** Moves a week, keeping the weekday, never past today. */
    fun moveWeek(offset: Long) {
        val target = selection.value.selectedDate.plusWeeks(offset)
        selectDate(if (target.isAfter(today)) today else target)
    }

    /** Selects the earliest gap of the visible month, if any. */
    fun jumpToGap() {
        val gap = uiState.value.month.stats.earliestGap ?: return
        selectDate(gap)
    }

    /** Turns a paused automation's schedule back on and re-arms it. */
    fun resume(profileId: String) {
        viewModelScope.launch {
            scheduledProfileEntryStore.update(profileId) { it.copy(isEnabled = true) }
            profileScheduler.reconcile()
        }
    }

    private fun buildState(
        entries: List<ExportHistoryEntry>,
        current: ArchiveSelection,
        sources: ArchiveLaneSources,
        isLoaded: Boolean,
        showsMonth: Boolean,
    ): ArchiveUiState {
        val day = today
        val profiles = ArchiveCoverage.profiles(entries)
        // A filter for a profile that no longer appears in history falls back to "All".
        val filter = current.filter?.takeIf { it in profiles }
        val laneInfo = profiles.associateWith { ArchiveLanes.lane(it, sources) }
        val dueToday = laneInfo.filterValues { it.isDueToday }.keys
        val month = ArchiveCoverage.month(entries, current.month, day, filter, dueToday)
        val lanes = filter?.let(::listOf) ?: profiles
        val automations = ArchiveLanes.automations(sources)
        val rows = ArchiveLanes.dayRows(entries, lanes, current.selectedDate, day, sources, laneInfo, automations)
        fun automationFor(lane: ArchiveProfile): ArchiveAutomation? = ArchiveLanes.automationFor(lane, automations, sources)
        val pausedLanes = profiles.filter { automationFor(it)?.isPaused == true }.toSet()
        val firstDay = WeekFields.of(Locale.getDefault()).firstDayOfWeek
        val weekStart = current.selectedDate.minusDays(((current.selectedDate.dayOfWeek.value - firstDay.value + 7) % 7).toLong())
        val week = (0L until 7L).map { offset ->
            val date = weekStart.plusDays(offset)
            val status = when {
                date.isAfter(day) -> CoverageStatus.NOT_DUE
                filter != null -> ArchiveCoverage.status(entries, filter, date, day, filter in dueToday)
                else -> ArchiveCoverage.aggregateDay(entries, date, day, dueToday)
            }
            ArchiveWeekDay(date, status, isFuture = date.isAfter(day))
        }
        return ArchiveUiState(
            isLoaded = isLoaded,
            hasHistory = entries.isNotEmpty(),
            today = day,
            selection = current.copy(filter = filter),
            month = month,
            selectedDay = rows,
            canShowNextMonth = current.month.isBefore(YearMonth.from(day)),
            currentSettingsName = sources.activeProfileName,
            showsMonth = showsMonth,
            week = week,
            canShowPreviousWeek = entries.isNotEmpty(),
            canShowNextWeek = weekStart.plusDays(7).let { !it.isAfter(day) },
            nextRun = nextRun(filter, automations, sources),
            automations = automations,
            filteredAutomation = filter?.let(::automationFor),
            pausedLanes = pausedLanes,
            hasFolder = sources.hasFolder,
        )
    }

    /** The earliest upcoming run, for the selected lane or across every schedule. */
    private fun nextRun(
        filter: ArchiveProfile?,
        automations: List<ArchiveAutomation>,
        sources: ArchiveLaneSources,
    ): ArchiveNextRun? {
        val now = clock.millis()
        val profileRuns = automations
            .filter { it.isRunning && (filter == null || it.profile.name == (filter.name ?: sources.activeProfileName)) }
            .mapNotNull { automation ->
                runCatching { ScheduledProfileOccurrenceMath.nextOccurrence(automation.entry!!, now) }
                    .getOrNull()
                    ?.let { ArchiveNextRun(automation.profile.name, it.toEpochMilli()) }
            }
        val appRun = if (filter == null || filter.name == null) {
            exportScheduler.nextScheduledAtMillis()
                ?.takeIf { sources.settings?.scheduleEnabled == true }
                ?.let { ArchiveNextRun(null, it) }
        } else {
            null
        }
        return (profileRuns + listOfNotNull(appRun)).filter { it.atMillis > now }.minByOrNull { it.atMillis }
    }

    private companion object {
        const val PREFERENCES = "archive_ui"
        const val KEY_SHOWS_MONTH = "shows_month"
    }
}
