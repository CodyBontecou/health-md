package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class HealthMetricCategory(val displayName: String) {
    SLEEP("Sleep"),
    ACTIVITY("Activity"),
    HEART("Heart"),
    RESPIRATORY("Respiratory"),
    VITALS("Vitals"),
    BODY("Body Measurements"),
    NUTRITION("Nutrition"),
    MOBILITY("Mobility"),
    HEARING("Hearing"),
    MINDFULNESS("Mindfulness"),
    REPRODUCTIVE("Reproductive Health"),
    SYMPTOMS("Symptoms"),
    WORKOUTS("Workouts"),
}

@Serializable
data class HealthMetricDefinition(
    val id: String,
    val name: String,
    val category: HealthMetricCategory,
    val unit: String,
)

object HealthMetrics {
    val allMetrics: List<HealthMetricDefinition> = ALL_METRICS
    val categories: List<HealthMetricCategory> = HealthMetricCategory.entries.toList()
    val totalCount: Int get() = ALL_METRICS.size

    fun metricsForCategory(category: HealthMetricCategory): List<HealthMetricDefinition> =
        ALL_METRICS.filter { it.category == category }
}

@Serializable
data class MetricSelectionState(
    val enabledMetrics: Set<String> = ALL_METRIC_IDS,
) {
    val enabledCount: Int get() = enabledMetrics.size

    fun isEnabled(metricId: String): Boolean = metricId in enabledMetrics
    fun isMetricEnabled(metricId: String): Boolean = metricId in enabledMetrics

    fun toggle(metricId: String): MetricSelectionState =
        if (metricId in enabledMetrics) copy(enabledMetrics = enabledMetrics - metricId)
        else copy(enabledMetrics = enabledMetrics + metricId)

    fun toggleMetric(metricId: String): MetricSelectionState = toggle(metricId)

    fun enabledMetricCount(category: HealthMetricCategory): Int =
        ALL_METRICS.filter { it.category == category }.count { it.id in enabledMetrics }

    fun enabledCountForCategory(category: HealthMetricCategory): Int =
        enabledMetricCount(category)

    fun totalMetricCount(category: HealthMetricCategory): Int =
        ALL_METRICS.count { it.category == category }

    fun isCategoryFullyEnabled(category: HealthMetricCategory): Boolean =
        enabledMetricCount(category) == totalMetricCount(category)

    fun isCategoryPartiallyEnabled(category: HealthMetricCategory): Boolean {
        val count = enabledMetricCount(category)
        return count > 0 && count < totalMetricCount(category)
    }

    fun toggleCategory(category: HealthMetricCategory): MetricSelectionState {
        val categoryMetricIds = ALL_METRICS.filter { it.category == category }.map { it.id }.toSet()
        return if (isCategoryFullyEnabled(category)) {
            copy(enabledMetrics = enabledMetrics - categoryMetricIds)
        } else {
            copy(enabledMetrics = enabledMetrics + categoryMetricIds)
        }
    }

    fun enableAll(): MetricSelectionState = copy(enabledMetrics = ALL_METRIC_IDS)
    fun selectAll(): MetricSelectionState = enableAll()
    fun disableAll(): MetricSelectionState = copy(enabledMetrics = emptySet())
    fun deselectAll(): MetricSelectionState = disableAll()
}

private val ALL_METRICS: List<HealthMetricDefinition> = listOf(
    // Sleep
    HealthMetricDefinition("sleep_total", "Total Sleep", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_deep", "Deep Sleep", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_rem", "REM Sleep", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_light", "Light Sleep", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_awake", "Awake Time", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_in_bed", "In Bed Time", HealthMetricCategory.SLEEP, "hours"),
    // Activity
    HealthMetricDefinition("steps", "Steps", HealthMetricCategory.ACTIVITY, "steps"),
    HealthMetricDefinition("active_calories", "Active Calories", HealthMetricCategory.ACTIVITY, "kcal"),
    HealthMetricDefinition("total_calories", "Total Calories", HealthMetricCategory.ACTIVITY, "kcal"),
    HealthMetricDefinition("basal_calories", "Basal Calories", HealthMetricCategory.ACTIVITY, "kcal"),
    HealthMetricDefinition("exercise_minutes", "Exercise Minutes", HealthMetricCategory.ACTIVITY, "min"),
    HealthMetricDefinition("flights_climbed", "Floors Climbed", HealthMetricCategory.ACTIVITY, "floors"),
    HealthMetricDefinition("distance", "Distance", HealthMetricCategory.ACTIVITY, "km"),
    HealthMetricDefinition("cycling_distance", "Cycling Distance", HealthMetricCategory.ACTIVITY, "km"),
    HealthMetricDefinition("elevation_gained", "Elevation Gained", HealthMetricCategory.ACTIVITY, "m"),
    HealthMetricDefinition("wheelchair_pushes", "Wheelchair Pushes", HealthMetricCategory.ACTIVITY, "count"),
    // Heart
    HealthMetricDefinition("resting_hr", "Resting Heart Rate", HealthMetricCategory.HEART, "bpm"),
    HealthMetricDefinition("avg_hr", "Average Heart Rate", HealthMetricCategory.HEART, "bpm"),
    HealthMetricDefinition("min_hr", "Min Heart Rate", HealthMetricCategory.HEART, "bpm"),
    HealthMetricDefinition("max_hr", "Max Heart Rate", HealthMetricCategory.HEART, "bpm"),
    HealthMetricDefinition("hrv", "HRV (RMSSD)", HealthMetricCategory.HEART, "ms"),
    // Respiratory
    HealthMetricDefinition("respiratory_rate", "Respiratory Rate", HealthMetricCategory.RESPIRATORY, "bpm"),
    HealthMetricDefinition("blood_oxygen", "Blood Oxygen", HealthMetricCategory.RESPIRATORY, "%"),
    // Vitals
    HealthMetricDefinition("body_temp", "Body Temperature", HealthMetricCategory.VITALS, "\u00B0"),
    HealthMetricDefinition("bp_systolic", "Blood Pressure (Systolic)", HealthMetricCategory.VITALS, "mmHg"),
    HealthMetricDefinition("bp_diastolic", "Blood Pressure (Diastolic)", HealthMetricCategory.VITALS, "mmHg"),
    HealthMetricDefinition("blood_glucose", "Blood Glucose", HealthMetricCategory.VITALS, "mg/dL"),
    HealthMetricDefinition("basal_body_temp", "Basal Body Temperature", HealthMetricCategory.VITALS, "\u00B0"),
    HealthMetricDefinition("skin_temperature", "Skin Temperature Delta", HealthMetricCategory.VITALS, "\u00B0"),
    // Body
    HealthMetricDefinition("weight", "Weight", HealthMetricCategory.BODY, "kg"),
    HealthMetricDefinition("height", "Height", HealthMetricCategory.BODY, "m"),
    HealthMetricDefinition("bmi", "BMI", HealthMetricCategory.BODY, ""),
    HealthMetricDefinition("body_fat", "Body Fat", HealthMetricCategory.BODY, "%"),
    HealthMetricDefinition("lean_mass", "Lean Body Mass", HealthMetricCategory.BODY, "kg"),
    HealthMetricDefinition("body_water_mass", "Body Water Mass", HealthMetricCategory.BODY, "kg"),
    HealthMetricDefinition("bone_mass", "Bone Mass", HealthMetricCategory.BODY, "kg"),
    // Nutrition
    HealthMetricDefinition("dietary_energy", "Dietary Energy", HealthMetricCategory.NUTRITION, "kcal"),
    HealthMetricDefinition("protein", "Protein", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("carbs", "Carbohydrates", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("fat", "Fat", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("saturated_fat", "Saturated Fat", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("fiber", "Fiber", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("sugar", "Sugar", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("sodium", "Sodium", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("cholesterol", "Cholesterol", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("water", "Water", HealthMetricCategory.NUTRITION, "L"),
    HealthMetricDefinition("caffeine", "Caffeine", HealthMetricCategory.NUTRITION, "mg"),
    // Mobility
    HealthMetricDefinition("walking_speed", "Walking Speed", HealthMetricCategory.MOBILITY, "m/s"),
    HealthMetricDefinition("vo2_max", "VO2 Max", HealthMetricCategory.MOBILITY, "mL/kg/min"),
    HealthMetricDefinition("cycling_cadence", "Cycling Cadence", HealthMetricCategory.MOBILITY, "rpm"),
    HealthMetricDefinition("steps_cadence", "Steps Cadence", HealthMetricCategory.MOBILITY, "steps/min"),
    HealthMetricDefinition("power_avg", "Average Power", HealthMetricCategory.MOBILITY, "W"),
    HealthMetricDefinition("power_max", "Max Power", HealthMetricCategory.MOBILITY, "W"),
    // Hearing
    HealthMetricDefinition("audio_exposure", "Audio Exposure", HealthMetricCategory.HEARING, "dB"),
    // Mindfulness
    HealthMetricDefinition("mindful_minutes", "Mindful Minutes", HealthMetricCategory.MINDFULNESS, "min"),
    // Reproductive Health
    HealthMetricDefinition("menstrual_flow", "Menstrual Flow", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("cervical_mucus", "Cervical Mucus Quality", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("ovulation_test", "Ovulation Test", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("sexual_activity", "Sexual Activity", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("intermenstrual_bleeding", "Intermenstrual Bleeding", HealthMetricCategory.REPRODUCTIVE, ""),
    // Workouts
    HealthMetricDefinition("workouts", "Workouts", HealthMetricCategory.WORKOUTS, ""),
)

private val ALL_METRIC_IDS: Set<String> = ALL_METRICS.map { it.id }.toSet()
