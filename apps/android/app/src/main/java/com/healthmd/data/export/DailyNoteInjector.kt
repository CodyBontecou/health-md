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
        val converter = customization.unitConverter
        val frontmatterValues = buildFrontmatterValues(data, settings.enabledMetrics, dateString, converter)

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
        converter: UnitConverter,
    ): Map<String, String> {
        val values = LinkedHashMap<String, String>()
        values["date"] = dateString

        fun add(metricId: String, key: String, value: Any?) {
            if (value == null || metricId !in enabledMetrics) return
            values[key] = value.toString()
        }

        val s = data.sleep
        add("sleep_total_hours", "sleep_total_hours", s.totalDuration.inWholeMinutes.takeIf { it > 0 }?.let { String.format("%.2f", it / 60.0) })
        add("steps", "steps", data.activity.steps)
        add("active_calories", "active_calories", data.activity.activeCalories?.toInt())
        add("total_calories", "total_calories", data.activity.totalCalories?.toInt())
        add("resting_heart_rate", "resting_heart_rate", data.heart.restingHeartRate?.toInt())
        add("weight_kg", "weight_kg", data.body.weight?.let { String.format("%.1f", converter.convertWeight(it)) })
        add("mindful_minutes", "mindful_minutes", data.mindfulness.mindfulnessMinutes?.toInt())
        add("menstrual_flow", "menstrual_flow", data.reproductiveHealth.menstrualFlow)

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
