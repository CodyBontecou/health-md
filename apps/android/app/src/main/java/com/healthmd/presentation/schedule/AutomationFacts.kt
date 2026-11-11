package com.healthmd.presentation.schedule

import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.presentation.archive.ArchiveCoverage
import com.healthmd.presentation.archive.ArchiveProfile
import com.healthmd.presentation.archive.CoverageStatus
import java.time.LocalDate
import java.time.ZoneId

/**
 * Pure derivations shared by the Automations list, an automation's detail and its pages,
 * mirroring the iOS `AutomationFacts`. Kept free of Compose so they are unit tested.
 */
object AutomationFacts {
    /** Days the list card's strip shows: the completed days before today. */
    const val RECENT_DAY_COUNT = 14

    /** Coverage of the [RECENT_DAY_COUNT] completed days before [today], oldest first. */
    fun recentDays(
        entries: List<ExportHistoryEntry>,
        profileName: String,
        today: LocalDate,
    ): List<CoverageStatus> = (RECENT_DAY_COUNT downTo 1).map { offset ->
        ArchiveCoverage.status(entries, ArchiveProfile(profileName), today.minusDays(offset.toLong()), today)
    }

    /** "MD · Bases": file-type abbreviations in format order, so they are not translated. */
    fun formatsShortLabel(formats: Set<ExportFormat>): String =
        ExportFormat.entries.filter { it in formats }.joinToString(" · ") { format ->
            when (format) {
                ExportFormat.MARKDOWN -> "MD"
                ExportFormat.OBSIDIAN_BASES -> "Bases"
                ExportFormat.JSON -> "JSON"
                ExportFormat.CSV -> "CSV"
            }
        }

    /** "Standard" until the frontmatter fields or the Markdown body are customized (iOS parity). */
    fun isStandardFormat(customization: FormatCustomization): Boolean {
        val standard = FormatCustomization()
        return customization.frontmatterConfig == standard.frontmatterConfig &&
            customization.markdownTemplate == standard.markdownTemplate
    }

    /** What the Schedule row and card read: no schedule, paused, or the cadence. */
    fun scheduleKind(entry: ScheduledProfileEntry?): AutomationScheduleKind = when {
        entry == null -> AutomationScheduleKind.OFF
        !entry.isEnabled -> AutomationScheduleKind.PAUSED
        else -> when (ProfileScheduleFrequency.of(entry)) {
            ProfileScheduleFrequency.DAILY -> AutomationScheduleKind.DAILY
            ProfileScheduleFrequency.WEEKLY -> AutomationScheduleKind.WEEKLY
            ProfileScheduleFrequency.CUSTOM -> AutomationScheduleKind.CUSTOM
        }
    }

    /** First and last day a pending recovery still holds, or null without dates. */
    fun pendingRecoveryDays(entry: ScheduledProfileEntry): Pair<LocalDate, LocalDate>? {
        val days = entry.pendingExports.flatMap { it.ownerEpochDays }
        val first = days.minOrNull() ?: return null
        return LocalDate.ofEpochDay(first) to LocalDate.ofEpochDay(days.max())
    }

    /** A profile can be saved only with an output format (as the profile editor requires). */
    fun hasOutput(settings: ExportSettings): Boolean = settings.exportFormats.isNotEmpty()
}

enum class AutomationScheduleKind { OFF, PAUSED, DAILY, WEEKLY, CUSTOM }

/**
 * The Schedule page's Repeat choice (iOS `ScheduleFrequency`). Android stores a count and a
 * unit; one day is Daily, one week is Weekly, and every other cadence is Custom.
 */
enum class ProfileScheduleFrequency {
    DAILY, WEEKLY, CUSTOM;

    companion object {
        fun of(entry: ScheduledProfileEntry): ProfileScheduleFrequency = when {
            entry.cadenceValue == 1 && entry.cadenceUnit == ScheduledProfileCadenceUnit.DAY -> DAILY
            entry.cadenceValue == 1 && entry.cadenceUnit == ScheduledProfileCadenceUnit.WEEK -> WEEKLY
            else -> CUSTOM
        }
    }
}

/** Edits the Schedule page makes to a draft entry. The clamps match the entry's own rules. */
object ProfileScheduleForm {
    const val MAX_CUSTOM_INTERVAL = 365
    const val MIN_LOOKBACK_DAYS = 1
    const val MAX_LOOKBACK_DAYS = 30

    /** A first schedule for a profile without one: daily, on, at the app's preferred time. */
    fun newEntry(profileId: String, hour: Int, minute: Int, today: LocalDate, zone: ZoneId): ScheduledProfileEntry =
        ScheduledProfileEntry(
            profileId = profileId,
            isEnabled = true,
            anchorEpochDay = today.toEpochDay(),
            hour = hour.coerceIn(0, 23),
            minute = minute.coerceIn(0, 59),
            cadenceUnit = ScheduledProfileCadenceUnit.DAY,
            lookbackDays = 1,
            zoneId = zone.id,
        )

    /**
     * Daily and Weekly are one day or week. Entering Custom starts its cadence today, as on
     * iOS, and moves off the plain daily/weekly count so the choice is not read back as one.
     */
    fun withFrequency(
        entry: ScheduledProfileEntry,
        frequency: ProfileScheduleFrequency,
        today: LocalDate,
    ): ScheduledProfileEntry = when (frequency) {
        ProfileScheduleFrequency.DAILY -> entry.copy(cadenceUnit = ScheduledProfileCadenceUnit.DAY, cadenceValue = 1)
        ProfileScheduleFrequency.WEEKLY -> entry.copy(cadenceUnit = ScheduledProfileCadenceUnit.WEEK, cadenceValue = 1)
        ProfileScheduleFrequency.CUSTOM -> if (ProfileScheduleFrequency.of(entry) == ProfileScheduleFrequency.CUSTOM) {
            entry
        } else {
            entry.copy(cadenceValue = 2, anchorEpochDay = today.toEpochDay())
        }
    }

    fun withInterval(entry: ScheduledProfileEntry, value: Int): ScheduledProfileEntry =
        entry.copy(cadenceValue = value.coerceIn(1, MAX_CUSTOM_INTERVAL))

    fun withLookback(entry: ScheduledProfileEntry, days: Int): ScheduledProfileEntry =
        entry.copy(lookbackDays = days.coerceIn(MIN_LOOKBACK_DAYS, MAX_LOOKBACK_DAYS))
}

/**
 * The composer's staged choices (iOS `ComposerDraft`): field checks and the daily-note switch,
 * applied on top of the SAVED settings so a page saved meanwhile is never undone. Choices made
 * on their own pages save there.
 */
data class ComposerDraft(
    /** Field checks keyed by metric ID. */
    val fields: Map<String, Boolean> = emptyMap(),
    val note: Boolean? = null,
) {
    val isEmpty: Boolean get() = fields.isEmpty() && note == null

    fun applyTo(saved: ExportSettings): ExportSettings {
        var selection = saved.metricSelection
        fields.forEach { (id, enabled) ->
            if (selection.isEnabled(id) != enabled) selection = selection.toggle(id)
        }
        return saved.copy(
            metricSelection = selection,
            dailyNoteInjection = note?.let { saved.dailyNoteInjection.copy(enabled = it) } ?: saved.dailyNoteInjection,
        )
    }

    /** A second toggle back to the saved value unstages the choice. */
    fun toggleField(metricId: String, saved: ExportSettings): ComposerDraft {
        val wasOn = saved.metricSelection.isEnabled(metricId)
        val next = !(fields[metricId] ?: wasOn)
        return copy(fields = if (next == wasOn) fields - metricId else fields + (metricId to next))
    }

    fun toggleNote(saved: ExportSettings): ComposerDraft {
        val wasOn = saved.dailyNoteInjection.enabled
        val next = !(note ?: wasOn)
        return copy(note = if (next == wasOn) null else next)
    }
}
