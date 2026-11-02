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
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.data.export.PreparedWakeDateDailyNote
import com.healthmd.domain.exportengine.DailyAggregateExportIds
import com.healthmd.direct.protocol.ScopedDailyNotePolicy
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.forCaptureOperation
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
    val scopedNotePolicy: ScopedDailyNotePolicy? = null,
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
        scopedNoteVersion: Int? = null,
        onProgress: (completed: Int, total: Int) -> Unit = { _, _ -> },
    ): List<ProducedGeneratedFile> {
        require(dates.isNotEmpty())
        require(scopedNoteVersion == null || scopedNoteVersion == 1)
        require(captureContext.sleepDayAttribution != SleepDayAttribution.MORNING_ENDS ||
            !settings.dailyNoteInjection.enabled || scopedNoteVersion == 1) {
            "Update the Health.md CLI before exporting Morning ends daily notes."
        }
        captureContext.requireShippedProfile()
        requireDirectGeneratedFilesAuthority(captureContext, settings.executionEnginePin)
        require(!settings.executionSleepCaptureAuthorityIsFrozen ||
            settings.executionSleepCaptureContext == captureContext) {
            "Direct generated capture authority conflicts with frozen settings."
        }
        val capturedSettings = settings.copy(executionSleepCaptureContext = captureContext,
            executionSleepCaptureAuthorityIsFrozen = true)
        val operationRepository = try {
            healthRepository.forCaptureOperation(capturedSettings)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            throw IllegalStateException("Export source selection is unavailable.")
        }
        val output = File(jobDirectory, "generated").apply {
            check(mkdirs() || isDirectory) { "Unable to create direct generated-file storage." }
        }
        val effectiveSelection = capturedSettings.effectiveDataTypeSelection()
        val staged = linkedMapOf<String, StagedContent>()
        var completed = 0
        val chunkSize = if (capturedSettings.shouldFetchGranularData()) 7 else 30
        dates.chunked(chunkSize).forEach { chunk ->
            currentCoroutineContext().ensureActive()
            val byDate = try {
                operationRepository.fetchHealthDataRange(
                    dates = chunk,
                    dataTypes = effectiveSelection,
                    includeGranularData = capturedSettings.shouldFetchGranularData(),
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
                    .filtered(capturedSettings.metricSelection, captureContext)
                if (data.hasAnyData) {
                    (plannedAggregateFiles(data, capturedSettings) +
                        dailyNote(data, capturedSettings, scopedNoteVersion) +
                        individualEntries(data, capturedSettings))
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
                scopedNotePolicy = item.scopedNotePolicy,
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
                    existing.format == item.format && existing.writeMode == item.writeMode &&
                    existing.scopedNotePolicy == item.scopedNotePolicy,
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
            scopedNotePolicy = item.scopedNotePolicy,
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
    ): List<PlannedContent> = when (val selection = dailyAggregatePlanner.plan(data, settings.copy(
        dailyNoteInjection = settings.dailyNoteInjection.copy(enabled = false),
        individualTracking = settings.individualTracking.copy(globalEnabled = false),
    ))) {
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
                writeMode = settings.writeMode.toProtocolMode(format == ExportFormat.MARKDOWN),
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

    private suspend fun dailyNote(data: HealthData, settings: ExportSettings, scopedNoteVersion: Int?): List<PlannedContent> {
        val injection = settings.dailyNoteInjection
        if (!injection.enabled) return emptyList()
        val context = requireNotNull(settings.executionSleepCaptureContext)
        if (context.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS) {
            require(scopedNoteVersion == 1)
            val prepared = PreparedWakeDateDailyNote.prepare(data, settings,
                DailyAggregateExportIds(UUID.randomUUID().toString(), UUID.randomUUID().toString()))
            return listOf(PlannedContent(prepared.relativePath, prepared.patch.encodeToByteArray(),
                ArtifactFormat.MARKDOWN, FileWriteMode.MERGE_MARKDOWN_PRESERVING_PREAMBLE,
                ScopedDailyNotePolicy(1, requireNotNull(context.exportProfileID), data.date.toString(), context.zoneId.id,
                    injection.createIfMissing, injection.injectMarkdownSections)))
        }
        if (scopedNoteVersion == 1) {
            val profile = if (settings.formatCustomization.compatibilitySchemaProfile == com.healthmd.domain.model.CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5) "android-analytical-v5" else "android-frozen-v4"
            val patch = dailyNoteInjector.prepareScopedNightPatch(data, injection, settings.formatCustomization,
                settings.metricSelection, context, settings.includeGranularData)
            return listOf(PlannedContent(injection.resolvedPath(data.date), patch.encodeToByteArray(),
                ArtifactFormat.MARKDOWN, FileWriteMode.MERGE_MARKDOWN_PRESERVING_PREAMBLE,
                ScopedDailyNotePolicy(1, profile, data.date.toString(), context.zoneId.id,
                    injection.createIfMissing, injection.injectMarkdownSections)))
        }
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
        val scopedNotePolicy: ScopedDailyNotePolicy? = null,
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
        val scopedNotePolicy: ScopedDailyNotePolicy? = null,
    )

    companion object {
        const val MAXIMUM_GENERATED_ARTIFACTS = 4_096
    }
}
