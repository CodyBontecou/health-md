package com.healthmd.data.export

import com.healthmd.domain.model.*

class ObsidianBasesExporter {

    fun export(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
    ): String {
        val dateString = customization.dateFormat.format(data.date)
        val converter = customization.unitConverter
        val fmConfig = customization.frontmatterConfig

        return buildString {
            append("---\n")
            if (fmConfig.includeDate) {
                append("${fmConfig.customDateKey}: $dateString\n")
            }
            if (fmConfig.includeType) {
                append("${fmConfig.customTypeKey}: ${fmConfig.customTypeValue}\n")
            }

            // Custom static fields
            for ((key, value) in fmConfig.customFields.toSortedMap()) {
                append("$key: $value\n")
            }

            // Placeholder fields
            for (key in fmConfig.placeholderFields.sorted()) {
                append("$key: \n")
            }

            // Health data as frontmatter properties — driven by HealthDataFields (single source of truth)
            for (field in HealthDataFields.extract(data, converter)) {
                if (field.value == null) continue
                val outputKey = fmConfig.outputKey(field.key) ?: continue
                append("$outputKey: ${field.value}\n")
            }

            append("---\n")
        }
    }

}
