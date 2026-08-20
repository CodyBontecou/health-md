package com.healthmd.data.drive

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.DailyNoteInjector
import com.healthmd.data.export.IndividualEntryExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
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
class GeneratedExportBundleFactory @Inject constructor(
    private val markdownExporter: MarkdownExporter,
    private val jsonExporter: JsonExporter,
    private val csvExporter: CsvExporter,
    private val obsidianBasesExporter: ObsidianBasesExporter,
) {
    private val json = Json { encodeDefaults = true; explicitNulls = false }
    private val dailyNoteInjector = DailyNoteInjector()
    private val individualEntryExporter = IndividualEntryExporter()

    fun daily(
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
        val artifacts = sorted.flatMap { healthData ->
            aggregateArtifacts(operationId, healthData, settings) +
                dailyNoteArtifact(operationId, healthData, settings).orEmpty() +
                individualArtifacts(operationId, healthData, settings)
        }
        return GeneratedExportBundle(
            operationId = operationId,
            profileId = profileId,
            source = source,
            dates = sorted.map(HealthData::date),
            settingsSnapshotSha256 = sha256Hex(settingsSnapshotJson.encodeToByteArray()),
            rendererPin = rendererPin(settings),
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

    private fun aggregateArtifacts(
        operationId: String,
        data: HealthData,
        settings: ExportSettings,
    ): List<GeneratedExportArtifact> = settings.selectedExportFormats.sortedBy(ExportFormat::ordinal).map { format ->
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

    private fun rendererPin(settings: ExportSettings): String = buildString {
        append(
            when (settings.formatCustomization.compatibilitySchemaProfile) {
                com.healthmd.domain.model.CompatibilitySchemaProfile.IOS_V4_FROZEN -> "android-frozen-v4"
                com.healthmd.domain.model.CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> "android-analytical-v5"
            },
        )
        settings.executionEnginePin?.let { append(':').append(it.engine.name) }
    }

    companion object { private const val MAX_RAW_BYTES = 256L * 1024 * 1024 }
}
