package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FolderOrganization
import org.junit.Test
import java.time.LocalDate

class ExportSettingsPathTest {

    @Test
    fun aggregatePathCombinesSubfolderFolderStructureFilenameAndFormat() {
        val settings = ExportSettings(
            subfolder = "health",
            folderStructure = "{year}/{month}/{day}",
            filenameFormat = "Health-{date}",
            exportFormats = setOf(ExportFormat.MARKDOWN, ExportFormat.OBSIDIAN_BASES),
        )
        val date = LocalDate.of(2026, 6, 5)

        assertThat(settings.aggregateRelativePath(date, ExportFormat.MARKDOWN))
            .isEqualTo("health/2026/06/05/Health-2026-06-05.md")
        assertThat(settings.aggregateRelativePath(date, ExportFormat.OBSIDIAN_BASES))
            .isEqualTo("health/2026/06/05/Health-2026-06-05-bases.md")
    }

    @Test
    fun folderOrganizationAppliesWhenCustomTemplateIsBlank() {
        val settings = ExportSettings(
            subfolder = "health",
            folderStructure = "",
            folderOrganization = FolderOrganization.BY_YEAR_MONTH,
        )

        assertThat(settings.aggregateRelativePath(LocalDate.of(2026, 6, 5), ExportFormat.JSON))
            .isEqualTo("health/2026/06/2026-06-05.json")
    }

    @Test
    fun isoWeekPathsUseWeekYearAndKeepExistingTokensUnchanged() {
        val originalLocale = java.util.Locale.getDefault()
        try {
            // Sunday-first and non-Latin locales must still use ISO Monday/four-day weeks.
            for (locale in listOf(java.util.Locale.US, java.util.Locale.FRANCE, java.util.Locale.forLanguageTag("ar"))) {
                java.util.Locale.setDefault(locale)
                for ((day, folder) in listOf(
                    "2026-11-01" to "2026/Week 44",
                    "2027-01-01" to "2026/Week 53",
                    "2027-01-04" to "2027/Week 01",
                    "2029-12-31" to "2030/Week 01",
                )) {
                    val date = LocalDate.parse(day)
                    val settings = ExportSettings(folderStructure = ExportSettings.YEAR_WEEK_FOLDER_TEMPLATE)
                    assertThat(settings.formatFolderPath(date)).isEqualTo(folder)
                    assertThat(settings.formatFilename(date)).isEqualTo(day)
                    assertThat(ExportSettings.applyDatePlaceholders("{weekYear}/Week {week}/{date}", date))
                        .isEqualTo("$folder/$day")
                    val daily = com.healthmd.domain.model.DailyNoteInjectionSettings(filenamePattern = "{weekYear}-W{week}-{date}")
                    assertThat(daily.resolvedPath(date)).isEqualTo("Daily/${folder.replace("/Week ", "-W")}-$day.md")
                }
            }
        } finally {
            java.util.Locale.setDefault(originalLocale)
        }
        assertThat(ExportSettings.applyDatePlaceholders("{year}/{month}/{day}/{quarter}/{custom}", LocalDate.of(2027, 1, 1)))
            .isEqualTo("2027/01/01/Q1/{custom}")
    }
}
