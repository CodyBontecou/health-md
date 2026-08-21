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
import com.healthmd.domain.exportengine.AndroidDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.ExportArtifactWriteMode
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.exportengine.ProductionDailyAggregateNativePlanBuilder
import com.healthmd.domain.exportengine.ShadowExportDiagnosticSink
import com.healthmd.domain.model.AndroidCaptureContext
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
class DirectGeneratedFilesProducer private constructor(
    private val healthRepository: HealthRepository,
    private val markdownExporter: MarkdownExporter,
    private val jsonExporter: JsonExporter,
    private val csvExporter: CsvExporter,
    private val obsidianBasesExporter: ObsidianBasesExporter,
    private val dailyAggregatePlanner: LocalDailyAggregateExportPlanner,
) {
    @Inject
    constructor(
        healthRepository: HealthRepository,
        markdownExporter: MarkdownExporter,
        jsonExporter: JsonExporter,
        csvExporter: CsvExporter,
        obsidianBasesExporter: ObsidianBasesExporter,
        diagnosticSink: ShadowExportDiagnosticSink = ShadowExportDiagnosticSink { },
    ) : this(
        healthRepository = healthRepository,
        markdownExporter = markdownExporter,
        jsonExporter = jsonExporter,
        csvExporter = csvExporter,
        obsidianBasesExporter = obsidianBasesExporter,
        dailyAggregatePlanner = AndroidDailyAggregateExportPlanner(
            nativePlanner = ProductionDailyAggregateNativePlanBuilder(
                markdownExporter = markdownExporter,
                jsonExporter = jsonExporter,
                csvExporter = csvExporter,
                obsidianBasesExporter = obsidianBasesExporter,
            ),
            diagnosticSink = diagnosticSink,
        ),
    )

    internal constructor(
        healthRepository: HealthRepository,
        markdownExporter: MarkdownExporter,
        jsonExporter: JsonExporter,
        csvExporter: CsvExporter,
        obsidianBasesExporter: ObsidianBasesExporter,
        dailyAggregatePlanner: LocalDailyAggregateExportPlanner,
        @Suppress("UNUSED_PARAMETER") testSeam: Unit = Unit,
    ) : this(
        healthRepository = healthRepository,
        markdownExporter = markdownExporter,
        jsonExporter = jsonExporter,
        csvExporter = csvExporter,
        obsidianBasesExporter = obsidianBasesExporter,
        dailyAggregatePlanner = dailyAggregatePlanner,
    )
    private val dailyNoteInjector = DailyNoteInjector()
    private val individualEntryExporter = IndividualEntryExporter()
    private val markdownMerger = MarkdownMerger()

    suspend fun produce(
        jobDirectory: File,
        dates: List<LocalDate>,
        settings: ExportSettings,
        captureContext: AndroidCaptureContext,
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
                    zoneId = captureContext.zoneId,
                    sleepDayAttributionOverride = captureContext.explicitSleepDayAttributionOverride,
                ).associateBy(HealthData::date)
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                emptyMap()
            }
            chunk.forEach { date ->
                currentCoroutineContext().ensureActive()
                val data = (byDate[date] ?: HealthData(date))
                    .filtered(effectiveSelection)
                    .filtered(settings.metricSelection)
                if (data.hasAnyData) {
                    (plannedAggregateFiles(data, settings) +
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
        when {
            !target.file.isFile || target.file.length() == 0L ->
                writeDurably(target.file, item.bytes, append = false)
            item.writeMode == FileWriteMode.OVERWRITE ->
                writeDurably(target.file, item.bytes, append = false)
            item.writeMode == FileWriteMode.APPEND ->
                writeDurably(target.file, byteArrayOf('\n'.code.toByte()) + item.bytes, append = true)
            else -> {
                val merged = markdownMerger.merge(target.file.readText(), item.content)
                writeDurably(target.file, merged.encodeToByteArray(), append = false)
            }
        }
    }

    private fun writeDurably(file: File, bytes: ByteArray, append: Boolean) {
        java.io.FileOutputStream(file, append).use { stream ->
            stream.write(bytes)
            stream.flush()
            stream.fd.sync()
        }
    }

    private suspend fun plannedAggregateFiles(
        data: HealthData,
        settings: ExportSettings,
    ): List<PlannedContent> = when (val selection = dailyAggregatePlanner.plan(data, settings)) {
        LocalDailyAggregatePlanningResult.Legacy -> aggregateFiles(data, settings)
        is LocalDailyAggregatePlanningResult.Failed ->
            throw IllegalStateException("Pinned generated-file rendering failed before staging.")
        is LocalDailyAggregatePlanningResult.Planned -> selection.plan.items.zip(selection.formats).map { (item, format) ->
            require(item.writeMode == ExportArtifactWriteMode.overwrite) {
                "Pinned generated-file plan has an unsupported write mode."
            }
            PlannedContent(
                relativePath = item.relativePath,
                bytes = item.content,
                format = format.toProtocolFormat(),
                writeMode = FileWriteMode.OVERWRITE,
            )
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
                bytes = content(format, data, settings).encodeToByteArray(),
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
            bytes = requireNotNull(content).encodeToByteArray(),
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
                bytes = content.encodeToByteArray(),
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

    /** Exact immutable UTF-8 content. Rust plan bytes are never replaced by a decoded String. */
    private class PlannedContent(
        val relativePath: String,
        bytes: ByteArray,
        val format: ArtifactFormat,
        val writeMode: FileWriteMode,
    ) {
        private val storedBytes = bytes.copyOf()
        val bytes: ByteArray get() = storedBytes.copyOf()
        val content: String = storedBytes.decodeToString()

        init {
            require(content.encodeToByteArray().contentEquals(storedBytes)) {
                "Generated artifact content is not canonical UTF-8."
            }
        }
    }

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
