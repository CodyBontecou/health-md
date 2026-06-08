package com.healthmd.data.export

import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.MarkdownTemplateStyle

enum class InjectionResult {
    UPDATED, CREATED, SKIPPED, FAILED
}

class DailyNoteInjector {

    private val markdownExporter = MarkdownExporter()
    private val markdownMerger = MarkdownMerger()

    fun inject(
        existingContent: String?,
        data: HealthData,
        settings: DailyNoteInjectionSettings,
        customization: FormatCustomization = FormatCustomization(),
    ): Pair<InjectionResult, String?> {
        if (!settings.enabled) return Pair(InjectionResult.SKIPPED, null)

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
            customization.includeAndroidCompatibilityKeys,
        )) {
            val value = field.value ?: continue
            val outputKey = frontmatterConfig.outputKey(field.key) ?: continue
            values[outputKey] = value.toString()
        }

        return values
    }
}
