package com.healthmd.domain.onboarding

import com.healthmd.domain.model.HealthMetrics

/**
 * Onboarding metric packs. A pack is a user-facing bundle of existing metric IDs, so selecting
 * packs only writes the ordinary [com.healthmd.domain.model.MetricSelectionState]; exporters and
 * the full metric picker keep their meaning. Pack IDs are shared with iOS
 * (`sleep`, `activity`, `heart`, `body`, `mind`, `nutrition`, `cycle`).
 *
 * Android differences: HRV is Health Connect RMSSD (`hrv`), and Health Connect has no State of
 * Mind record, so Mind holds only mindfulness minutes and sessions. Packs never overlap, so the
 * selected metric count is the plain sum of pack sizes.
 */
enum class HealthPack(
    val id: String,
    val metricIds: List<String>,
    val selectedByDefault: Boolean,
) {
    SLEEP(
        "sleep",
        listOf(
            "sleep_total", "sleep_deep", "sleep_rem", "sleep_light", "sleep_awake", "sleep_in_bed",
            "hrv", "resting_hr", "respiratory_rate", "skin_temperature",
        ),
        selectedByDefault = true,
    ),
    ACTIVITY(
        "activity",
        listOf(
            "steps", "active_calories", "total_calories", "exercise_minutes", "flights_climbed",
            "distance", "cycling_distance", "elevation_gained", "activity_intensity_minutes", "workouts",
        ),
        selectedByDefault = true,
    ),
    HEART(
        "heart",
        listOf("avg_hr", "min_hr", "max_hr", "walking_hr", "blood_oxygen", "bp_systolic", "bp_diastolic"),
        selectedByDefault = true,
    ),
    BODY("body", listOf("weight", "height", "bmi", "body_fat", "lean_mass"), selectedByDefault = false),
    MIND("mind", listOf("mindful_minutes", "mindful_sessions"), selectedByDefault = false),
    NUTRITION(
        "nutrition",
        listOf("dietary_energy", "protein", "carbs", "fat", "fiber", "sugar", "water", "caffeine"),
        selectedByDefault = false,
    ),

    /** Sensitive data: never selected by default. */
    CYCLE(
        "cycle",
        listOf(
            "menstrual_flow", "menstruation_periods", "menstruation_period_days",
            "ovulation_test", "cervical_mucus", "intermenstrual_bleeding",
        ),
        selectedByDefault = false,
    ),
    ;

    val metricCount: Int get() = metricIds.size

    companion object {
        val defaults: Set<HealthPack> = entries.filter { it.selectedByDefault }.toSet()

        fun fromId(id: String): HealthPack? = entries.firstOrNull { it.id == id }

        /** Union of the packs' metric IDs, restricted to metrics this build can export. */
        fun metricIds(packs: Set<HealthPack>): Set<String> {
            val known = HealthMetrics.allMetrics.mapTo(HashSet()) { it.id }
            return packs.flatMapTo(sortedSetOf()) { it.metricIds }.filterTo(sortedSetOf()) { it in known }
        }

        fun metricCount(packs: Set<HealthPack>): Int = metricIds(packs).size

        /** Packs whose metrics are all enabled in an existing selection (used when replaying setup). */
        fun fullySelectedIn(enabledMetrics: Set<String>): Set<HealthPack> =
            entries.filter { pack -> pack.metricIds.all { it in enabledMetrics } }.toSet()
    }
}
