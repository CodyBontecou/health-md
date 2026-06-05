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

@Serializable
data class UnavailableHealthMetricDefinition(
    val id: String,
    val category: HealthMetricCategory,
    val displayName: String,
    val reason: String,
)

object HealthMetrics {
    val allMetrics: List<HealthMetricDefinition> = ALL_METRICS
    val unavailableMetrics: List<UnavailableHealthMetricDefinition> = UNAVAILABLE_METRICS
    val categories: List<HealthMetricCategory> = ALL_METRICS.map { it.category }.distinct()
    val totalCount: Int get() = ALL_METRICS.size
    val unavailableCount: Int get() = UNAVAILABLE_METRICS.size

    fun metricsForCategory(category: HealthMetricCategory): List<HealthMetricDefinition> =
        ALL_METRICS.filter { it.category == category }

    fun unavailableMetricsForCategory(category: HealthMetricCategory): List<UnavailableHealthMetricDefinition> =
        UNAVAILABLE_METRICS.filter { it.category == category }
}

@Serializable
data class MetricSelectionState(
    val enabledMetrics: Set<String> = ALL_METRIC_IDS,
) {
    val enabledCount: Int get() = enabledMetrics.count { it in ALL_METRIC_IDS }

    fun isEnabled(metricId: String): Boolean = metricId in ALL_METRIC_IDS && metricId in enabledMetrics
    fun isMetricEnabled(metricId: String): Boolean = isEnabled(metricId)

    fun toggle(metricId: String): MetricSelectionState {
        if (metricId !in ALL_METRIC_IDS) return this
        return if (metricId in enabledMetrics) copy(enabledMetrics = enabledMetrics - metricId)
        else copy(enabledMetrics = enabledMetrics + metricId)
    }

    fun toggleMetric(metricId: String): MetricSelectionState = toggle(metricId)

    fun enabledMetricCount(category: HealthMetricCategory): Int =
        ALL_METRICS.filter { it.category == category }.count { it.id in enabledMetrics }

    fun enabledCountForCategory(category: HealthMetricCategory): Int =
        enabledMetricCount(category)

    fun totalMetricCount(category: HealthMetricCategory): Int =
        ALL_METRICS.count { it.category == category }

    fun isCategoryFullyEnabled(category: HealthMetricCategory): Boolean {
        val total = totalMetricCount(category)
        return total > 0 && enabledMetricCount(category) == total
    }

    fun isCategoryPartiallyEnabled(category: HealthMetricCategory): Boolean {
        val total = totalMetricCount(category)
        val count = enabledMetricCount(category)
        return total > 0 && count > 0 && count < total
    }

    fun toggleCategory(category: HealthMetricCategory): MetricSelectionState {
        val categoryMetricIds = ALL_METRICS.filter { it.category == category }.map { it.id }.toSet()
        if (categoryMetricIds.isEmpty()) return this
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

private val UNAVAILABLE_METRICS: List<UnavailableHealthMetricDefinition> = listOf(
    // Phase 3: Apple-exclusive / HealthKit-only signals.
    UnavailableHealthMetricDefinition(
        "wrist_temperature",
        HealthMetricCategory.VITALS,
        "Wrist Temperature",
        "Apple Watch wrist-temperature hardware; Android exports Skin Temperature Delta when Health Connect provides it.",
    ),
    UnavailableHealthMetricDefinition(
        "electrodermal_activity",
        HealthMetricCategory.VITALS,
        "Electrodermal Activity",
        "Apple Watch sensor; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "heart_rate_recovery",
        HealthMetricCategory.HEART,
        "Heart Rate Recovery",
        "Apple Watch-derived metric; Health Connect does not expose a matching daily aggregate.",
    ),
    UnavailableHealthMetricDefinition(
        "afib_burden_percent",
        HealthMetricCategory.HEART,
        "AFib Burden",
        "Apple Watch-derived atrial fibrillation burden; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "state_of_mind_entries",
        HealthMetricCategory.MINDFULNESS,
        "State of Mind Entries",
        "HealthKit State of Mind is iOS 17+/Apple platform-specific and is not exposed by Health Connect.",
    ),
    UnavailableHealthMetricDefinition(
        "state_of_mind_count",
        HealthMetricCategory.MINDFULNESS,
        "State of Mind Count",
        "HealthKit State of Mind is iOS 17+/Apple platform-specific and is not exposed by Health Connect.",
    ),
    UnavailableHealthMetricDefinition(
        "average_valence",
        HealthMetricCategory.MINDFULNESS,
        "Average Mood Valence",
        "HealthKit mood valence is iOS 17+/Apple platform-specific and is not exposed by Health Connect.",
    ),
    UnavailableHealthMetricDefinition(
        "average_valence_percent",
        HealthMetricCategory.MINDFULNESS,
        "Average Mood Percent",
        "HealthKit mood valence is iOS 17+/Apple platform-specific and is not exposed by Health Connect.",
    ),
    UnavailableHealthMetricDefinition(
        "daily_mood_count",
        HealthMetricCategory.MINDFULNESS,
        "Daily Mood Count",
        "HealthKit State of Mind is iOS 17+/Apple platform-specific and is not exposed by Health Connect.",
    ),
    UnavailableHealthMetricDefinition(
        "average_daily_mood_valence",
        HealthMetricCategory.MINDFULNESS,
        "Average Daily Mood Valence",
        "HealthKit State of Mind is iOS 17+/Apple platform-specific and is not exposed by Health Connect.",
    ),
    UnavailableHealthMetricDefinition(
        "momentary_emotion_count",
        HealthMetricCategory.MINDFULNESS,
        "Momentary Emotion Count",
        "HealthKit State of Mind is iOS 17+/Apple platform-specific and is not exposed by Health Connect.",
    ),
    UnavailableHealthMetricDefinition(
        "forced_vital_capacity_l",
        HealthMetricCategory.RESPIRATORY,
        "Forced Vital Capacity",
        "No Health Connect 1.1.0-beta02 respiratory volume record equivalent.",
    ),
    UnavailableHealthMetricDefinition(
        "fev1_l",
        HealthMetricCategory.RESPIRATORY,
        "FEV1",
        "No Health Connect 1.1.0-beta02 spirometry record equivalent.",
    ),
    UnavailableHealthMetricDefinition(
        "peak_expiratory_flow",
        HealthMetricCategory.RESPIRATORY,
        "Peak Expiratory Flow",
        "No Health Connect 1.1.0-beta02 peak-flow record equivalent.",
    ),
    UnavailableHealthMetricDefinition(
        "inhaler_usage",
        HealthMetricCategory.RESPIRATORY,
        "Inhaler Usage",
        "No Health Connect 1.1.0-beta02 inhaler-use record equivalent.",
    ),

    // Phase 2 audit: Health Connect-unavailable iOS fields that should not be selectable as live metrics.
    UnavailableHealthMetricDefinition(
        "audio_exposure",
        HealthMetricCategory.HEARING,
        "Audio Exposure",
        "Health Connect 1.1.0-beta02 does not expose headphone or environmental audio exposure records.",
    ),
    UnavailableHealthMetricDefinition(
        "headphone_audio_db",
        HealthMetricCategory.HEARING,
        "Headphone Audio Level",
        "Health Connect 1.1.0-beta02 does not expose headphone audio exposure records.",
    ),
    UnavailableHealthMetricDefinition(
        "environmental_sound_db",
        HealthMetricCategory.HEARING,
        "Environmental Sound Level",
        "Health Connect 1.1.0-beta02 does not expose environmental sound exposure records.",
    ),
    UnavailableHealthMetricDefinition(
        "stand_hours",
        HealthMetricCategory.ACTIVITY,
        "Stand Hours",
        "Apple Stand Time has no Health Connect equivalent.",
    ),
    UnavailableHealthMetricDefinition(
        "move_minutes",
        HealthMetricCategory.ACTIVITY,
        "Move Minutes",
        "Health Connect has exercise/session duration but no Apple Move Minutes equivalent.",
    ),
    UnavailableHealthMetricDefinition(
        "physical_effort",
        HealthMetricCategory.ACTIVITY,
        "Physical Effort",
        "Health Connect 1.1.0-beta02 does not expose Apple's physical-effort metric.",
    ),
    UnavailableHealthMetricDefinition(
        "waist_circumference_cm",
        HealthMetricCategory.BODY,
        "Waist Circumference",
        "Health Connect 1.1.0-beta02 has no waist-circumference/body-measurement record.",
    ),
    UnavailableHealthMetricDefinition(
        "step_length_cm",
        HealthMetricCategory.MOBILITY,
        "Walking Step Length",
        "Health Connect 1.1.0-beta02 does not expose this walking-mobility metric.",
    ),
    UnavailableHealthMetricDefinition(
        "double_support_percent",
        HealthMetricCategory.MOBILITY,
        "Double Support Percentage",
        "Health Connect 1.1.0-beta02 does not expose this walking-mobility metric.",
    ),
    UnavailableHealthMetricDefinition(
        "walking_asymmetry_percent",
        HealthMetricCategory.MOBILITY,
        "Walking Asymmetry",
        "Health Connect 1.1.0-beta02 does not expose this walking-mobility metric.",
    ),
    UnavailableHealthMetricDefinition(
        "stair_ascent_speed",
        HealthMetricCategory.MOBILITY,
        "Stair Ascent Speed",
        "Health Connect 1.1.0-beta02 does not expose stair-speed metrics.",
    ),
    UnavailableHealthMetricDefinition(
        "stair_descent_speed",
        HealthMetricCategory.MOBILITY,
        "Stair Descent Speed",
        "Health Connect 1.1.0-beta02 does not expose stair-speed metrics.",
    ),
    UnavailableHealthMetricDefinition(
        "six_min_walk_m",
        HealthMetricCategory.MOBILITY,
        "Six-Minute Walk Distance",
        "Health Connect 1.1.0-beta02 does not expose a six-minute-walk metric.",
    ),
    UnavailableHealthMetricDefinition(
        "walking_steadiness_percent",
        HealthMetricCategory.MOBILITY,
        "Walking Steadiness",
        "Health Connect 1.1.0-beta02 does not expose walking steadiness.",
    ),
    UnavailableHealthMetricDefinition(
        "running_stride_length_m",
        HealthMetricCategory.MOBILITY,
        "Running Stride Length",
        "Health Connect 1.1.0-beta02 does not expose this running-dynamics metric.",
    ),
    UnavailableHealthMetricDefinition(
        "running_ground_contact_ms",
        HealthMetricCategory.MOBILITY,
        "Running Ground Contact Time",
        "Health Connect 1.1.0-beta02 does not expose this running-dynamics metric.",
    ),
    UnavailableHealthMetricDefinition(
        "running_vertical_oscillation_cm",
        HealthMetricCategory.MOBILITY,
        "Running Vertical Oscillation",
        "Health Connect 1.1.0-beta02 does not expose this running-dynamics metric.",
    ),
    UnavailableHealthMetricDefinition(
        "symptoms",
        HealthMetricCategory.SYMPTOMS,
        "Symptoms",
        "Health Connect 1.1.0-beta02 does not expose symptom records comparable to HealthKit symptoms.",
    ),
)

private val ALL_METRIC_IDS: Set<String> = ALL_METRICS.map { it.id }.toSet()
