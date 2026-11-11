package com.healthmd.presentation.archive

import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportProfileRules
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import java.time.LocalDate

/** Everything besides history that the Archive and the day page resolve lanes from. */
data class ArchiveLaneSources(
    val profiles: List<ExportProfile> = emptyList(),
    val schedules: List<ScheduledProfileEntry> = emptyList(),
    val settings: ExportSettings? = null,
    val activeProfileName: String? = null,
    /** The app's chosen export folder (a SAF tree URI). */
    val appFolderUri: String? = null,
) {
    val hasFolder: Boolean get() = !appFolderUri.isNullOrBlank()
}

/** Lane resolution shared by the Archive and the day page. */
object ArchiveLanes {
    fun automations(sources: ArchiveLaneSources): List<ArchiveAutomation> = sources.profiles.map { profile ->
        ArchiveAutomation(profile, sources.schedules.firstOrNull { it.profileId == profile.id })
    }

    /** The current-settings lane reads as the active profile, so it maps to that automation. */
    fun automationFor(
        lane: ArchiveProfile,
        automations: List<ArchiveAutomation>,
        sources: ArchiveLaneSources,
    ): ArchiveAutomation? =
        (lane.name ?: sources.activeProfileName)?.let { name -> automations.firstOrNull { it.profile.name == name } }

    /** Resolves a history lane to its schedule and output; unknown parts stay null. */
    fun lane(profile: ArchiveProfile, sources: ArchiveLaneSources): ArchiveLane {
        val settings = sources.settings
        val name = profile.name
        if (name == null) {
            return ArchiveLane(
                isDueToday = settings?.let(ArchiveCoverage::isDueToday) == true,
                output = settings?.let { currentOutput(it, sources.appFolderUri) },
            )
        }
        val exportProfile = ExportProfileRules.byName(sources.profiles, name) ?: return ArchiveLane()
        val schedule = sources.schedules.firstOrNull { it.profileId == exportProfile.id }
        return ArchiveLane(
            isDueToday = ArchiveCoverage.isDueToday(schedule),
            hasTodayRefresh = schedule?.isEnabled == true && schedule.todayRefreshEnabled,
            output = profileOutput(exportProfile, settings, sources.appFolderUri),
        )
    }

    /** One row per lane for [date]: coverage, path line, action, file and automation. */
    fun dayRows(
        entries: List<ExportHistoryEntry>,
        lanes: List<ArchiveProfile>,
        date: LocalDate,
        today: LocalDate,
        sources: ArchiveLaneSources,
        laneInfo: Map<ArchiveProfile, ArchiveLane> = lanes.associateWith { lane(it, sources) },
        automations: List<ArchiveAutomation> = automations(sources),
    ): List<ArchiveDayRow> {
        val dueToday = laneInfo.filterValues { it.isDueToday }.keys
        return ArchiveCoverage.profileDays(entries, lanes, date, today, dueToday).map { row ->
            val info = laneInfo[row.profile] ?: ArchiveLane()
            val output = info.output
            val relative = (output as? ArchiveOutput.DeviceFolder)?.let { ArchiveCoverage.relativeFilePath(it.settings, date) }
            // The day page renders a per-date file, so Open needs one in a device folder.
            val canOpen = relative != null
            ArchiveDayRow(
                day = row,
                path = ArchiveCoverage.pathLine(output, date, row.status),
                action = ArchiveCoverage.action(row.status, info.hasTodayRefresh, canOpen),
                file = relative?.let { path ->
                    (output as ArchiveOutput.DeviceFolder).folderUri?.takeIf { it.isNotBlank() }?.let { ArchiveFileRef(it, path) }
                },
                automationId = automationFor(row.profile, automations, sources)?.profile?.id,
                writesFilesOnDevice = output is ArchiveOutput.DeviceFolder,
            )
        }
    }

    /** What to read for a row (iOS `dayFileRequest`): only a written or updating day with a file. */
    fun fileKey(row: ArchiveDayRow, date: LocalDate): ArchiveDayFileKey? {
        val status = row.day.status
        if (status != CoverageStatus.COMPLETE && status != CoverageStatus.PARTIAL && status != CoverageStatus.IN_PROGRESS) {
            return null
        }
        val ref = row.file ?: return null
        return ArchiveDayFileKey(row.day.profile, date, ref, status, row.day.latestEntry?.timestamp)
    }

    private fun currentOutput(settings: ExportSettings, appFolderUri: String?): ArchiveOutput? = when (settings.exportTarget) {
        // The current folder's display name is not stored with settings; show the relative path.
        ExportTarget.DEVICE_FOLDER -> ArchiveOutput.DeviceFolder(folderName = null, settings = settings, folderUri = appFolderUri)
        ExportTarget.API_ENDPOINT -> ArchiveCoverage.endpointLine(settings.apiEndpointUrl)?.let(ArchiveOutput::Endpoint)
        ExportTarget.GOOGLE_DRIVE, ExportTarget.AGENT_DATA_GATEWAY -> null
    }

    private fun profileOutput(profile: ExportProfile, current: ExportSettings?, appFolderUri: String?): ArchiveOutput? =
        when (profile.target) {
            ExportTarget.DEVICE_FOLDER -> current?.let { base ->
                val restored = runCatching {
                    AndroidExportSettingsSnapshotCodec.decodeOrNull(profile.settingsSnapshotJson)?.restoreOnto(base)
                }.getOrNull()
                restored?.let {
                    ArchiveOutput.DeviceFolder(
                        folderName = profile.folderDisplayName,
                        settings = it,
                        // A bound folder is where this profile writes; otherwise the app's folder.
                        folderUri = profile.folderUri?.takeIf { uri -> uri.isNotBlank() } ?: appFolderUri,
                    )
                }
            }
            ExportTarget.API_ENDPOINT -> ArchiveCoverage.endpointLine(profile.apiEndpointUrl)?.let(ArchiveOutput::Endpoint)
            ExportTarget.GOOGLE_DRIVE, ExportTarget.AGENT_DATA_GATEWAY -> null
        }
}
