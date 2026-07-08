package com.healthmd.domain.model

import java.util.Locale
import kotlin.math.roundToInt
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
        "cycling_cadence_rpm",   // iOS canonical cycling metric key
        "cycling_power_w",       // iOS canonical cycling metric key (best-effort from PowerRecord avg)
        "elevation_gained_m",
        "wheelchair_pushes",
        "swimming_m",
        "swimming_strokes",
        "wheelchair_km",
        "downhill_snow_km",
        "activity_intensity_minutes",
        "moderate_activity_minutes",
        "vigorous_activity_minutes",
        // ── Heart ──────────────────────────────────────────────────────────────────────────────
        "resting_heart_rate",
        "average_heart_rate",
        "walking_heart_rate",
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
        "monounsaturated_fat_g",
        "polyunsaturated_fat_g",
        "unsaturated_fat_g",
        "trans_fat_g",
        "fiber_g",
        "sugar_g",
        "sodium_mg",
        "potassium_mg",
        "calcium_mg",
        "iron_mg",
        "magnesium_mg",
        "zinc_mg",
        "phosphorus_mg",
        "iodine_ug",         // iOS canonical; micrograms
        "iodine_mcg",        // Android legacy alias
        "selenium_ug",       // iOS canonical; micrograms
        "selenium_mcg",      // Android legacy alias
        "copper_mg",
        "manganese_mg",
        "chromium_ug",       // iOS canonical; micrograms
        "chromium_mcg",      // Android legacy alias
        "molybdenum_ug",     // iOS canonical; micrograms
        "molybdenum_mcg",    // Android legacy alias
        "chloride_mg",
        "vitamin_a_ug",      // iOS canonical; micrograms
        "vitamin_a_mcg",     // Android legacy alias
        "vitamin_b6_mg",
        "vitamin_b12_ug",    // iOS canonical; micrograms
        "vitamin_b12_mcg",   // Android legacy alias
        "vitamin_c_mg",
        "vitamin_d_ug",      // iOS canonical; micrograms
        "vitamin_d_mcg",     // Android legacy alias
        "vitamin_e_mg",
        "vitamin_k_ug",      // iOS canonical; micrograms
        "vitamin_k_mcg",     // Android legacy alias
        "thiamin_mg",
        "riboflavin_mg",
        "niacin_mg",
        "folate_ug",         // iOS canonical; micrograms
        "folate_mcg",        // Android legacy alias
        "folic_acid_mcg",
        "pantothenic_acid_mg",
        "biotin_ug",         // iOS canonical; micrograms
        "biotin_mcg",        // Android legacy alias
        "cholesterol_mg",
        "water_l",
        "caffeine_mg",
        "energy_from_fat_kcal",
        "nutrition_meal_count",
        // ── Mobility ───────────────────────────────────────────────────────────────────────────
        "walking_speed",
        "vo2_max",
        "vo2_max_measurement_method",
        "cycling_cadence",
        "steps_cadence",
        "power_avg",
        "power_max",
        "running_speed",
        "running_power_w",      // iOS canonical running power key (= Android running_power_avg)
        "running_power_avg",
        "running_power_max",
        // ── Reproductive Health ────────────────────────────────────────────────────────────────
        "menstrual_flow",
        "cervical_mucus",       // iOS canonical key (best-effort from appearance/sensation)
        "cervical_mucus_appearance",
        "cervical_mucus_sensation",
        "ovulation_test",
        "intermenstrual_bleeding",
        "sexual_activity",
        "protection_used",
        "menstruation_period_count",
        "menstruation_period_days",
        "menstruation_period_hours",
        // ── Mindfulness ────────────────────────────────────────────────────────────────────────
        "mindful_minutes",
        "mindful_sessions",          // T1-14
        // ── Workouts (aggregated summary) ──────────────────────────────────────────────────────
        "workout_count",
        "planned_workout_count",
        "workout_minutes",
        "workout_calories",
        "workout_distance_km",
        "workout_avg_heart_rate",
        "workout_max_heart_rate",
        "workout_min_heart_rate",
        "workout_running_cadence",
        "workout_cycling_cadence",
        "workout_avg_power",
        "workout_max_power",
        "workouts",
        "medical_resource_count",
    )

    /** Android pre-parity aliases/extras that are hidden by default in the iOS-compatible contract. */
    private val androidCompatibilityKeys: Set<String> = setOf(
        "sleep_light_hours",
        "total_calories",
        "elevation_gained_m",
        "skin_temperature_delta",
        "body_water_mass_kg",
        "bone_mass_kg",
        "unsaturated_fat_g",
        "trans_fat_g",
        "iodine_mcg",
        "selenium_mcg",
        "chromium_mcg",
        "molybdenum_mcg",
        "vitamin_a_mcg",
        "vitamin_b12_mcg",
        "vitamin_d_mcg",
        "vitamin_k_mcg",
        "folate_mcg",
        "folic_acid_mcg",
        "biotin_mcg",
        "steps_cadence",
        "power_avg",
        "power_max",
        "running_power_avg",
        "running_power_max",
        "cervical_mucus_appearance",
        "cervical_mucus_sensation",
        "protection_used",
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
        includeAndroidCompatibilityKeys: Boolean = false,
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
        add(HealthField("walking_running_km", a.walkingRunningDistance?.let { String.format(Locale.US, "%.2f", it / 1000) }, "km"))
        add(HealthField("cycling_km", a.cyclingDistance?.let { String.format(Locale.US, "%.2f", it / 1000) }, "km"))
        // iOS cycling-performance flat keys. Android exposes cadence/power separately via MobilityData,
        // but the canonical iOS flat contract uses cycling_* names.
        add(HealthField("cycling_cadence_rpm", data.mobility.cyclingCadenceAvg?.let { String.format(Locale.US, "%.0f", it) }, "rpm"))
        add(HealthField("cycling_power_w", data.mobility.powerAvg?.let { String.format(Locale.US, "%.0f", it) }, "W"))
        add(HealthField("elevation_gained_m", a.elevationGained?.let { String.format(Locale.US, "%.1f", it) }, "m"))
        add(HealthField("wheelchair_pushes", a.wheelchairPushes, "count"))
        add(HealthField("swimming_m", a.swimmingDistance?.let { String.format(Locale.US, "%.1f", it) }, "m"))
        add(HealthField("swimming_strokes", a.swimmingStrokes, "count"))
        add(HealthField("wheelchair_km", a.wheelchairDistance?.let { String.format(Locale.US, "%.2f", it / 1000) }, "km"))
        add(HealthField("downhill_snow_km", a.downhillSnowSportsDistance?.let { String.format(Locale.US, "%.2f", it / 1000) }, "km"))
        add(HealthField("activity_intensity_minutes", a.activityIntensityMinutes, "minutes"))
        add(HealthField("moderate_activity_minutes", a.moderateActivityMinutes?.toInt(), "minutes"))
        add(HealthField("vigorous_activity_minutes", a.vigorousActivityMinutes?.toInt(), "minutes"))

        // ── Heart ──────────────────────────────────────────────────────────────────────────────
        val h = data.heart
        add(HealthField("resting_heart_rate", h.restingHeartRate?.toInt(), "bpm"))
        add(HealthField("average_heart_rate", h.averageHeartRate?.toInt(), "bpm"))
        add(HealthField("walking_heart_rate", h.walkingHeartRateAverage?.toInt(), "bpm"))
        add(HealthField("heart_rate_min", h.heartRateMin?.toInt(), "bpm"))
        add(HealthField("heart_rate_max", h.heartRateMax?.toInt(), "bpm"))
        add(HealthField("hrv_ms", h.hrv?.let { String.format(Locale.US, "%.1f", it) }, "ms"))

        // ── Vitals (respiratory) ───────────────────────────────────────────────────────────────
        val v = data.vitals
        // iOS canonical key is `respiratory_rate` (also `respiratory_rate_avg`); emit both
        add(HealthField("respiratory_rate",
            v.respiratoryRateAvg?.let { String.format(Locale.US, "%.1f", it) }, "breaths/min"))
        add(HealthField("respiratory_rate_avg",
            v.respiratoryRateAvg?.let { String.format(Locale.US, "%.1f", it) }, "breaths/min"))  // T1-07
        add(HealthField("respiratory_rate_min",
            v.respiratoryRateMin?.let { String.format(Locale.US, "%.1f", it) }, "breaths/min"))  // T1-07
        add(HealthField("respiratory_rate_max",
            v.respiratoryRateMax?.let { String.format(Locale.US, "%.1f", it) }, "breaths/min"))  // T1-07

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
            v.bodyTemperatureAvg?.let { String.format(Locale.US, "%.1f", converter.convertTemperature(it)) },
            converter.temperatureUnit()))
        add(HealthField("body_temperature_avg",                                        // T1-07
            v.bodyTemperatureAvg?.let { String.format(Locale.US, "%.1f", converter.convertTemperature(it)) },
            converter.temperatureUnit()))
        add(HealthField("body_temperature_min",                                        // T1-07
            v.bodyTemperatureMin?.let { String.format(Locale.US, "%.1f", converter.convertTemperature(it)) },
            converter.temperatureUnit()))
        add(HealthField("body_temperature_max",                                        // T1-07
            v.bodyTemperatureMax?.let { String.format(Locale.US, "%.1f", converter.convertTemperature(it)) },
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
            v.bloodGlucoseAvg?.let { String.format(Locale.US, "%.1f", it) }, "mg/dL"))
        add(HealthField("blood_glucose_avg",                                           // T1-07
            v.bloodGlucoseAvg?.let { String.format(Locale.US, "%.1f", it) }, "mg/dL"))
        add(HealthField("blood_glucose_min",                                           // T1-07
            v.bloodGlucoseMin?.let { String.format(Locale.US, "%.1f", it) }, "mg/dL"))
        add(HealthField("blood_glucose_max",                                           // T1-07
            v.bloodGlucoseMax?.let { String.format(Locale.US, "%.1f", it) }, "mg/dL"))

        add(HealthField("basal_body_temperature",
            v.basalBodyTemperature?.let { String.format(Locale.US, "%.1f", converter.convertTemperature(it)) },
            converter.temperatureUnit()))
        add(HealthField("skin_temperature_delta",
            v.skinTemperatureDelta?.let { String.format(Locale.US, "%.2f", it) }, "\u00B0C"))

        // ── Body ───────────────────────────────────────────────────────────────────────────────
        val b = data.body
        add(HealthField("weight_kg", b.weight?.let { String.format(Locale.US, "%.1f", converter.convertWeight(it)) }, converter.weightUnit()))
        add(HealthField("height_m", b.height?.let { String.format(Locale.US, "%.1f", converter.convertHeight(it)) }, converter.heightUnit()))
        add(HealthField("bmi", b.bmi?.let { String.format(Locale.US, "%.1f", it) }, ""))
        add(HealthField("body_fat_percent", b.bodyFatPercentage?.let { String.format(Locale.US, "%.1f", it * 100) }, "%"))
        add(HealthField("lean_body_mass_kg", b.leanBodyMass?.let { String.format(Locale.US, "%.1f", converter.convertWeight(it)) }, converter.weightUnit()))
        add(HealthField("body_water_mass_kg", b.bodyWaterMass?.let { String.format(Locale.US, "%.1f", converter.convertWeight(it)) }, converter.weightUnit()))
        add(HealthField("bone_mass_kg", b.boneMass?.let { String.format(Locale.US, "%.1f", converter.convertWeight(it)) }, converter.weightUnit()))

        // ── Nutrition ──────────────────────────────────────────────────────────────────────────
        val n = data.nutrition
        add(HealthField("dietary_calories", n.dietaryEnergy?.toInt(), "kcal"))
        add(HealthField("protein_g", n.protein?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("carbohydrates_g", n.carbohydrates?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("fat_g", n.fat?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("saturated_fat_g", n.saturatedFat?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("monounsaturated_fat_g", n.monounsaturatedFat?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("polyunsaturated_fat_g", n.polyunsaturatedFat?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("unsaturated_fat_g", n.unsaturatedFat?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("trans_fat_g", n.transFat?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("fiber_g", n.fiber?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("sugar_g", n.sugar?.let { String.format(Locale.US, "%.1f", it) }, "g"))
        add(HealthField("sodium_mg", n.sodium?.toInt(), "mg"))
        add(HealthField("potassium_mg", n.potassium?.toInt(), "mg"))
        add(HealthField("calcium_mg", n.calcium?.toInt(), "mg"))
        add(HealthField("iron_mg", n.iron?.let { String.format(Locale.US, "%.1f", it) }, "mg"))
        add(HealthField("magnesium_mg", n.magnesium?.toInt(), "mg"))
        add(HealthField("zinc_mg", n.zinc?.let { String.format(Locale.US, "%.1f", it) }, "mg"))
        add(HealthField("phosphorus_mg", n.phosphorus?.let { String.format(Locale.US, "%.1f", it) }, "mg"))
        add(HealthField("iodine_ug", n.iodine?.let { String.format(Locale.US, "%.1f", it) }, "µg"))
        add(HealthField("iodine_mcg", n.iodine?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("selenium_ug", n.selenium?.let { String.format(Locale.US, "%.1f", it) }, "µg"))
        add(HealthField("selenium_mcg", n.selenium?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("copper_mg", n.copper?.let { String.format(Locale.US, "%.3f", it) }, "mg"))
        add(HealthField("manganese_mg", n.manganese?.let { String.format(Locale.US, "%.2f", it) }, "mg"))
        add(HealthField("chromium_ug", n.chromium?.let { String.format(Locale.US, "%.1f", it) }, "µg"))
        add(HealthField("chromium_mcg", n.chromium?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("molybdenum_ug", n.molybdenum?.let { String.format(Locale.US, "%.1f", it) }, "µg"))
        add(HealthField("molybdenum_mcg", n.molybdenum?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("chloride_mg", n.chloride?.let { String.format(Locale.US, "%.1f", it) }, "mg"))
        add(HealthField("vitamin_a_ug", n.vitaminA?.let { String.format(Locale.US, "%.1f", it) }, "µg"))
        add(HealthField("vitamin_a_mcg", n.vitaminA?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("vitamin_b6_mg", n.vitaminB6?.let { String.format(Locale.US, "%.2f", it) }, "mg"))
        add(HealthField("vitamin_b12_ug", n.vitaminB12?.let { String.format(Locale.US, "%.2f", it) }, "µg"))
        add(HealthField("vitamin_b12_mcg", n.vitaminB12?.let { String.format(Locale.US, "%.2f", it) }, "mcg"))
        add(HealthField("vitamin_c_mg", n.vitaminC?.let { String.format(Locale.US, "%.1f", it) }, "mg"))
        add(HealthField("vitamin_d_ug", n.vitaminD?.let { String.format(Locale.US, "%.1f", it) }, "µg"))
        add(HealthField("vitamin_d_mcg", n.vitaminD?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("vitamin_e_mg", n.vitaminE?.let { String.format(Locale.US, "%.2f", it) }, "mg"))
        add(HealthField("vitamin_k_ug", n.vitaminK?.let { String.format(Locale.US, "%.1f", it) }, "µg"))
        add(HealthField("vitamin_k_mcg", n.vitaminK?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("thiamin_mg", n.thiamin?.let { String.format(Locale.US, "%.2f", it) }, "mg"))
        add(HealthField("riboflavin_mg", n.riboflavin?.let { String.format(Locale.US, "%.2f", it) }, "mg"))
        add(HealthField("niacin_mg", n.niacin?.let { String.format(Locale.US, "%.1f", it) }, "mg"))
        add(HealthField("folate_ug", n.folate?.let { String.format(Locale.US, "%.1f", it) }, "µg"))
        add(HealthField("folate_mcg", n.folate?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("folic_acid_mcg", n.folicAcid?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("pantothenic_acid_mg", n.pantothenicAcid?.let { String.format(Locale.US, "%.2f", it) }, "mg"))
        add(HealthField("biotin_ug", n.biotin?.let { String.format(Locale.US, "%.1f", it) }, "µg"))
        add(HealthField("biotin_mcg", n.biotin?.let { String.format(Locale.US, "%.1f", it) }, "mcg"))
        add(HealthField("cholesterol_mg", n.cholesterol?.let { String.format(Locale.US, "%.1f", it) }, "mg"))
        add(HealthField("water_l", n.water?.let { String.format(Locale.US, "%.2f", converter.convertVolume(it)) }, converter.volumeUnit()))
        add(HealthField("caffeine_mg", n.caffeine?.let { String.format(Locale.US, "%.1f", it) }, "mg"))
        add(HealthField("energy_from_fat_kcal", n.energyFromFat?.toInt(), "kcal"))
        add(HealthField("nutrition_meal_count", n.meals.size.takeIf { it > 0 }, "count"))

        // ── Mobility ───────────────────────────────────────────────────────────────────────────
        val m = data.mobility
        add(HealthField("walking_speed", m.walkingSpeed?.let { String.format(Locale.US, "%.2f", it) }, "m/s"))
        add(HealthField("vo2_max", m.vo2Max?.let { String.format(Locale.US, "%.1f", it) }, "mL/kg/min"))
        add(HealthField("vo2_max_measurement_method", m.vo2MaxMeasurementMethod, ""))
        add(HealthField("cycling_cadence", m.cyclingCadenceAvg?.let { String.format(Locale.US, "%.1f", it) }, "rpm"))
        add(HealthField("steps_cadence", m.stepsCadenceAvg?.let { String.format(Locale.US, "%.1f", it) }, "steps/min"))
        add(HealthField("power_avg", m.powerAvg?.let { String.format(Locale.US, "%.1f", it) }, "W"))
        add(HealthField("power_max", m.powerMax?.let { String.format(Locale.US, "%.1f", it) }, "W"))
        add(HealthField("running_speed", m.runningSpeed?.let { String.format(Locale.US, "%.2f", it) }, "m/s"))
        add(HealthField("running_power_w", m.runningPowerAvg?.let { String.format(Locale.US, "%.0f", it) }, "W"))
        add(HealthField("running_power_avg", m.runningPowerAvg?.let { String.format(Locale.US, "%.1f", it) }, "W"))
        add(HealthField("running_power_max", m.runningPowerMax?.let { String.format(Locale.US, "%.1f", it) }, "W"))

        // ── Reproductive Health ────────────────────────────────────────────────────────────────
        val r = data.reproductiveHealth
        add(HealthField("menstrual_flow", r.menstrualFlow, ""))
        add(HealthField("cervical_mucus", r.cervicalMucusAppearance ?: r.cervicalMucusSensation, ""))
        add(HealthField("cervical_mucus_appearance", r.cervicalMucusAppearance, ""))
        add(HealthField("cervical_mucus_sensation", r.cervicalMucusSensation, ""))
        add(HealthField("ovulation_test", r.ovulationTestResult, ""))
        add(HealthField("intermenstrual_bleeding", if (r.intermenstrualBleeding) "true" else null, ""))
        add(HealthField("sexual_activity", if (r.sexualActivityRecorded) "true" else null, ""))
        add(HealthField("protection_used", if (r.sexualActivityRecorded) r.sexualActivityProtectionUsed else null, ""))
        add(HealthField("menstruation_period_count", r.menstruationPeriodCount, "count"))
        add(HealthField("menstruation_period_days", r.menstruationPeriodDuration.takeIf { it > Duration.ZERO }?.let { String.format(Locale.US, "%.2f", it.inWholeHours / 24.0) }, "days"))
        add(HealthField("menstruation_period_hours", r.menstruationPeriodDuration.takeIf { it > Duration.ZERO }?.inWholeHours, "hours"))

        // ── Mindfulness ────────────────────────────────────────────────────────────────────────
        add(HealthField("mindful_minutes", data.mindfulness.mindfulnessMinutes?.toInt(), "minutes"))
        add(HealthField("mindful_sessions", data.mindfulness.mindfulSessions, "sessions")) // T1-14

        // ── Workouts (aggregated) ──────────────────────────────────────────────────────────────
        add(HealthField("planned_workout_count", data.plannedWorkouts.size.takeIf { it > 0 }, "count"))
        add(HealthField("medical_resource_count", data.medicalResources.resources.size.takeIf { it > 0 }, "count"))

        if (data.workouts.isNotEmpty()) {
            add(HealthField("workout_count", data.workouts.size, "count"))
            add(HealthField("workout_minutes", data.workouts.sumOf { it.duration.inWholeMinutes }.toInt(), "minutes"))
            add(HealthField("workout_calories", data.workouts.mapNotNull { it.calories }.sum().takeIf { it > 0 }?.toInt(), "kcal"))
            add(HealthField("workout_distance_km", data.workouts.mapNotNull { it.distance }.sum().takeIf { it > 0 }?.let { String.format(Locale.US, "%.2f", it / 1000) }, "km"))
            add(HealthField("workout_avg_heart_rate", data.workouts.durationWeightedAverage { it.averageHeartRate }?.roundToInt(), "bpm"))
            add(HealthField("workout_max_heart_rate", data.workouts.mapNotNull { it.heartRateMax }.maxOrNull()?.roundToInt(), "bpm"))
            add(HealthField("workout_min_heart_rate", data.workouts.mapNotNull { it.heartRateMin }.minOrNull()?.roundToInt(), "bpm"))
            add(HealthField("workout_running_cadence", data.workouts
                .filter { it.workoutType == WorkoutType.RUNNING }
                .durationWeightedAverage { it.stepsCadenceAvg }
                ?.roundToInt(), "spm"))
            add(HealthField("workout_cycling_cadence", data.workouts
                .filter { it.workoutType == WorkoutType.CYCLING }
                .durationWeightedAverage { it.cyclingCadenceAvg }
                ?.roundToInt(), "rpm"))
            add(HealthField("workout_avg_power", data.workouts.durationWeightedAverage { it.powerAvg }?.roundToInt(), "W"))
            add(HealthField("workout_max_power", data.workouts.mapNotNull { it.powerMax }.maxOrNull()?.roundToInt(), "W"))
            val types = data.workouts
                .map { it.workoutType.slug() }
                .distinct()
                .sorted()
            add(HealthField("workouts", "[${types.joinToString(", ")}]", ""))
        }
    }.filter { field ->
        includeAndroidCompatibilityKeys || field.key !in androidCompatibilityKeys
    }

    private fun Duration.toHoursRounded(): String? {
        if (this <= Duration.ZERO) return null
        return String.format(Locale.US, "%.2f", this.inWholeMinutes / 60.0)
    }

    private fun List<WorkoutData>.durationWeightedAverage(value: (WorkoutData) -> Double?): Double? {
        var totalWeight = 0.0
        var weightedSum = 0.0
        for (workout in this) {
            val metricValue = value(workout) ?: continue
            val weight = workout.duration.inWholeSeconds.toDouble()
            if (weight <= 0.0) continue
            totalWeight += weight
            weightedSum += metricValue * weight
        }
        return if (totalWeight > 0.0) weightedSum / totalWeight else null
    }
}
