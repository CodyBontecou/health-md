package com.healthmd.data.drive

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.DailyNoteInjector
import com.healthmd.data.export.IndividualEntryExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.exportengine.AndroidDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.exportengine.ProductionDailyAggregateNativePlanBuilder
import com.healthmd.domain.exportengine.ShadowExportDiagnosticSink
import com.healthmd.domain.exportengine.sha256Hex
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WriteMode
import java.io.File
import java.time.LocalDate
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.json.Json

/** Materializes existing renderer outputs before any Drive network effect. */
@Singleton
class GeneratedExportBundleFactory private constructor(
    private val markdownExporter: MarkdownExporter,
    private val jsonExporter: JsonExporter,
    private val csvExporter: CsvExporter,
    private val obsidianBasesExporter: ObsidianBasesExporter,
    private val dailyAggregatePlanner: LocalDailyAggregateExportPlanner,
) {
    @Inject
    constructor(
        markdownExporter: MarkdownExporter,
        jsonExporter: JsonExporter,
        csvExporter: CsvExporter,
        obsidianBasesExporter: ObsidianBasesExporter,
        diagnosticSink: ShadowExportDiagnosticSink = ShadowExportDiagnosticSink { },
    ) : this(
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
        markdownExporter: MarkdownExporter,
        jsonExporter: JsonExporter,
        csvExporter: CsvExporter,
        obsidianBasesExporter: ObsidianBasesExporter,
        dailyAggregatePlanner: LocalDailyAggregateExportPlanner,
        @Suppress("UNUSED_PARAMETER") testSeam: Unit = Unit,
    ) : this(
        markdownExporter,
        jsonExporter,
        csvExporter,
        obsidianBasesExporter,
        dailyAggregatePlanner,
    )
    private val json = Json { encodeDefaults = true; explicitNulls = false }
    private val dailyNoteInjector = DailyNoteInjector()
    private val individualEntryExporter = IndividualEntryExporter()

    suspend fun daily(
        operationId: String = UUID.randomUUID().toString(),
        profileId: String?,
        source: String,
        data: List<HealthData>,
        settings: ExportSettings,
        settingsSnapshotJson: String = json.encodeToString(ExportSettings.serializer(), settings.normalized()),
    ): GeneratedExportBundle {
        require(data.isNotEmpty())
        val sorted = data.sortedBy { it.date }
        require(sorted.map { it.date }.distinct().size == sorted.size)
        val artifacts = mutableListOf<GeneratedExportArtifact>()
        val rendererAuthorities = mutableSetOf<String>()
        sorted.forEach { healthData ->
            val aggregate = aggregateArtifacts(operationId, healthData, settings)
            artifacts += aggregate.artifacts
            rendererAuthorities += aggregate.rendererAuthority
            artifacts += dailyNoteArtifact(operationId, healthData, settings)
            artifacts += individualArtifacts(operationId, healthData, settings)
        }
        require(rendererAuthorities.size == 1) { "daily bundle mixed renderer authorities" }
        return GeneratedExportBundle(
            operationId = operationId,
            profileId = profileId,
            source = source,
            dates = sorted.map(HealthData::date),
            settingsSnapshotSha256 = sha256Hex(settingsSnapshotJson.encodeToByteArray()),
            rendererPin = rendererPin(settings, rendererAuthorities.single()),
            artifacts = artifacts,
        )
    }

    fun rawSnapshot(
        operationId: String = UUID.randomUUID().toString(),
        profileId: String?,
        source: String = "raw",
        startDate: LocalDate,
        endDate: LocalDate,
        settingsSnapshotJson: String,
        relativePath: String,
        mediaType: String,
        exactFile: File,
    ): GeneratedExportBundle {
        require(exactFile.isFile && exactFile.length() <= MAX_RAW_BYTES)
        val bytes = exactFile.readBytes()
        val artifact = artifact(
            operationId = operationId,
            path = relativePath,
            mediaType = mediaType,
            intent = GeneratedArtifactWriteIntent.OVERWRITE,
            bytes = bytes,
        )
        return GeneratedExportBundle(
            operationId = operationId,
            profileId = profileId,
            source = source,
            dates = generateSequence(startDate) { it.plusDays(1) }.takeWhile { !it.isAfter(endDate) }.toList(),
            settingsSnapshotSha256 = sha256Hex(settingsSnapshotJson.encodeToByteArray()),
            rendererPin = "android-raw-snapshot-v1",
            artifacts = listOf(artifact),
        )
    }

    private suspend fun aggregateArtifacts(
        operationId: String,
        data: HealthData,
        settings: ExportSettings,
    ): AggregateMaterialization {
        val authoritySettings = settings.copy(exportTarget = com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER)
        return when (val planning = dailyAggregatePlanner.plan(data, authoritySettings)) {
            LocalDailyAggregatePlanningResult.Legacy -> AggregateMaterialization(
                artifacts = legacyAggregateArtifacts(operationId, data, settings),
                rendererAuthority = "legacy",
            )
            is LocalDailyAggregatePlanningResult.Failed ->
                error("${planning.mode.name} aggregate planning failed")
            is LocalDailyAggregatePlanningResult.Planned -> AggregateMaterialization(
                artifacts = planning.plan.items.map { item ->
                    require(sha256Hex(item.content) == item.sha256) { "planner returned invalid bytes" }
                    artifact(
                        operationId = operationId,
                        path = item.relativePath,
                        mediaType = item.mediaType,
                        intent = GeneratedArtifactWriteIntent.OVERWRITE,
                        bytes = item.content,
                    )
                },
                rendererAuthority = planning.mode.name,
            )
        }
    }

    private fun legacyAggregateArtifacts(
        operationId: String,
        data: HealthData,
        settings: ExportSettings,
    ): List<GeneratedExportArtifact> =
        settings.selectedExportFormats.sortedBy(ExportFormat::ordinal).map { format ->
            val text = when (format) {
                ExportFormat.MARKDOWN -> markdownExporter.export(
                    data,
                    settings.includeMetadata,
                    settings.groupByCategory,
                    settings.formatCustomization,
                    settings.includeGranularData,
                )
                ExportFormat.OBSIDIAN_BASES -> obsidianBasesExporter.export(data, settings.formatCustomization)
                ExportFormat.JSON -> jsonExporter.export(data, settings.formatCustomization, settings.includeGranularData)
                ExportFormat.CSV -> csvExporter.export(data, settings.formatCustomization, settings.includeGranularData)
            }
            val intent = when (settings.writeMode) {
                WriteMode.OVERWRITE -> GeneratedArtifactWriteIntent.OVERWRITE
                WriteMode.APPEND -> GeneratedArtifactWriteIntent.APPEND
                WriteMode.UPDATE -> if (format.fileExtension.equals("md", ignoreCase = true)) {
                    GeneratedArtifactWriteIntent.MARKDOWN_UPDATE
                } else {
                    GeneratedArtifactWriteIntent.OVERWRITE
                }
            }
            artifact(
                operationId,
                settings.aggregateRelativePath(data.date, format),
                format.mediaType(),
                intent,
                text.encodeToByteArray(),
            )
        }

    private fun dailyNoteArtifact(
        operationId: String,
        data: HealthData,
        settings: ExportSettings,
    ): List<GeneratedExportArtifact> {
        val injection = settings.dailyNoteInjection
        if (!injection.enabled) return emptyList()
        val fragment = dailyNoteInjector.buildInjectionFragment(data, injection, settings.formatCustomization)
        if (fragment.isBlank()) return emptyList()
        val dateString = settings.formatCustomization.dateFormat.format(data.date)
        return listOf(
            artifact(
                operationId = operationId,
                path = injection.resolvedPath(data.date),
                mediaType = "text/markdown; charset=utf-8",
                intent = GeneratedArtifactWriteIntent.DAILY_NOTE_MERGE,
                bytes = fragment.encodeToByteArray(),
                missingPrefix = "# $dateString\n".encodeToByteArray(),
                createIfMissing = injection.createIfMissing,
            ),
        )
    }

    private fun individualArtifacts(
        operationId: String,
        data: HealthData,
        settings: ExportSettings,
    ): List<GeneratedExportArtifact> {
        if (!settings.individualTracking.globalEnabled) return emptyList()
        val intent = when (settings.writeMode) {
            WriteMode.OVERWRITE -> GeneratedArtifactWriteIntent.OVERWRITE
            WriteMode.APPEND -> GeneratedArtifactWriteIntent.APPEND
            WriteMode.UPDATE -> GeneratedArtifactWriteIntent.MARKDOWN_UPDATE
        }
        return individualEntryExporter.exportEntries(
            data,
            settings.individualTracking,
            settings.formatCustomization,
        ).map { (path, content) ->
            artifact(operationId, path, "text/markdown; charset=utf-8", intent, content.encodeToByteArray())
        }
    }

    private fun artifact(
        operationId: String,
        path: String,
        mediaType: String,
        intent: GeneratedArtifactWriteIntent,
        bytes: ByteArray,
        missingPrefix: ByteArray? = null,
        createIfMissing: Boolean = true,
    ): GeneratedExportArtifact {
        val normalized = normalizeDriveRelativePath(path) ?: error("invalid relative export path")
        val digest = sha256Hex(bytes)
        val id = sha256Hex(
            "healthmd.drive.artifact.v1\u0000$operationId\u0000$normalized\u0000$mediaType\u0000${intent.name}\u0000$digest"
                .encodeToByteArray(),
        )
        return GeneratedExportArtifact(
            artifactId = id,
            relativePath = normalized,
            mediaType = mediaType,
            writeIntent = intent,
            bytes = bytes,
            missingRemotePrefix = missingPrefix,
            createIfMissing = createIfMissing,
        )
    }

    private fun ExportFormat.mediaType(): String = when (this) {
        ExportFormat.MARKDOWN, ExportFormat.OBSIDIAN_BASES -> "text/markdown; charset=utf-8"
        ExportFormat.JSON -> "application/json"
        ExportFormat.CSV -> "text/csv; charset=utf-8"
    }

    private fun rendererPin(settings: ExportSettings, authority: String): String = buildString {
        append(
            when (settings.formatCustomization.compatibilitySchemaProfile) {
                com.healthmd.domain.model.CompatibilitySchemaProfile.IOS_V4_FROZEN -> "android-frozen-v4"
                com.healthmd.domain.model.CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> "android-analytical-v5"
            },
        )
        append(':').append(authority)
    }

    private data class AggregateMaterialization(
        val artifacts: List<GeneratedExportArtifact>,
        val rendererAuthority: String,
    )

    companion object { private const val MAX_RAW_BYTES = 256L * 1024 * 1024 }
}
