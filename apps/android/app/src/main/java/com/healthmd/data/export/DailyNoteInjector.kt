package com.healthmd.data.export

import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.DateFormatPreference
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.core.HealthMdCoreService
import com.healthmd.core.HealthMdCoreServiceException
import com.healthmd.core.HealthMdRenderServiceException
import kotlinx.coroutines.CancellationException

enum class InjectionResult {
    UPDATED, CREATED, SKIPPED, FAILED
}

class DailyNoteInjector {

    fun injectPrepared(existingContent: String?, prepared: PreparedWakeDateDailyNote): Pair<InjectionResult, String?> =
        prepared.inject(existingContent)

    private val markdownExporter = MarkdownExporter()
    private val markdownMerger = MarkdownMerger()

    fun inject(
        existingContent: String?,
        data: HealthData,
        settings: DailyNoteInjectionSettings,
        customization: FormatCustomization = FormatCustomization(),
        metricSelection: MetricSelectionState? = null,
        captureContext: AndroidCaptureContext? = null,
        includeGranularData: Boolean = false,
    ): Pair<InjectionResult, String?> {
        if (!settings.enabled) return Pair(InjectionResult.SKIPPED, null)
        if (existingContent != null && hasScopedCapture(existingContent)) {
            return injectScopedNight(existingContent, data, settings, customization, metricSelection,
                captureContext, includeGranularData)
        }

        val dateString = customization.dateFormat.format(data.date)
        val injectionContent = buildInjectionContent(data, dateString, settings, customization)
        if (injectionContent.isBlank()) return Pair(InjectionResult.SKIPPED, null)

        if (existingContent == null && !settings.createIfMissing) {
            return Pair(InjectionResult.SKIPPED, null)
        }

        val baseContent = existingContent ?: "# $dateString\n"
        val mergedContent = markdownMerger.merge(baseContent, injectionContent)
        return Pair(if (existingContent == null) InjectionResult.CREATED else InjectionResult.UPDATED, mergedContent)
    }

    private fun scopedHeader(content: String): List<String> {
        val lines = content.lineSequence().iterator()
        if (!lines.hasNext() || lines.next() != "---") return emptyList()
        val header = mutableListOf<String>()
        while (lines.hasNext()) {
            val line = lines.next()
            if (line == "---") return header
            header += line
        }
        return emptyList()
    }

    private fun captureKey(line: String): String? {
        if (line.isEmpty() || line.first().isWhitespace()) return null
        return line.substringBefore(':').trim().removeSurrounding("\"").removeSurrounding("'")
            .takeIf { it in setOf("healthmd_injection_kind","healthmd_daily_injection_v1","healthmd_daily_injection_v2") }
    }

    internal fun hasScopedCapture(content: String): Boolean = scopedHeader(content).any { captureKey(it) != null }

    private fun injectScopedNight(
        existing: String, data: HealthData, settings: DailyNoteInjectionSettings,
        customization: FormatCustomization, selection: MetricSelectionState?,
        context: AndroidCaptureContext?, includeGranularData: Boolean,
    ): Pair<InjectionResult,String?> = try {
        require(context?.sleepDayAttribution == SleepDayAttribution.NIGHT_BEGINS)
        val kinds = scopedHeader(existing).filter { captureKey(it) == "healthmd_injection_kind" }
        require(kinds.size == 1 && kinds.single().substringAfter(':').trim().removeSurrounding("\"")
            .removeSurrounding("'") in setOf("daily_capture_v1","daily_capture_v2"))
        val profile = if (customization.compatibilitySchemaProfile == CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5)
            CoreMetricRegistryProfile.ANDROID_ANALYTICAL_V5 else CoreMetricRegistryProfile.ANDROID_FROZEN_V4
        require(context.exportProfileID == null || context.exportProfileID ==
            if (profile == CoreMetricRegistryProfile.ANDROID_ANALYTICAL_V5) "android-analytical-v5" else "android-frozen-v4")
        val selected = if (selection == null) data else data.filtered(selection, context)
        val rendering = customization.copy(dateFormat = DateFormatPreference.ISO8601,
            markdownTemplate = customization.markdownTemplate.copy(style = MarkdownTemplateStyle.STANDARD),
            frontmatterConfig = customization.frontmatterConfig.copy(
                fields = customization.frontmatterConfig.fields.map { it.copy(isEnabled=true) },
                customFields=emptyMap(),placeholderFields=emptyList()))
        val names = HealthDataFields.extract(selected, rendering.unitConverter, rendering.timeFormat,
            rendering.includeLegacyAndroidAliases, rendering.includeAndroidNativeFields)
            .filter { it.value != null }.mapNotNull { rendering.frontmatterConfig.outputKey(it.key) }
        val record = JsonExporter().export(selected,rendering,includeGranularData && settings.injectMarkdownSections)
        val markdown = if(settings.injectMarkdownSections) markdownExporter.export(selected,false,true,rendering,
            includeGranularData) else ""
        val core = HealthMdCoreService()
        val patch = core.prepareScopedAndroidNightNote(profile,record,context.zoneId.id,
            ObsidianBasesExporter().export(selected,rendering),markdown,names,settings.injectMarkdownSections)
        InjectionResult.UPDATED to core.mergeScopedNote(profile,existing,patch,settings.injectMarkdownSections)
    } catch (error: CancellationException) { throw error }
    catch (_: HealthMdRenderServiceException) { InjectionResult.FAILED to null }
    catch (_: HealthMdCoreServiceException) { InjectionResult.FAILED to null }
    catch (_: RuntimeException) { InjectionResult.FAILED to null }
    catch (_: LinkageError) { InjectionResult.FAILED to null }

    private fun buildInjectionContent(
        data: HealthData,
        dateString: String,
        settings: DailyNoteInjectionSettings,
        customization: FormatCustomization,
    ): String = buildString {
        val frontmatterValues = buildFrontmatterValues(data, dateString, customization)
        if (frontmatterValues.isNotEmpty()) {
            append("---\n")
            for ((key, value) in frontmatterValues) {
                append("$key: $value\n")
            }
            append("---\n\n")
        }

        if (settings.injectMarkdownSections) {
            val sectionCustomization = customization.copy(
                markdownTemplate = customization.markdownTemplate.copy(
                    style = MarkdownTemplateStyle.STANDARD,
                ),
            )
            append(
                markdownExporter.export(
                    data = data,
                    includeMetadata = false,
                    groupByCategory = true,
                    customization = sectionCustomization,
                    includeGranularData = false,
                ).trimEnd(),
            )
            append("\n")
        }
    }

    private fun buildFrontmatterValues(
        data: HealthData,
        dateString: String,
        customization: FormatCustomization,
    ): Map<String, String> {
        val values = LinkedHashMap<String, String>()
        val frontmatterConfig = customization.frontmatterConfig
        if (frontmatterConfig.includeDate) {
            values[frontmatterConfig.customDateKey] = dateString
        }

        for (field in HealthDataFields.extract(
            data,
            customization.unitConverter,
            customization.timeFormat,
            customization.includeLegacyAndroidAliases,
            customization.includeAndroidNativeFields,
        )) {
            val value = field.value ?: continue
            val outputKey = frontmatterConfig.outputKey(field.key) ?: continue
            values[outputKey] = value.toString()
        }

        return values
    }
}
