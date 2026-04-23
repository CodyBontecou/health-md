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

    private fun exportJson(data: HealthData, granular: Boolean = false): JsonObject {
        val output = exporter.export(data, includeGranularData = granular)
        return Json.parseToJsonElement(output).jsonObject
    }

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
        // Both keys should equal each other (they're aliases)
        assertEquals(sleep["coreSleep"]!!.jsonPrimitive.double,
            sleep["lightSleep"]!!.jsonPrimitive.double, 0.001)
    }

    @Test
    fun sleep_T1_01_lightSleepAlsoPresent() {
        // Android extra kept
        val json = exportJson(HealthData(date = referenceDate, sleep = fullSleepData()))
        val sleep = json["sleep"]!!.jsonObject
        assertNotNull("lightSleep should still be present as Android extra", sleep["lightSleep"])
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
    fun activity_T0_10_vo2MaxAlsoUnderMobility() {
        // Android extra: vo2Max is also kept under mobility
        val data = HealthData(date = referenceDate, mobility = fullMobilityData())
        val json = exportJson(data)
        val mob = json["mobility"]!!.jsonObject
        assertNotNull("vo2Max should still be under mobility as Android extra", mob["vo2Max"])
    }

    @Test
    fun activity_T1_04_pushCountAlias() {
        // T1-04: `pushCount` must be present when wheelchairPushes is set
        val data = HealthData(date = referenceDate, activity = fullActivityData())
        val json = exportJson(data)
        val act = json["activity"]!!.jsonObject
        assertNotNull("pushCount alias missing (T1-04)", act["pushCount"])
        assertNotNull("wheelchairPushes Android extra should remain", act["wheelchairPushes"])
        assertEquals(act["pushCount"]!!.jsonPrimitive.int, act["wheelchairPushes"]!!.jsonPrimitive.int)
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

    // ── Helpers ───────────────────────────────────────────────────────────────────────────────

    private fun assertDoesNotThrow(block: () -> Unit) {
        try {
            block()
        } catch (e: Exception) {
            fail("Expected no exception but got: ${e.message}")
        }
    }
}
