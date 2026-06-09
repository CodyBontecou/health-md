package com.healthmd.data.storage

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.DailyNoteInjector
import com.healthmd.data.export.IndividualEntryExporter
import com.healthmd.data.export.InjectionResult
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.MarkdownMerger
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportPreviewDay
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.model.ExportPreviewSideEffect
import com.healthmd.domain.model.ExportPreviewSideEffectType
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WriteMode as SettingsWriteMode
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

    private val dailyNoteInjector = DailyNoteInjector()
    private val individualEntryExporter = IndividualEntryExporter()
    private val markdownMerger = MarkdownMerger()

    override suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean {
        val folderUri = settingsRepository.getExportFolderUri() ?: return false
        if (settings.selectedExportFormats.isEmpty()) return false

        val writeMode = settings.writeMode.toFileWriteMode()
        val aggregateFiles = buildAggregateFiles(data, settings)
        if (aggregateFiles.isEmpty()) return false

        val aggregateSuccess = aggregateFiles.all { planned ->
            fileExportManager.writeFile(
                folderUriString = folderUri,
                subfolder = planned.subfolder,
                fileName = planned.fileName,
                extension = planned.extension,
                content = planned.content,
                writeMode = writeMode,
            )
        }

        val sideEffectSuccess = buildSideEffects(folderUri, data, settings).all { planned ->
            if (!planned.wouldWrite) {
                true
            } else {
                fileExportManager.writeFileAtRelativePath(
                    folderUriString = folderUri,
                    relativePath = planned.relativePath,
                    content = planned.content.orEmpty(),
                    writeMode = writeMode,
                )
            }
        }

        return aggregateSuccess && sideEffectSuccess
    }

    override suspend fun previewHealthData(data: HealthData, settings: ExportSettings): ExportPreviewDay {
        val folderUri = settingsRepository.getExportFolderUri()
            ?: return ExportPreviewDay(date = data.date, failureReason = ExportFailureReason.NO_FOLDER_SELECTED)

        if (settings.selectedExportFormats.isEmpty()) {
            return ExportPreviewDay(date = data.date, warning = "No export formats selected")
        }

        val files = buildAggregateFiles(data, settings).map { planned ->
            val previewContent = contentAfterWriteMode(
                folderUri = folderUri,
                relativePath = planned.relativePath,
                extension = planned.extension,
                newContent = planned.content,
                settings = settings,
            )
            ExportPreviewFile(
                format = planned.format,
                relativePath = planned.relativePath,
                byteCount = previewContent.toByteArray(Charsets.UTF_8).size,
                content = previewContent,
            )
        }

        val sideEffects = buildSideEffects(folderUri, data, settings).map { planned ->
            val previewContent = planned.content?.let { content ->
                if (planned.wouldWrite) {
                    contentAfterWriteMode(
                        folderUri = folderUri,
                        relativePath = planned.relativePath,
                        extension = extensionForRelativePath(planned.relativePath),
                        newContent = content,
                        settings = settings,
                    )
                } else {
                    content
                }
            }
            ExportPreviewSideEffect(
                type = planned.type,
                relativePath = planned.relativePath,
                action = planned.action,
                byteCount = previewContent?.toByteArray(Charsets.UTF_8)?.size ?: 0,
                content = previewContent,
                wouldWrite = planned.wouldWrite,
            )
        }

        return ExportPreviewDay(
            date = data.date,
            files = files,
            sideEffects = sideEffects,
            warning = if (files.isEmpty() && sideEffects.none { it.wouldWrite }) "No files would be written" else null,
        )
    }

    override suspend fun hasExportFolder(): Boolean =
        settingsRepository.getExportFolderUri() != null

    override fun getExportFolderName(): String? {
        return null
    }

    private fun buildAggregateFiles(data: HealthData, settings: ExportSettings): List<PlannedAggregateFile> {
        val selectedFormats = settings.selectedExportFormats.sortedBy { it.ordinal }
        if (selectedFormats.isEmpty()) return emptyList()

        val subfolder = settings.aggregateSubfolderPath(data.date)
        val baseName = settings.formatFilename(data.date)

        return selectedFormats.map { format ->
            val fileName = when {
                format == ExportFormat.OBSIDIAN_BASES && ExportFormat.MARKDOWN in selectedFormats -> "${baseName}-bases"
                else -> baseName
            }
            val extension = format.fileExtension
            val content = contentForFormat(format, data, settings)
            PlannedAggregateFile(
                format = format,
                subfolder = subfolder,
                fileName = fileName,
                extension = extension,
                relativePath = relativePath(subfolder, "$fileName.$extension"),
                content = content,
            )
        }
    }

    private fun contentForFormat(format: ExportFormat, data: HealthData, settings: ExportSettings): String = when (format) {
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

    private fun buildSideEffects(
        folderUri: String,
        data: HealthData,
        settings: ExportSettings,
    ): List<PlannedSideEffect> = buildList {
        dailyNoteSideEffect(folderUri, data, settings)?.let { add(it) }
        addAll(individualEntrySideEffects(data, settings))
    }

    private fun dailyNoteSideEffect(
        folderUri: String,
        data: HealthData,
        settings: ExportSettings,
    ): PlannedSideEffect? {
        val injectionSettings = settings.dailyNoteInjection
        if (!injectionSettings.enabled) return null

        val relativePath = injectionSettings.resolvedPath(data.date)
        val existing = fileExportManager.readFileAtRelativePath(folderUri, relativePath)
        val (result, content) = dailyNoteInjector.inject(
            existingContent = existing,
            data = data,
            settings = injectionSettings,
            customization = settings.formatCustomization,
        )

        return PlannedSideEffect(
            type = ExportPreviewSideEffectType.DAILY_NOTE,
            relativePath = relativePath,
            action = when (result) {
                InjectionResult.UPDATED -> "Update daily note"
                InjectionResult.CREATED -> "Create daily note"
                InjectionResult.SKIPPED -> "Skip daily note"
                InjectionResult.FAILED -> "Daily note failed"
            },
            content = content,
            wouldWrite = result == InjectionResult.UPDATED || result == InjectionResult.CREATED,
        )
    }

    private fun individualEntrySideEffects(
        data: HealthData,
        settings: ExportSettings,
    ): List<PlannedSideEffect> {
        val trackingSettings = settings.individualTracking
        if (!trackingSettings.globalEnabled) return emptyList()

        return individualEntryExporter.exportEntries(
            data = data,
            settings = trackingSettings,
            customization = settings.formatCustomization,
        ).map { (entryPath, content) ->
            PlannedSideEffect(
                type = ExportPreviewSideEffectType.INDIVIDUAL_ENTRY,
                relativePath = entryPath,
                action = "Write individual entry",
                content = content,
                wouldWrite = true,
            )
        }
    }

    private fun relativePath(subfolder: String?, fileName: String): String =
        listOfNotNull(subfolder?.trim('/').takeUnless { it.isNullOrBlank() }, fileName)
            .joinToString("/")

    private fun contentAfterWriteMode(
        folderUri: String,
        relativePath: String,
        extension: String,
        newContent: String,
        settings: ExportSettings,
    ): String {
        val existing = when (settings.writeMode) {
            SettingsWriteMode.OVERWRITE -> null
            SettingsWriteMode.APPEND,
            SettingsWriteMode.UPDATE -> fileExportManager.readFileAtRelativePath(folderUri, relativePath)
        }
        val existingFileExists = existing != null ||
            (settings.writeMode == SettingsWriteMode.APPEND && fileExportManager.fileExistsAtRelativePath(folderUri, relativePath))

        return when {
            settings.writeMode == SettingsWriteMode.APPEND && existing != null -> existing + "\n" + newContent
            settings.writeMode == SettingsWriteMode.APPEND && existingFileExists -> "\n" + newContent
            existing != null && settings.writeMode == SettingsWriteMode.UPDATE && extension.equals("md", ignoreCase = true) ->
                markdownMerger.merge(existing, newContent)
            else -> newContent
        }
    }

    private fun extensionForRelativePath(relativePath: String): String =
        relativePath.substringAfterLast('/').substringAfterLast('.', missingDelimiterValue = "txt")

    private fun SettingsWriteMode.toFileWriteMode(): FileExportManager.WriteMode = when (this) {
        SettingsWriteMode.OVERWRITE -> FileExportManager.WriteMode.OVERWRITE
        SettingsWriteMode.APPEND -> FileExportManager.WriteMode.APPEND
        SettingsWriteMode.UPDATE -> FileExportManager.WriteMode.UPDATE
    }

    private data class PlannedAggregateFile(
        val format: ExportFormat,
        val subfolder: String?,
        val fileName: String,
        val extension: String,
        val relativePath: String,
        val content: String,
    )

    private data class PlannedSideEffect(
        val type: ExportPreviewSideEffectType,
        val relativePath: String,
        val action: String,
        val content: String?,
        val wouldWrite: Boolean,
    )
}
