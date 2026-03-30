package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
data class IndividualTrackingSettings(
    val globalEnabled: Boolean = false,
    val enabledMetrics: Set<String> = emptySet(),
    val entriesFolder: String = "entries",
    val organizeByCategory: Boolean = true,
    val filenameTemplate: String = "{metric}-{date}-{time}",
) {
    fun enableAll(allMetrics: List<String>) = copy(enabledMetrics = allMetrics.toSet())
    fun disableAll() = copy(enabledMetrics = emptySet())
    fun enableSuggested() = copy(enabledMetrics = suggestedMetrics)
    fun toggleMetric(metric: String) = copy(
        enabledMetrics = if (metric in enabledMetrics) enabledMetrics - metric else enabledMetrics + metric
    )

    companion object {
        val suggestedMetrics = setOf(
            "workouts", "blood_pressure", "blood_glucose", "weight",
        )
    }
}
