package com.healthmd.domain.render

import com.healthmd.domain.model.HealthDataFields

/**
 * Format → Custom fields that own each "Morning ends" native Bases frontmatter block (#353).
 *
 * Native records stay in JSON, CSV and the Markdown body. A record's lines go into Bases
 * frontmatter only while at least one owning field is switched on (a blood pressure pair needs
 * both). Pinned to packages/contracts/sleep-attribution/v1/native-frontmatter-owners.json, which
 * Apple's WakeDateNativeFrontmatterOwners.swift is pinned to as well.
 */
internal object NativeFrontmatterOwners {
    val quantity: Map<String, List<String>> = mapOf(
        "heartRateSamples" to listOf("average_heart_rate", "heart_rate_min", "heart_rate_max"),
        "hrvSamples" to listOf("hrv_ms"),
        "bloodOxygenSamples" to listOf("blood_oxygen", "blood_oxygen_avg", "blood_oxygen_min", "blood_oxygen_max"),
        "bloodGlucoseSamples" to listOf("blood_glucose", "blood_glucose_avg", "blood_glucose_min", "blood_glucose_max"),
        "respiratoryRateSamples" to listOf("respiratory_rate", "respiratory_rate_avg", "respiratory_rate_min", "respiratory_rate_max"),
    )
    val correlation: List<String> = listOf("blood_pressure_systolic", "blood_pressure_diastolic")
    val sleepStage: Map<String, String> = mapOf(
        "deep" to "sleep_deep_hours", "rem" to "sleep_rem_hours", "light" to "sleep_light_hours",
        "awake" to "sleep_awake_hours", "wake" to "sleep_awake_hours", "sleeping" to "sleep_total_hours",
        "unknown" to "sleep_total_hours",
    )
    val sleepSession: List<String> = listOf("sleep_total_hours", "sleep_in_bed_hours")
    val mindfulness: List<String> = listOf("mindful_minutes", "mindful_sessions")
    val activity: Map<String, String> = mapOf("stepSamples" to "steps", "activityIntensity" to "activity_intensity_minutes")
    val plannedWorkouts: List<String> = listOf("planned_workout_count")
    val medicalResources: List<String> = listOf("medical_resource_count")
    val androidRecords: Map<String, List<String>> = mapOf(
        "bodyTemperatureSamples" to listOf("body_temperature", "body_temperature_avg", "body_temperature_min", "body_temperature_max"),
        "basalBodyTemperatureSamples" to listOf("basal_body_temperature"),
        "skinTemperatureDeltas" to listOf("skin_temperature_delta"),
        "meals" to listOf("nutrition_meal_count", "dietary_calories", "protein_g", "carbohydrates_g", "fat_g", "energy_from_fat_kcal"),
        "menstruationPeriods" to listOf("menstruation_period_count", "menstruation_period_days", "menstruation_period_hours"),
    )

    /** Every Workouts field owns the workout block: `workouts` and each `workout_*` key. */
    fun isWorkoutField(key: String): Boolean = key == "workouts" || key.startsWith("workout_")

    /** The Workouts fields Format → Custom lists. */
    val workoutFieldKeys: List<String> by lazy { HealthDataFields.allKeys.filter(::isWorkoutField) }

    /**
     * Each workout record holds every workout property (calories, heart rate, distance, …), so the
     * block shows only while *every* Workouts field is on (#465). A customized Workouts group writes
     * exactly the fields switched on and no record block with the others.
     */
    fun showsWorkouts(isEnabled: (String) -> Boolean): Boolean = workoutFieldKeys.all(isEnabled)
}
