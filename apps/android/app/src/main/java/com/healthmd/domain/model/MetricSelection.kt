package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class HealthMetricCategory {
    SLEEP,
    ACTIVITY,
    HEART,
    RESPIRATORY,
    VITALS,
    BODY,
    NUTRITION,
    MOBILITY,
    HEARING,
    MINDFULNESS,
    REPRODUCTIVE,
    SYMPTOMS,
    WORKOUTS,
}

@Serializable
data class HealthMetricDefinition(
    val id: String,
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
    HealthMetricDefinition("sleep_total", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_deep", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_rem", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_light", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_awake", HealthMetricCategory.SLEEP, "hours"),
    HealthMetricDefinition("sleep_in_bed", HealthMetricCategory.SLEEP, "hours"),
    // Activity
    HealthMetricDefinition("steps", HealthMetricCategory.ACTIVITY, "steps"),
    HealthMetricDefinition("active_calories", HealthMetricCategory.ACTIVITY, "kcal"),
    HealthMetricDefinition("total_calories", HealthMetricCategory.ACTIVITY, "kcal"),
    HealthMetricDefinition("basal_calories", HealthMetricCategory.ACTIVITY, "kcal"),
    HealthMetricDefinition("exercise_minutes", HealthMetricCategory.ACTIVITY, "min"),
    HealthMetricDefinition("flights_climbed", HealthMetricCategory.ACTIVITY, "floors"),
    HealthMetricDefinition("distance", HealthMetricCategory.ACTIVITY, "km"),
    HealthMetricDefinition("cycling_distance", HealthMetricCategory.ACTIVITY, "km"),
    HealthMetricDefinition("elevation_gained", HealthMetricCategory.ACTIVITY, "m"),
    HealthMetricDefinition("wheelchair_pushes", HealthMetricCategory.ACTIVITY, "count"),
    HealthMetricDefinition("swimming_distance", HealthMetricCategory.ACTIVITY, "m"),
    HealthMetricDefinition("swimming_strokes", HealthMetricCategory.ACTIVITY, "count"),
    HealthMetricDefinition("wheelchair_distance", HealthMetricCategory.ACTIVITY, "km"),
    HealthMetricDefinition("downhill_snow_distance", HealthMetricCategory.ACTIVITY, "km"),
    // Heart
    HealthMetricDefinition("resting_hr", HealthMetricCategory.HEART, "bpm"),
    HealthMetricDefinition("avg_hr", HealthMetricCategory.HEART, "bpm"),
    HealthMetricDefinition("walking_hr", HealthMetricCategory.HEART, "bpm"),
    HealthMetricDefinition("min_hr", HealthMetricCategory.HEART, "bpm"),
    HealthMetricDefinition("max_hr", HealthMetricCategory.HEART, "bpm"),
    HealthMetricDefinition("hrv", HealthMetricCategory.HEART, "ms"),
    // Respiratory
    HealthMetricDefinition("respiratory_rate", HealthMetricCategory.RESPIRATORY, "bpm"),
    HealthMetricDefinition("blood_oxygen", HealthMetricCategory.RESPIRATORY, "%"),
    // Vitals
    HealthMetricDefinition("body_temp", HealthMetricCategory.VITALS, "\u00B0"),
    HealthMetricDefinition("bp_systolic", HealthMetricCategory.VITALS, "mmHg"),
    HealthMetricDefinition("bp_diastolic", HealthMetricCategory.VITALS, "mmHg"),
    HealthMetricDefinition("blood_glucose", HealthMetricCategory.VITALS, "mg/dL"),
    HealthMetricDefinition("basal_body_temp", HealthMetricCategory.VITALS, "\u00B0"),
    HealthMetricDefinition("skin_temperature", HealthMetricCategory.VITALS, "\u00B0"),
    // Body
    HealthMetricDefinition("weight", HealthMetricCategory.BODY, "kg"),
    HealthMetricDefinition("height", HealthMetricCategory.BODY, "m"),
    HealthMetricDefinition("bmi", HealthMetricCategory.BODY, ""),
    HealthMetricDefinition("body_fat", HealthMetricCategory.BODY, "%"),
    HealthMetricDefinition("lean_mass", HealthMetricCategory.BODY, "kg"),
    HealthMetricDefinition("body_water_mass", HealthMetricCategory.BODY, "kg"),
    HealthMetricDefinition("bone_mass", HealthMetricCategory.BODY, "kg"),
    // Nutrition
    HealthMetricDefinition("dietary_energy", HealthMetricCategory.NUTRITION, "kcal"),
    HealthMetricDefinition("protein", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("carbs", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("fat", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("saturated_fat", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("monounsaturated_fat", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("polyunsaturated_fat", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("unsaturated_fat", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("trans_fat", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("fiber", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("sugar", HealthMetricCategory.NUTRITION, "g"),
    HealthMetricDefinition("sodium", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("potassium", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("calcium", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("iron", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("magnesium", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("zinc", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("phosphorus", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("iodine", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("selenium", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("copper", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("manganese", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("chromium", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("molybdenum", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("chloride", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("vitamin_a", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("vitamin_b6", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("vitamin_b12", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("vitamin_c", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("vitamin_d", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("vitamin_e", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("vitamin_k", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("thiamin", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("riboflavin", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("niacin", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("folate", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("folic_acid", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("pantothenic_acid", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("biotin", HealthMetricCategory.NUTRITION, "mcg"),
    HealthMetricDefinition("cholesterol", HealthMetricCategory.NUTRITION, "mg"),
    HealthMetricDefinition("water", HealthMetricCategory.NUTRITION, "L"),
    HealthMetricDefinition("caffeine", HealthMetricCategory.NUTRITION, "mg"),
    // Mobility
    HealthMetricDefinition("walking_speed", HealthMetricCategory.MOBILITY, "m/s"),
    HealthMetricDefinition("vo2_max", HealthMetricCategory.MOBILITY, "mL/kg/min"),
    HealthMetricDefinition("cycling_cadence", HealthMetricCategory.MOBILITY, "rpm"),
    HealthMetricDefinition("steps_cadence", HealthMetricCategory.MOBILITY, "steps/min"),
    HealthMetricDefinition("power_avg", HealthMetricCategory.MOBILITY, "W"),
    HealthMetricDefinition("power_max", HealthMetricCategory.MOBILITY, "W"),
    HealthMetricDefinition("running_speed", HealthMetricCategory.MOBILITY, "m/s"),
    HealthMetricDefinition("running_power", HealthMetricCategory.MOBILITY, "W"),
    // Hearing
    HealthMetricDefinition("audio_exposure", HealthMetricCategory.HEARING, "dB"),
    // Mindfulness
    HealthMetricDefinition("mindful_minutes", HealthMetricCategory.MINDFULNESS, "min"),
    // Reproductive Health
    HealthMetricDefinition("menstrual_flow", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("cervical_mucus", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("ovulation_test", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("sexual_activity", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("intermenstrual_bleeding", HealthMetricCategory.REPRODUCTIVE, ""),
    // Workouts
    HealthMetricDefinition("workouts", HealthMetricCategory.WORKOUTS, ""),
)

private val ALL_METRIC_IDS: Set<String> = ALL_METRICS.map { it.id }.toSet()
