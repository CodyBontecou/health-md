package com.healthmd.domain.model

import kotlinx.serialization.Serializable
import java.time.LocalDate

@Serializable
data class DailyNoteInjectionSettings(
    val enabled: Boolean = false,
    val folderPath: String = "Daily",
    val filenamePattern: String = "{date}",
    // Android historically defaulted this to true. Keep that default so previously saved
    // settings that omitted the field keep creating notes after migration.
    val createIfMissing: Boolean = true,
    val injectMarkdownSections: Boolean = false,
    // Legacy field retained for backwards-compatible decoding. Metric inclusion is now driven by
    // ExportSettings.metricSelection before the injector receives HealthData, matching iOS parity.
    val enabledMetrics: Set<String> = emptySet(),
) {
    fun resolvedPath(date: LocalDate): String {
        val filename = ExportSettings.applyDatePlaceholders(filenamePattern, date)
        return if (folderPath.isNotEmpty()) "$folderPath/$filename.md" else "$filename.md"
    }

    fun previewPath(): String = resolvedPath(LocalDate.now())

    companion object {
        val legacyDefaultMetrics = setOf(
            "sleep_total_hours", "steps", "active_calories",
            "resting_heart_rate", "weight_kg",
        )
    }
}
