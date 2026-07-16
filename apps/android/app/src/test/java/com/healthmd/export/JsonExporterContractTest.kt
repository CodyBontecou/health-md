package com.healthmd.export

import com.healthmd.data.export.JsonExporter
import com.healthmd.domain.model.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime

/**
 * Contract tests for [JsonExporter] against the iOS JSON schema.
 *
 * These tests verify:
 *  - top-level keys (date, type, units)
 *  - category presence / absence rules
 *  - iOS-parity key names (T0-01 through T0-10, T1-01 through T1-05)
 *  - ISO 8601 timestamps on all sample arrays
 *  - backward-compat alias presence
 */
class JsonExporterContractTest {

    private lateinit var exporter: JsonExporter
    private val referenceDate: LocalDate = LocalDate.of(2026, 3, 15)
    private val referenceDateTime: LocalDateTime = LocalDateTime.of(2026, 3, 15, 6, 0, 0)

    @Before
    fun setUp() {
        exporter = JsonExporter()
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────────────────

    private fun exportJson(
        data: HealthData,
        granular: Boolean = false,
        customization: FormatCustomization = FormatCustomization(),
    ): JsonObject {
        val output = exporter.export(data, customization = customization, includeGranularData = granular)
        return Json.parseToJsonElement(output).jsonObject
    }

    private val androidCompatibilityCustomization = FormatCustomization(includeLegacyAndroidAliases = true, includeAndroidNativeFields = true)

    private fun fullActivityData() = ActivityData(
        steps = 12500,
        activeCalories = 520.0,
        basalEnergyBurned = 1650.0,
        exerciseMinutes = 45.0,
        flightsClimbed = 8,
        walkingRunningDistance = 9500.0,
        cyclingDistance = 3200.0,
        wheelchairPushes = 5,
    )

    private fun fullHeartData() = HeartData(
        restingHeartRate = 58.0,
        averageHeartRate = 72.0,
        heartRateMin = 52.0,
        heartRateMax = 155.0,
        hrv = 42.0,
        samples = listOf(
            TimestampedSample(referenceDateTime, 55.0),
            TimestampedSample(referenceDateTime.plusHours(6), 72.0),
        ),
        hrvSamples = listOf(
            TimestampedSample(referenceDateTime, 45.0),
        ),
    )

    private fun fullVitalsData() = VitalsData(
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
        bloodOxygenSamples = listOf(
            TimestampedSample(referenceDateTime, 0.96),
            TimestampedSample(referenceDateTime.plusHours(6), 0.98),
        ),
        bloodGlucoseSamples = listOf(
            TimestampedSample(referenceDateTime.plusHours(3), 90.0),
        ),
        respiratoryRateSamples = listOf(
            TimestampedSample(referenceDateTime, 14.0),
        ),
    )

    private fun fullSleepData(withStages: Boolean = false): SleepData {
        val stages = if (withStages) listOf(
            SleepStageEntry(
                startTime = referenceDateTime.minusHours(8),
                endTime = referenceDateTime.minusHours(6),
                stage = "deep",
            ),
            SleepStageEntry(
                startTime = referenceDateTime.minusHours(6),
                endTime = referenceDateTime.minusHours(4),
                stage = "rem",
            ),
            SleepStageEntry(
                startTime = referenceDateTime.minusHours(4),
                endTime = referenceDateTime,
                stage = "light",
            ),
        ) else emptyList()

        return SleepData(
            totalDuration = kotlin.time.Duration.parse("7h 30m"),
            deepSleep = kotlin.time.Duration.parse("1h 30m"),
            remSleep = kotlin.time.Duration.parse("2h"),
            lightSleep = kotlin.time.Duration.parse("4h"),
            awakeTime = kotlin.time.Duration.parse("15m"),
            inBedTime = kotlin.time.Duration.parse("8h"),
            stages = stages,
        )
    }

    private fun fullMobilityData() = MobilityData(vo2Max = 42.5, walkingSpeed = 1.4)

    // ── Top-level keys ────────────────────────────────────────────────────────────────────────

    @Test
    fun topLevel_alwaysHasDateTypeUnits() {
        val json = exportJson(HealthData(date = referenceDate))
        assertEquals("2026-03-15", json["date"]?.jsonPrimitive?.content)
        assertEquals("health-data", json["type"]?.jsonPrimitive?.content)
        assertNotNull(json["units"])
    }

    @Test
    fun topLevel_units_defaultsToMetric() {
        val json = exportJson(HealthData(date = referenceDate))
        assertEquals("metric", json["units"]?.jsonPrimitive?.content)
    }

    @Test
    fun emptyDay_hasOnlyCoreKeys() {
        val json = exportJson(HealthData(date = referenceDate))
        assertNull(json["sleep"])
        assertNull(json["activity"])
        assertNull(json["heart"])
        assertNull(json["vitals"])
        assertNull(json["body"])
        assertNull(json["nutrition"])
        assertNull(json["mindfulness"])
        assertNull(json["workouts"])
    }

    // ── Sleep ─────────────────────────────────────────────────────────────────────────────────

    @Test
    fun sleep_aggregateKeys_present() {
        val json = exportJson(HealthData(date = referenceDate, sleep = fullSleepData()))
        val sleep = json["sleep"]!!.jsonObject
        assertNotNull(sleep["totalDuration"])
        assertNotNull(sleep["totalDurationFormatted"])
        assertNotNull(sleep["deepSleep"])
        assertNotNull(sleep["remSleep"])
        assertNotNull(sleep["awakeTime"])
        assertNotNull(sleep["inBedTime"])
    }

    @Test
    fun sleep_T1_01_coreSleepAliasPresent() {
        // T1-01: coreSleep should be emitted (= lightSleep value) for iOS parity
        val json = exportJson(HealthData(date = referenceDate, sleep = fullSleepData()))
        val sleep = json["sleep"]!!.jsonObject
        assertNotNull("coreSleep key missing (T1-01)", sleep["coreSleep"])
        assertNotNull("coreSleepFormatted key missing (T1-01)", sleep["coreSleepFormatted"])
        assertEquals(4 * 3600.0, sleep["coreSleep"]!!.jsonPrimitive.double, 0.001)
    }

    @Test
    fun sleep_androidLightSleepOmittedByDefault() {
        val json = exportJson(HealthData(date = referenceDate, sleep = fullSleepData()))
        val sleep = json["sleep"]!!.jsonObject
        assertNull("lightSleep is an Android compatibility alias and should be off by default", sleep["lightSleep"])
    }

    @Test
    fun sleep_androidLightSleepPresentWhenCompatibilityKeysEnabled() {
        val json = exportJson(
            HealthData(date = referenceDate, sleep = fullSleepData()),
            customization = androidCompatibilityCustomization,
        )
        val sleep = json["sleep"]!!.jsonObject
        assertNotNull("lightSleep should be available for Android compatibility", sleep["lightSleep"])
    }

    @Test
    fun sleep_T0_01_granularArrayKeyIsSleepStages() {
        // T0-01: array key must be `sleepStages` (was `stages`)
        val json = exportJson(HealthData(date = referenceDate, sleep = fullSleepData(withStages = true)), granular = true)
        val sleep = json["sleep"]!!.jsonObject
        assertNotNull("sleepStages key missing (T0-01)", sleep["sleepStages"])
        assertNull("old `stages` key must not exist", sleep["stages"])
    }

    @Test
    fun sleep_T0_02_stageItemKeys_startDateEndDate() {
        // T0-02: items must have `startDate` + `endDate` (not `startTime`/`endTime`)
        val json = exportJson(HealthData(date = referenceDate, sleep = fullSleepData(withStages = true)), granular = true)
        val stages = json["sleep"]!!.jsonObject["sleepStages"]!!.jsonArray
        val first = stages[0].jsonObject
        assertNotNull("startDate key missing (T0-02)", first["startDate"])
        assertNotNull("endDate key missing (T0-02)", first["endDate"])
        assertNull("startTime must not exist (T0-02)", first["startTime"])
        assertNull("endTime must not exist (T0-02)", first["endTime"])
    }

    @Test
    fun sleep_T0_03_stageItemHasDurationSeconds() {
        // T0-03: items must have `durationSeconds`
        val json = exportJson(HealthData(date = referenceDate, sleep = fullSleepData(withStages = true)), granular = true)
        val stages = json["sleep"]!!.jsonObject["sleepStages"]!!.jsonArray
        val first = stages[0].jsonObject
        assertNotNull("durationSeconds key missing (T0-03)", first["durationSeconds"])
        val dur = first["durationSeconds"]!!.jsonPrimitive.double
        assertTrue("durationSeconds must be > 0", dur > 0)
    }

    @Test
    fun sleep_T0_04_stageTimestampsAreIso8601() {
        // T0-04: startDate/endDate must be ISO 8601 strings parseable by Date.parse
        val json = exportJson(HealthData(date = referenceDate, sleep = fullSleepData(withStages = true)), granular = true)
        val stages = json["sleep"]!!.jsonObject["sleepStages"]!!.jsonArray
        val first = stages[0].jsonObject
        val startDate = first["startDate"]!!.jsonPrimitive.content
        assertTrue("startDate should contain 'T' (ISO 8601): $startDate", startDate.contains("T"))
        assertTrue("startDate should contain '-' date separators: $startDate", startDate.contains("-"))
    }

    @Test
    fun sleep_T1_02_bedtimeWakeFromStages() {
        // T1-02: bedtime/wakeTime derived from stages when no explicit sessionStart/End
        val json = exportJson(HealthData(date = referenceDate, sleep = fullSleepData(withStages = true)))
        val sleep = json["sleep"]!!.jsonObject
        assertNotNull("bedtime should be derived from stages (T1-02)", sleep["bedtime"])
        assertNotNull("bedtimeISO should be derived from stages (T1-02)", sleep["bedtimeISO"])
        assertNotNull("wakeTime should be derived from stages (T1-02)", sleep["wakeTime"])
        assertNotNull("wakeTimeISO should be derived from stages (T1-02)", sleep["wakeTimeISO"])
        // ISO versions should contain 'T'
        val bedtimeISO = sleep["bedtimeISO"]!!.jsonPrimitive.content
        assertTrue("bedtimeISO must be ISO 8601: $bedtimeISO", bedtimeISO.contains("T"))
    }

    @Test
    fun sleep_T1_02_bedtimeFromSessionStartEnd() {
        // T1-02: sessionStart/End fields take priority over stage derivation
        val sleep = fullSleepData().copy(
            sessionStart = referenceDateTime.minusHours(8),
            sessionEnd = referenceDateTime,
        )
        val json = exportJson(HealthData(date = referenceDate, sleep = sleep))
        val sleepObj = json["sleep"]!!.jsonObject
        assertNotNull("bedtimeISO from sessionStart (T1-02)", sleepObj["bedtimeISO"])
        assertNotNull("wakeTimeISO from sessionEnd (T1-02)", sleepObj["wakeTimeISO"])
        val wakeISO = sleepObj["wakeTimeISO"]!!.jsonPrimitive.content
        assertTrue("wakeTimeISO must be ISO 8601: $wakeISO", wakeISO.contains("T"))
    }

    // ── Activity ──────────────────────────────────────────────────────────────────────────────

    @Test
    fun activity_standardKeys_present() {
        val data = HealthData(date = referenceDate, activity = fullActivityData())
        val json = exportJson(data)
        val act = json["activity"]!!.jsonObject
        assertNotNull(act["steps"])
        assertNotNull(act["activeCalories"])
        assertNotNull(act["basalEnergyBurned"])
        assertNotNull(act["exerciseMinutes"])
        assertNotNull(act["flightsClimbed"])
        assertNotNull(act["walkingRunningDistance"])
        assertNotNull(act["walkingRunningDistanceKm"])
    }

    @Test
    fun activity_T0_10_vo2MaxUnderActivity() {
        // T0-10: vo2Max must appear under `activity` (iOS canonical placement)
        val data = HealthData(date = referenceDate, mobility = fullMobilityData())
        val json = exportJson(data)
        val act = json["activity"]!!.jsonObject
        assertNotNull("vo2Max missing from activity (T0-10)", act["vo2Max"])
        assertEquals(42.5, act["vo2Max"]!!.jsonPrimitive.double, 0.001)
    }

    @Test
    fun activity_T0_10_vo2MaxNotDuplicatedUnderMobilityByDefault() {
        val data = HealthData(date = referenceDate, mobility = fullMobilityData())
        val json = exportJson(data)
        val mob = json["mobility"]!!.jsonObject
        assertNotNull("walkingSpeed should still be exported under mobility", mob["walkingSpeed"])
        assertNull("mobility.vo2Max is an Android compatibility alias and should be off by default", mob["vo2Max"])
    }

    @Test
    fun activity_T0_10_vo2MaxUnderMobilityWhenCompatibilityKeysEnabled() {
        val data = HealthData(date = referenceDate, mobility = fullMobilityData())
        val json = exportJson(data, customization = androidCompatibilityCustomization)
        val mob = json["mobility"]!!.jsonObject
        assertNotNull("vo2Max should be available under mobility for Android compatibility", mob["vo2Max"])
    }

    @Test
    fun activity_T1_04_pushCountAlias() {
        // T1-04: `pushCount` must be present when wheelchairPushes is set
        val data = HealthData(date = referenceDate, activity = fullActivityData())
        val json = exportJson(data)
        val act = json["activity"]!!.jsonObject
        assertNotNull("pushCount alias missing (T1-04)", act["pushCount"])
        assertNull("wheelchairPushes is an Android compatibility key and should be off by default", act["wheelchairPushes"])

        val compatibilityAct = exportJson(data, customization = androidCompatibilityCustomization)["activity"]!!.jsonObject
        assertNotNull("wheelchairPushes Android key should be available when compatibility is enabled", compatibilityAct["wheelchairPushes"])
        assertEquals(compatibilityAct["pushCount"]!!.jsonPrimitive.int, compatibilityAct["wheelchairPushes"]!!.jsonPrimitive.int)
    }

    @Test
    fun activity_T0_04_stepSampleTimestampIsIso8601() {
        val activity = fullActivityData().copy(
            stepSamples = listOf(TimestampedSample(referenceDateTime, 500.0)),
        )
        val data = HealthData(date = referenceDate, activity = activity)
        val json = exportJson(data, granular = true)
        val samples = json["activity"]!!.jsonObject["stepSamples"]!!.jsonArray
        val ts = samples[0].jsonObject["timestamp"]!!.jsonPrimitive.content
        assertTrue("Step sample timestamp must be ISO 8601: $ts", ts.contains("T"))
    }

    // ── Heart ─────────────────────────────────────────────────────────────────────────────────

    @Test
    fun heart_standardKeys_present() {
        val json = exportJson(HealthData(date = referenceDate, heart = fullHeartData()), granular = true)
        val heart = json["heart"]!!.jsonObject
        assertNotNull(heart["restingHeartRate"])
        assertNotNull(heart["averageHeartRate"])
        assertNotNull(heart["heartRateMin"])
        assertNotNull(heart["heartRateMax"])
        assertNotNull(heart["hrv"])
    }

    @Test
    fun heart_T0_05_hrSampleKeyIsValue() {
        // T0-05: heart rate sample value key must be `value` (was `bpm`)
        val json = exportJson(HealthData(date = referenceDate, heart = fullHeartData()), granular = true)
        val samples = json["heart"]!!.jsonObject["heartRateSamples"]!!.jsonArray
        val first = samples[0].jsonObject
        assertNotNull("heart rate sample must have `value` key (T0-05)", first["value"])
        assertNull("heart rate sample must not have `bpm` key (T0-05)", first["bpm"])
    }

    @Test
    fun heart_T0_06_hrvSampleKeyIsValue() {
        // T0-06: HRV sample value key must be `value` (was `ms`)
        val json = exportJson(HealthData(date = referenceDate, heart = fullHeartData()), granular = true)
        val samples = json["heart"]!!.jsonObject["hrvSamples"]!!.jsonArray
        val first = samples[0].jsonObject
        assertNotNull("HRV sample must have `value` key (T0-06)", first["value"])
        assertNull("HRV sample must not have `ms` key (T0-06)", first["ms"])
    }

    @Test
    fun heart_T0_04_sampleTimestampIsIso8601() {
        // T0-04: heart sample timestamps must be ISO 8601
        val json = exportJson(HealthData(date = referenceDate, heart = fullHeartData()), granular = true)
        val samples = json["heart"]!!.jsonObject["heartRateSamples"]!!.jsonArray
        val ts = samples[0].jsonObject["timestamp"]!!.jsonPrimitive.content
        assertTrue("HR sample timestamp must be ISO 8601: $ts", ts.contains("T"))
        assertNull("HR sample must not have `time` key", samples[0].jsonObject["time"])
    }

    @Test
    fun heart_T0_04_hrvSampleTimestampIsIso8601() {
        val json = exportJson(HealthData(date = referenceDate, heart = fullHeartData()), granular = true)
        val samples = json["heart"]!!.jsonObject["hrvSamples"]!!.jsonArray
        val ts = samples[0].jsonObject["timestamp"]!!.jsonPrimitive.content
        assertTrue("HRV sample timestamp must be ISO 8601: $ts", ts.contains("T"))
        assertNull("HRV sample must not have `time` key", samples[0].jsonObject["time"])
    }

    // ── Vitals ────────────────────────────────────────────────────────────────────────────────

    @Test
    fun vitals_aggregateKeys_present() {
        val json = exportJson(HealthData(date = referenceDate, vitals = fullVitalsData()))
        val vitals = json["vitals"]!!.jsonObject
        assertNotNull(vitals["respiratoryRateAvg"])
        assertNotNull(vitals["bloodOxygenAvg"])
        assertNotNull(vitals["bodyTemperatureAvg"])
        assertNotNull(vitals["bloodPressureSystolicAvg"])
        assertNotNull(vitals["bloodPressureDiastolicAvg"])
        assertNotNull(vitals["bloodGlucoseAvg"])
    }

    @Test
    fun vitals_T1_05_backwardCompatAliases_present() {
        // T1-05: backward-compat aliases used by plugin summary-card.ts
        val json = exportJson(HealthData(date = referenceDate, vitals = fullVitalsData()))
        val vitals = json["vitals"]!!.jsonObject
        assertNotNull("respiratoryRate alias missing (T1-05)", vitals["respiratoryRate"])
        assertNotNull("bloodOxygen alias missing (T1-05)", vitals["bloodOxygen"])
        assertNotNull("bloodOxygenPercent alias missing (T1-05)", vitals["bloodOxygenPercent"])
        assertNotNull("bodyTemperature alias missing (T1-05)", vitals["bodyTemperature"])
        assertNotNull("bloodPressureSystolic alias missing (T1-05)", vitals["bloodPressureSystolic"])
        assertNotNull("bloodPressureDiastolic alias missing (T1-05)", vitals["bloodPressureDiastolic"])
        assertNotNull("bloodGlucose alias missing (T1-05)", vitals["bloodGlucose"])
    }

    @Test
    fun vitals_bloodOxygenPercent_isMultipliedBy100() {
        // bloodOxygenPercent = bloodOxygenAvg * 100 (0.97 -> 97.0)
        val json = exportJson(HealthData(date = referenceDate, vitals = fullVitalsData()))
        val vitals = json["vitals"]!!.jsonObject
        val avg = vitals["bloodOxygenAvg"]!!.jsonPrimitive.double
        val pct = vitals["bloodOxygenPercent"]!!.jsonPrimitive.double
        assertEquals(avg * 100, pct, 0.01)
        assertEquals(97.0, pct, 0.01)
    }

    @Test
    fun vitals_T0_07_bloodOxygenSampleKeyIsValue() {
        // T0-07: blood oxygen sample value key must be `value` (was `percent`)
        val json = exportJson(HealthData(date = referenceDate, vitals = fullVitalsData()), granular = true)
        val samples = json["vitals"]!!.jsonObject["bloodOxygenSamples"]!!.jsonArray
        val first = samples[0].jsonObject
        assertNotNull("bloodOxygenSamples must have `value` key (T0-07)", first["value"])
        assertNull("bloodOxygenSamples must not have `percent` key (T0-07)", first["percent"])
    }

    @Test
    fun vitals_T0_08_bloodGlucoseSampleKeyIsValue() {
        // T0-08: blood glucose sample value key must be `value` (was `mgPerDl`)
        val json = exportJson(HealthData(date = referenceDate, vitals = fullVitalsData()), granular = true)
        val samples = json["vitals"]!!.jsonObject["bloodGlucoseSamples"]!!.jsonArray
        val first = samples[0].jsonObject
        assertNotNull("bloodGlucoseSamples must have `value` key (T0-08)", first["value"])
        assertNull("bloodGlucoseSamples must not have `mgPerDl` key (T0-08)", first["mgPerDl"])
    }

    @Test
    fun vitals_T0_09_respiratoryRateSampleKeyIsValue() {
        // T0-09: respiratory rate sample value key must be `value` (was `breathsPerMin`)
        val json = exportJson(HealthData(date = referenceDate, vitals = fullVitalsData()), granular = true)
        val samples = json["vitals"]!!.jsonObject["respiratoryRateSamples"]!!.jsonArray
        val first = samples[0].jsonObject
        assertNotNull("respiratoryRateSamples must have `value` key (T0-09)", first["value"])
        assertNull("respiratoryRateSamples must not have `breathsPerMin` key (T0-09)", first["breathsPerMin"])
    }

    @Test
    fun vitals_T0_04_sampleTimestampsAreIso8601() {
        // T0-04: all vitals sample timestamps must be ISO 8601
        val json = exportJson(HealthData(date = referenceDate, vitals = fullVitalsData()), granular = true)
        val vitals = json["vitals"]!!.jsonObject
        for (arrayKey in listOf("bloodOxygenSamples", "bloodGlucoseSamples", "respiratoryRateSamples")) {
            val samples = vitals[arrayKey]?.jsonArray ?: continue
            val ts = samples[0].jsonObject["timestamp"]!!.jsonPrimitive.content
            assertTrue("$arrayKey timestamp must be ISO 8601: $ts", ts.contains("T"))
            assertNull("$arrayKey must not have `time` key", samples[0].jsonObject["time"])
        }
    }

    @Test
    fun vitals_minMaxVariants_present() {
        val json = exportJson(HealthData(date = referenceDate, vitals = fullVitalsData()))
        val vitals = json["vitals"]!!.jsonObject
        for (key in listOf("respiratoryRateMin", "respiratoryRateMax",
                "bloodOxygenMin", "bloodOxygenMax",
                "bodyTemperatureMin", "bodyTemperatureMax",
                "bloodPressureSystolicMin", "bloodPressureSystolicMax",
                "bloodPressureDiastolicMin", "bloodPressureDiastolicMax",
                "bloodGlucoseMin", "bloodGlucoseMax")) {
            assertNotNull("vitals missing min/max key: $key", vitals[key])
        }
    }

    // ── Cycling / micronutrient category parity ──────────────────────────────────────────────

    @Test
    fun cyclingPerformance_androidBackedMetricsUseIosCategoryAndKeys() {
        // Android backs cycling distance/cadence/power via Health Connect; iOS exports these
        // equivalents under the top-level `cyclingPerformance` object with snake_case keys.
        val data = HealthData(
            date = referenceDate,
            activity = ActivityData(cyclingDistance = 3_200.0),
            mobility = MobilityData(cyclingCadenceAvg = 87.4, powerAvg = 210.2),
        )
        val json = exportJson(data)
        val cycling = json["cyclingPerformance"]!!.jsonObject
        assertEquals(3.2, cycling["cycling_km"]!!.jsonPrimitive.double, 0.001)
        // iOS JSON is backed by formatted flat metrics, so cadence/power are whole-number values.
        assertEquals(87.0, cycling["cycling_cadence_rpm"]!!.jsonPrimitive.double, 0.001)
        assertEquals(210.0, cycling["cycling_power_w"]!!.jsonPrimitive.double, 0.001)
    }

    @Test
    fun vitamins_androidBackedMetricsUseIosCategoryAndKeys() {
        val data = HealthData(
            date = referenceDate,
            nutrition = NutritionData(
                vitaminA = 900.0,
                vitaminB6 = 1.7,
                vitaminB12 = 2.345,
                vitaminC = 90.0,
                vitaminD = 20.0,
                vitaminE = 15.0,
                vitaminK = 120.0,
                thiamin = 1.2,
                riboflavin = 1.3,
                niacin = 16.0,
                folate = 400.0,
                biotin = 30.0,
                pantothenicAcid = 5.0,
            ),
        )
        val json = exportJson(data)
        val vitamins = json["vitamins"]!!.jsonObject
        for (key in listOf(
            "vitamin_a_ug", "vitamin_b6_mg", "vitamin_b12_ug", "vitamin_c_mg",
            "vitamin_d_ug", "vitamin_e_mg", "vitamin_k_ug", "thiamin_mg",
            "riboflavin_mg", "niacin_mg", "folate_ug", "biotin_ug", "pantothenic_acid_mg",
        )) {
            assertNotNull("vitamins missing iOS key: $key", vitamins[key])
        }
        assertEquals(900.0, vitamins["vitamin_a_ug"]!!.jsonPrimitive.double, 0.001)
        assertEquals(2.35, vitamins["vitamin_b12_ug"]!!.jsonPrimitive.double, 0.001)
    }

    @Test
    fun minerals_androidBackedMetricsUseIosCategoryAndKeys() {
        val data = HealthData(
            date = referenceDate,
            nutrition = NutritionData(
                calcium = 1_000.0,
                iron = 18.0,
                potassium = 3_400.0,
                magnesium = 420.0,
                phosphorus = 700.0,
                zinc = 11.0,
                selenium = 55.0,
                copper = 0.9449,
                manganese = 2.3,
                chromium = 35.0,
                molybdenum = 45.0,
                chloride = 2_300.0,
                iodine = 150.0,
            ),
        )
        val json = exportJson(data)
        val minerals = json["minerals"]!!.jsonObject
        for (key in listOf(
            "calcium_mg", "iron_mg", "potassium_mg", "magnesium_mg", "phosphorus_mg",
            "zinc_mg", "selenium_ug", "copper_mg", "manganese_mg", "chromium_ug",
            "molybdenum_ug", "chloride_mg", "iodine_ug",
        )) {
            assertNotNull("minerals missing iOS key: $key", minerals[key])
        }
        assertEquals(55.0, minerals["selenium_ug"]!!.jsonPrimitive.double, 0.001)
        assertEquals(150.0, minerals["iodine_ug"]!!.jsonPrimitive.double, 0.001)
        assertEquals(0.945, minerals["copper_mg"]!!.jsonPrimitive.double, 0.001)
    }

    // ── Mindfulness ───────────────────────────────────────────────────────────────────────────

    @Test
    fun mindfulness_T1_03_keyIsMindfulMinutes() {
        // T1-03: key must be `mindfulMinutes` (was `mindfulnessMinutes`)
        val data = HealthData(
            date = referenceDate,
            mindfulness = MindfulnessData(mindfulnessMinutes = 15.0),
        )
        val json = exportJson(data)
        val mind = json["mindfulness"]!!.jsonObject
        assertNotNull("mindfulMinutes key missing (T1-03)", mind["mindfulMinutes"])
        assertNull("mindfulnessMinutes old key must not exist (T1-03)", mind["mindfulnessMinutes"])
    }

    // ── Workouts ──────────────────────────────────────────────────────────────────────────────

    @Test
    fun workouts_richDetailsAreAdditiveAndGranularRouteIsExported() {
        val data = HealthData(
            date = referenceDate,
            workouts = listOf(
                WorkoutData(
                    workoutType = WorkoutType.RUNNING,
                    startTime = referenceDateTime,
                    endTime = referenceDateTime.plusMinutes(30),
                    isIndoor = true,
                    metadata = mapOf("title" to "Tempo run", "data_origin_package" to "com.example"),
                    duration = kotlin.time.Duration.parse("30m"),
                    calories = 300.0,
                    distance = 5_000.0,
                    elevationGained = 40.0,
                    elevationLoss = 35.0,
                    averageHeartRate = 142.0,
                    laps = listOf(
                        WorkoutLapData(referenceDateTime, referenceDateTime.plusMinutes(10), length = 1_600.0),
                    ),
                    splits = listOf(
                        WorkoutSplitData(
                            index = 1,
                            startTime = referenceDateTime,
                            endTime = referenceDateTime.plusMinutes(5),
                            duration = kotlin.time.Duration.parse("5m"),
                            distance = 1_000.0,
                            averageHeartRate = 138.0,
                        ),
                    ),
                    routeAccess = WorkoutRouteAccess.DATA,
                    route = listOf(
                        WorkoutRoutePointData(referenceDateTime, 45.0, -122.0, altitude = 10.0),
                        WorkoutRoutePointData(referenceDateTime.plusMinutes(1), 45.001, -122.001, altitude = 12.0),
                    ),
                ),
            ),
        )

        val workout = exportJson(
            data,
            granular = true,
            customization = androidCompatibilityCustomization,
        )["workouts"]!!.jsonArray[0].jsonObject

        assertEquals("Tempo run", workout["title"]!!.jsonPrimitive.content)
        assertEquals(true, workout["isIndoor"]!!.jsonPrimitive.boolean)
        assertEquals("data", workout["routeAccess"]!!.jsonPrimitive.content)
        assertEquals(35.0, workout["elevationLoss"]!!.jsonPrimitive.double, 0.001)
        assertEquals("com.example", workout["metadata"]!!.jsonObject["data_origin_package"]!!.jsonPrimitive.content)
        assertEquals(1, workout["splits"]!!.jsonArray.size)
        assertEquals(2, workout["route"]!!.jsonArray.size)
        assertNotNull(workout["laps"]!!.jsonArray[0].jsonObject["durationSeconds"])
    }

    @Test
    fun workouts_androidBackedMetricsAlsoUseIosWorkoutKeys() {
        val data = HealthData(
            date = referenceDate,
            workouts = listOf(
                WorkoutData(
                    workoutType = WorkoutType.CYCLING,
                    startTime = referenceDateTime,
                    endTime = referenceDateTime.plusMinutes(45),
                    isIndoor = false,
                    duration = kotlin.time.Duration.parse("45m"),
                    distance = 20_000.0,
                    elevationGained = 120.0,
                    elevationLoss = 110.0,
                    averageHeartRate = 142.4,
                    heartRateMin = 100.0,
                    heartRateMax = 168.0,
                    cyclingCadenceAvg = 86.7,
                    powerAvg = 205.3,
                    powerMax = 650.0,
                    speedSamples = listOf(TimestampedSample(referenceDateTime, 8.0)),
                    powerSamples = listOf(TimestampedSample(referenceDateTime, 205.0)),
                    cyclingCadenceSamples = listOf(TimestampedSample(referenceDateTime, 87.0)),
                ),
            ),
        )

        val workout = exportJson(data, granular = true)["workouts"]!!.jsonArray[0].jsonObject
        assertEquals("outdoor", workout["locationType"]!!.jsonPrimitive.content)
        assertEquals(142, workout["avgHeartRate"]!!.jsonPrimitive.int)
        assertEquals(168, workout["maxHeartRate"]!!.jsonPrimitive.int)
        assertEquals(100, workout["minHeartRate"]!!.jsonPrimitive.int)
        assertEquals(87, workout["avgCyclingCadence"]!!.jsonPrimitive.int)
        assertEquals(205, workout["avgPower"]!!.jsonPrimitive.int)
        assertEquals(650, workout["maxPower"]!!.jsonPrimitive.int)
        assertEquals(120.0, workout["elevationGainMeters"]!!.jsonPrimitive.double, 0.001)
        assertEquals(110.0, workout["elevationLossMeters"]!!.jsonPrimitive.double, 0.001)
        val timeSeries = workout["timeSeries"]!!.jsonObject
        assertNotNull("iOS-style workout timeSeries.speed missing", timeSeries["speed"])
        assertNotNull("iOS-style workout timeSeries.power missing", timeSeries["power"])
        assertNotNull("iOS-style workout timeSeries.cadence missing", timeSeries["cadence"])
    }

    // ── Full JSON validity ────────────────────────────────────────────────────────────────────

    @Test
    fun fullExport_isValidJson() {
        val data = HealthData(
            date = referenceDate,
            sleep = fullSleepData(withStages = true),
            activity = fullActivityData(),
            heart = fullHeartData(),
            vitals = fullVitalsData(),
            body = BodyData(weight = 75.0, height = 1.78, bmi = 23.7, bodyFatPercentage = 0.18),
            nutrition = NutritionData(dietaryEnergy = 2100.0, protein = 120.0),
            mobility = fullMobilityData(),
            mindfulness = MindfulnessData(mindfulnessMinutes = 15.0),
            workouts = listOf(
                WorkoutData(
                    workoutType = WorkoutType.RUNNING,
                    startTime = referenceDateTime,
                    duration = kotlin.time.Duration.parse("30m"),
                    calories = 300.0,
                    distance = 5000.0,
                ),
            ),
        )
        val output = exporter.export(data, includeGranularData = true)
        // Should parse without exception
        assertDoesNotThrow { Json.parseToJsonElement(output) }
    }

    @Test
    fun fullExport_allExpectedCategoriesPresent() {
        val data = HealthData(
            date = referenceDate,
            sleep = fullSleepData(),
            activity = fullActivityData(),
            heart = fullHeartData(),
            vitals = fullVitalsData(),
            body = BodyData(weight = 75.0),
            nutrition = NutritionData(dietaryEnergy = 2100.0),
            mobility = fullMobilityData(),
            mindfulness = MindfulnessData(mindfulnessMinutes = 15.0),
            workouts = listOf(
                WorkoutData(
                    workoutType = WorkoutType.RUNNING,
                    startTime = referenceDateTime,
                    duration = kotlin.time.Duration.parse("30m"),
                ),
            ),
        )
        val json = exportJson(data)
        for (key in listOf("sleep", "activity", "heart", "vitals", "body", "nutrition", "mobility", "mindfulness", "workouts")) {
            assertNotNull("Missing top-level category: $key", json[key])
        }
    }

    @Test
    fun detailedExport_includesFullSessionAndSampleFidelity() {
        val context = mapOf(
            "meal_type" to "breakfast",
            "specimen_source" to "capillary_blood",
            "relation_to_meal" to "after_meal",
        )
        val metadata = mapOf("health_connect_id" to "record-1")
        val data = HealthData(
            date = referenceDate,
            sleep = SleepData(
                sessions = listOf(
                    SleepSessionEntry(
                        startTime = referenceDateTime.minusHours(8),
                        endTime = referenceDateTime,
                        title = "Night sleep",
                        notes = "Restful",
                        source = "com.example.sleep",
                        metadata = metadata,
                    )
                )
            ),
            heart = HeartData(
                samples = listOf(
                    TimestampedSample(referenceDateTime, 61.0, "com.example.heart", metadata, mapOf("zone" to "rest"))
                )
            ),
            vitals = VitalsData(
                bloodPressureSamples = listOf(
                    BloodPressureSample(
                        time = referenceDateTime,
                        systolic = 120.0,
                        diastolic = 80.0,
                        measurementLocation = "left_upper_arm",
                        bodyPosition = "sitting",
                        source = "com.example.bp",
                        metadata = metadata,
                    )
                ),
                bloodGlucoseSamples = listOf(
                    TimestampedSample(referenceDateTime, 92.0, "com.example.glucose", metadata, context)
                ),
                bodyTemperatureSamples = listOf(
                    TimestampedSample(referenceDateTime, 36.7, "com.example.temp", metadata, mapOf("measurement_location" to "mouth"))
                ),
                basalBodyTemperatureSamples = listOf(
                    TimestampedSample(referenceDateTime, 36.4, "com.example.temp", metadata, mapOf("measurement_location" to "vagina"))
                ),
                skinTemperatureBaseline = 33.1,
                skinTemperatureDeltas = listOf(
                    TimestampedSample(
                        referenceDateTime,
                        0.2,
                        "com.example.skin",
                        metadata,
                        mapOf("measurement_location" to "wrist", "baseline_celsius" to "33.1"),
                    )
                ),
            ),
            mobility = MobilityData(vo2Max = 44.0, vo2MaxMeasurementMethod = "cooper_test"),
        )

        val json = exportJson(data, granular = true)
        val sleepSession = json.getValue("sleep").jsonObject.getValue("sleepSessions").jsonArray.single().jsonObject
        assertEquals("Night sleep", sleepSession.getValue("title").jsonPrimitive.content)
        assertEquals("Restful", sleepSession.getValue("notes").jsonPrimitive.content)
        assertEquals("com.example.sleep", sleepSession.getValue("source").jsonPrimitive.content)
        assertEquals("record-1", sleepSession.getValue("metadata").jsonObject.getValue("health_connect_id").jsonPrimitive.content)

        val heartSample = json.getValue("heart").jsonObject.getValue("heartRateSamples").jsonArray.single().jsonObject
        assertEquals("com.example.heart", heartSample.getValue("source").jsonPrimitive.content)
        assertEquals("rest", heartSample.getValue("context").jsonObject.getValue("zone").jsonPrimitive.content)

        val vitals = json.getValue("vitals").jsonObject
        val pressure = vitals.getValue("bloodPressureSamples").jsonArray.single().jsonObject
        assertEquals("left_upper_arm", pressure.getValue("measurementLocation").jsonPrimitive.content)
        assertEquals("sitting", pressure.getValue("bodyPosition").jsonPrimitive.content)
        assertEquals("com.example.bp", pressure.getValue("source").jsonPrimitive.content)
        val glucose = vitals.getValue("bloodGlucoseSamples").jsonArray.single().jsonObject
        assertEquals("breakfast", glucose.getValue("context").jsonObject.getValue("meal_type").jsonPrimitive.content)
        assertEquals("mouth", vitals.getValue("bodyTemperatureSamples").jsonArray.single().jsonObject
            .getValue("context").jsonObject.getValue("measurement_location").jsonPrimitive.content)
        assertEquals("wrist", vitals.getValue("skinTemperatureDeltas").jsonArray.single().jsonObject
            .getValue("context").jsonObject.getValue("measurement_location").jsonPrimitive.content)
        assertEquals("cooper_test", json.getValue("activity").jsonObject
            .getValue("vo2MaxMeasurementMethod").jsonPrimitive.content)
    }

    @Test
    fun nonDetailedExport_omitsDetailedFidelityFields() {
        val sample = TimestampedSample(referenceDateTime, 61.0, "private.source", mapOf("id" to "private"), mapOf("meal" to "breakfast"))
        val data = HealthData(
            date = referenceDate,
            sleep = SleepData(sessions = listOf(SleepSessionEntry(referenceDateTime.minusHours(8), referenceDateTime, notes = "private"))),
            heart = HeartData(averageHeartRate = 61.0, samples = listOf(sample)),
            vitals = VitalsData(bloodGlucoseAvg = 90.0, bloodGlucoseSamples = listOf(sample)),
            mobility = MobilityData(vo2Max = 44.0, vo2MaxMeasurementMethod = "cooper_test"),
        )

        val json = exportJson(data, granular = false)
        assertNull(json.getValue("sleep").jsonObject["sleepSessions"])
        assertNull(json.getValue("heart").jsonObject["heartRateSamples"])
        assertNull(json.getValue("vitals").jsonObject["bloodGlucoseSamples"])
        assertNull(json.getValue("activity").jsonObject["vo2MaxMeasurementMethod"])
    }

    // ── Helpers ───────────────────────────────────────────────────────────────────────────────

    private fun assertDoesNotThrow(block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            fail("Expected no exception but got: ${e.message}")
        }
    }
}
