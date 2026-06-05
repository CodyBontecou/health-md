package com.healthmd.data.export

import com.healthmd.domain.model.*
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

class IndividualEntryExporter {

    fun exportEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        customization: FormatCustomization = FormatCustomization(),
    ): List<Pair<String, String>> {
        if (!settings.globalEnabled) return emptyList()

        val results = mutableListOf<Pair<String, String>>() // relative path to content
        val dateStr = customization.dateFormat.format(data.date)
        val filenameTimeFormatter = DateTimeFormatter.ofPattern("HH-mm")

        if ("workouts" in settings.enabledMetrics && data.workouts.isNotEmpty()) {
            for (workout in data.workouts) {
                val relativePath = relativePath(
                    settings = settings,
                    metric = workout.workoutType.slug(),
                    date = data.date,
                    time = workout.startTime.format(filenameTimeFormatter),
                    category = "workouts",
                )

                val content = buildString {
                    append("---\n")
                    append("date: $dateStr\n")
                    append("time: ${customization.timeFormat.format(workout.startTime)}\n")
                    append("type: workout\n")
                    append("metric: ${workout.workoutType.displayName()}\n")
                    append("duration_minutes: ${workout.duration.inWholeMinutes}\n")
                    workout.calories?.takeIf { it > 0 }?.let { append("calories: ${it.toInt()}\n") }
                    workout.distance?.takeIf { it > 0 }?.let { append("distance_m: ${String.format("%.0f", it)}\n") }
                    append("---\n\n")
                    append("# ${workout.workoutType.displayName()}\n\n")
                    append("- **Duration:** ${ExportHelpers.formatDuration(workout.duration)}\n")
                    workout.calories?.takeIf { it > 0 }?.let { append("- **Calories:** ${it.toInt()} kcal\n") }
                    workout.distance?.takeIf { it > 0 }?.let { d ->
                        append("- **Distance:** ${customization.unitConverter.formatDistance(d)}\n")
                    }
                }

                results.add(relativePath to content)
            }
        }

        if ("blood_pressure" in settings.enabledMetrics) {
            if (data.vitals.bloodPressureSamples.isNotEmpty()) {
                for (sample in data.vitals.bloodPressureSamples) {
                    val relativePath = relativePath(
                        settings = settings,
                        metric = "blood-pressure",
                        date = data.date,
                        time = sample.time.format(filenameTimeFormatter),
                        category = "vitals",
                    )
                    results.add(relativePath to bloodPressureContent(dateStr, sample.time, sample.systolic, sample.diastolic, customization))
                }
            } else if (data.vitals.bloodPressureSystolicAvg != null && data.vitals.bloodPressureDiastolicAvg != null) {
                val relativePath = relativePath(settings, "blood-pressure", data.date, "00-00", "vitals")
                results.add(relativePath to bloodPressureContent(
                    dateStr = dateStr,
                    time = null,
                    systolic = data.vitals.bloodPressureSystolicAvg,
                    diastolic = data.vitals.bloodPressureDiastolicAvg,
                    customization = customization,
                ))
            }
        }

        if ("blood_glucose" in settings.enabledMetrics) {
            if (data.vitals.bloodGlucoseSamples.isNotEmpty()) {
                for (sample in data.vitals.bloodGlucoseSamples) {
                    val relativePath = relativePath(
                        settings = settings,
                        metric = "blood-glucose",
                        date = data.date,
                        time = sample.time.format(filenameTimeFormatter),
                        category = "vitals",
                    )
                    results.add(relativePath to bloodGlucoseContent(dateStr, sample.time, sample.value, customization))
                }
            } else if (data.vitals.bloodGlucoseAvg != null) {
                val relativePath = relativePath(settings, "blood-glucose", data.date, "00-00", "vitals")
                results.add(relativePath to bloodGlucoseContent(dateStr, null, data.vitals.bloodGlucoseAvg, customization))
            }
        }

        if ("weight" in settings.enabledMetrics) {
            data.body.weight?.let { weightKg ->
                val relativePath = relativePath(settings, "weight", data.date, "00-00", "body")
                val content = buildString {
                    append("---\n")
                    append("date: $dateStr\n")
                    append("type: weight\n")
                    append("value: ${String.format("%.1f", customization.unitConverter.convertWeight(weightKg))}\n")
                    append("unit: ${customization.unitConverter.weightUnit()}\n")
                    append("---\n\n")
                    append("# Weight\n\n")
                    append("- **Weight:** ${customization.unitConverter.formatWeight(weightKg)}\n")
                }
                results.add(relativePath to content)
            }
        }

        return results
    }

    private fun relativePath(
        settings: IndividualTrackingSettings,
        metric: String,
        date: LocalDate,
        time: String,
        category: String,
    ): String {
        val filename = settings.filenameTemplate
            .replace("{metric}", metric)
            .replace("{date}", date.toString())
            .replace("{time}", time)
            .replace("{category}", category)
            .let { if (it.endsWith(".md")) it else "$it.md" }

        return if (settings.organizeByCategory) "$category/$filename" else filename
    }

    private fun bloodPressureContent(
        dateStr: String,
        time: LocalDateTime?,
        systolic: Double,
        diastolic: Double,
        customization: FormatCustomization,
    ): String = buildString {
        append("---\n")
        append("date: $dateStr\n")
        time?.let { append("time: ${customization.timeFormat.format(it)}\n") }
        append("type: blood-pressure\n")
        append("systolic: ${systolic.toInt()}\n")
        append("diastolic: ${diastolic.toInt()}\n")
        append("unit: mmHg\n")
        append("---\n\n")
        append("# Blood Pressure\n\n")
        append("- **Blood Pressure:** ${systolic.toInt()}/${diastolic.toInt()} mmHg\n")
    }

    private fun bloodGlucoseContent(
        dateStr: String,
        time: LocalDateTime?,
        value: Double,
        customization: FormatCustomization,
    ): String = buildString {
        append("---\n")
        append("date: $dateStr\n")
        time?.let { append("time: ${customization.timeFormat.format(it)}\n") }
        append("type: blood-glucose\n")
        append("value: ${String.format("%.1f", value)}\n")
        append("unit: mg/dL\n")
        append("---\n\n")
        append("# Blood Glucose\n\n")
        append("- **Blood Glucose:** ${String.format("%.1f", value)} mg/dL\n")
    }
}
