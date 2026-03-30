package com.healthmd.data.export

import com.healthmd.domain.model.*
import java.time.format.DateTimeFormatter

data class IndividualHealthEntry(
    val metricId: String,
    val category: String,
    val timestamp: String,
    val value: String,
    val unit: String,
)

class IndividualEntryExporter {

    fun exportEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        customization: FormatCustomization = FormatCustomization(),
    ): List<Pair<String, String>> {
        if (!settings.globalEnabled) return emptyList()

        val results = mutableListOf<Pair<String, String>>() // filename to content
        val dateStr = customization.dateFormat.format(data.date)
        val timeFormatter = DateTimeFormatter.ofPattern("HH-mm")

        // Export workouts as individual entries
        if ("workouts" in settings.enabledMetrics && data.workouts.isNotEmpty()) {
            for (workout in data.workouts) {
                val timeStr = workout.startTime.format(timeFormatter)
                val filename = settings.filenameTemplate
                    .replace("{metric}", workout.workoutType.slug())
                    .replace("{date}", data.date.toString())
                    .replace("{time}", timeStr)
                    .replace("{category}", "workouts")

                val subfolder = if (settings.organizeByCategory) "workouts" else ""
                val fullPath = if (subfolder.isNotEmpty()) "$subfolder/$filename" else filename

                val content = buildString {
                    append("---\n")
                    append("date: $dateStr\n")
                    append("time: ${customization.timeFormat.format(workout.startTime)}\n")
                    append("type: workout\n")
                    append("metric: ${workout.workoutType.displayName()}\n")
                    append("duration_minutes: ${workout.duration.inWholeMinutes}\n")
                    workout.calories?.let { append("calories: ${it.toInt()}\n") }
                    workout.distance?.let { append("distance_m: ${String.format("%.0f", it)}\n") }
                    append("---\n\n")
                    append("# ${workout.workoutType.displayName()}\n\n")
                    append("- **Duration:** ${ExportHelpers.formatDuration(workout.duration)}\n")
                    workout.calories?.let { append("- **Calories:** ${it.toInt()} kcal\n") }
                    workout.distance?.let { d ->
                        append("- **Distance:** ${customization.unitConverter.formatDistance(d)}\n")
                    }
                }

                results.add(Pair("$fullPath.md", content))
            }
        }

        // Export blood pressure readings as individual entries
        if ("blood_pressure" in settings.enabledMetrics && data.vitals.bloodPressureSystolicAvg != null) {
            val filename = settings.filenameTemplate
                .replace("{metric}", "blood-pressure")
                .replace("{date}", data.date.toString())
                .replace("{time}", "00-00")
                .replace("{category}", "vitals")

            val subfolder = if (settings.organizeByCategory) "vitals" else ""
            val fullPath = if (subfolder.isNotEmpty()) "$subfolder/$filename" else filename

            val content = buildString {
                append("---\n")
                append("date: $dateStr\n")
                append("type: blood-pressure\n")
                append("systolic: ${data.vitals.bloodPressureSystolicAvg?.toInt()}\n")
                append("diastolic: ${data.vitals.bloodPressureDiastolicAvg?.toInt()}\n")
                append("---\n")
            }

            results.add(Pair("$fullPath.md", content))
        }

        // Export blood glucose readings
        if ("blood_glucose" in settings.enabledMetrics && data.vitals.bloodGlucoseAvg != null) {
            val filename = settings.filenameTemplate
                .replace("{metric}", "blood-glucose")
                .replace("{date}", data.date.toString())
                .replace("{time}", "00-00")
                .replace("{category}", "vitals")

            val subfolder = if (settings.organizeByCategory) "vitals" else ""
            val fullPath = if (subfolder.isNotEmpty()) "$subfolder/$filename" else filename

            val content = buildString {
                append("---\n")
                append("date: $dateStr\n")
                append("type: blood-glucose\n")
                append("value: ${String.format("%.1f", data.vitals.bloodGlucoseAvg)}\n")
                append("unit: mg/dL\n")
                append("---\n")
            }

            results.add(Pair("$fullPath.md", content))
        }

        // Export weight
        if ("weight" in settings.enabledMetrics && data.body.weight != null) {
            val filename = settings.filenameTemplate
                .replace("{metric}", "weight")
                .replace("{date}", data.date.toString())
                .replace("{time}", "00-00")
                .replace("{category}", "body")

            val subfolder = if (settings.organizeByCategory) "body" else ""
            val fullPath = if (subfolder.isNotEmpty()) "$subfolder/$filename" else filename

            val content = buildString {
                append("---\n")
                append("date: $dateStr\n")
                append("type: weight\n")
                append("value: ${String.format("%.1f", customization.unitConverter.convertWeight(data.body.weight))}\n")
                append("unit: ${customization.unitConverter.weightUnit()}\n")
                append("---\n")
            }

            results.add(Pair("$fullPath.md", content))
        }

        return results
    }
}
