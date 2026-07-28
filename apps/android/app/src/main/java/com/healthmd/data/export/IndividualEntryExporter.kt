package com.healthmd.data.export

import com.healthmd.domain.model.*
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

class IndividualEntryExporter {

    fun exportEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        customization: FormatCustomization = FormatCustomization(),
    ): List<Pair<String, String>> {
        if (!settings.globalEnabled) return emptyList()

        val entries = mutableListOf<Pair<String, String>>()
        val pathCounts = mutableMapOf<String, Int>()

        fun add(entry: IndividualEntry) {
            val relativePath = settings.relativePathFor(
                metricId = entry.trackingMetricId,
                metricSlug = entry.metricSlug,
                category = entry.category,
                date = entry.timestamp.toLocalDate(),
                time = entry.timestamp.format(FILENAME_TIME_FORMATTER),
            )
            entries.add(uniquePath(relativePath, pathCounts) to entry.render(customization))
        }

        addWorkoutEntries(data, settings, customization, ::add)
        addPlannedWorkoutEntries(data, settings, ::add)
        addMenstruationPeriodEntries(data, settings, ::add)
        addSleepStageEntries(data, settings, ::add)
        addStepEntries(data, settings, ::add)
        addHeartRateEntries(data, settings, ::add)
        addHrvEntries(data, settings, ::add)
        addVitalSampleEntries(data, settings, customization, ::add)
        addMindfulnessEntries(data, settings, ::add)
        addWeightEntry(data, settings, customization, ::add)

        return entries
    }

    private fun addWorkoutEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        customization: FormatCustomization,
        add: (IndividualEntry) -> Unit,
    ) {
        if (!settings.shouldTrackIndividually("workouts")) return

        for (workout in data.workouts) {
            val additional = linkedMapOf<String, EntryValue>(
                "workout_type" to EntryValue.Text(workout.workoutType.displayName()),
                "duration_minutes" to EntryValue.Number(workout.duration.inWholeMinutes.toDouble(), 0),
            )
            workout.endTime?.let { additional["end_time"] = EntryValue.Text(it.format(DISPLAY_TIME_FORMATTER)) }
            workout.isIndoor?.let { additional["is_indoor"] = EntryValue.Bool(it) }
            workout.metadata["title"]?.takeIf { it.isNotBlank() }?.let { additional["title"] = EntryValue.Text(it) }
            workout.metadata["notes"]?.takeIf { it.isNotBlank() }?.let { additional["notes"] = EntryValue.Text(it) }
            workout.calories?.takeIf { it > 0 }?.let { additional["calories"] = EntryValue.Number(it, 0) }
            workout.distance?.takeIf { it > 0 }?.let { additional["distance_m"] = EntryValue.Number(it, 0) }
            workout.elevationGained?.takeIf { it > 0 }?.let { additional["elevation_gained_m"] = EntryValue.Number(it, 0) }
            workout.elevationLoss?.takeIf { it > 0 }?.let { additional["elevation_loss_m"] = EntryValue.Number(it, 0) }
            workout.averageHeartRate?.let { additional["average_heart_rate"] = EntryValue.Number(it, 1) }
            workout.heartRateMin?.let { additional["heart_rate_min"] = EntryValue.Number(it, 1) }
            workout.heartRateMax?.let { additional["heart_rate_max"] = EntryValue.Number(it, 1) }
            workout.averageSpeed?.let { additional["average_speed_mps"] = EntryValue.Number(it, 2) }
            workout.maxSpeed?.let { additional["max_speed_mps"] = EntryValue.Number(it, 2) }
            workout.averagePaceSecondsPerKm?.let { additional["average_pace_sec_per_km"] = EntryValue.Number(it, 1) }
            workout.cyclingCadenceAvg?.let { additional["cycling_cadence_avg"] = EntryValue.Number(it, 1) }
            workout.stepsCadenceAvg?.let { additional["steps_cadence_avg"] = EntryValue.Number(it, 1) }
            workout.powerAvg?.let { additional["power_avg_w"] = EntryValue.Number(it, 1) }
            workout.powerMax?.let { additional["power_max_w"] = EntryValue.Number(it, 1) }
            if (workout.laps.isNotEmpty()) additional["laps"] = EntryValue.Number(workout.laps.size.toDouble(), 0)
            if (workout.splits.isNotEmpty()) additional["splits"] = EntryValue.Number(workout.splits.size.toDouble(), 0)
            if (workout.segments.isNotEmpty()) additional["segments"] = EntryValue.Number(workout.segments.size.toDouble(), 0)
            if (workout.routeAccess != WorkoutRouteAccess.NO_DATA) additional["route_access"] = EntryValue.Text(workout.routeAccess.name.lowercase())
            if (workout.route.isNotEmpty()) additional["route_points"] = EntryValue.Number(workout.route.size.toDouble(), 0)

            val bodyLines = buildList {
                workout.metadata["title"]?.takeIf { it.isNotBlank() }?.let { add("- **Title:** $it") }
                workout.endTime?.let { add("- **End:** ${it.format(DISPLAY_TIME_FORMATTER)}") }
                workout.isIndoor?.let { add("- **Location:** ${if (it) "Indoor" else "Outdoor"}") }
                add("- **Duration:** ${ExportHelpers.formatDuration(workout.duration)}")
                workout.calories?.takeIf { it > 0 }?.let { add("- **Calories:** ${it.toInt()} kcal") }
                workout.distance?.takeIf { it > 0 }?.let { add("- **Distance:** ${customization.unitConverter.formatDistance(it)}") }
                workout.elevationGained?.takeIf { it > 0 }?.let { add("- **Elevation gained:** ${String.format(Locale.US, "%.0f", it)} m") }
                workout.elevationLoss?.takeIf { it > 0 }?.let { add("- **Elevation loss:** ${String.format(Locale.US, "%.0f", it)} m") }
                workout.averageHeartRate?.let { add("- **Average HR:** ${it.toInt()} bpm") }
                workout.averageSpeed?.let { add("- **Average speed:** ${customization.unitConverter.formatSpeed(it)}") }
                workout.powerAvg?.let { add("- **Average power:** ${String.format(Locale.US, "%.0f", it)} W") }
                if (workout.laps.isNotEmpty()) add("- **Laps:** ${workout.laps.size}")
                if (workout.splits.isNotEmpty()) add("- **Splits:** ${workout.splits.size}")
                if (workout.segments.isNotEmpty()) add("- **Segments:** ${workout.segments.size}")
                if (workout.routeAccess != WorkoutRouteAccess.NO_DATA || workout.route.isNotEmpty()) {
                    add("- **Route:** ${workout.routeAccess.name.lowercase().replace('_', ' ')}${workout.route.takeIf { it.isNotEmpty() }?.let { " (${it.size} points)" } ?: ""}")
                }
                workout.metadata["notes"]?.takeIf { it.isNotBlank() }?.let { add("- **Notes:** $it") }
            }

            add(
                IndividualEntry(
                    trackingMetricId = "workouts",
                    metricId = "workouts",
                    metricSlug = workout.workoutType.slug(),
                    metricName = workout.workoutType.displayName(),
                    category = HealthMetricCategory.WORKOUTS,
                    timestamp = workout.startTime,
                    value = EntryValue.Text(workout.workoutType.displayName()),
                    unit = "",
                    additionalFields = additional,
                    bodyLines = bodyLines,
                )
            )
        }
    }

    private fun addPlannedWorkoutEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        add: (IndividualEntry) -> Unit,
    ) {
        if (!settings.shouldTrackIndividually("planned_workouts")) return
        data.plannedWorkouts.forEach { plan ->
            val minutes = plan.duration.inWholeMinutes.toDouble()
            add(
                IndividualEntry(
                    trackingMetricId = "planned_workouts",
                    metricId = "planned_workouts",
                    metricSlug = "planned-${plan.workoutType.slug()}",
                    metricName = "Planned ${plan.workoutType.displayName()}",
                    category = HealthMetricCategory.WORKOUTS,
                    timestamp = plan.startTime,
                    value = EntryValue.Number(minutes, 0),
                    unit = "min",
                    additionalFields = linkedMapOf(
                        "workout_type" to EntryValue.Text(plan.workoutType.displayName()),
                        "has_explicit_time" to EntryValue.Bool(plan.hasExplicitTime),
                        "block_count" to EntryValue.Number(plan.blockCount.toDouble(), 0),
                        "step_count" to EntryValue.Number(plan.stepCount.toDouble(), 0),
                    ),
                    bodyLines = buildList {
                        add("- **Type:** ${plan.workoutType.displayName()}")
                        add("- **Duration:** ${formatDurationMinutes(minutes)}")
                        plan.title?.let { add("- **Title:** $it") }
                        plan.notes?.let { add("- **Notes:** $it") }
                    },
                )
            )
        }
    }

    private fun addMenstruationPeriodEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        add: (IndividualEntry) -> Unit,
    ) {
        val trackingMetricId = when {
            settings.shouldTrackIndividually("menstruation_periods") -> "menstruation_periods"
            settings.shouldTrackIndividually("menstruation_period_days") -> "menstruation_period_days"
            else -> null
        } ?: return
        data.reproductiveHealth.menstruationPeriods.forEach { period ->
            val hours = period.duration.inWholeMinutes / 60.0
            add(
                IndividualEntry(
                    trackingMetricId = trackingMetricId,
                    metricId = "menstruation_period",
                    metricSlug = "menstruation-period",
                    metricName = "Menstruation Period",
                    category = HealthMetricCategory.REPRODUCTIVE,
                    timestamp = period.startTime,
                    value = EntryValue.Number(hours / 24.0, 2),
                    unit = "days",
                    additionalFields = linkedMapOf(
                        "start_time" to EntryValue.Text(period.startTime.format(DISPLAY_TIME_FORMATTER)),
                        "end_time" to EntryValue.Text(period.endTime.format(DISPLAY_TIME_FORMATTER)),
                        "duration_hours" to EntryValue.Number(hours, 1),
                    ),
                    bodyLines = listOf(
                        "- **Duration:** ${ExportHelpers.formatDuration(period.duration)}",
                        "- **Start:** ${period.startTime.format(DISPLAY_TIME_FORMATTER)}",
                        "- **End:** ${period.endTime.format(DISPLAY_TIME_FORMATTER)}",
                    ),
                )
            )
        }
    }

    private fun addSleepStageEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        add: (IndividualEntry) -> Unit,
    ) {
        for (stage in data.sleep.stages) {
            val stageMetricId = when (stage.stage.lowercase()) {
                "deep" -> "sleep_deep"
                "rem" -> "sleep_rem"
                "light", "core", "sleeping" -> "sleep_light"
                "awake", "wake" -> "sleep_awake"
                else -> "sleep_total"
            }
            val trackingMetricId = when {
                settings.shouldTrackIndividually(stageMetricId) -> stageMetricId
                settings.shouldTrackIndividually("sleep_total") -> "sleep_total"
                else -> null
            } ?: continue
            val minutes = java.time.Duration.between(stage.startTime, stage.endTime).toMinutes().toDouble()
            val stageName = stage.stage.replaceFirstChar { it.titlecase() }
            add(
                IndividualEntry(
                    trackingMetricId = trackingMetricId,
                    metricId = stageMetricId,
                    metricSlug = "sleep-${stage.stage.lowercase()}",
                    metricName = "$stageName Sleep",
                    category = HealthMetricCategory.SLEEP,
                    timestamp = stage.startTime,
                    value = EntryValue.Number(minutes, 0),
                    unit = "min",
                    additionalFields = linkedMapOf(
                        "stage" to EntryValue.Text(stage.stage.lowercase()),
                        "start_time" to EntryValue.Text(stage.startTime.format(DISPLAY_TIME_FORMATTER)),
                        "end_time" to EntryValue.Text(stage.endTime.format(DISPLAY_TIME_FORMATTER)),
                        "duration_minutes" to EntryValue.Number(minutes, 0),
                    ),
                    bodyLines = listOf(
                        "- **Stage:** $stageName",
                        "- **Duration:** ${formatDurationMinutes(minutes)}",
                        "- **Start:** ${stage.startTime.format(DISPLAY_TIME_FORMATTER)}",
                        "- **End:** ${stage.endTime.format(DISPLAY_TIME_FORMATTER)}",
                    ),
                )
            )
        }
    }

    private fun addStepEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        add: (IndividualEntry) -> Unit,
    ) {
        if (!settings.shouldTrackIndividually("steps")) return
        data.activity.stepSamples.forEach { sample ->
            add(
                sampleEntry(
                    trackingMetricId = "steps",
                    metricId = "steps",
                    metricSlug = "steps",
                    metricName = "Steps",
                    category = HealthMetricCategory.ACTIVITY,
                    sample = sample,
                    unit = "steps",
                    decimals = 0,
                )
            )
        }
    }

    private fun addHeartRateEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        add: (IndividualEntry) -> Unit,
    ) {
        val trackingMetricId = listOf("avg_hr", "min_hr", "max_hr", "walking_hr")
            .firstOrNull { settings.shouldTrackIndividually(it) } ?: return
        data.heart.samples.forEach { sample ->
            add(
                sampleEntry(
                    trackingMetricId = trackingMetricId,
                    metricId = "heart_rate",
                    metricSlug = "heart-rate",
                    metricName = "Heart Rate",
                    category = HealthMetricCategory.HEART,
                    sample = sample,
                    unit = "bpm",
                    decimals = 0,
                )
            )
        }
    }

    private fun addHrvEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        add: (IndividualEntry) -> Unit,
    ) {
        if (!settings.shouldTrackIndividually("hrv")) return
        data.heart.hrvSamples.forEach { sample ->
            add(
                sampleEntry(
                    trackingMetricId = "hrv",
                    metricId = "hrv",
                    metricSlug = "hrv",
                    metricName = "Heart Rate Variability",
                    category = HealthMetricCategory.HEART,
                    sample = sample,
                    unit = "ms",
                    decimals = 1,
                )
            )
        }
    }

    private fun addVitalSampleEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        customization: FormatCustomization,
        add: (IndividualEntry) -> Unit,
    ) {
        val bloodPressureTrackingId = when {
            settings.shouldTrackIndividually("bp_systolic") -> "bp_systolic"
            settings.shouldTrackIndividually("bp_diastolic") -> "bp_diastolic"
            else -> null
        }
        if (bloodPressureTrackingId != null) {
            if (data.vitals.bloodPressureSamples.isNotEmpty()) {
                data.vitals.bloodPressureSamples.forEach { sample ->
                    add(bloodPressureEntry(bloodPressureTrackingId, sample.time, sample.systolic, sample.diastolic))
                }
            } else if (data.vitals.bloodPressureSystolicAvg != null && data.vitals.bloodPressureDiastolicAvg != null) {
                add(
                    bloodPressureEntry(
                        bloodPressureTrackingId,
                        data.date.atStartOfDay(),
                        data.vitals.bloodPressureSystolicAvg,
                        data.vitals.bloodPressureDiastolicAvg,
                    )
                )
            }
        }

        if (settings.shouldTrackIndividually("blood_glucose")) {
            if (data.vitals.bloodGlucoseSamples.isNotEmpty()) {
                data.vitals.bloodGlucoseSamples.forEach { sample ->
                    add(sampleEntry("blood_glucose", "blood_glucose", "blood-glucose", "Blood Glucose", HealthMetricCategory.VITALS, sample, "mg/dL", 1))
                }
            } else if (data.vitals.bloodGlucoseAvg != null) {
                add(
                    simpleEntry(
                        trackingMetricId = "blood_glucose",
                        metricId = "blood_glucose",
                        metricSlug = "blood-glucose",
                        metricName = "Blood Glucose",
                        category = HealthMetricCategory.VITALS,
                        timestamp = data.date.atStartOfDay(),
                        value = data.vitals.bloodGlucoseAvg,
                        unit = "mg/dL",
                        decimals = 1,
                    )
                )
            }
        }

        if (settings.shouldTrackIndividually("blood_oxygen")) {
            data.vitals.bloodOxygenSamples.forEach { sample ->
                val percent = if (sample.value <= 1.0) sample.value * 100.0 else sample.value
                add(
                    simpleEntry(
                        trackingMetricId = "blood_oxygen",
                        metricId = "blood_oxygen",
                        metricSlug = "blood-oxygen",
                        metricName = "Blood Oxygen",
                        category = HealthMetricCategory.RESPIRATORY,
                        timestamp = sample.time,
                        value = percent,
                        unit = "%",
                        decimals = 1,
                    )
                )
            }
        }

        if (settings.shouldTrackIndividually("respiratory_rate")) {
            data.vitals.respiratoryRateSamples.forEach { sample ->
                add(sampleEntry("respiratory_rate", "respiratory_rate", "respiratory-rate", "Respiratory Rate", HealthMetricCategory.RESPIRATORY, sample, "breaths/min", 1))
            }
        }

        if (settings.shouldTrackIndividually("body_temp")) {
            data.vitals.bodyTemperatureSamples.forEach { sample ->
                val converted = customization.unitConverter.convertTemperature(sample.value)
                add(
                    simpleEntry(
                        trackingMetricId = "body_temp",
                        metricId = "body_temp",
                        metricSlug = "body-temperature",
                        metricName = "Body Temperature",
                        category = HealthMetricCategory.VITALS,
                        timestamp = sample.time,
                        value = converted,
                        unit = customization.unitConverter.temperatureUnit(),
                        decimals = 1,
                    )
                )
            }
        }
    }

    private fun addMindfulnessEntries(
        data: HealthData,
        settings: IndividualTrackingSettings,
        add: (IndividualEntry) -> Unit,
    ) {
        val trackingMetricId = when {
            settings.shouldTrackIndividually("mindful_sessions") -> "mindful_sessions"
            settings.shouldTrackIndividually("mindful_minutes") -> "mindful_minutes"
            else -> null
        } ?: return

        data.mindfulness.sessions.forEach { session ->
            val minutes = java.time.Duration.between(session.startTime, session.endTime).toMinutes().toDouble()
            add(
                IndividualEntry(
                    trackingMetricId = trackingMetricId,
                    metricId = "mindful_sessions",
                    metricSlug = "mindful-session",
                    metricName = "Mindful Session",
                    category = HealthMetricCategory.MINDFULNESS,
                    timestamp = session.startTime,
                    value = EntryValue.Number(minutes, 0),
                    unit = "min",
                    additionalFields = linkedMapOf(
                        "start_time" to EntryValue.Text(session.startTime.format(DISPLAY_TIME_FORMATTER)),
                        "end_time" to EntryValue.Text(session.endTime.format(DISPLAY_TIME_FORMATTER)),
                        "duration_minutes" to EntryValue.Number(minutes, 0),
                    ),
                    bodyLines = listOf(
                        "- **Duration:** ${formatDurationMinutes(minutes)}",
                        "- **Start:** ${session.startTime.format(DISPLAY_TIME_FORMATTER)}",
                        "- **End:** ${session.endTime.format(DISPLAY_TIME_FORMATTER)}",
                    ),
                )
            )
        }
    }

    private fun addWeightEntry(
        data: HealthData,
        settings: IndividualTrackingSettings,
        customization: FormatCustomization,
        add: (IndividualEntry) -> Unit,
    ) {
        if (!settings.shouldTrackIndividually("weight")) return
        data.body.weight?.let { weightKg ->
            val converted = customization.unitConverter.convertWeight(weightKg)
            add(
                simpleEntry(
                    trackingMetricId = "weight",
                    metricId = "weight",
                    metricSlug = "weight",
                    metricName = "Weight",
                    category = HealthMetricCategory.BODY,
                    timestamp = data.date.atStartOfDay(),
                    value = converted,
                    unit = customization.unitConverter.weightUnit(),
                    decimals = 1,
                    bodyValue = customization.unitConverter.formatWeight(weightKg),
                )
            )
        }
    }

    private fun bloodPressureEntry(
        trackingMetricId: String,
        timestamp: LocalDateTime,
        systolic: Double,
        diastolic: Double,
    ): IndividualEntry = IndividualEntry(
        trackingMetricId = trackingMetricId,
        metricId = "blood_pressure",
        metricSlug = "blood-pressure",
        metricName = "Blood Pressure",
        category = HealthMetricCategory.VITALS,
        timestamp = timestamp,
        value = EntryValue.Text("${systolic.toInt()}/${diastolic.toInt()}"),
        unit = "mmHg",
        additionalFields = linkedMapOf(
            "systolic" to EntryValue.Number(systolic, 0),
            "diastolic" to EntryValue.Number(diastolic, 0),
        ),
        bodyLines = listOf("- **Blood Pressure:** ${systolic.toInt()}/${diastolic.toInt()} mmHg"),
    )

    private fun sampleEntry(
        trackingMetricId: String,
        metricId: String,
        metricSlug: String,
        metricName: String,
        category: HealthMetricCategory,
        sample: TimestampedSample,
        unit: String,
        decimals: Int,
    ): IndividualEntry = simpleEntry(
        trackingMetricId = trackingMetricId,
        metricId = metricId,
        metricSlug = metricSlug,
        metricName = metricName,
        category = category,
        timestamp = sample.time,
        value = sample.value,
        unit = unit,
        decimals = decimals,
    )

    private fun simpleEntry(
        trackingMetricId: String,
        metricId: String,
        metricSlug: String,
        metricName: String,
        category: HealthMetricCategory,
        timestamp: LocalDateTime,
        value: Double,
        unit: String,
        decimals: Int,
        bodyValue: String? = null,
    ): IndividualEntry {
        val renderedValue = EntryValue.Number(value, decimals).render()
        val displayedValue = bodyValue ?: "$renderedValue${unit.takeIf { it.isNotBlank() }?.let { " $it" } ?: ""}"
        return IndividualEntry(
            trackingMetricId = trackingMetricId,
            metricId = metricId,
            metricSlug = metricSlug,
            metricName = metricName,
            category = category,
            timestamp = timestamp,
            value = EntryValue.Number(value, decimals),
            unit = unit,
            bodyLines = listOf("- **$metricName:** $displayedValue"),
        )
    }

    private data class IndividualEntry(
        val trackingMetricId: String,
        val metricId: String,
        val metricSlug: String,
        val metricName: String,
        val category: HealthMetricCategory,
        val timestamp: LocalDateTime,
        val value: EntryValue,
        val unit: String,
        val additionalFields: Map<String, EntryValue> = emptyMap(),
        val bodyLines: List<String> = emptyList(),
    ) {
        fun render(customization: FormatCustomization): String = buildString {
            append("---\n")
            append("date: ${customization.dateFormat.format(timestamp.toLocalDate())}\n")
            append("time: ${customization.timeFormat.format(timestamp)}\n")
            append("type: ${category.folderName()}\n")
            append("metric: $metricId\n")
            append("metric_name: ${EntryValue.Text(metricName).renderYaml()}\n")
            append("value: ${value.renderYaml()}\n")
            if (unit.isNotBlank()) append("unit: $unit\n")
            additionalFields.toSortedMap().forEach { (key, value) ->
                append("$key: ${value.renderYaml()}\n")
            }
            append("---\n\n")
            append("# $metricName\n\n")
            if (bodyLines.isEmpty()) {
                append("- **Value:** ${value.render()}${unit.takeIf { it.isNotBlank() }?.let { " $it" } ?: ""}\n")
            } else {
                bodyLines.forEach { line -> append(line).append('\n') }
            }
        }
    }

    private sealed class EntryValue {
        data class Text(val value: String) : EntryValue()
        data class Number(val value: Double, val decimals: Int = 1) : EntryValue()
        data class Bool(val value: Boolean) : EntryValue()

        fun render(): String = when (this) {
            is Text -> value
            is Number -> if (decimals == 0) value.toLong().toString() else String.format(Locale.US, "%.${decimals}f", value)
            is Bool -> value.toString()
        }

        fun renderYaml(): String = when (this) {
            is Text -> yamlString(value)
            is Number -> render()
            is Bool -> value.toString()
        }
    }

    companion object {
        private val FILENAME_TIME_FORMATTER: DateTimeFormatter = DateTimeFormatter.ofPattern("HH-mm")
        private val DISPLAY_TIME_FORMATTER: DateTimeFormatter = DateTimeFormatter.ofPattern("HH:mm")

        private fun uniquePath(path: String, counts: MutableMap<String, Int>): String {
            val nextCount = (counts[path] ?: 0) + 1
            counts[path] = nextCount
            if (nextCount == 1) return path
            val extensionIndex = path.lastIndexOf('.')
            return if (extensionIndex > path.lastIndexOf('/')) {
                path.substring(0, extensionIndex) + "-$nextCount" + path.substring(extensionIndex)
            } else {
                "$path-$nextCount"
            }
        }

        private fun yamlString(value: String): String {
            val escaped = value.replace("\\", "\\\\").replace("\"", "\\\"")
            return "\"$escaped\""
        }

        private fun formatDurationMinutes(minutes: Double): String {
            val wholeMinutes = minutes.toLong()
            val hours = wholeMinutes / 60
            val remainingMinutes = wholeMinutes % 60
            return if (hours > 0) "${hours}h ${remainingMinutes}m" else "${remainingMinutes}m"
        }
    }
}
