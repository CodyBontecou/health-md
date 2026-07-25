package com.healthmd.direct

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.DailyNoteInjector
import com.healthmd.data.export.IndividualEntryExporter
import com.healthmd.data.export.InjectionResult
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.MarkdownMerger
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.direct.protocol.ArtifactFormat
import com.healthmd.direct.protocol.FileWriteMode
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.repository.HealthRepository
import java.io.File
import java.time.LocalDate
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive

class DirectGeneratedArtifactLimitException : Exception(
    "Direct CLI generated export exceeds the 4,096-file transfer limit.",
)

data class ProducedGeneratedFile(
    val artifactId: String,
    val relativePath: String,
    val file: File,
    val format: ArtifactFormat,
    val writeMode: FileWriteMode,
)

@Singleton
class DirectGeneratedFilesProducer @Inject constructor(
    private val healthRepository: HealthRepository,
    private val markdownExporter: MarkdownExporter,
    private val jsonExporter: JsonExporter,
    private val csvExporter: CsvExporter,
    private val obsidianBasesExporter: ObsidianBasesExporter,
) {
    private val dailyNoteInjector = DailyNoteInjector()
    private val individualEntryExporter = IndividualEntryExporter()
    private val markdownMerger = MarkdownMerger()

    suspend fun produce(
        jobDirectory: File,
        dates: List<LocalDate>,
        settings: ExportSettings,
        onProgress: (completed: Int, total: Int) -> Unit = { _, _ -> },
    ): List<ProducedGeneratedFile> {
        require(dates.isNotEmpty())
        val output = File(jobDirectory, "generated").apply {
            check(mkdirs() || isDirectory) { "Unable to create direct generated-file storage." }
        }
        val effectiveSelection = settings.effectiveDataTypeSelection()
        val staged = linkedMapOf<String, StagedContent>()
        var completed = 0
        val chunkSize = if (settings.shouldFetchGranularData()) 7 else 30
        dates.chunked(chunkSize).forEach { chunk ->
            currentCoroutineContext().ensureActive()
            val byDate = try {
                healthRepository.fetchHealthDataRange(
                    dates = chunk,
                    dataTypes = effectiveSelection,
                    includeGranularData = settings.shouldFetchGranularData(),
                ).associateBy(HealthData::date)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                emptyMap()
            }
            chunk.forEach { date ->
                currentCoroutineContext().ensureActive()
                var data = (byDate[date] ?: HealthData(date))
                    .filtered(effectiveSelection)
                    .filtered(settings.metricSelection)
                if (!data.hasAnyData) {
                    data = healthRepository.fetchHealthData(date)
                        .filtered(effectiveSelection)
                        .filtered(settings.metricSelection)
                }
                if (data.hasAnyData) {
                    (aggregateFiles(data, settings) +
                        dailyNote(data, settings) +
                        individualEntries(data, settings))
                        .forEach { stage(it, staged, output) }
                }
                completed += 1
                onProgress(completed, dates.size)
            }
        }
        require(staged.isNotEmpty()) { "No health data was available for the requested dates." }
        return staged.values.map { item ->
            ProducedGeneratedFile(
                artifactId = item.artifactId,
                relativePath = item.relativePath,
                file = item.file,
                format = item.format,
                writeMode = item.writeMode,
            )
        }
    }

    private fun stage(
        item: PlannedContent,
        staged: MutableMap<String, StagedContent>,
        output: File,
    ) {
        require(isSafeRelativePath(item.relativePath)) { "Generated file path is unsafe." }
        val key = item.relativePath.lowercase()
        val existing = staged[key]
        if (existing != null) {
            require(
                existing.relativePath.equals(item.relativePath, ignoreCase = true) &&
                    existing.format == item.format && existing.writeMode == item.writeMode,
            ) { "Generated files contain incompatible destination collisions." }
        }
        if (existing == null && staged.size >= MAXIMUM_GENERATED_ARTIFACTS) {
            throw DirectGeneratedArtifactLimitException()
        }
        val target = existing ?: StagedContent(
            artifactId = UUID.randomUUID().toString(),
            relativePath = item.relativePath,
            file = File(output, "${UUID.randomUUID()}.bin"),
            format = item.format,
            writeMode = item.writeMode,
        ).also { staged[key] = it }
        val content = when {
            !target.file.isFile || target.file.length() == 0L -> item.content
            item.writeMode == FileWriteMode.OVERWRITE -> item.content
            item.writeMode == FileWriteMode.APPEND -> null
            else -> markdownMerger.merge(target.file.readText(), item.content)
        }
        if (content != null) {
            writeDurably(target.file, content.toByteArray(Charsets.UTF_8), append = false)
        } else {
            writeDurably(target.file, "\n${item.content}".toByteArray(Charsets.UTF_8), append = true)
        }
    }

    private fun writeDurably(file: File, bytes: ByteArray, append: Boolean) {
        java.io.FileOutputStream(file, append).use { stream ->
            stream.write(bytes)
            stream.flush()
            stream.fd.sync()
        }
    }

    private fun aggregateFiles(data: HealthData, settings: ExportSettings): List<PlannedContent> {
        val formats = settings.selectedExportFormats.sortedBy(ExportFormat::ordinal)
        val subfolder = settings.aggregateSubfolderPath(data.date)
        val baseName = settings.formatFilename(data.date)
        return formats.map { format ->
            val fileName = if (format == ExportFormat.OBSIDIAN_BASES && ExportFormat.MARKDOWN in formats) {
                "$baseName-bases"
            } else {
                baseName
            }
            PlannedContent(
                relativePath = relativePath(subfolder, "$fileName.${format.fileExtension}"),
                content = content(format, data, settings),
                format = format.toProtocolFormat(),
                writeMode = settings.writeMode.toProtocolMode(format == ExportFormat.MARKDOWN),
            )
        }
    }

    private fun dailyNote(data: HealthData, settings: ExportSettings): List<PlannedContent> {
        val injection = settings.dailyNoteInjection
        if (!injection.enabled) return emptyList()
        val (result, content) = dailyNoteInjector.inject(
            existingContent = null,
            data = data,
            settings = injection,
            customization = settings.formatCustomization,
        )
        if (result != InjectionResult.CREATED && result != InjectionResult.UPDATED) return emptyList()
        return listOf(PlannedContent(
            relativePath = injection.resolvedPath(data.date),
            content = requireNotNull(content),
            format = ArtifactFormat.MARKDOWN,
            writeMode = FileWriteMode.MERGE_MARKDOWN_PRESERVING_PREAMBLE,
        ))
    }

    private fun individualEntries(data: HealthData, settings: ExportSettings): List<PlannedContent> {
        if (!settings.individualTracking.globalEnabled) return emptyList()
        return individualEntryExporter.exportEntries(
            data = data,
            settings = settings.individualTracking,
            customization = settings.formatCustomization,
        ).map { (path, content) ->
            PlannedContent(
                relativePath = path,
                content = content,
                format = ArtifactFormat.MARKDOWN,
                writeMode = settings.writeMode.toProtocolMode(markdown = true),
            )
        }
    }

    private fun content(
        format: ExportFormat,
        data: HealthData,
        settings: ExportSettings,
    ): String = when (format) {
        ExportFormat.MARKDOWN -> markdownExporter.export(
            data = data,
            includeMetadata = settings.includeMetadata,
            groupByCategory = settings.groupByCategory,
            customization = settings.formatCustomization,
            includeGranularData = settings.includeGranularData,
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
        ExportFormat.OBSIDIAN_BASES -> obsidianBasesExporter.export(
            data = data,
            customization = settings.formatCustomization,
        )
    }

    private fun relativePath(subfolder: String?, fileName: String): String =
        listOfNotNull(subfolder?.trim('/')?.takeIf(String::isNotBlank), fileName).joinToString("/")

    private fun isSafeRelativePath(path: String): Boolean =
        path.isNotBlank() && path.length <= 4096 && !path.startsWith('/') && !path.contains('\\') &&
            path.split('/').all { it.isNotBlank() && it != "." && it != ".." && '\u0000' !in it }

    private fun ExportFormat.toProtocolFormat(): ArtifactFormat = when (this) {
        ExportFormat.MARKDOWN -> ArtifactFormat.MARKDOWN
        ExportFormat.JSON -> ArtifactFormat.JSON
        ExportFormat.CSV -> ArtifactFormat.CSV
        ExportFormat.OBSIDIAN_BASES -> ArtifactFormat.OBSIDIAN_BASES
    }

    private fun WriteMode.toProtocolMode(markdown: Boolean): FileWriteMode = when (this) {
        WriteMode.OVERWRITE -> FileWriteMode.OVERWRITE
        WriteMode.APPEND -> FileWriteMode.APPEND
        WriteMode.UPDATE -> if (markdown) FileWriteMode.MERGE_MARKDOWN else FileWriteMode.OVERWRITE
    }

    private data class PlannedContent(
        val relativePath: String,
        val content: String,
        val format: ArtifactFormat,
        val writeMode: FileWriteMode,
    )

    private data class StagedContent(
        val artifactId: String,
        val relativePath: String,
        val file: File,
        val format: ArtifactFormat,
        val writeMode: FileWriteMode,
    )

    companion object {
        const val MAXIMUM_GENERATED_ARTIFACTS = 4_096
    }
}
