package com.healthmd.data.export

import com.healthmd.domain.model.*
import kotlin.time.Duration

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

            // All health data as frontmatter properties
            fun addField(originalKey: String, value: Any?) {
                if (value == null) return
                val outputKey = fmConfig.outputKey(originalKey) ?: return
                append("$outputKey: $value\n")
            }

            // Sleep
            val s = data.sleep
            addField("sleep_total_hours", s.totalDuration.toHoursRounded())
            addField("sleep_deep_hours", s.deepSleep.toHoursRounded())
            addField("sleep_rem_hours", s.remSleep.toHoursRounded())
            addField("sleep_light_hours", s.lightSleep.toHoursRounded())
            addField("sleep_awake_hours", s.awakeTime.toHoursRounded())
            addField("sleep_in_bed_hours", s.inBedTime.toHoursRounded())

            // Activity
            val a = data.activity
            addField("steps", a.steps)
            addField("active_calories", a.activeCalories?.toInt())
            addField("basal_calories", a.basalEnergyBurned?.toInt())
            addField("exercise_minutes", a.exerciseMinutes?.toInt())
            addField("flights_climbed", a.flightsClimbed)
            addField("walking_running_km", a.walkingRunningDistance?.let { String.format("%.2f", converter.convertDistance(it)) })
            addField("cycling_km", a.cyclingDistance?.let { String.format("%.2f", converter.convertDistance(it)) })

            // Heart
            val h = data.heart
            addField("resting_heart_rate", h.restingHeartRate?.toInt())
            addField("average_heart_rate", h.averageHeartRate?.toInt())
            addField("heart_rate_min", h.heartRateMin?.toInt())
            addField("heart_rate_max", h.heartRateMax?.toInt())
            addField("hrv_ms", h.hrv?.let { String.format("%.1f", it) })

            // Vitals
            val v = data.vitals
            addField("respiratory_rate", v.respiratoryRateAvg?.let { String.format("%.1f", it) })
            addField("blood_oxygen", v.bloodOxygenAvg?.let { "${(it * 100).toInt()}" })
            addField("body_temperature", v.bodyTemperatureAvg?.let { String.format("%.1f", converter.convertTemperature(it)) })
            addField("blood_pressure_systolic", v.bloodPressureSystolicAvg?.toInt())
            addField("blood_pressure_diastolic", v.bloodPressureDiastolicAvg?.toInt())
            addField("blood_glucose", v.bloodGlucoseAvg?.let { String.format("%.1f", it) })

            // Body
            val b = data.body
            addField("weight_kg", b.weight?.let { String.format("%.1f", converter.convertWeight(it)) })
            addField("height_m", b.height?.let { String.format("%.1f", converter.convertHeight(it)) })
            addField("bmi", b.bmi?.let { String.format("%.1f", it) })
            addField("body_fat_percent", b.bodyFatPercentage?.let { String.format("%.1f", it * 100) })
            addField("lean_body_mass_kg", b.leanBodyMass?.let { String.format("%.1f", converter.convertWeight(it)) })

            // Nutrition
            val n = data.nutrition
            addField("dietary_calories", n.dietaryEnergy?.toInt())
            addField("protein_g", n.protein?.let { String.format("%.1f", it) })
            addField("carbohydrates_g", n.carbohydrates?.let { String.format("%.1f", it) })
            addField("fat_g", n.fat?.let { String.format("%.1f", it) })
            addField("saturated_fat_g", n.saturatedFat?.let { String.format("%.1f", it) })
            addField("fiber_g", n.fiber?.let { String.format("%.1f", it) })
            addField("sugar_g", n.sugar?.let { String.format("%.1f", it) })
            addField("sodium_mg", n.sodium?.toInt())
            addField("cholesterol_mg", n.cholesterol?.let { String.format("%.1f", it) })
            addField("water_l", n.water?.let { String.format("%.2f", converter.convertVolume(it)) })
            addField("caffeine_mg", n.caffeine?.let { String.format("%.1f", it) })

            // Mobility
            val m = data.mobility
            addField("walking_speed", m.walkingSpeed?.let { String.format("%.2f", it) })
            addField("vo2_max", m.vo2Max?.let { String.format("%.1f", it) })

            // Workouts
            if (data.workouts.isNotEmpty()) {
                addField("workout_count", data.workouts.size)
                addField("workout_minutes", data.workouts.sumOf { it.duration.inWholeMinutes }.toInt())
                addField("workout_calories", data.workouts.mapNotNull { it.calories }.sum().takeIf { it > 0 }?.toInt())
            }

            append("---\n")
        }
    }

    private fun Duration.toHoursRounded(): String? {
        if (this <= Duration.ZERO) return null
        return String.format("%.2f", this.inWholeMinutes / 60.0)
    }
}
