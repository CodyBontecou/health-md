package com.healthmd.domain.model

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.Locale

@Serializable
data class DailyNoteInjectionSettings(
    val enabled: Boolean = false,
    val folderPath: String = "Daily",
    val filenamePattern: String = "{date}",
    val createIfMissing: Boolean = true,
    val enabledMetrics: Set<String> = defaultMetrics,
) {
    fun resolvedPath(date: LocalDate): String {
        val filename = ExportSettings.applyDatePlaceholders(filenamePattern, date)
        return if (folderPath.isNotEmpty()) "$folderPath/$filename.md" else "$filename.md"
    }

    fun previewPath(): String = resolvedPath(LocalDate.now())

    companion object {
        val defaultMetrics = setOf(
            "sleep_total_hours", "steps", "active_calories",
            "resting_heart_rate", "weight_kg",
        )
    }
}
