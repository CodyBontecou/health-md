package com.healthmd.export

import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.Locale

/**
 * Contract tests for [ObsidianBasesExporter] and [HealthDataFields] against the iOS
 * frontmatter/Obsidian Bases key set.
 *
 * Schema contract: docs/export-contract/ios-export-contract.md (§2)
 * Gap matrix fixes: docs/export-contract/android-ios-gap-matrix.md (§4 Tier-1)
 *   T1-02  sleep_bedtime, sleep_wake derived from sessionStart/sessionEnd or stages
 *   T1-06  sleep_core_hours alias (= sleep_light_hours value)
 *   T1-07  vitals min/max variant keys
 *   T1-14  mindful_sessions
 */
class ObsidianBasesContractTest {

    private lateinit var exporter: ObsidianBasesExporter
    private val referenceDate: LocalDate = LocalDate.of(2026, 3, 15)
    private val referenceDateTime: LocalDateTime = LocalDateTime.of(2026, 3, 15, 6, 0, 0)

    @Before
    fun setUp() {
        exporter = ObsidianBasesExporter()
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────────────────

    private fun export(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
    ): Map<String, String> {
        val output = exporter.export(data, customization)
        return parseFrontmatter(output)
    }

    private val androidCompatibilityCustomization = FormatCustomization(includeLegacyAndroidAliases = true, includeAndroidNativeFields = true)

    private fun parseFrontmatter(output: String): Map<String, String> {
        val result = mutableMapOf<String, String>()
        var inside = false
        for (line in output.lines()) {
            val trimmed = line.trim()
            if (trimmed == "---") {
                if (!inside) { inside = true; continue }
                else break
            }
            if (!inside) continue
            val colonIdx = trimmed.indexOf(':')
            if (colonIdx < 0) continue
            val key = trimmed.substring(0, colonIdx).trim()
            val value = trimmed.substring(colonIdx + 1).trim()
            result[key] = value
        }
        return result
    }

    private fun sleepWithStages(withSessionTimes: Boolean = false): SleepData {
        val bedtime = referenceDateTime.minusHours(8)
        val wakeTime = referenceDateTime
        return SleepData(
            totalDuration = kotlin.time.Duration.parse("7h 30m"),
            deepSleep = kotlin.time.Duration.parse("1h 30m"),
            remSleep = kotlin.time.Duration.parse("2h"),
            lightSleep = kotlin.time.Duration.parse("4h"),
            awakeTime = kotlin.time.Duration.parse("15m"),
            inBedTime = kotlin.time.Duration.parse("8h"),
            sessionStart = if (withSessionTimes) bedtime else null,
            sessionEnd = if (withSessionTimes) wakeTime else null,
            stages = if (!withSessionTimes) listOf(
                SleepStageEntry(bedtime, bedtime.plusHours(4), "deep"),
                SleepStageEntry(bedtime.plusHours(4), wakeTime, "light"),
            ) else emptyList(),
        )
    }

    private fun fullVitals() = VitalsData(
        respiratoryRateAvg = 15.0,
        respiratoryRateMin = 12.0,
        respiratoryRateMax = 18.0,
        bloodOxygenAvg = 0.97,
        bloodOxygenMin = 0.94,
        bloodOxygenMax = 0.99,
        bodyTemperatureAvg = 36.8,
        bodyTemperatureMin = 36.5,
        bodyTemperatureMax = 37.1,
        bloodPressureSystolicAvg = 120.0,
        bloodPressureSystolicMin = 115.0,
        bloodPressureSystolicMax = 125.0,
        bloodPressureDiastolicAvg = 80.0,
        bloodPressureDiastolicMin = 76.0,
        bloodPressureDiastolicMax = 84.0,
        bloodGlucoseAvg = 95.0,
        bloodGlucoseMin = 85.0,
        bloodGlucoseMax = 110.0,
    )

    // ── Basic structure ───────────────────────────────────────────────────────────────────────

    @Test
    fun output_startAndEndWithDelimiters() {
        val out = exporter.export(HealthData(date = referenceDate))
        assertTrue("Should start with ---", out.startsWith("---\n"))
        assertTrue("Should contain closing ---", out.contains("\n---\n"))
    }

    @Test
    fun emptyDay_hasOnlyDateAndType() {
        val fm = export(HealthData(date = referenceDate))
        assertEquals("2026-03-15", fm["date"])
        assertEquals("health-data", fm["type"])
        val healthKeys = fm.keys - setOf("date", "type")
        assertTrue("Empty day should have no health metric keys, found: $healthKeys", healthKeys.isEmpty())
    }

    @Test
    fun metadataKeys_dateAndType_alwaysPresent() {
        val fm = export(HealthData(date = referenceDate,
            activity = ActivityData(steps = 5000)))
        assertNotNull(fm["date"])
        assertNotNull(fm["type"])
        assertEquals("health-data", fm["type"])
    }

    @Test
    fun numericFrontmatterValues_areLocaleInvariant_whenDeviceLocaleUsesCommaDecimal() {
        val previousLocale = Locale.getDefault()
        Locale.setDefault(Locale.FRANCE)
        try {
            val fm = export(HealthData(
                date = referenceDate,
                activity = ActivityData(cyclingDistance = 1234.5),
                vitals = VitalsData(bodyTemperatureAvg = 36.7, bloodGlucoseAvg = 123.4),
                body = BodyData(weight = 70.4),
                mobility = MobilityData(walkingSpeed = 1.23),
            ))

            assertEquals("1.23", fm["cycling_km"])
            assertEquals("36.7", fm["body_temperature"])
            assertEquals("123.4", fm["blood_glucose"])
            assertEquals("70.4", fm["weight_kg"])
            assertEquals("1.23", fm["walking_speed"])
        } finally {
            Locale.setDefault(previousLocale)
        }
    }

    // ── Sleep keys ────────────────────────────────────────────────────────────────────────────

    @Test
    fun sleep_coreKeys_present() {
        val fm = export(HealthData(date = referenceDate, sleep = sleepWithStages()))
        assertNotNull(fm["sleep_total_hours"])
        assertNotNull(fm["sleep_deep_hours"])
        assertNotNull(fm["sleep_rem_hours"])
        assertNotNull(fm["sleep_awake_hours"])
        assertNotNull(fm["sleep_in_bed_hours"])
    }

    @Test
    fun sleep_T1_06_coreSleepHoursPresent() {
        // T1-06: `sleep_core_hours` iOS canonical key must be present
        val fm = export(HealthData(date = referenceDate, sleep = sleepWithStages()))
        assertNotNull("sleep_core_hours missing (T1-06)", fm["sleep_core_hours"])
    }

    @Test
    fun sleep_androidLightSleepOmittedByDefault() {
        val fm = export(HealthData(date = referenceDate, sleep = sleepWithStages()))
        assertNull("sleep_light_hours is an Android compatibility key and should be off by default", fm["sleep_light_hours"])
    }

    @Test
    fun sleep_androidLightSleepPresentWhenCompatibilityKeysEnabled() {
        val fm = export(
            HealthData(date = referenceDate, sleep = sleepWithStages()),
            androidCompatibilityCustomization,
        )
        assertNotNull("sleep_light_hours Android key should be available when compatibility is enabled", fm["sleep_light_hours"])
        assertEquals("sleep_core_hours should equal sleep_light_hours when compatibility is enabled",
            fm["sleep_light_hours"], fm["sleep_core_hours"])
    }

    @Test
    fun sleep_T1_02_bedtimeWakeFromSessionTimes() {
        // T1-02: sleep_bedtime / sleep_wake from sessionStart/sessionEnd
        val fm = export(HealthData(date = referenceDate, sleep = sleepWithStages(withSessionTimes = true)))
        assertNotNull("sleep_bedtime missing (T1-02 via sessionStart)", fm["sleep_bedtime"])
        assertNotNull("sleep_wake missing (T1-02 via sessionEnd)", fm["sleep_wake"])
    }

    @Test
    fun sleep_T1_02_bedtimeWakeDerivedFromStages() {
        // T1-02: sleep_bedtime / sleep_wake derived from stage min/max when no sessionStart/End
        val fm = export(HealthData(date = referenceDate, sleep = sleepWithStages(withSessionTimes = false)))
        assertNotNull("sleep_bedtime missing (T1-02 derived from stages)", fm["sleep_bedtime"])
        assertNotNull("sleep_wake missing (T1-02 derived from stages)", fm["sleep_wake"])
    }

    @Test
    fun sleep_noStagesAndNoSessionTimes_bedtimeIsAbsent() {
        // With no stages and no sessionStart/End, bedtime/wake must not be emitted
        val sleep = SleepData(
            totalDuration = kotlin.time.Duration.parse("7h"),
            lightSleep = kotlin.time.Duration.parse("4h"),
        )
        val fm = export(HealthData(date = referenceDate, sleep = sleep))
        assertNull("sleep_bedtime should be absent when no stages or session times", fm["sleep_bedtime"])
        assertNull("sleep_wake should be absent when no stages or session times", fm["sleep_wake"])
    }

    // ── Activity keys ─────────────────────────────────────────────────────────────────────────

    @Test
    fun activity_coreKeys_present() {
        val fm = export(HealthData(date = referenceDate, activity = ActivityData(
            steps = 12500, activeCalories = 520.0, exerciseMinutes = 45.0, flightsClimbed = 8,
            walkingRunningDistance = 9500.0,
        )))
        assertNotNull(fm["steps"])
        assertNotNull(fm["active_calories"])
        assertNotNull(fm["exercise_minutes"])
        assertNotNull(fm["flights_climbed"])
        assertNotNull(fm["walking_running_km"])
        assertEquals("12500", fm["steps"])
    }

    // ── Heart keys ────────────────────────────────────────────────────────────────────────────

    @Test
    fun heart_coreKeys_present() {
        val fm = export(HealthData(date = referenceDate, heart = HeartData(
            restingHeartRate = 58.0, averageHeartRate = 72.0,
            heartRateMin = 52.0, heartRateMax = 155.0, hrv = 42.0,
        )))
        assertNotNull(fm["resting_heart_rate"])
        assertNotNull(fm["average_heart_rate"])
        assertNotNull(fm["heart_rate_min"])
        assertNotNull(fm["heart_rate_max"])
        assertNotNull(fm["hrv_ms"])
        assertEquals("58", fm["resting_heart_rate"])
        assertEquals("42.0", fm["hrv_ms"])
    }

    // ── Vitals keys ───────────────────────────────────────────────────────────────────────────

    @Test
    fun vitals_T1_07_respiratoryRateMinMaxPresent() {
        val fm = export(HealthData(date = referenceDate, vitals = fullVitals()))
        assertNotNull("respiratory_rate alias missing", fm["respiratory_rate"])
        assertNotNull("respiratory_rate_avg missing (T1-07)", fm["respiratory_rate_avg"])
        assertNotNull("respiratory_rate_min missing (T1-07)", fm["respiratory_rate_min"])
        assertNotNull("respiratory_rate_max missing (T1-07)", fm["respiratory_rate_max"])
        // avg alias == the primary key
        assertEquals(fm["respiratory_rate"], fm["respiratory_rate_avg"])
    }

    @Test
    fun vitals_T1_07_bloodOxygenMinMaxPresent() {
        val fm = export(HealthData(date = referenceDate, vitals = fullVitals()))
        assertNotNull("blood_oxygen alias missing", fm["blood_oxygen"])
        assertNotNull("blood_oxygen_avg missing (T1-07)", fm["blood_oxygen_avg"])
        assertNotNull("blood_oxygen_min missing (T1-07)", fm["blood_oxygen_min"])
        assertNotNull("blood_oxygen_max missing (T1-07)", fm["blood_oxygen_max"])
        // blood oxygen stored as fraction → frontmatter value should be whole-number percent
        assertEquals("97", fm["blood_oxygen"])
        assertEquals("94", fm["blood_oxygen_min"])
        assertEquals("99", fm["blood_oxygen_max"])
    }

    @Test
    fun vitals_T1_07_bodyTemperatureMinMaxPresent() {
        val fm = export(HealthData(date = referenceDate, vitals = fullVitals()))
        assertNotNull("body_temperature alias missing", fm["body_temperature"])
        assertNotNull("body_temperature_avg missing (T1-07)", fm["body_temperature_avg"])
        assertNotNull("body_temperature_min missing (T1-07)", fm["body_temperature_min"])
        assertNotNull("body_temperature_max missing (T1-07)", fm["body_temperature_max"])
        assertEquals(fm["body_temperature"], fm["body_temperature_avg"])
    }

    @Test
    fun vitals_T1_07_bloodPressureMinMaxPresent() {
        val fm = export(HealthData(date = referenceDate, vitals = fullVitals()))
        // Systolic
        assertNotNull("blood_pressure_systolic alias missing", fm["blood_pressure_systolic"])
        assertNotNull("blood_pressure_systolic_avg missing (T1-07)", fm["blood_pressure_systolic_avg"])
        assertNotNull("blood_pressure_systolic_min missing (T1-07)", fm["blood_pressure_systolic_min"])
        assertNotNull("blood_pressure_systolic_max missing (T1-07)", fm["blood_pressure_systolic_max"])
        // Diastolic
        assertNotNull("blood_pressure_diastolic alias missing", fm["blood_pressure_diastolic"])
        assertNotNull("blood_pressure_diastolic_avg missing (T1-07)", fm["blood_pressure_diastolic_avg"])
        assertNotNull("blood_pressure_diastolic_min missing (T1-07)", fm["blood_pressure_diastolic_min"])
        assertNotNull("blood_pressure_diastolic_max missing (T1-07)", fm["blood_pressure_diastolic_max"])
        assertEquals(fm["blood_pressure_systolic"], fm["blood_pressure_systolic_avg"])
        assertEquals("120", fm["blood_pressure_systolic"])
        assertEquals("115", fm["blood_pressure_systolic_min"])
    }

    @Test
    fun vitals_T1_07_bloodGlucoseMinMaxPresent() {
        val fm = export(HealthData(date = referenceDate, vitals = fullVitals()))
        assertNotNull("blood_glucose alias missing", fm["blood_glucose"])
        assertNotNull("blood_glucose_avg missing (T1-07)", fm["blood_glucose_avg"])
        assertNotNull("blood_glucose_min missing (T1-07)", fm["blood_glucose_min"])
        assertNotNull("blood_glucose_max missing (T1-07)", fm["blood_glucose_max"])
        assertEquals(fm["blood_glucose"], fm["blood_glucose_avg"])
    }

    // ── Body keys ─────────────────────────────────────────────────────────────────────────────

    @Test
    fun body_coreKeys_present() {
        val fm = export(HealthData(date = referenceDate, body = BodyData(
            weight = 75.0, height = 1.78, bmi = 23.7, bodyFatPercentage = 0.18,
        )))
        assertNotNull(fm["weight_kg"])
        assertNotNull(fm["height_m"])
        assertNotNull(fm["bmi"])
        assertNotNull(fm["body_fat_percent"])
        assertEquals("75.0", fm["weight_kg"])
        assertEquals("18.0", fm["body_fat_percent"])
    }

    // ── Nutrition keys ────────────────────────────────────────────────────────────────────────

    @Test
    fun nutrition_coreKeys_present() {
        val fm = export(HealthData(date = referenceDate, nutrition = NutritionData(
            dietaryEnergy = 2100.0, protein = 120.0, carbohydrates = 250.0, fat = 70.0,
        )))
        assertNotNull(fm["dietary_calories"])
        assertNotNull(fm["protein_g"])
        assertNotNull(fm["carbohydrates_g"])
        assertNotNull(fm["fat_g"])
        assertEquals("2100", fm["dietary_calories"])
    }

    @Test
    fun nutrition_micronutrientsUseIosUgSuffixKeysWhenAndroidBacksThem() {
        val fm = export(HealthData(date = referenceDate, nutrition = NutritionData(
            vitaminA = 900.0,
            vitaminB12 = 2.4,
            vitaminD = 20.0,
            vitaminK = 120.0,
            folate = 400.0,
            biotin = 30.0,
            selenium = 55.0,
            chromium = 35.0,
            molybdenum = 45.0,
            iodine = 150.0,
        )))
        for (key in listOf(
            "vitamin_a_ug", "vitamin_b12_ug", "vitamin_d_ug", "vitamin_k_ug",
            "folate_ug", "biotin_ug", "selenium_ug", "chromium_ug", "molybdenum_ug", "iodine_ug",
        )) {
            assertNotNull("frontmatter missing iOS micronutrient key: $key", fm[key])
        }
        assertEquals("2.40", fm["vitamin_b12_ug"])
        assertEquals("55.0", fm["selenium_ug"])
    }

    @Test
    fun cycling_androidBackedMetricsUseIosFlatKeys() {
        val fm = export(HealthData(
            date = referenceDate,
            activity = ActivityData(cyclingDistance = 3_200.0),
            mobility = MobilityData(cyclingCadenceAvg = 87.4, powerAvg = 210.2),
        ))
        assertEquals("3.20", fm["cycling_km"])
        assertEquals("87", fm["cycling_cadence_rpm"])
        assertEquals("210", fm["cycling_power_w"])
    }

    @Test
    fun workouts_androidBackedAggregatesUseIosFlatKeys() {
        val fm = export(HealthData(date = referenceDate, workouts = listOf(
            WorkoutData(
                workoutType = WorkoutType.CYCLING,
                startTime = referenceDateTime,
                duration = kotlin.time.Duration.parse("45m"),
                averageHeartRate = 142.4,
                heartRateMin = 100.0,
                heartRateMax = 168.0,
                cyclingCadenceAvg = 86.7,
                powerAvg = 205.3,
                powerMax = 650.0,
            ),
        )))
        assertEquals("142", fm["workout_avg_heart_rate"])
        assertEquals("168", fm["workout_max_heart_rate"])
        assertEquals("100", fm["workout_min_heart_rate"])
        assertEquals("87", fm["workout_cycling_cadence"])
        assertEquals("205", fm["workout_avg_power"])
        assertEquals("650", fm["workout_max_power"])
    }

    // ── Mindfulness keys ──────────────────────────────────────────────────────────────────────

    @Test
    fun mindfulness_T1_14_mindfulSessionsPresent() {
        // T1-14: mindful_sessions key must be emitted
        val fm = export(HealthData(date = referenceDate,
            mindfulness = MindfulnessData(mindfulnessMinutes = 15.0, mindfulSessions = 2)))
        assertNotNull("mindful_minutes missing", fm["mindful_minutes"])
        assertNotNull("mindful_sessions missing (T1-14)", fm["mindful_sessions"])
        assertEquals("15", fm["mindful_minutes"])
        assertEquals("2", fm["mindful_sessions"])
    }

    @Test
    fun mindfulness_sessionsMissing_notEmitted() {
        // null mindfulSessions should not produce a key
        val fm = export(HealthData(date = referenceDate,
            mindfulness = MindfulnessData(mindfulnessMinutes = 10.0, mindfulSessions = null)))
        assertNull("mindful_sessions should be absent when null", fm["mindful_sessions"])
    }

    // ── Key style (snake_case / camelCase) ────────────────────────────────────────────────────

    @Test
    fun keyStyle_default_isSnakeCase() {
        val fm = export(HealthData(date = referenceDate, activity = ActivityData(steps = 5000)))
        assertTrue("Default should use snake_case", fm.containsKey("steps"))
        // steps has no underscore but active_calories does
        val fm2 = export(HealthData(date = referenceDate, activity = ActivityData(
            steps = 5000, activeCalories = 400.0,
        )))
        assertNotNull(fm2["active_calories"])
        assertNull("camelCase key must not appear in snake_case mode", fm2["activeCalories"])
    }

    @Test
    fun keyStyle_camelCase_convertsKeys() {
        val customization = FormatCustomization(
            frontmatterConfig = FrontmatterConfiguration.defaultFields
                .let { FrontmatterConfiguration() }
                .withKeyStyle(FrontmatterKeyStyle.CAMEL_CASE),
        )
        val data = HealthData(date = referenceDate, sleep = SleepData(
            totalDuration = kotlin.time.Duration.parse("7h"),
            lightSleep = kotlin.time.Duration.parse("4h"),
        ))
        val output = exporter.export(data, customization)
        val fm = parseFrontmatter(output)
        assertNotNull("camelCase: sleepTotalHours missing", fm["sleepTotalHours"])
        assertNull("camelCase: snake_case key must not appear", fm["sleep_total_hours"])
    }

    // ── allKeys / defaultFields parity ────────────────────────────────────────────────────────

    @Test
    fun defaultFields_derivedFromAllKeys_noDrift() {
        // FrontmatterConfiguration.defaultFields must cover every key in HealthDataFields.allKeys
        val defaultFieldKeys = FrontmatterConfiguration.defaultFields.map { it.originalKey }.toSet()
        for (key in HealthDataFields.allKeys) {
            assertTrue("defaultFields missing key: $key", defaultFieldKeys.contains(key))
        }
    }

    @Test
    fun missingNewFieldsInSavedFrontmatterConfig_defaultToEnabled() {
        // Saved configs from older app versions do not contain newly-added canonical keys.
        // They should still export with the configured key style instead of being silently skipped.
        val oldSavedFields = FrontmatterConfiguration.defaultFields
            .filterNot { it.originalKey in setOf("vitamin_a_ug", "cycling_power_w") }
        val customization = FormatCustomization(
            frontmatterConfig = FrontmatterConfiguration(fields = oldSavedFields),
        )
        val output = exporter.export(
            HealthData(
                date = referenceDate,
                nutrition = NutritionData(vitaminA = 900.0),
                mobility = MobilityData(powerAvg = 210.2),
            ),
            customization,
        )
        val fm = parseFrontmatter(output)
        assertEquals("900.0", fm["vitamin_a_ug"])
        assertEquals("210", fm["cycling_power_w"])
    }

    @Test
    fun allKeys_noRepeats() {
        val seen = mutableSetOf<String>()
        for (key in HealthDataFields.allKeys) {
            assertFalse("Duplicate key in allKeys: $key", seen.contains(key))
            seen.add(key)
        }
    }

    // ── Full export smoke test ────────────────────────────────────────────────────────────────

    @Test
    fun fullExport_defaultsToIosCanonicalKeys() {
        val data = HealthData(
            date = referenceDate,
            sleep = sleepWithStages(withSessionTimes = true),
            activity = ActivityData(steps = 12500),
            heart = HeartData(restingHeartRate = 58.0, hrv = 42.0),
            vitals = fullVitals(),
            body = BodyData(weight = 75.0),
            nutrition = NutritionData(dietaryEnergy = 2100.0),
            mobility = MobilityData(vo2Max = 42.5),
            mindfulness = MindfulnessData(mindfulnessMinutes = 15.0, mindfulSessions = 2),
        )
        val fm = export(data)
        // iOS canonical sleep key only by default
        assertNotNull(fm["sleep_core_hours"])
        assertNull(fm["sleep_light_hours"])
        // Bedtime
        assertNotNull(fm["sleep_bedtime"])
        assertNotNull(fm["sleep_wake"])
        // Vitals aliases
        assertNotNull(fm["respiratory_rate"])
        assertNotNull(fm["respiratory_rate_avg"])
        assertNotNull(fm["blood_oxygen"])
        assertNotNull(fm["blood_oxygen_avg"])
        assertNotNull(fm["blood_oxygen_min"])
        // Mindfulness
        assertNotNull(fm["mindful_minutes"])
        assertNotNull(fm["mindful_sessions"])
    }
}
