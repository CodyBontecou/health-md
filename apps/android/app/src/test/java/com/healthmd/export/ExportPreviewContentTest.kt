package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.MarkdownMerger
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.data.storage.ExportRepositoryImpl
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test

class ExportPreviewContentTest {

    private val folderUri = "content://exports"

    @Test
    fun previewHealthData_appendModeShowsFinalAppendedAggregateFileContent() = runTest {
        val existing = "existing export content"
        val fileExportManager = mockFileExportManager(
            existingByPath = mapOf("health/2026-03-15.json" to existing),
        )
        val repository = repository(fileExportManager)

        val preview = repository.previewHealthData(
            data = ExportFixtures.fullDay,
            settings = ExportSettings(
                exportFormat = ExportFormat.JSON,
                exportFormats = setOf(ExportFormat.JSON),
                writeMode = WriteMode.APPEND,
            ),
        )

        val file = preview.files.single()
        assertThat(file.relativePath).isEqualTo("health/2026-03-15.json")
        assertThat(file.content).startsWith("$existing\n")
        assertThat(file.byteCount).isEqualTo(file.content.toByteArray(Charsets.UTF_8).size)
    }

    @Test
    fun previewHealthData_updateModeShowsMergedMarkdownAggregateFileContent() = runTest {
        val existing = """
            ---
            date: 2026-03-15
            custom: keep-me
            ---

            User-authored note.

            ## Activity
            - Steps: 1
        """.trimIndent()
        val fileExportManager = mockFileExportManager(
            existingByPath = mapOf("health/2026-03-15.md" to existing),
        )
        val repository = repository(fileExportManager)
        val settings = ExportSettings(
            exportFormat = ExportFormat.MARKDOWN,
            exportFormats = setOf(ExportFormat.MARKDOWN),
            writeMode = WriteMode.UPDATE,
        )
        val generated = MarkdownExporter().export(
            data = ExportFixtures.fullDay,
            includeMetadata = settings.includeMetadata,
            groupByCategory = settings.groupByCategory,
            customization = settings.formatCustomization,
            includeGranularData = settings.includeGranularData,
        )

        val preview = repository.previewHealthData(ExportFixtures.fullDay, settings)

        assertThat(preview.files.single().content)
            .isEqualTo(MarkdownMerger().merge(existing, generated))
    }

    private fun repository(fileExportManager: FileExportManager): ExportRepositoryImpl {
        val settingsRepository = mockk<SettingsRepository>()
        coEvery { settingsRepository.getExportFolderUri() } returns folderUri
        return ExportRepositoryImpl(
            fileExportManager = fileExportManager,
            markdownExporter = MarkdownExporter(),
            jsonExporter = JsonExporter(),
            csvExporter = CsvExporter(),
            obsidianBasesExporter = ObsidianBasesExporter(),
            settingsRepository = settingsRepository,
        )
    }

    private fun mockFileExportManager(existingByPath: Map<String, String>): FileExportManager {
        val fileExportManager = mockk<FileExportManager>(relaxed = true)
        every { fileExportManager.readFileAtRelativePath(any(), any()) } answers {
            val requestedFolder = firstArg<String>()
            val requestedPath = secondArg<String>()
            if (requestedFolder == folderUri) existingByPath[requestedPath] else null
        }
        return fileExportManager
    }
}
