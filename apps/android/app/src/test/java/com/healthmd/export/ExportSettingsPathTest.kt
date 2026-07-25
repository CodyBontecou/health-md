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
}
