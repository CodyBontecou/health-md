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
    CYCLING,
    HEARING,
    MINDFULNESS,
    REPRODUCTIVE,
    SYMPTOMS,
    MEDICATIONS,
    OTHER,
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
    HealthMetricDefinition("activity_intensity_minutes", HealthMetricCategory.ACTIVITY, "min"),
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
    HealthMetricDefinition("energy_from_fat", HealthMetricCategory.NUTRITION, "kcal"),
    HealthMetricDefinition("nutrition_meals", HealthMetricCategory.NUTRITION, "count"),
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
    HealthMetricDefinition("mindful_sessions", HealthMetricCategory.MINDFULNESS, "count"),
    // Reproductive Health
    HealthMetricDefinition("menstrual_flow", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("cervical_mucus", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("ovulation_test", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("sexual_activity", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("intermenstrual_bleeding", HealthMetricCategory.REPRODUCTIVE, ""),
    HealthMetricDefinition("menstruation_periods", HealthMetricCategory.REPRODUCTIVE, "count"),
    HealthMetricDefinition("menstruation_period_days", HealthMetricCategory.REPRODUCTIVE, "days"),
    // Workouts
    HealthMetricDefinition("workouts", HealthMetricCategory.WORKOUTS, ""),
    HealthMetricDefinition("planned_workouts", HealthMetricCategory.WORKOUTS, ""),
    // Medical resources / PHR
    HealthMetricDefinition("medical_resources", HealthMetricCategory.MEDICATIONS, "count"),
)

private val UNAVAILABLE_METRICS: List<UnavailableHealthMetricDefinition> = listOf(
    // iOS parity ledger: Health Connect-unavailable signals.
    UnavailableHealthMetricDefinition(
        "wrist_temperature",
        HealthMetricCategory.VITALS,
        "Wrist Temperature",
        "Health Connect does not expose wrist-temperature records; Android exports Skin Temperature Delta when available.",
    ),
    UnavailableHealthMetricDefinition(
        "electrodermal_activity",
        HealthMetricCategory.VITALS,
        "Electrodermal Activity",
        "Health Connect does not expose electrodermal-activity records.",
    ),
    UnavailableHealthMetricDefinition(
        "heart_rate_recovery",
        HealthMetricCategory.HEART,
        "Heart Rate Recovery",
        "Health Connect does not expose a matching heart-rate recovery daily aggregate.",
    ),
    UnavailableHealthMetricDefinition(
        "afib_burden",
        HealthMetricCategory.HEART,
        "Atrial Fibrillation Burden",
        "Health Connect does not expose an atrial fibrillation burden record.",
    ),
    UnavailableHealthMetricDefinition(
        "state_of_mind_entries",
        HealthMetricCategory.MINDFULNESS,
        "Mood Entries",
        "Health Connect does not expose mood entry records.",
    ),
    UnavailableHealthMetricDefinition(
        "daily_mood",
        HealthMetricCategory.MINDFULNESS,
        "Daily Mood",
        "Health Connect does not expose mood entry records.",
    ),
    UnavailableHealthMetricDefinition(
        "average_valence",
        HealthMetricCategory.MINDFULNESS,
        "Average Mood Valence",
        "Health Connect does not expose mood valence records.",
    ),
    UnavailableHealthMetricDefinition(
        "momentary_emotions",
        HealthMetricCategory.MINDFULNESS,
        "Momentary Emotions",
        "Health Connect does not expose mood entry records.",
    ),
    UnavailableHealthMetricDefinition(
        "stand_time",
        HealthMetricCategory.ACTIVITY,
        "Stand Time",
        "Health Connect 1.1.0-beta02 has no stand-time equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "move_time",
        HealthMetricCategory.ACTIVITY,
        "Move Time",
        "Health Connect 1.1.0-beta02 has no move-time equivalent record; Android exports Exercise Minutes instead.",
    ),
    UnavailableHealthMetricDefinition(
        "physical_effort",
        HealthMetricCategory.ACTIVITY,
        "Physical Effort",
        "Health Connect 1.1.0-beta02 does not expose physical-effort records.",
    ),
    UnavailableHealthMetricDefinition(
        "forced_vital_capacity",
        HealthMetricCategory.RESPIRATORY,
        "Forced Vital Capacity",
        "Health Connect 1.1.0-beta02 has no respiratory volume record equivalent.",
    ),
    UnavailableHealthMetricDefinition(
        "fev1",
        HealthMetricCategory.RESPIRATORY,
        "Forced Expiratory Volume (FEV1)",
        "Health Connect 1.1.0-beta02 has no spirometry FEV1 record equivalent.",
    ),
    UnavailableHealthMetricDefinition(
        "peak_expiratory_flow",
        HealthMetricCategory.RESPIRATORY,
        "Peak Expiratory Flow Rate",
        "Health Connect 1.1.0-beta02 has no peak-flow record equivalent.",
    ),
    UnavailableHealthMetricDefinition(
        "inhaler_usage",
        HealthMetricCategory.RESPIRATORY,
        "Inhaler Usage",
        "Health Connect 1.1.0-beta02 has no inhaler-use record equivalent.",
    ),
    UnavailableHealthMetricDefinition(
        "waist_circumference",
        HealthMetricCategory.BODY,
        "Waist Circumference",
        "Health Connect 1.1.0-beta02 has no waist-circumference body-measurement record.",
    ),
    UnavailableHealthMetricDefinition(
        "walking_step_length",
        HealthMetricCategory.MOBILITY,
        "Walking Step Length",
        "Health Connect 1.1.0-beta02 does not expose this walking-mobility metric.",
    ),
    UnavailableHealthMetricDefinition(
        "walking_double_support",
        HealthMetricCategory.MOBILITY,
        "Double Support Time",
        "Health Connect 1.1.0-beta02 does not expose this walking-mobility metric.",
    ),
    UnavailableHealthMetricDefinition(
        "walking_asymmetry",
        HealthMetricCategory.MOBILITY,
        "Walking Asymmetry",
        "Health Connect 1.1.0-beta02 does not expose this walking-mobility metric.",
    ),
    UnavailableHealthMetricDefinition(
        "walking_steadiness",
        HealthMetricCategory.MOBILITY,
        "Walking Steadiness",
        "Health Connect 1.1.0-beta02 does not expose walking steadiness.",
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
        "six_minute_walk",
        HealthMetricCategory.MOBILITY,
        "Six-Minute Walk Distance",
        "Health Connect 1.1.0-beta02 does not expose a six-minute-walk metric.",
    ),
    UnavailableHealthMetricDefinition(
        "running_stride_length",
        HealthMetricCategory.MOBILITY,
        "Running Stride Length",
        "Health Connect 1.1.0-beta02 does not expose this running-dynamics metric.",
    ),
    UnavailableHealthMetricDefinition(
        "running_ground_contact",
        HealthMetricCategory.MOBILITY,
        "Running Ground Contact Time",
        "Health Connect 1.1.0-beta02 does not expose this running-dynamics metric.",
    ),
    UnavailableHealthMetricDefinition(
        "running_vertical_oscillation",
        HealthMetricCategory.MOBILITY,
        "Running Vertical Oscillation",
        "Health Connect 1.1.0-beta02 does not expose this running-dynamics metric.",
    ),
    UnavailableHealthMetricDefinition(
        "cycling_ftp",
        HealthMetricCategory.CYCLING,
        "Functional Threshold Power",
        "Health Connect 1.1.0-beta02 does not expose functional threshold power.",
    ),
    UnavailableHealthMetricDefinition(
        "headphone_audio",
        HealthMetricCategory.HEARING,
        "Headphone Audio Level",
        "Health Connect 1.1.0-beta02 does not expose headphone audio exposure records.",
    ),
    UnavailableHealthMetricDefinition(
        "environmental_audio",
        HealthMetricCategory.HEARING,
        "Environmental Sound Level",
        "Health Connect 1.1.0-beta02 does not expose environmental sound exposure records.",
    ),
    UnavailableHealthMetricDefinition(
        "medications",
        HealthMetricCategory.MEDICATIONS,
        "Medications",
        "Health Connect does not expose a medication dose-event catalog; feature-gated PHR medication FHIR resources export under medical_resources when available and granted.",
    ),
    UnavailableHealthMetricDefinition(
        "uv_exposure",
        HealthMetricCategory.OTHER,
        "UV Exposure",
        "Health Connect 1.1.0-beta02 does not expose UV exposure records.",
    ),
    UnavailableHealthMetricDefinition(
        "time_in_daylight",
        HealthMetricCategory.OTHER,
        "Time in Daylight",
        "Health Connect 1.1.0-beta02 does not expose time-in-daylight records.",
    ),
    UnavailableHealthMetricDefinition(
        "number_of_falls",
        HealthMetricCategory.OTHER,
        "Number of Falls",
        "Health Connect 1.1.0-beta02 does not expose fall-count records.",
    ),
    UnavailableHealthMetricDefinition(
        "blood_alcohol",
        HealthMetricCategory.OTHER,
        "Blood Alcohol Content",
        "Health Connect 1.1.0-beta02 does not expose blood-alcohol records.",
    ),
    UnavailableHealthMetricDefinition(
        "alcoholic_beverages",
        HealthMetricCategory.OTHER,
        "Alcoholic Beverages",
        "Health Connect 1.1.0-beta02 does not expose alcoholic-beverage count records.",
    ),
    UnavailableHealthMetricDefinition(
        "insulin_delivery",
        HealthMetricCategory.OTHER,
        "Insulin Delivery",
        "Health Connect 1.1.0-beta02 does not expose insulin-delivery records.",
    ),
    UnavailableHealthMetricDefinition(
        "toothbrushing",
        HealthMetricCategory.OTHER,
        "Toothbrushing",
        "Health Connect 1.1.0-beta02 does not expose toothbrushing event records.",
    ),
    UnavailableHealthMetricDefinition(
        "handwashing",
        HealthMetricCategory.OTHER,
        "Handwashing",
        "Health Connect 1.1.0-beta02 does not expose handwashing event records.",
    ),
    UnavailableHealthMetricDefinition(
        "water_temperature",
        HealthMetricCategory.OTHER,
        "Water Temperature",
        "Health Connect 1.1.0-beta02 does not expose water-temperature records.",
    ),
    UnavailableHealthMetricDefinition(
        "underwater_depth",
        HealthMetricCategory.OTHER,
        "Underwater Depth",
        "Health Connect 1.1.0-beta02 does not expose underwater-depth records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_headache",
        HealthMetricCategory.SYMPTOMS,
        "Headache",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_fatigue",
        HealthMetricCategory.SYMPTOMS,
        "Fatigue",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_nausea",
        HealthMetricCategory.SYMPTOMS,
        "Nausea",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_dizziness",
        HealthMetricCategory.SYMPTOMS,
        "Dizziness",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_mood_changes",
        HealthMetricCategory.SYMPTOMS,
        "Mood Changes",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_sleep_changes",
        HealthMetricCategory.SYMPTOMS,
        "Sleep Changes",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_appetite_changes",
        HealthMetricCategory.SYMPTOMS,
        "Appetite Changes",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_hot_flashes",
        HealthMetricCategory.SYMPTOMS,
        "Hot Flashes",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_chills",
        HealthMetricCategory.SYMPTOMS,
        "Chills",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_fever",
        HealthMetricCategory.SYMPTOMS,
        "Fever",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_lower_back_pain",
        HealthMetricCategory.SYMPTOMS,
        "Lower Back Pain",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_bloating",
        HealthMetricCategory.SYMPTOMS,
        "Bloating",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_constipation",
        HealthMetricCategory.SYMPTOMS,
        "Constipation",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_diarrhea",
        HealthMetricCategory.SYMPTOMS,
        "Diarrhea",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_heartburn",
        HealthMetricCategory.SYMPTOMS,
        "Heartburn",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_coughing",
        HealthMetricCategory.SYMPTOMS,
        "Coughing",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_sore_throat",
        HealthMetricCategory.SYMPTOMS,
        "Sore Throat",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_runny_nose",
        HealthMetricCategory.SYMPTOMS,
        "Runny Nose",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_shortness_of_breath",
        HealthMetricCategory.SYMPTOMS,
        "Shortness of Breath",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_chest_pain",
        HealthMetricCategory.SYMPTOMS,
        "Chest Tightness or Pain",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_skipped_heartbeat",
        HealthMetricCategory.SYMPTOMS,
        "Skipped Heartbeat",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_rapid_heartbeat",
        HealthMetricCategory.SYMPTOMS,
        "Rapid/Pounding Heartbeat",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_acne",
        HealthMetricCategory.SYMPTOMS,
        "Acne",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_dry_skin",
        HealthMetricCategory.SYMPTOMS,
        "Dry Skin",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_hair_loss",
        HealthMetricCategory.SYMPTOMS,
        "Hair Loss",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_memory_lapse",
        HealthMetricCategory.SYMPTOMS,
        "Memory Lapse",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_night_sweats",
        HealthMetricCategory.SYMPTOMS,
        "Night Sweats",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_vomiting",
        HealthMetricCategory.SYMPTOMS,
        "Vomiting",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_abdominal_cramps",
        HealthMetricCategory.SYMPTOMS,
        "Abdominal Cramps",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_breast_pain",
        HealthMetricCategory.SYMPTOMS,
        "Breast Pain",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_pelvic_pain",
        HealthMetricCategory.SYMPTOMS,
        "Pelvic Pain",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_body_ache",
        HealthMetricCategory.SYMPTOMS,
        "Generalized Body Ache",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_fainting",
        HealthMetricCategory.SYMPTOMS,
        "Fainting",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_loss_of_smell",
        HealthMetricCategory.SYMPTOMS,
        "Loss of Smell",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_loss_of_taste",
        HealthMetricCategory.SYMPTOMS,
        "Loss of Taste",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_wheezing",
        HealthMetricCategory.SYMPTOMS,
        "Wheezing",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_sinus_congestion",
        HealthMetricCategory.SYMPTOMS,
        "Sinus Congestion",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_bladder_incontinence",
        HealthMetricCategory.SYMPTOMS,
        "Bladder Incontinence",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),
    UnavailableHealthMetricDefinition(
        "symptom_vaginal_dryness",
        HealthMetricCategory.SYMPTOMS,
        "Vaginal Dryness",
        "Health Connect 1.1.0-beta02 does not expose symptom records.",
    ),

    // Backward-compatible aliases for stale persisted Android selector/export IDs.
    UnavailableHealthMetricDefinition(
        "audio_exposure",
        HealthMetricCategory.HEARING,
        "Audio Exposure",
        "Legacy Android aggregate selector; Health Connect 1.1.0-beta02 has no headphone or environmental audio exposure records.",
    ),
    UnavailableHealthMetricDefinition(
        "afib_burden_percent",
        HealthMetricCategory.HEART,
        "AFib Burden Percent",
        "Legacy Android export-contract alias for afib_burden; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "state_of_mind_count",
        HealthMetricCategory.MINDFULNESS,
        "Mood Entry Count",
        "Legacy Android alias for mood entries; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "average_valence_percent",
        HealthMetricCategory.MINDFULNESS,
        "Average Mood Percent",
        "Legacy Android alias for mood valence; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "daily_mood_count",
        HealthMetricCategory.MINDFULNESS,
        "Daily Mood Count",
        "Legacy Android alias for daily mood; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "average_daily_mood_valence",
        HealthMetricCategory.MINDFULNESS,
        "Average Daily Mood Valence",
        "Legacy Android alias for daily mood valence; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "momentary_emotion_count",
        HealthMetricCategory.MINDFULNESS,
        "Momentary Emotion Count",
        "Legacy Android alias for momentary emotions; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "forced_vital_capacity_l",
        HealthMetricCategory.RESPIRATORY,
        "Forced Vital Capacity",
        "Legacy Android export-contract alias for forced_vital_capacity; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "fev1_l",
        HealthMetricCategory.RESPIRATORY,
        "FEV1",
        "Legacy Android export-contract alias for fev1; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "headphone_audio_db",
        HealthMetricCategory.HEARING,
        "Headphone Audio Level",
        "Legacy Android export-contract alias for headphone_audio; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "environmental_sound_db",
        HealthMetricCategory.HEARING,
        "Environmental Sound Level",
        "Legacy Android export-contract alias for environmental_audio; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "stand_hours",
        HealthMetricCategory.ACTIVITY,
        "Stand Hours",
        "Legacy Android stand-time label; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "move_minutes",
        HealthMetricCategory.ACTIVITY,
        "Move Minutes",
        "Legacy Android move-time label; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "waist_circumference_cm",
        HealthMetricCategory.BODY,
        "Waist Circumference",
        "Legacy Android export-contract alias for waist_circumference; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "step_length_cm",
        HealthMetricCategory.MOBILITY,
        "Walking Step Length",
        "Legacy Android export-contract alias for walking_step_length; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "double_support_percent",
        HealthMetricCategory.MOBILITY,
        "Double Support Percentage",
        "Legacy Android export-contract alias for walking_double_support; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "walking_asymmetry_percent",
        HealthMetricCategory.MOBILITY,
        "Walking Asymmetry",
        "Legacy Android export-contract alias for walking_asymmetry; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "six_min_walk_m",
        HealthMetricCategory.MOBILITY,
        "Six-Minute Walk Distance",
        "Legacy Android export-contract alias for six_minute_walk; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "walking_steadiness_percent",
        HealthMetricCategory.MOBILITY,
        "Walking Steadiness",
        "Legacy Android export-contract alias for walking_steadiness; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "running_stride_length_m",
        HealthMetricCategory.MOBILITY,
        "Running Stride Length",
        "Legacy Android export-contract alias for running_stride_length; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "running_ground_contact_ms",
        HealthMetricCategory.MOBILITY,
        "Running Ground Contact Time",
        "Legacy Android export-contract alias for running_ground_contact; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "running_vertical_oscillation_cm",
        HealthMetricCategory.MOBILITY,
        "Running Vertical Oscillation",
        "Legacy Android export-contract alias for running_vertical_oscillation; Health Connect has no equivalent record.",
    ),
    UnavailableHealthMetricDefinition(
        "symptoms",
        HealthMetricCategory.SYMPTOMS,
        "Symptoms",
        "Legacy Android grouped symptom selector; Health Connect 1.1.0-beta02 has no per-symptom records.",
    ),
)

private val ALL_METRIC_IDS: Set<String> = ALL_METRICS.map { it.id }.toSet()
