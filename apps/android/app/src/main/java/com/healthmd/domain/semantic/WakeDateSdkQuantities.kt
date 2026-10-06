package com.healthmd.domain.semantic

import com.healthmd.domain.model.HealthData
import kotlin.time.Duration
import kotlin.time.DurationUnit

/** Post-capture SDK aggregates in native units; never parse rounded display strings. */
internal object WakeDateSdkQuantities {
    data class Quantity(val value: Number, val unit: String)

    fun capture(data: HealthData): Map<String, Quantity> = buildMap {
        fun quantity(key: String, value: Number?, unit: String) {
            if (value != null) put(key, Quantity(value, unit))
        }
        fun duration(key: String, value: Duration, unit: DurationUnit, label: String) {
            if (value > Duration.ZERO) quantity(key, value.toDouble(unit), label)
        }
        with(data.sleep) {
            duration("sleep_total_hours", totalDuration, DurationUnit.HOURS, "hours")
            duration("sleep_deep_hours", deepSleep, DurationUnit.HOURS, "hours")
            duration("sleep_light_hours", lightSleep, DurationUnit.HOURS, "hours")
            duration("sleep_rem_hours", remSleep, DurationUnit.HOURS, "hours")
            duration("sleep_awake_hours", awakeTime, DurationUnit.HOURS, "hours")
            duration("sleep_in_bed_hours", inBedTime, DurationUnit.HOURS, "hours")
        }
        with(data.activity) {
            quantity("steps", steps, "count")
            quantity("active_calories", activeCalories, "kcal")
            quantity("basal_calories", basalEnergyBurned, "kcal")
            quantity("total_calories", totalCalories, "kcal")
            quantity("walking_running_km", walkingRunningDistance, "m")
            quantity("cycling_km", cyclingDistance, "m")
            quantity("swimming_m", swimmingDistance, "m")
            quantity("swimming_strokes", swimmingStrokes, "count")
            quantity("flights_climbed", flightsClimbed, "count")
            quantity("elevation_gained_m", elevationGained, "m")
            quantity("exercise_minutes", exerciseMinutes, "minutes")
            quantity("wheelchair_pushes", wheelchairPushes, "count")
            quantity("wheelchair_km", wheelchairDistance, "m")
            quantity("downhill_snow_km", downhillSnowSportsDistance, "m")
            quantity("activity_intensity_minutes", activityIntensityMinutes, "minutes")
            quantity("moderate_activity_minutes", moderateActivityMinutes, "minutes")
            quantity("vigorous_activity_minutes", vigorousActivityMinutes, "minutes")
        }
        with(data.heart) {
            quantity("average_heart_rate", averageHeartRate, "bpm")
            quantity("heart_rate_min", heartRateMin, "bpm")
            quantity("heart_rate_max", heartRateMax, "bpm")
            quantity("resting_heart_rate", restingHeartRate, "bpm")
            quantity("walking_heart_rate", walkingHeartRateAverage, "bpm")
            quantity("hrv_ms", hrv, "ms")
        }
        with(data.vitals) {
            quantity("blood_oxygen", bloodOxygenAvg, "ratio_0_1")
            quantity("blood_oxygen_avg", bloodOxygenAvg, "ratio_0_1")
            quantity("blood_oxygen_min", bloodOxygenMin, "ratio_0_1")
            quantity("blood_oxygen_max", bloodOxygenMax, "ratio_0_1")
            quantity("blood_pressure_systolic", bloodPressureSystolicAvg, "mmHg")
            quantity("blood_pressure_systolic_avg", bloodPressureSystolicAvg, "mmHg")
            quantity("blood_pressure_systolic_min", bloodPressureSystolicMin, "mmHg")
            quantity("blood_pressure_systolic_max", bloodPressureSystolicMax, "mmHg")
            quantity("blood_pressure_diastolic", bloodPressureDiastolicAvg, "mmHg")
            quantity("blood_pressure_diastolic_avg", bloodPressureDiastolicAvg, "mmHg")
            quantity("blood_pressure_diastolic_min", bloodPressureDiastolicMin, "mmHg")
            quantity("blood_pressure_diastolic_max", bloodPressureDiastolicMax, "mmHg")
            quantity("respiratory_rate", respiratoryRateAvg, "breaths/min")
            quantity("respiratory_rate_avg", respiratoryRateAvg, "breaths/min")
            quantity("respiratory_rate_min", respiratoryRateMin, "breaths/min")
            quantity("respiratory_rate_max", respiratoryRateMax, "breaths/min")
            quantity("body_temperature", bodyTemperatureAvg, "°C")
            quantity("body_temperature_avg", bodyTemperatureAvg, "°C")
            quantity("body_temperature_min", bodyTemperatureMin, "°C")
            quantity("body_temperature_max", bodyTemperatureMax, "°C")
            quantity("basal_body_temperature", basalBodyTemperature, "°C")
            quantity("skin_temperature_delta", skinTemperatureDelta, "°C")
            quantity("blood_glucose", bloodGlucoseAvg, "mg/dL")
            quantity("blood_glucose_avg", bloodGlucoseAvg, "mg/dL")
            quantity("blood_glucose_min", bloodGlucoseMin, "mg/dL")
            quantity("blood_glucose_max", bloodGlucoseMax, "mg/dL")
        }
        with(data.body) {
            quantity("weight_kg", weight, "kg")
            quantity("height_m", height, "m")
            quantity("bmi", bmi, "unitless")
            quantity("body_fat_percent", bodyFatPercentage, "ratio_0_1")
            quantity("lean_body_mass_kg", leanBodyMass, "kg")
            quantity("body_water_mass_kg", bodyWaterMass, "kg")
            quantity("bone_mass_kg", boneMass, "kg")
        }
        with(data.nutrition) {
            quantity("dietary_calories", dietaryEnergy, "kcal")
            quantity("fat_g", fat, "g")
            quantity("saturated_fat_g", saturatedFat, "g")
            quantity("unsaturated_fat_g", unsaturatedFat, "g")
            quantity("monounsaturated_fat_g", monounsaturatedFat, "g")
            quantity("polyunsaturated_fat_g", polyunsaturatedFat, "g")
            quantity("trans_fat_g", transFat, "g")
            quantity("carbohydrates_g", carbohydrates, "g")
            quantity("protein_g", protein, "g")
            quantity("sugar_g", sugar, "g")
            quantity("fiber_g", fiber, "g")
            quantity("cholesterol_mg", cholesterol, "mg")
            quantity("sodium_mg", sodium, "mg")
            quantity("water_l", water, "L")
            quantity("caffeine_mg", caffeine, "mg")
            quantity("calcium_mg", calcium, "mg")
            quantity("iron_mg", iron, "mg")
            quantity("magnesium_mg", magnesium, "mg")
            quantity("potassium_mg", potassium, "mg")
            quantity("zinc_mg", zinc, "mg")
            quantity("phosphorus_mg", phosphorus, "mg")
            quantity("vitamin_a_ug", vitaminA, "µg")
            quantity("vitamin_c_mg", vitaminC, "mg")
            quantity("vitamin_d_ug", vitaminD, "µg")
            quantity("vitamin_e_mg", vitaminE, "mg")
            quantity("vitamin_k_ug", vitaminK, "µg")
            quantity("vitamin_b6_mg", vitaminB6, "mg")
            quantity("vitamin_b12_ug", vitaminB12, "µg")
            quantity("thiamin_mg", thiamin, "mg")
            quantity("riboflavin_mg", riboflavin, "mg")
            quantity("niacin_mg", niacin, "mg")
            quantity("folate_ug", folate, "µg")
            quantity("folic_acid_mcg", folicAcid, "µg")
            quantity("biotin_ug", biotin, "µg")
            quantity("pantothenic_acid_mg", pantothenicAcid, "mg")
            quantity("selenium_ug", selenium, "µg")
            quantity("copper_mg", copper, "mg")
            quantity("manganese_mg", manganese, "mg")
            quantity("iodine_ug", iodine, "µg")
            quantity("chromium_ug", chromium, "µg")
            quantity("molybdenum_ug", molybdenum, "µg")
            quantity("chloride_mg", chloride, "mg")
            quantity("energy_from_fat_kcal", energyFromFat, "kcal")
            quantity("nutrition_meal_count", meals.size.takeIf { it > 0 }, "count")
        }
        with(data.mobility) {
            quantity("walking_speed", walkingSpeed, "m/s")
            quantity("vo2_max", vo2Max, "mL/kg/min")
            quantity("cycling_cadence_rpm", cyclingCadenceAvg, "rpm")
            quantity("cycling_cadence", cyclingCadenceAvg, "rpm")
            quantity("cycling_cadence_max", cyclingCadenceMax, "rpm")
            quantity("cycling_power_w", powerAvg, "W")
            quantity("power_max", powerMax, "W")
            quantity("steps_cadence", stepsCadenceAvg, "steps/min")
            quantity("steps_cadence_max", stepsCadenceMax, "steps/min")
            quantity("running_speed", runningSpeed, "m/s")
            quantity("running_power_w", runningPowerAvg, "W")
            quantity("running_power_max", runningPowerMax, "W")
        }
        with(data.mindfulness) {
            quantity("mindful_sessions", mindfulSessions, "sessions")
            quantity("mindful_minutes", mindfulnessMinutes, "minutes")
        }
        with(data.reproductiveHealth) {
            quantity("menstruation_period_count", menstruationPeriodCount, "count")
            duration("menstruation_period_days", menstruationPeriodDuration, DurationUnit.DAYS, "unitless")
            duration("menstruation_period_hours", menstruationPeriodDuration, DurationUnit.HOURS, "hours")
        }
        quantity("planned_workout_count", data.plannedWorkouts.size.takeIf { it > 0 }, "count")
        quantity("medical_resource_count", data.medicalResources.resources.size.takeIf { it > 0 }, "count")
        // Workout native details remain gated by the v6 planner. Preserve existing reducer meanings.
        if (data.workouts.isNotEmpty()) {
            quantity("workout_count", data.workouts.size, "count")
            quantity("workout_minutes", data.workouts.sumOf { it.duration.toDouble(DurationUnit.MINUTES) }, "minutes")
            quantity("workout_calories", data.workouts.mapNotNull { it.calories }.sum().takeIf { it > 0 }, "kcal")
            quantity("workout_distance_km", data.workouts.mapNotNull { it.distance }.sum().takeIf { it > 0 }, "m")
            quantity("workout_avg_heart_rate", data.workouts.weightedAverage { it.averageHeartRate }, "bpm")
            quantity("workout_max_heart_rate", data.workouts.mapNotNull { it.heartRateMax }.maxOrNull(), "bpm")
            quantity("workout_min_heart_rate", data.workouts.mapNotNull { it.heartRateMin }.minOrNull(), "bpm")
            quantity("workout_avg_power", data.workouts.weightedAverage { it.powerAvg }, "W")
            quantity("workout_max_power", data.workouts.mapNotNull { it.powerMax }.maxOrNull(), "W")
            quantity("workout_running_cadence", data.workouts.filter { it.workoutType == com.healthmd.domain.model.WorkoutType.RUNNING }.weightedAverage { it.stepsCadenceAvg }, "spm")
            quantity("workout_cycling_cadence", data.workouts.filter { it.workoutType == com.healthmd.domain.model.WorkoutType.CYCLING }.weightedAverage { it.cyclingCadenceAvg }, "rpm")
        }
    }

    private fun List<com.healthmd.domain.model.WorkoutData>.weightedAverage(value: (com.healthmd.domain.model.WorkoutData) -> Double?): Double? {
        var totalWeight = 0.0
        var weightedSum = 0.0
        for (workout in this) {
            val sample = value(workout) ?: continue
            val weight = workout.duration.inWholeSeconds.toDouble()
            if (weight <= 0.0) continue
            totalWeight += weight
            weightedSum += sample * weight
        }
        return if (totalWeight > 0.0) weightedSum / totalWeight else null
    }
}
