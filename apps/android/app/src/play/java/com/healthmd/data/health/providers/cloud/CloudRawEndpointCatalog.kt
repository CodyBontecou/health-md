package com.healthmd.data.health.providers.cloud

import com.healthmd.rawexport.RawPaginationSupport
import com.healthmd.rawexport.RawProviderTypeDefinition
import com.healthmd.rawexport.RawRangeBehavior

internal object CloudRawMetrics {
    val sleep = setOf("sleep_total", "sleep_deep", "sleep_rem", "sleep_light", "sleep_awake", "sleep_in_bed")
    val activity = setOf(
        "steps", "active_calories", "total_calories", "basal_calories", "exercise_minutes",
        "flights_climbed", "distance", "cycling_distance", "elevation_gained", "wheelchair_pushes",
        "swimming_distance", "swimming_strokes", "wheelchair_distance", "downhill_snow_distance",
        "activity_intensity_minutes",
    )
    val heart = setOf("resting_hr", "avg_hr", "walking_hr", "min_hr", "max_hr", "hrv")
    val body = setOf("weight", "height", "bmi", "body_fat", "lean_mass", "body_water_mass", "bone_mass")
    val workouts = setOf("workouts", "planned_workouts")
    val respiratory = setOf("respiratory_rate", "blood_oxygen")
    val vitals = setOf("body_temp", "bp_systolic", "bp_diastolic", "blood_glucose", "basal_body_temp", "skin_temperature")
    val nutrition = setOf(
        "dietary_energy", "protein", "carbs", "fat", "saturated_fat", "monounsaturated_fat",
        "polyunsaturated_fat", "unsaturated_fat", "trans_fat", "fiber", "sugar", "sodium",
        "potassium", "calcium", "iron", "magnesium", "zinc", "phosphorus", "iodine", "selenium",
        "copper", "manganese", "chromium", "molybdenum", "chloride", "vitamin_a", "vitamin_b6",
        "vitamin_b12", "vitamin_c", "vitamin_d", "vitamin_e", "vitamin_k", "thiamin",
        "riboflavin", "niacin", "folate", "folic_acid", "pantothenic_acid", "biotin",
        "cholesterol", "water", "caffeine", "energy_from_fat", "nutrition_meals",
    )
    val mobility = setOf(
        "walking_speed", "vo2_max", "cycling_cadence", "steps_cadence", "power_avg", "power_max",
        "running_speed", "running_power",
    )
    val reproductive = setOf(
        "menstrual_flow", "cervical_mucus", "ovulation_test", "sexual_activity",
        "intermenstrual_bleeding", "menstruation_periods", "menstruation_period_days",
    )
    val otherKnown = setOf("medical_resources", "mindful_minutes", "mindful_sessions")

    fun endpoint(
        providerId: String,
        key: String,
        metrics: Set<String>,
        pagination: RawPaginationSupport = RawPaginationSupport.NONE,
        serverAggregation: Boolean = false,
    ) = RawProviderTypeDefinition(
        typeKey = key,
        wireType = "provider_payload",
        providerId = providerId,
        rangeBehavior = RawRangeBehavior.OVERLAP,
        metricIds = metrics,
        pagination = pagination,
        serverAggregation = serverAggregation,
    )

    fun unsupported(providerId: String, covered: Set<String>): List<RawProviderTypeDefinition> {
        val categories = listOf(
            "sleep" to sleep,
            "activity" to activity,
            "heart" to heart,
            "body" to body,
            "workouts" to workouts,
            "respiratory" to respiratory,
            "vitals" to vitals,
            "nutrition" to nutrition,
            "mobility" to mobility,
            "reproductive" to reproductive,
            "other" to otherKnown,
        )
        return categories.mapNotNull { (category, metrics) ->
            val missing = metrics - covered
            missing.takeIf { it.isNotEmpty() }?.let {
                endpoint(providerId, "unsupported/$category", it)
            }
        }
    }
}
