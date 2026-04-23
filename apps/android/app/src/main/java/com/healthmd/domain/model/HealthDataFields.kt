package com.healthmd.domain.model

import kotlin.time.Duration

/**
 * A single resolved health metric ready for flat key-value export (frontmatter / Obsidian Bases).
 *
 * @param key   Canonical snake_case key — matches [FrontmatterConfiguration] keys.
 * @param value Formatted value (String or Int), or null when the metric was not recorded.
 * @param unit  Unit label for CSV/display use, e.g. "kcal", "bpm".
 */
data class HealthField(
    val key: String,
    val value: Any?,
    val unit: String = "",
)

/**
 * **Single source of truth** for all exportable health fields.
 *
 * - [allKeys] drives [FrontmatterConfiguration.defaultFields] so the registry is always complete.
 * - [extract] is called by every flat-key exporter (Markdown frontmatter, Obsidian Bases) instead
 *   of each exporter maintaining its own duplicated field block.
 *
 * Adding a new metric requires a change in exactly one place: add it here.
 *
 * iOS-parity changes (see docs/export-contract/android-ios-gap-matrix.md, §4 Tier-1):
 *   T1-06  `sleep_core_hours` alias (= sleep_light_hours; Health Connect "light" ≈ iOS "core")
 *   T1-07  vitals min/max variants for respiratory rate, blood oxygen, body temperature,
 *          blood pressure systolic/diastolic, blood glucose
 *   T1-14  `mindful_sessions`
 *   T1-02  `sleep_bedtime`, `sleep_wake` from sessionStart/sessionEnd or derived from stages
 */
object HealthDataFields {

    /**
     * Canonical list of all field keys in declaration order.
     * [FrontmatterConfiguration.defaultFields] is derived from this list — they cannot drift.
     */
    val allKeys: List<String> = listOf(
        // ── Sleep ──────────────────────────────────────────────────────────────────────────────
        "sleep_total_hours",
        "sleep_bedtime",         // T1-02: from sessionStart/derived from stages
        "sleep_wake",            // T1-02: from sessionEnd/derived from stages
        "sleep_deep_hours",
        "sleep_rem_hours",
        "sleep_core_hours",      // T1-06: iOS canonical key (= sleep_light_hours value)
        "sleep_light_hours",     // Android extra (Health Connect terminology)
        "sleep_awake_hours",
        "sleep_in_bed_hours",
        // ── Activity ───────────────────────────────────────────────────────────────────────────
        "steps",
        "active_calories",
        "total_calories",
        "basal_calories",
        "exercise_minutes",
        "flights_climbed",
        "walking_running_km",
        "cycling_km",
        "elevation_gained_m",
        "wheelchair_pushes",
        // ── Heart ──────────────────────────────────────────────────────────────────────────────
        "resting_heart_rate",
        "average_heart_rate",
        "heart_rate_min",
        "heart_rate_max",
        "hrv_ms",
        // ── Vitals (respiratory) ───────────────────────────────────────────────────────────────
        "respiratory_rate",          // iOS canonical (avg alias)
        "respiratory_rate_avg",      // T1-07
        "respiratory_rate_min",      // T1-07
        "respiratory_rate_max",      // T1-07
        "blood_oxygen",              // iOS canonical (avg alias)
        "blood_oxygen_avg",          // T1-07
        "blood_oxygen_min",          // T1-07
        "blood_oxygen_max",          // T1-07
        // ── Vitals (biometrics) ────────────────────────────────────────────────────────────────
        "body_temperature",          // iOS canonical (avg alias)
        "body_temperature_avg",      // T1-07
        "body_temperature_min",      // T1-07
        "body_temperature_max",      // T1-07
        "blood_pressure_systolic",   // iOS canonical (avg alias)
        "blood_pressure_systolic_avg",  // T1-07
        "blood_pressure_systolic_min",  // T1-07
        "blood_pressure_systolic_max",  // T1-07
        "blood_pressure_diastolic",  // iOS canonical (avg alias)
        "blood_pressure_diastolic_avg", // T1-07
        "blood_pressure_diastolic_min", // T1-07
        "blood_pressure_diastolic_max", // T1-07
        "blood_glucose",             // iOS canonical (avg alias)
        "blood_glucose_avg",         // T1-07
        "blood_glucose_min",         // T1-07
        "blood_glucose_max",         // T1-07
        "basal_body_temperature",
        "skin_temperature_delta",    // Android extra (Wear OS)
        // ── Body ───────────────────────────────────────────────────────────────────────────────
        "weight_kg",
        "height_m",
        "bmi",
        "body_fat_percent",
        "lean_body_mass_kg",
        "body_water_mass_kg",
        "bone_mass_kg",
        // ── Nutrition ──────────────────────────────────────────────────────────────────────────
        "dietary_calories",
        "protein_g",
        "carbohydrates_g",
        "fat_g",
        "saturated_fat_g",
        "fiber_g",
        "sugar_g",
        "sodium_mg",
        "cholesterol_mg",
        "water_l",
        "caffeine_mg",
        // ── Mobility ───────────────────────────────────────────────────────────────────────────
        "walking_speed",
        "vo2_max",
        "cycling_cadence",
        "steps_cadence",
        "power_avg",
        "power_max",
        // ── Reproductive Health ────────────────────────────────────────────────────────────────
        "menstrual_flow",
        "cervical_mucus_appearance",
        "cervical_mucus_sensation",
        "ovulation_test",
        "intermenstrual_bleeding",
        "sexual_activity",
        "protection_used",
        // ── Mindfulness ────────────────────────────────────────────────────────────────────────
        "mindful_minutes",
        "mindful_sessions",          // T1-14
        // ── Workouts (aggregated summary) ──────────────────────────────────────────────────────
        "workout_count",
        "workout_minutes",
        "workout_calories",
        "workout_distance_km",
        "workouts",
    )

    /**
     * Extracts all health fields from [data], formatting values and converting units via
     * [converter]. Timestamps (bedtime/wake) are formatted using [timeFormat].
     *
     * Fields whose underlying data was not recorded have [HealthField.value] == null;
     * exporters skip those via their own null-check.
     */
    fun extract(
        data: HealthData,
        converter: UnitConverter,
        timeFormat: TimeFormatPreference = TimeFormatPreference.HOUR_24,
    ): List<HealthField> = buildList {

        // ── Sleep ──────────────────────────────────────────────────────────────────────────────
        val s = data.sleep
        add(HealthField("sleep_total_hours", s.totalDuration.toHoursRounded(), "hours"))

        // T1-02: bedtime/wake from sessionStart/End or derived from stage boundaries
        val derivedStart = s.sessionStart
            ?: s.stages.minByOrNull { it.startTime }?.startTime
        val derivedEnd = s.sessionEnd
            ?: s.stages.maxByOrNull { it.endTime }?.endTime
        add(HealthField("sleep_bedtime", derivedStart?.let { timeFormat.format(it) }, "time"))
        add(HealthField("sleep_wake", derivedEnd?.let { timeFormat.format(it) }, "time"))

        add(HealthField("sleep_deep_hours", s.deepSleep.toHoursRounded(), "hours"))
        add(HealthField("sleep_rem_hours", s.remSleep.toHoursRounded(), "hours"))
        // T1-06: coreSleep alias — same value as lightSleep for visualization parity
        add(HealthField("sleep_core_hours", s.lightSleep.toHoursRounded(), "hours"))
        add(HealthField("sleep_light_hours", s.lightSleep.toHoursRounded(), "hours"))
        add(HealthField("sleep_awake_hours", s.awakeTime.toHoursRounded(), "hours"))
        add(HealthField("sleep_in_bed_hours", s.inBedTime.toHoursRounded(), "hours"))

        // ── Activity ───────────────────────────────────────────────────────────────────────────
        val a = data.activity
        add(HealthField("steps", a.steps, "count"))
        add(HealthField("active_calories", a.activeCalories?.toInt(), "kcal"))
        add(HealthField("total_calories", a.totalCalories?.toInt(), "kcal"))
        add(HealthField("basal_calories", a.basalEnergyBurned?.toInt(), "kcal"))
        add(HealthField("exercise_minutes", a.exerciseMinutes?.toInt(), "minutes"))
        add(HealthField("flights_climbed", a.flightsClimbed, "count"))
        add(HealthField("walking_running_km", a.walkingRunningDistance?.let { String.format("%.2f", it / 1000) }, "km"))
        add(HealthField("cycling_km", a.cyclingDistance?.let { String.format("%.2f", it / 1000) }, "km"))
        add(HealthField("elevation_gained_m", a.elevationGained?.let { String.format("%.1f", it) }, "m"))
        add(HealthField("wheelchair_pushes", a.wheelchairPushes, "count"))

        // ── Heart ──────────────────────────────────────────────────────────────────────────────
        val h = data.heart
        add(HealthField("resting_heart_rate", h.restingHeartRate?.toInt(), "bpm"))
        add(HealthField("average_heart_rate", h.averageHeartRate?.toInt(), "bpm"))
        add(HealthField("heart_rate_min", h.heartRateMin?.toInt(), "bpm"))
        add(HealthField("heart_rate_max", h.heartRateMax?.toInt(), "bpm"))
        add(HealthField("hrv_ms", h.hrv?.let { String.format("%.1f", it) }, "ms"))

        // ── Vitals (respiratory) ───────────────────────────────────────────────────────────────
        val v = data.vitals
        // iOS canonical key is `respiratory_rate` (also `respiratory_rate_avg`); emit both
        add(HealthField("respiratory_rate",
            v.respiratoryRateAvg?.let { String.format("%.1f", it) }, "breaths/min"))
        add(HealthField("respiratory_rate_avg",
            v.respiratoryRateAvg?.let { String.format("%.1f", it) }, "breaths/min"))  // T1-07
        add(HealthField("respiratory_rate_min",
            v.respiratoryRateMin?.let { String.format("%.1f", it) }, "breaths/min"))  // T1-07
        add(HealthField("respiratory_rate_max",
            v.respiratoryRateMax?.let { String.format("%.1f", it) }, "breaths/min"))  // T1-07

        // Blood oxygen stored as fraction (0-1); emit as whole-number percent for frontmatter
        add(HealthField("blood_oxygen",
            v.bloodOxygenAvg?.let { "${(it * 100).toInt()}" }, "%"))
        add(HealthField("blood_oxygen_avg",
            v.bloodOxygenAvg?.let { "${(it * 100).toInt()}" }, "%"))                  // T1-07
        add(HealthField("blood_oxygen_min",
            v.bloodOxygenMin?.let { "${(it * 100).toInt()}" }, "%"))                  // T1-07
        add(HealthField("blood_oxygen_max",
            v.bloodOxygenMax?.let { "${(it * 100).toInt()}" }, "%"))                  // T1-07

        // ── Vitals (biometrics) ────────────────────────────────────────────────────────────────
        add(HealthField("body_temperature",
            v.bodyTemperatureAvg?.let { String.format("%.1f", converter.convertTemperature(it)) },
            converter.temperatureUnit()))
        add(HealthField("body_temperature_avg",                                        // T1-07
            v.bodyTemperatureAvg?.let { String.format("%.1f", converter.convertTemperature(it)) },
            converter.temperatureUnit()))
        add(HealthField("body_temperature_min",                                        // T1-07
            v.bodyTemperatureMin?.let { String.format("%.1f", converter.convertTemperature(it)) },
            converter.temperatureUnit()))
        add(HealthField("body_temperature_max",                                        // T1-07
            v.bodyTemperatureMax?.let { String.format("%.1f", converter.convertTemperature(it)) },
            converter.temperatureUnit()))

        add(HealthField("blood_pressure_systolic", v.bloodPressureSystolicAvg?.toInt(), "mmHg"))
        add(HealthField("blood_pressure_systolic_avg",                                 // T1-07
            v.bloodPressureSystolicAvg?.toInt(), "mmHg"))
        add(HealthField("blood_pressure_systolic_min",                                 // T1-07
            v.bloodPressureSystolicMin?.toInt(), "mmHg"))
        add(HealthField("blood_pressure_systolic_max",                                 // T1-07
            v.bloodPressureSystolicMax?.toInt(), "mmHg"))

        add(HealthField("blood_pressure_diastolic", v.bloodPressureDiastolicAvg?.toInt(), "mmHg"))
        add(HealthField("blood_pressure_diastolic_avg",                                // T1-07
            v.bloodPressureDiastolicAvg?.toInt(), "mmHg"))
        add(HealthField("blood_pressure_diastolic_min",                                // T1-07
            v.bloodPressureDiastolicMin?.toInt(), "mmHg"))
        add(HealthField("blood_pressure_diastolic_max",                                // T1-07
            v.bloodPressureDiastolicMax?.toInt(), "mmHg"))

        add(HealthField("blood_glucose",
            v.bloodGlucoseAvg?.let { String.format("%.1f", it) }, "mg/dL"))
        add(HealthField("blood_glucose_avg",                                           // T1-07
            v.bloodGlucoseAvg?.let { String.format("%.1f", it) }, "mg/dL"))
        add(HealthField("blood_glucose_min",                                           // T1-07
            v.bloodGlucoseMin?.let { String.format("%.1f", it) }, "mg/dL"))
        add(HealthField("blood_glucose_max",                                           // T1-07
            v.bloodGlucoseMax?.let { String.format("%.1f", it) }, "mg/dL"))

        add(HealthField("basal_body_temperature",
            v.basalBodyTemperature?.let { String.format("%.1f", converter.convertTemperature(it)) },
            converter.temperatureUnit()))
        add(HealthField("skin_temperature_delta",
            v.skinTemperatureDelta?.let { String.format("%.2f", it) }, "\u00B0C"))

        // ── Body ───────────────────────────────────────────────────────────────────────────────
        val b = data.body
        add(HealthField("weight_kg", b.weight?.let { String.format("%.1f", converter.convertWeight(it)) }, converter.weightUnit()))
        add(HealthField("height_m", b.height?.let { String.format("%.1f", converter.convertHeight(it)) }, converter.heightUnit()))
        add(HealthField("bmi", b.bmi?.let { String.format("%.1f", it) }, ""))
        add(HealthField("body_fat_percent", b.bodyFatPercentage?.let { String.format("%.1f", it * 100) }, "%"))
        add(HealthField("lean_body_mass_kg", b.leanBodyMass?.let { String.format("%.1f", converter.convertWeight(it)) }, converter.weightUnit()))
        add(HealthField("body_water_mass_kg", b.bodyWaterMass?.let { String.format("%.1f", converter.convertWeight(it)) }, converter.weightUnit()))
        add(HealthField("bone_mass_kg", b.boneMass?.let { String.format("%.1f", converter.convertWeight(it)) }, converter.weightUnit()))

        // ── Nutrition ──────────────────────────────────────────────────────────────────────────
        val n = data.nutrition
        add(HealthField("dietary_calories", n.dietaryEnergy?.toInt(), "kcal"))
        add(HealthField("protein_g", n.protein?.let { String.format("%.1f", it) }, "g"))
        add(HealthField("carbohydrates_g", n.carbohydrates?.let { String.format("%.1f", it) }, "g"))
        add(HealthField("fat_g", n.fat?.let { String.format("%.1f", it) }, "g"))
        add(HealthField("saturated_fat_g", n.saturatedFat?.let { String.format("%.1f", it) }, "g"))
        add(HealthField("fiber_g", n.fiber?.let { String.format("%.1f", it) }, "g"))
        add(HealthField("sugar_g", n.sugar?.let { String.format("%.1f", it) }, "g"))
        add(HealthField("sodium_mg", n.sodium?.toInt(), "mg"))
        add(HealthField("cholesterol_mg", n.cholesterol?.let { String.format("%.1f", it) }, "mg"))
        add(HealthField("water_l", n.water?.let { String.format("%.2f", converter.convertVolume(it)) }, converter.volumeUnit()))
        add(HealthField("caffeine_mg", n.caffeine?.let { String.format("%.1f", it) }, "mg"))

        // ── Mobility ───────────────────────────────────────────────────────────────────────────
        val m = data.mobility
        add(HealthField("walking_speed", m.walkingSpeed?.let { String.format("%.2f", it) }, "m/s"))
        add(HealthField("vo2_max", m.vo2Max?.let { String.format("%.1f", it) }, "mL/kg/min"))
        add(HealthField("cycling_cadence", m.cyclingCadenceAvg?.let { String.format("%.1f", it) }, "rpm"))
        add(HealthField("steps_cadence", m.stepsCadenceAvg?.let { String.format("%.1f", it) }, "steps/min"))
        add(HealthField("power_avg", m.powerAvg?.let { String.format("%.1f", it) }, "W"))
        add(HealthField("power_max", m.powerMax?.let { String.format("%.1f", it) }, "W"))

        // ── Reproductive Health ────────────────────────────────────────────────────────────────
        val r = data.reproductiveHealth
        add(HealthField("menstrual_flow", r.menstrualFlow, ""))
        add(HealthField("cervical_mucus_appearance", r.cervicalMucusAppearance, ""))
        add(HealthField("cervical_mucus_sensation", r.cervicalMucusSensation, ""))
        add(HealthField("ovulation_test", r.ovulationTestResult, ""))
        add(HealthField("intermenstrual_bleeding", if (r.intermenstrualBleeding) "true" else null, ""))
        add(HealthField("sexual_activity", if (r.sexualActivityRecorded) "true" else null, ""))
        add(HealthField("protection_used", if (r.sexualActivityRecorded) r.sexualActivityProtectionUsed else null, ""))

        // ── Mindfulness ────────────────────────────────────────────────────────────────────────
        add(HealthField("mindful_minutes", data.mindfulness.mindfulnessMinutes?.toInt(), "minutes"))
        add(HealthField("mindful_sessions", data.mindfulness.mindfulSessions, "sessions")) // T1-14

        // ── Workouts (aggregated) ──────────────────────────────────────────────────────────────
        if (data.workouts.isNotEmpty()) {
            add(HealthField("workout_count", data.workouts.size, "count"))
            add(HealthField("workout_minutes", data.workouts.sumOf { it.duration.inWholeMinutes }.toInt(), "minutes"))
            add(HealthField("workout_calories", data.workouts.mapNotNull { it.calories }.sum().takeIf { it > 0 }?.toInt(), "kcal"))
            add(HealthField("workout_distance_km", data.workouts.mapNotNull { it.distance }.sum().takeIf { it > 0 }?.let { String.format("%.2f", it / 1000) }, "km"))
            val types = data.workouts
                .map { it.workoutType.slug() }
                .distinct()
                .sorted()
            add(HealthField("workouts", "[${types.joinToString(", ")}]", ""))
        }
    }

    private fun Duration.toHoursRounded(): String? {
        if (this <= Duration.ZERO) return null
        return String.format("%.2f", this.inWholeMinutes / 60.0)
    }
}
