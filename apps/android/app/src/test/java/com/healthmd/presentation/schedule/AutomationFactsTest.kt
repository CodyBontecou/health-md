package com.healthmd.presentation.schedule

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfilePendingExport
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.UnitPreference
import com.healthmd.presentation.archive.CoverageStatus
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Test

class AutomationFactsTest {
    private val today = LocalDate.of(2026, 11, 7)

    private fun entry(
        value: Int = 1,
        unit: ScheduledProfileCadenceUnit = ScheduledProfileCadenceUnit.DAY,
        enabled: Boolean = true,
    ) = ScheduledProfileEntry(
        profileId = "p1",
        isEnabled = enabled,
        anchorEpochDay = 20_000L,
        cadenceValue = value,
        cadenceUnit = unit,
    )

    @Test
    fun recentDaysCoverTheFourteenCompletedDaysBeforeTodayOldestFirst() {
        val history = listOf(
            ExportHistoryEntry(
                timestamp = 1,
                source = ExportSource.SCHEDULED,
                dateRangeStart = today.minusDays(2),
                dateRangeEnd = today.minusDays(1),
                successCount = 2,
                totalCount = 2,
                profileName = "Daily",
            ),
            // Another automation's run never colours this one's strip.
            ExportHistoryEntry(
                timestamp = 2,
                source = ExportSource.SCHEDULED,
                dateRangeStart = today.minusDays(14),
                dateRangeEnd = today.minusDays(14),
                successCount = 0,
                totalCount = 1,
                profileName = "Weekly",
            ),
        )
        val days = AutomationFacts.recentDays(history, "Daily", today)
        assertThat(days).hasSize(AutomationFacts.RECENT_DAY_COUNT)
        assertThat(days.takeLast(2)).containsExactly(CoverageStatus.COMPLETE, CoverageStatus.COMPLETE)
        assertThat(days.dropLast(2).toSet()).containsExactly(CoverageStatus.NOT_DUE)
        assertThat(AutomationFacts.recentDays(history, "Weekly", today).first()).isEqualTo(CoverageStatus.MISSING)
    }

    @Test
    fun formatsReadAsUntranslatedAbbreviationsInFormatOrder() {
        assertThat(AutomationFacts.formatsShortLabel(setOf(ExportFormat.CSV, ExportFormat.MARKDOWN, ExportFormat.OBSIDIAN_BASES)))
            .isEqualTo("MD · Bases · CSV")
        assertThat(AutomationFacts.formatsShortLabel(emptySet())).isEmpty()
    }

    @Test
    fun formatIsStandardUntilFrontmatterOrBodyIsCustomized() {
        assertThat(AutomationFacts.isStandardFormat(FormatCustomization())).isTrue()
        // Units and dates are format choices, not a custom note layout.
        assertThat(AutomationFacts.isStandardFormat(FormatCustomization(unitPreference = UnitPreference.IMPERIAL))).isTrue()
        assertThat(
            AutomationFacts.isStandardFormat(FormatCustomization(frontmatterConfig = FrontmatterConfiguration(customDateKey = "day"))),
        ).isFalse()
    }

    @Test
    fun scheduleKindReadsOffPausedAndTheCadence() {
        assertThat(AutomationFacts.scheduleKind(null)).isEqualTo(AutomationScheduleKind.OFF)
        assertThat(AutomationFacts.scheduleKind(entry(enabled = false))).isEqualTo(AutomationScheduleKind.PAUSED)
        assertThat(AutomationFacts.scheduleKind(entry())).isEqualTo(AutomationScheduleKind.DAILY)
        assertThat(AutomationFacts.scheduleKind(entry(unit = ScheduledProfileCadenceUnit.WEEK))).isEqualTo(AutomationScheduleKind.WEEKLY)
        assertThat(AutomationFacts.scheduleKind(entry(value = 3))).isEqualTo(AutomationScheduleKind.CUSTOM)
        assertThat(AutomationFacts.scheduleKind(entry(unit = ScheduledProfileCadenceUnit.MONTH))).isEqualTo(AutomationScheduleKind.CUSTOM)
    }

    @Test
    fun outputNeedsAFormat() {
        assertThat(AutomationFacts.hasOutput(ExportSettings())).isTrue()
        assertThat(AutomationFacts.hasOutput(ExportSettings(exportFormats = emptySet()))).isFalse()
    }

    @Test
    fun pendingRecoverySpansItsOwnerDays() {
        assertThat(AutomationFacts.pendingRecoveryDays(entry())).isNull()
        val pending = entry().copy(
            pendingExports = listOf(
                pendingExport("a", listOf(20_010L, 20_008L)),
                pendingExport("b", listOf(20_012L)),
            ),
        )
        assertThat(AutomationFacts.pendingRecoveryDays(pending))
            .isEqualTo(LocalDate.ofEpochDay(20_008L) to LocalDate.ofEpochDay(20_012L))
    }

    private fun pendingExport(id: String, days: List<Long>) = ScheduledProfilePendingExport(
        id = id,
        ownerEpochDays = days,
        fireAtMillis = 0L,
        settingsSnapshotJson = "{}",
        target = ExportTarget.DEVICE_FOLDER,
        profileName = "Daily",
    )

    @Test
    fun frequencyReadsOneDayAsDailyOneWeekAsWeeklyAndTheRestAsCustom() {
        assertThat(ProfileScheduleFrequency.of(entry())).isEqualTo(ProfileScheduleFrequency.DAILY)
        assertThat(ProfileScheduleFrequency.of(entry(unit = ScheduledProfileCadenceUnit.WEEK))).isEqualTo(ProfileScheduleFrequency.WEEKLY)
        assertThat(ProfileScheduleFrequency.of(entry(value = 2))).isEqualTo(ProfileScheduleFrequency.CUSTOM)
        assertThat(ProfileScheduleFrequency.of(entry(unit = ScheduledProfileCadenceUnit.MONTH))).isEqualTo(ProfileScheduleFrequency.CUSTOM)
    }

    @Test
    fun enteringCustomStartsTodayAndLeavesThePlainCount() {
        val custom = ProfileScheduleForm.withFrequency(entry(), ProfileScheduleFrequency.CUSTOM, today)
        assertThat(custom.cadenceValue).isEqualTo(2)
        assertThat(custom.cadenceUnit).isEqualTo(ScheduledProfileCadenceUnit.DAY)
        assertThat(custom.anchorEpochDay).isEqualTo(today.toEpochDay())
        assertThat(ProfileScheduleFrequency.of(custom)).isEqualTo(ProfileScheduleFrequency.CUSTOM)

        // An existing custom cadence is kept, anchor included.
        val existing = entry(value = 5, unit = ScheduledProfileCadenceUnit.WEEK)
        assertThat(ProfileScheduleForm.withFrequency(existing, ProfileScheduleFrequency.CUSTOM, today)).isEqualTo(existing)

        val weekly = ProfileScheduleForm.withFrequency(existing, ProfileScheduleFrequency.WEEKLY, today)
        assertThat(weekly.cadenceValue to weekly.cadenceUnit).isEqualTo(1 to ScheduledProfileCadenceUnit.WEEK)
        val daily = ProfileScheduleForm.withFrequency(existing, ProfileScheduleFrequency.DAILY, today)
        assertThat(daily.cadenceValue to daily.cadenceUnit).isEqualTo(1 to ScheduledProfileCadenceUnit.DAY)
    }

    @Test
    fun steppersClampToTheEntryRules() {
        assertThat(ProfileScheduleForm.withInterval(entry(), 0).cadenceValue).isEqualTo(1)
        assertThat(ProfileScheduleForm.withInterval(entry(), 999).cadenceValue).isEqualTo(ProfileScheduleForm.MAX_CUSTOM_INTERVAL)
        assertThat(ProfileScheduleForm.withLookback(entry(), 0).lookbackDays).isEqualTo(1)
        assertThat(ProfileScheduleForm.withLookback(entry(), 31).lookbackDays).isEqualTo(30)
    }

    @Test
    fun aNewScheduleIsDailyOnAndAtThePreferredTime() {
        val created = ProfileScheduleForm.newEntry("p9", hour = 25, minute = 70, today = today, zone = ZoneId.of("Europe/Berlin"))
        assertThat(created.isEnabled).isTrue()
        assertThat(created.hour to created.minute).isEqualTo(23 to 59)
        assertThat(ProfileScheduleFrequency.of(created)).isEqualTo(ProfileScheduleFrequency.DAILY)
        assertThat(created.anchorEpochDay).isEqualTo(today.toEpochDay())
        assertThat(created.zoneId).isEqualTo("Europe/Berlin")
    }

    @Test
    fun composerDraftStagesChoicesOverTheSavedSettings() {
        val saved = ExportSettings()
        val metric = saved.metricSelection.enabledMetrics.first()
        var draft = ComposerDraft()
        assertThat(draft.isEmpty).isTrue()

        draft = draft.toggleField(metric, saved).toggleNote(saved)
        assertThat(draft.fields).containsExactly(metric, false)
        assertThat(draft.note).isEqualTo(!saved.dailyNoteInjection.enabled)

        val applied = draft.applyTo(saved)
        assertThat(applied.metricSelection.isEnabled(metric)).isFalse()
        assertThat(applied.dailyNoteInjection.enabled).isEqualTo(!saved.dailyNoteInjection.enabled)

        // Staged choices apply on top of whatever was saved meanwhile.
        val savedMeanwhile = saved.copy(filenameFormat = "{year}", dailyNoteInjection = DailyNoteInjectionSettings(folderPath = "Journal"))
        val reapplied = draft.applyTo(savedMeanwhile)
        assertThat(reapplied.filenameFormat).isEqualTo("{year}")
        assertThat(reapplied.dailyNoteInjection.folderPath).isEqualTo("Journal")

        // A second toggle back to the saved value unstages the choice.
        draft = draft.toggleField(metric, saved).toggleNote(saved)
        assertThat(draft.isEmpty).isTrue()
        assertThat(draft.applyTo(saved)).isEqualTo(saved)
    }
}
