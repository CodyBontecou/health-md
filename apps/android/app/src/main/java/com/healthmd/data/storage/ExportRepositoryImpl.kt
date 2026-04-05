package com.healthmd.data.storage

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.SettingsRepository

class ExportRepositoryImpl(
    private val fileExportManager: FileExportManager,
    private val markdownExporter: MarkdownExporter,
    private val jsonExporter: JsonExporter,
    private val csvExporter: CsvExporter,
    private val obsidianBasesExporter: ObsidianBasesExporter,
    private val settingsRepository: SettingsRepository,
) : ExportRepository {

    override suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean {
        val folderUri = settingsRepository.getExportFolderUri() ?: return false

        val content = when (settings.exportFormat) {
            ExportFormat.MARKDOWN -> markdownExporter.export(
                data = data,
                includeMetadata = settings.includeMetadata,
                groupByCategory = settings.groupByCategory,
                customization = settings.formatCustomization,
                includeGranularData = settings.includeGranularData,
            )
            ExportFormat.OBSIDIAN_BASES -> obsidianBasesExporter.export(
                data = data,
                customization = settings.formatCustomization,
            )
            ExportFormat.JSON -> jsonExporter.export(
                data = data,
                customization = settings.formatCustomization,
                includeGranularData = settings.includeGranularData,
            )
            ExportFormat.CSV -> csvExporter.export(
                data = data,
                customization = settings.formatCustomization,
                includeGranularData = settings.includeGranularData,
            )
        }

        val fileName = settings.formatFilename(data.date)
        val subfolder = settings.formatFolderPath(data.date)

        val writeMode = when (settings.writeMode) {
            com.healthmd.domain.model.WriteMode.OVERWRITE -> FileExportManager.WriteMode.OVERWRITE
            com.healthmd.domain.model.WriteMode.APPEND -> FileExportManager.WriteMode.APPEND
            com.healthmd.domain.model.WriteMode.UPDATE -> FileExportManager.WriteMode.UPDATE
        }

        return fileExportManager.writeFile(
            folderUriString = folderUri,
            subfolder = subfolder,
            fileName = fileName,
            extension = settings.exportFormat.fileExtension,
            content = content,
            writeMode = writeMode,
        )
    }

    override suspend fun hasExportFolder(): Boolean =
        settingsRepository.getExportFolderUri() != null

    override fun getExportFolderName(): String? {
        return null
    }
}
