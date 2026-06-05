package com.healthmd.data.export

import com.healthmd.domain.model.*

enum class InjectionResult {
    UPDATED, CREATED, SKIPPED, FAILED
}

class DailyNoteInjector {

    fun inject(
        existingContent: String?,
        data: HealthData,
        settings: DailyNoteInjectionSettings,
        customization: FormatCustomization = FormatCustomization(),
    ): Pair<InjectionResult, String?> {
        if (!settings.enabled) return Pair(InjectionResult.SKIPPED, null)

        val dateString = customization.dateFormat.format(data.date)
        val frontmatterValues = buildFrontmatterValues(data, settings.enabledMetrics, dateString, customization)

        if (existingContent == null) {
            if (!settings.createIfMissing) return Pair(InjectionResult.SKIPPED, null)
            // Create new note with frontmatter
            val content = buildString {
                append("---\n")
                for ((key, value) in frontmatterValues) {
                    append("$key: $value\n")
                }
                append("---\n\n")
                append("# ${customization.dateFormat.format(data.date)}\n")
            }
            return Pair(InjectionResult.CREATED, content)
        }

        // Merge into existing note's frontmatter
        val mergedContent = mergeIntoFrontmatter(existingContent, frontmatterValues)
        return Pair(InjectionResult.UPDATED, mergedContent)
    }

    private fun buildFrontmatterValues(
        data: HealthData,
        enabledMetrics: Set<String>,
        dateString: String,
        customization: FormatCustomization,
    ): Map<String, String> {
        val values = LinkedHashMap<String, String>()
        val frontmatterConfig = customization.frontmatterConfig
        if (frontmatterConfig.includeDate) {
            values[frontmatterConfig.customDateKey] = dateString
        }

        for (field in HealthDataFields.extract(data, customization.unitConverter, customization.timeFormat)) {
            val value = field.value ?: continue
            if (field.key !in enabledMetrics) continue
            val outputKey = frontmatterConfig.outputKey(field.key) ?: continue
            values[outputKey] = value.toString()
        }

        return values
    }

    private fun mergeIntoFrontmatter(content: String, newValues: Map<String, String>): String {
        val hasFrontmatter = content.startsWith("---")

        if (!hasFrontmatter) {
            return buildString {
                append("---\n")
                for ((key, value) in newValues) {
                    append("$key: $value\n")
                }
                append("---\n\n")
                append(content)
            }
        }

        val endIndex = content.indexOf("---", 3)
        if (endIndex == -1) return content

        val existingFm = content.substring(4, endIndex).trim()
        val body = content.substring(endIndex + 3)

        // Parse existing frontmatter
        val fmMap = LinkedHashMap<String, String>()
        for (line in existingFm.lines()) {
            val trimmed = line.trim()
            if (trimmed.isEmpty()) continue
            val colonIdx = trimmed.indexOf(':')
            if (colonIdx > 0) {
                fmMap[trimmed.substring(0, colonIdx).trim()] = trimmed.substring(colonIdx + 1).trim()
            }
        }

        // Merge new values (overwrite health values, preserve custom values)
        fmMap.putAll(newValues)

        return buildString {
            append("---\n")
            for ((key, value) in fmMap) {
                append("$key: $value\n")
            }
            append("---")
            append(body)
        }
    }
}
