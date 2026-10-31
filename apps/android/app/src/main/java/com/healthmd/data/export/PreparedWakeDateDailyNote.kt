package com.healthmd.data.export

import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.core.HealthMdCoreService
import com.healthmd.core.HealthMdCoreServiceException
import com.healthmd.core.HealthMdRenderServiceException
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.DailyAggregateExportIds
import com.healthmd.domain.exportengine.DailyAggregateRustPlanner
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import com.healthmd.domain.exportengine.ExportArtifactWriteMode
import com.healthmd.domain.exportengine.FrozenDailyAggregateExportRequest
import com.healthmd.domain.exportengine.HealthMdRustDailyAggregatePlanner
import com.healthmd.domain.exportengine.frozenCopy
import com.healthmd.domain.exportengine.validateRelativePath
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.FrontmatterKeyStyle
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.WriteMode
import com.healthmd.rawexport.ExportMode
import java.time.LocalDate
import java.util.Collections
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/** Immutable projection of an accepted native plan. No destination handle or source reader is retained. */
class PreparedWakeDateDailyNote private constructor(
    val ownerDate: LocalDate,
    val relativePath: String,
    val pin: ExportEnginePin,
    val captureContext: AndroidCaptureContext,
    private val settings: DailyNoteInjectionSettings,
    private val creationPreamble: String,
    internal val patch: String,
    private val core: HealthMdCoreService,
) {
    internal fun inject(existingContent: String?): Pair<InjectionResult, String?> {
        if (existingContent == null && !settings.createIfMissing) return InjectionResult.SKIPPED to null
        return try {
            val content = core.mergeScopedNote(CoreMetricRegistryProfile.ANDROID_SLEEP_V6,
                existingContent ?: creationPreamble, patch, settings.injectMarkdownSections)
            (if (existingContent == null) InjectionResult.CREATED else InjectionResult.UPDATED) to content
        } catch (error: CancellationException) { throw error }
        catch (_: HealthMdRenderServiceException) { InjectionResult.FAILED to null }
        catch (_: HealthMdCoreServiceException) { InjectionResult.FAILED to null }
        catch (_: RuntimeException) { InjectionResult.FAILED to null }
        catch (_: LinkageError) { InjectionResult.FAILED to null }
    }

    override fun toString(): String = "PreparedWakeDateDailyNote(<redacted>)"

    companion object {
        /** Freeze selection, clock, path and presentation before the first renderer suspension. */
        suspend fun prepare(
            data: HealthData,
            settings: ExportSettings,
            ids: DailyAggregateExportIds,
            core: HealthMdCoreService = HealthMdCoreService(),
            planner: DailyAggregateRustPlanner = HealthMdRustDailyAggregatePlanner(coreService = core),
        ): PreparedWakeDateDailyNote {
            require(settings.exportMode == ExportMode.COMPATIBILITY &&
                (!settings.executionEngineAuthorityIsFrozen || settings.executionEnginePin != null)) {
                "scoped operation authority is incompatible"
            }
            val context = requireNotNull(settings.executionSleepCaptureContext).copy()
            require(context.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS &&
                context.exportProfileID == "android-sleep-v6") { "scoped capture authority is incompatible" }
            val injection = settings.dailyNoteInjection.copy(
                enabledMetrics = Collections.unmodifiableSet(settings.dailyNoteInjection.enabledMetrics.toSet()),
            )
            require(injection.enabled) { "scoped capture injection is disabled" }
            val path = injection.resolvedPath(data.date)
            validateRelativePath(path)
            val presentation = settings.formatCustomization.frozenCopy()
            val preamble = "# ${presentation.dateFormat.format(data.date)}\n"
            // These transient formats are projected privately, never emitted as additional files.
            val rendering = settings.copy(
                exportFormats = setOf(ExportFormat.JSON, ExportFormat.MARKDOWN, ExportFormat.OBSIDIAN_BASES),
                includeMetadata = true, groupByCategory = true,
                filenameFormat = "{date}", folderStructure = "", subfolder = "",
                folderOrganization = FolderOrganization.FLAT, writeMode = WriteMode.OVERWRITE,
                includeGranularData = settings.includeGranularData && injection.injectMarkdownSections,
                individualTracking = settings.individualTracking.copy(globalEnabled = false),
                dailyNoteInjection = injection.copy(enabled = false),
                metricSelection = settings.metricSelection.copy(
                    enabledMetrics = Collections.unmodifiableSet(settings.metricSelection.enabledMetrics.toSet())),
                executionSleepCaptureContext = context,
                formatCustomization = presentation.copy(
                    markdownTemplate = presentation.markdownTemplate.copy(style = MarkdownTemplateStyle.STANDARD),
                    frontmatterConfig = presentation.frontmatterConfig.copy(
                    fields = presentation.frontmatterConfig.fields.map { it.copy(isEnabled = true) },
                    customFields = emptyMap(), placeholderFields = emptyList(), keyStyle = FrontmatterKeyStyle.SNAKE_CASE,
                )),
            )
            val request = FrozenDailyAggregateExportRequest.capture(data, rendering,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust, ids.copy())
            val rendered = planner.plan(request)
            require(rendered.pin.engine == ExportEngineMode.rust && rendered.pin.profile == request.profile &&
                rendered.pin.ianaTimeZone == context.zoneId.id && ExportEnginePinCodec.isStructurallyValid(rendered.pin) &&
                (request.suppliedPin == null || request.suppliedPin == rendered.pin) &&
                rendered.plan.profile == request.profile && rendered.plan.requestId == request.ids.requestId &&
                rendered.plan.sessionId == request.ids.sessionId && rendered.plan.items.size == request.formats.size) {
                "scoped renderer authority is incompatible"
            }
            fun text(format: ExportFormat): String {
                val artifact = rendered.plan.items.single { it.relativePath == request.relativePath(format) }
                val media = if (format == ExportFormat.JSON) "application/json" else "text/markdown"
                require(artifact.writeMode == ExportArtifactWriteMode.overwrite && artifact.mediaType.substringBefore(';') == media) {
                    "scoped artifact role is incompatible"
                }
                return artifact.content.decodeToString(throwOnInvalidSequence = true)
            }
            val json = text(ExportFormat.JSON)
            val identity = try { Json { ignoreUnknownKeys = true }.decodeFromString<Identity>(json) }
            catch (_: RuntimeException) { throw IllegalArgumentException("scoped record authority is incompatible") }
            require(identity.date == request.data.date.toString() && identity.profile == "android-sleep-v6" &&
                identity.context["calendar_timezone"] == context.zoneId.id) { "scoped record authority is incompatible" }
            val selected = request.data.filtered(request.metricSelection, context)
            val names = HealthDataFields.extractForWakeDate(selected, request.customization.unitConverter,
                request.customization.timeFormat, request.customization.includeLegacyAndroidAliases,
                request.customization.includeAndroidNativeFields)
                .filter { it.value != null }.map { field ->
                request.customization.frontmatterConfig.fields.firstOrNull { it.originalKey == field.key }
                    ?.outputKey ?: field.key
            }
            val patch = core.prepareScopedNote(CoreMetricRegistryProfile.ANDROID_SLEEP_V6, json,
                text(ExportFormat.OBSIDIAN_BASES), text(ExportFormat.MARKDOWN), names, injection.injectMarkdownSections)
            return PreparedWakeDateDailyNote(request.data.date, path, rendered.pin, context, injection, preamble, patch, core)
        }
    }

    @Serializable
    private data class Identity(
        val date: String,
        @SerialName("schema_profile") val profile: String,
        @SerialName("time_context") val context: Map<String, String>,
    )
}
