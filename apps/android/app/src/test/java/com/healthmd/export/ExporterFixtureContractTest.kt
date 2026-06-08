package com.healthmd.export

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.HealthData
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.JsonObject
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

/**
 * Cross-format fixture contract tests.
 *
 * Uses canonical fixture datasets from [ExportFixtures] (mirroring iOS ExportFixtures.swift)
 * to verify correct output shape across JSON, Frontmatter/Obsidian Bases, and CSV formats.
 *
 * Coverage goals:
 *  - Empty day   : no health categories in output
 *  - Partial day : only sleep + activity categories
 *  - Full day    : all expected categories present, concrete values match fixture
 *  - Granular day: sample arrays present with correct structure
 *  - Edge cases  : zero values, missing fields handled gracefully
 *  - Cross-format: same metric value consistent across all three formats
 */
class ExporterFixtureContractTest {

    private lateinit var json: JsonExporter
    private lateinit var bases: ObsidianBasesExporter
    private lateinit var csv: CsvExporter

    @Before
    fun setUp() {
        json = JsonExporter()
        bases = ObsidianBasesExporter()
        csv = CsvExporter()
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────────────────

    private fun parseJson(data: HealthData, granular: Boolean = false): JsonObject =
        Json.parseToJsonElement(json.export(data, includeGranularData = granular)).jsonObject

    private fun parseBases(data: HealthData): Map<String, String> {
        val result = mutableMapOf<String, String>()
        var inside = false
        for (line in bases.export(data).lines()) {
            val t = line.trim()
            if (t == "---") { if (!inside) { inside = true; continue } else break }
            if (!inside) continue
            val c = t.indexOf(':')
            if (c < 0) continue
            result[t.substring(0, c).trim()] = t.substring(c + 1).trim()
        }
        return result
    }

    private fun parseCsv(data: HealthData, granular: Boolean = false): List<List<String>> =
        csv.export(data, includeGranularData = granular)
            .lines()
            .filter { it.isNotBlank() }
            .map { it.split(",") }

    private fun csvDataRows(data: HealthData, granular: Boolean = false): List<List<String>> =
        parseCsv(data, granular).drop(1)

    private fun csvRowFor(category: String, metric: String, data: HealthData): List<String>? =
        csvDataRows(data).firstOrNull { it.size > 2 && it[1] == category && it[2] == metric }

    private fun csvCategories(data: HealthData): Set<String> =
        csvDataRows(data).filter { it.size > 1 }.map { it[1] }.toSet()

    // ── Empty day ─────────────────────────────────────────────────────────────────────────────

    @Test
    fun json_emptyDay_hasOnlyTopLevel() {
        val j = parseJson(ExportFixtures.emptyDay)
        assertEquals("2026-03-15", j["date"]?.toString()?.trim('"'))
        assertEquals("\"health-data\"", j["type"].toString())
        for (cat in listOf("sleep", "activity", "heart", "vitals", "body", "nutrition",
                           "mindfulness", "mobility", "workouts")) {
            assertNull("Empty day JSON must not have category: $cat", j[cat])
        }
    }

    @Test
    fun bases_emptyDay_hasOnlyDateAndType() {
        val fm = parseBases(ExportFixtures.emptyDay)
        assertNotNull(fm["date"])
        assertNotNull(fm["type"])
        val healthKeys = fm.keys - setOf("date", "type")
        assertTrue("Empty day bases must have no health keys, found: $healthKeys",
            healthKeys.isEmpty())
    }

    @Test
    fun csv_emptyDay_hasHeaderOnly() {
        val rows = parseCsv(ExportFixtures.emptyDay)
        assertEquals("Empty day CSV must have only header row", 1, rows.size)
        assertEquals("Date", rows[0][0])
        assertEquals("Timestamp", rows[0][5])
    }

    // ── Partial day ───────────────────────────────────────────────────────────────────────────

    @Test
    fun json_partialDay_hasSleepAndActivityOnly() {
        val j = parseJson(ExportFixtures.partialDay)
        assertNotNull(j["sleep"])
        assertNotNull(j["activity"])
        // Heart/vitals/body/nutrition not in partialDay
        assertNull(j["heart"])
        assertNull(j["vitals"])
        assertNull(j["body"])
        assertNull(j["nutrition"])
    }

    @Test
    fun json_partialDay_stepsValue() {
        val j = parseJson(ExportFixtures.partialDay)
        val steps = j["activity"]?.jsonObject?.get("steps").toString().toInt()
        assertEquals("partialDay steps should be 8500", 8500, steps)
    }

    @Test
    fun bases_partialDay_hasSleepAndActivityKeys() {
        val fm = parseBases(ExportFixtures.partialDay)
        assertNotNull(fm["sleep_total_hours"])
        assertNotNull(fm["sleep_deep_hours"])
        assertNotNull(fm["sleep_rem_hours"])
        assertNotNull(fm["sleep_core_hours"])   // T1-06 alias
        assertNotNull(fm["steps"])
        assertNotNull(fm["active_calories"])
        // No heart/body
        assertNull(fm["resting_heart_rate"])
        assertNull(fm["weight_kg"])
    }

    @Test
    fun bases_partialDay_stepsValue() {
        val fm = parseBases(ExportFixtures.partialDay)
        assertEquals("steps should be 8500", "8500", fm["steps"])
    }

    @Test
    fun csv_partialDay_hasSleepAndActivityOnly() {
        val cats = csvCategories(ExportFixtures.partialDay)
        assertTrue(cats.contains("Sleep"))
        assertTrue(cats.contains("Activity"))
        assertFalse("Heart not in partialDay CSV", cats.contains("Heart"))
        assertFalse("Body not in partialDay CSV", cats.contains("Body"))
    }

    @Test
    fun csv_partialDay_stepsRow() {
        val row = csvRowFor("Activity", "Steps", ExportFixtures.partialDay)
        assertNotNull("Steps row must be present", row)
        assertEquals("8500", row!![3])
        assertEquals("count", row[4])
    }

    // ── Full day ──────────────────────────────────────────────────────────────────────────────

    @Test
    fun json_fullDay_hasAllExpectedCategories() {
        val j = parseJson(ExportFixtures.fullDay)
        for (cat in listOf("sleep", "activity", "heart", "vitals", "body",
                           "nutrition", "mindfulness", "mobility", "workouts")) {
            assertNotNull("fullDay JSON missing category: $cat", j[cat])
        }
    }

    @Test
    fun json_fullDay_sleepValues() {
        val sleep = parseJson(ExportFixtures.fullDay)["sleep"]!!.jsonObject
        // totalDuration = 7h45m = 27900s
        assertEquals(27900.0, sleep["totalDuration"]!!.toString().toDouble(), 1.0)
        assertNotNull(sleep["totalDurationFormatted"])
        assertNotNull(sleep["deepSleep"])
        assertNotNull(sleep["remSleep"])
        assertNotNull(sleep["coreSleep"])     // T1-01 iOS canonical key
        assertNull(sleep["lightSleep"])       // Android compatibility key is opt-in
        assertNotNull(sleep["awakeTime"])
        assertNotNull(sleep["inBedTime"])
        // bedtime/wakeTime from sessionStart/End
        assertNotNull("bedtime must come from sessionStart", sleep["bedtime"])
        assertNotNull("wakeTime must come from sessionEnd", sleep["wakeTime"])
    }

    @Test
    fun json_fullDay_activityValues() {
        val act = parseJson(ExportFixtures.fullDay)["activity"]!!.jsonObject
        assertEquals(12500, act["steps"]!!.toString().toInt())
        assertNotNull("vo2Max must be under activity (T0-10)", act["vo2Max"])
        assertEquals(42.5, act["vo2Max"]!!.toString().toDouble(), 0.01)
    }

    @Test
    fun json_fullDay_heartValues() {
        val heart = parseJson(ExportFixtures.fullDay)["heart"]!!.jsonObject
        assertEquals(58.0, heart["restingHeartRate"]!!.toString().toDouble(), 0.01)
        assertEquals(42.0, heart["hrv"]!!.toString().toDouble(), 0.01)
        assertEquals(72.0, heart["averageHeartRate"]!!.toString().toDouble(), 0.01)
    }

    @Test
    fun json_fullDay_vitalsValues() {
        val vitals = parseJson(ExportFixtures.fullDay)["vitals"]!!.jsonObject
        assertEquals(15.0, vitals["respiratoryRateAvg"]!!.toString().toDouble(), 0.01)
        // bloodOxygenAvg stored as fraction
        assertEquals(0.97, vitals["bloodOxygenAvg"]!!.toString().toDouble(), 0.001)
        // Percent alias = 97.0
        assertEquals(97.0, vitals["bloodOxygenPercent"]!!.toString().toDouble(), 0.01)
        // Backward-compat aliases
        assertNotNull(vitals["respiratoryRate"])
        assertNotNull(vitals["bloodOxygen"])
    }

    @Test
    fun json_fullDay_bodyValues() {
        val body = parseJson(ExportFixtures.fullDay)["body"]!!.jsonObject
        assertEquals(75.0, body["weight"]!!.toString().toDouble(), 0.01)
        // bodyFatPercent = bodyFatPercentage * 100 = 18.0
        assertEquals(18.0, body["bodyFatPercent"]!!.toString().toDouble(), 0.01)
    }

    @Test
    fun json_fullDay_mindfulnessKey() {
        val mind = parseJson(ExportFixtures.fullDay)["mindfulness"]!!.jsonObject
        // T1-03: key is `mindfulMinutes` not `mindfulnessMinutes`
        assertNotNull("mindfulMinutes key missing (T1-03)", mind["mindfulMinutes"])
        assertNull("mindfulnessMinutes old key must not exist", mind["mindfulnessMinutes"])
        assertEquals(15.0, mind["mindfulMinutes"]!!.toString().toDouble(), 0.01)
    }

    @Test
    fun json_fullDay_workouts() {
        val workouts = parseJson(ExportFixtures.fullDay)["workouts"]
        assertNotNull(workouts)
        val arr = workouts!!.toString()
        assertTrue("workouts must be non-empty array", arr.contains("Running"))
    }

    @Test
    fun bases_fullDay_coreMetricKeys() {
        val fm = parseBases(ExportFixtures.fullDay)
        // Sleep
        assertNotNull(fm["sleep_total_hours"])
        assertNotNull(fm["sleep_core_hours"])   // T1-06
        assertNull(fm["sleep_light_hours"])     // Android compatibility key is opt-in
        assertNotNull(fm["sleep_bedtime"])      // T1-02
        assertNotNull(fm["sleep_wake"])         // T1-02
        // Activity
        assertEquals("12500", fm["steps"])
        assertNotNull(fm["walking_running_km"])
        // Heart
        assertNotNull(fm["resting_heart_rate"])
        assertNotNull(fm["hrv_ms"])
        // Vitals
        assertNotNull(fm["blood_oxygen"])
        assertNotNull(fm["blood_oxygen_avg"])   // T1-07
        assertNotNull(fm["blood_oxygen_min"])   // T1-07
        assertNotNull(fm["blood_oxygen_max"])   // T1-07
        assertNotNull(fm["respiratory_rate"])
        assertNotNull(fm["respiratory_rate_avg"]) // T1-07
        // Body
        assertNotNull(fm["weight_kg"])
        assertNotNull(fm["bmi"])
        // Nutrition
        assertNotNull(fm["dietary_calories"])
        assertNotNull(fm["protein_g"])
        // Mindfulness
        assertNotNull(fm["mindful_minutes"])
        assertNotNull(fm["mindful_sessions"])   // T1-14
        // VO2
        assertNotNull(fm["vo2_max"])
    }

    @Test
    fun csv_fullDay_hasAllCategories() {
        val cats = csvCategories(ExportFixtures.fullDay)
        for (cat in listOf("Sleep", "Activity", "Heart", "Vitals", "Body",
                           "Nutrition", "Mindfulness", "Mobility", "Workouts")) {
            assertTrue("CSV missing category: $cat", cats.contains(cat))
        }
    }

    @Test
    fun csv_fullDay_sleepHasCoreSleepRow() {
        val row = csvRowFor("Sleep", "Core Sleep", ExportFixtures.fullDay)
        assertNotNull("Core Sleep row must be present (T1-09)", row)
        assertEquals("seconds", row!![4])
    }

    @Test
    fun csv_fullDay_activityFlightsCombined() {
        // T1-10: Flights Climbed (not Floors Climbed)
        val row = csvRowFor("Activity", "Flights Climbed", ExportFixtures.fullDay)
        assertNotNull("Flights Climbed row missing (T1-10)", row)
        assertEquals("8", row!![3])
    }

    @Test
    fun csv_fullDay_vo2MaxUnderActivity() {
        // T1-11: Activity,Cardio Fitness (VO2 Max)
        val row = csvRowFor("Activity", "Cardio Fitness (VO2 Max)", ExportFixtures.fullDay)
        assertNotNull("Activity,Cardio Fitness (VO2 Max) row missing (T1-11)", row)
    }

    @Test
    fun csv_fullDay_hrvLabel() {
        // T1-12: HRV (not HRV (RMSSD))
        val row = csvRowFor("Heart", "HRV", ExportFixtures.fullDay)
        assertNotNull("HRV row must use 'HRV' label (T1-12)", row)
        assertNull("HRV (RMSSD) old label must not exist",
            csvRowFor("Heart", "HRV (RMSSD)", ExportFixtures.fullDay))
    }

    @Test
    fun csv_fullDay_allRowsHave6Columns() {
        val rows = csvDataRows(ExportFixtures.fullDay)
        for (row in rows) {
            // Values with quotes might have embedded commas; check length >= 6
            assertTrue("Row must have at least 6 parts: $row", row.size >= 6)
        }
    }

    // ── Granular day ──────────────────────────────────────────────────────────────────────────

    @Test
    fun json_granularDay_hasSleepStagesArray() {
        val sleep = parseJson(ExportFixtures.fullDayGranular, granular = true)["sleep"]!!.jsonObject
        // T0-01: array key must be `sleepStages`
        assertNotNull("sleepStages array missing (T0-01)", sleep["sleepStages"])
        assertNull("old `stages` key must not exist (T0-01)", sleep["stages"])
    }

    @Test
    fun json_granularDay_sleepStageItemShape() {
        val sleep = parseJson(ExportFixtures.fullDayGranular, granular = true)["sleep"]!!.jsonObject
        val stagesStr = sleep["sleepStages"].toString()
        // T0-02: must contain `startDate` and `endDate`
        assertTrue("sleepStages items must have `startDate` (T0-02)", stagesStr.contains("startDate"))
        assertTrue("sleepStages items must have `endDate` (T0-02)", stagesStr.contains("endDate"))
        // T0-03: must contain `durationSeconds`
        assertTrue("sleepStages items must have `durationSeconds` (T0-03)", stagesStr.contains("durationSeconds"))
        // T0-02: must NOT contain old key names
        assertFalse("startTime old key must not exist (T0-02)", stagesStr.contains("\"startTime\""))
        assertFalse("endTime old key must not exist (T0-02)", stagesStr.contains("\"endTime\""))
    }

    @Test
    fun json_granularDay_stageTimestampsAreIso8601() {
        val sleep = parseJson(ExportFixtures.fullDayGranular, granular = true)["sleep"]!!.jsonObject
        val stagesStr = sleep["sleepStages"].toString()
        // ISO 8601 contains 'T' between date and time
        assertTrue("Sleep stage timestamps must be ISO 8601 (T0-04)", stagesStr.contains("T"))
    }

    @Test
    fun json_granularDay_hasHeartRateSamples() {
        val heart = parseJson(ExportFixtures.fullDayGranular, granular = true)["heart"]!!.jsonObject
        assertNotNull("heartRateSamples array missing", heart["heartRateSamples"])
        val samplesStr = heart["heartRateSamples"].toString()
        // T0-05: key `value` (not `bpm`)
        assertTrue("HR sample must use `value` key (T0-05)", samplesStr.contains("\"value\""))
        assertFalse("HR sample must not use `bpm` key (T0-05)", samplesStr.contains("\"bpm\""))
        // T0-04: timestamp key + ISO 8601
        assertTrue("HR sample must use `timestamp` key (T0-04)", samplesStr.contains("\"timestamp\""))
        assertFalse("HR sample must not use `time` key (T0-04)", samplesStr.contains("\"time\""))
    }

    @Test
    fun json_granularDay_hasHrvSamples() {
        val heart = parseJson(ExportFixtures.fullDayGranular, granular = true)["heart"]!!.jsonObject
        assertNotNull("hrvSamples array missing", heart["hrvSamples"])
        val samplesStr = heart["hrvSamples"].toString()
        // T0-06: key `value` (not `ms`)
        assertTrue("HRV sample must use `value` key (T0-06)", samplesStr.contains("\"value\""))
        assertFalse("HRV sample must not use `ms` key (T0-06)", samplesStr.contains("\"ms\""))
    }

    @Test
    fun json_granularDay_hasVitalsSamples() {
        val vitals = parseJson(ExportFixtures.fullDayGranular, granular = true)["vitals"]!!.jsonObject
        assertNotNull("bloodOxygenSamples missing", vitals["bloodOxygenSamples"])
        assertNotNull("bloodGlucoseSamples missing", vitals["bloodGlucoseSamples"])
        assertNotNull("respiratoryRateSamples missing", vitals["respiratoryRateSamples"])

        val spo2Str = vitals["bloodOxygenSamples"].toString()
        // T0-07: `value` key (not `percent`)
        assertTrue("bloodOxygenSamples must use `value` key (T0-07)", spo2Str.contains("\"value\""))
        assertFalse("bloodOxygenSamples must not use `percent` key (T0-07)", spo2Str.contains("\"percent\""))
        // T0-04: ISO 8601 timestamps
        assertTrue("bloodOxygenSamples timestamps must be ISO 8601 (T0-04)", spo2Str.contains("T"))

        val glucStr = vitals["bloodGlucoseSamples"].toString()
        // T0-08: `value` (not `mgPerDl`)
        assertTrue("bloodGlucoseSamples must use `value` key (T0-08)", glucStr.contains("\"value\""))
        assertFalse("bloodGlucoseSamples must not use `mgPerDl` key (T0-08)", glucStr.contains("mgPerDl"))

        val rrStr = vitals["respiratoryRateSamples"].toString()
        // T0-09: `value` (not `breathsPerMin`)
        assertTrue("respiratoryRateSamples must use `value` key (T0-09)", rrStr.contains("\"value\""))
        assertFalse("respiratoryRateSamples must not use `breathsPerMin` key (T0-09)", rrStr.contains("breathsPerMin"))
    }

    @Test
    fun json_nonGranularDay_hasNoSampleArrays() {
        // Without granular data, sample arrays must be absent
        val j = parseJson(ExportFixtures.fullDayGranular, granular = false)
        val heartStr = j["heart"].toString()
        assertFalse("fullDay (non-granular) must not have heartRateSamples", heartStr.contains("heartRateSamples"))
        assertFalse("fullDay (non-granular) must not have hrvSamples", heartStr.contains("hrvSamples"))
        val sleepStr = j["sleep"].toString()
        assertFalse("fullDay (non-granular) must not have sleepStages", sleepStr.contains("sleepStages"))
    }

    @Test
    fun csv_granularDay_sleepStageHasIso8601Timestamp() {
        val rows = parseCsv(ExportFixtures.fullDayGranular, granular = true)
            .drop(1)
            .firstOrNull { it.size > 2 && it[1] == "Sleep" && it[2] == "Sleep Stage" }
        assertNotNull("Sleep Stage row missing", rows)
        val ts = rows!![5]
        assertTrue("Sleep Stage Timestamp must be ISO 8601 (T0-11): $ts", ts.contains("T"))
        assertFalse("Sleep Stage Timestamp must not be empty (T0-11)", ts.isBlank())
    }

    @Test
    fun csv_granularDay_heartSampleLabel_bloodOxygenSampleLabel() {
        val csvRows = parseCsv(ExportFixtures.fullDayGranular, granular = true).drop(1)
        // T1-13: Blood Oxygen Sample (not SpO2 Sample)
        val spo2Row = csvRows.firstOrNull { it.size > 2 && it[1] == "Vitals" && it[2] == "Blood Oxygen Sample" }
        assertNotNull("Blood Oxygen Sample row missing (T1-13)", spo2Row)
        assertNull("SpO2 Sample old label must not exist (T1-13)",
            csvRows.firstOrNull { it.size > 2 && it[2] == "SpO2 Sample" })
    }

    // ── Edge case day ─────────────────────────────────────────────────────────────────────────

    @Test
    fun json_edgeCaseDay_zeroSleepNotEmitted() {
        // SleepData with only Duration.ZERO → hasData = false → no sleep in JSON
        val j = parseJson(ExportFixtures.edgeCaseDay)
        assertNull("Zero-valued sleep must not appear in JSON", j["sleep"])
    }

    @Test
    fun json_edgeCaseDay_activityWithZeroStepsPresent() {
        // ActivityData with steps=0 → hasData=true (steps is non-null)
        val j = parseJson(ExportFixtures.edgeCaseDay)
        assertNotNull("Activity with 0 steps must still be present", j["activity"])
    }

    @Test
    fun json_edgeCaseDay_vitalsWithTempOnlyPresent() {
        val j = parseJson(ExportFixtures.edgeCaseDay)
        assertNotNull("Vitals must be present when bodyTemperatureAvg is set", j["vitals"])
    }

    @Test
    fun json_edgeCaseDay_noNullFields() {
        // No JSON null values should be present (omit-when-null pattern)
        val output = json.export(ExportFixtures.edgeCaseDay)
        assertFalse("JSON must not contain explicit null values", output.contains(": null"))
    }

    @Test
    fun bases_edgeCaseDay_handlesGracefully() {
        // Should not throw; should return valid frontmatter
        val output = bases.export(ExportFixtures.edgeCaseDay)
        assertTrue("Bases output must start with ---", output.startsWith("---"))
        assertTrue("Bases output must end with closing ---", output.contains("\n---"))
    }

    @Test
    fun csv_edgeCaseDay_noSleepCategory() {
        val cats = csvCategories(ExportFixtures.edgeCaseDay)
        assertFalse("Zero sleep → no Sleep category in CSV", cats.contains("Sleep"))
    }

    // ── Cross-format consistency ───────────────────────────────────────────────────────────────

    /**
     * The same metric value (steps) must be consistent across JSON, Frontmatter, and CSV.
     */
    @Test
    fun crossFormat_steps_consistent() {
        val data = ExportFixtures.fullDay
        // JSON
        val j = parseJson(data)
        val jsonSteps = j["activity"]!!.jsonObject["steps"]!!.toString().toInt()
        // Frontmatter
        val fmSteps = parseBases(data)["steps"]?.toInt()
        // CSV
        val csvRow = csvRowFor("Activity", "Steps", data)
        val csvSteps = csvRow!![3].toInt()

        assertEquals("JSON and FM steps must agree", jsonSteps, fmSteps)
        assertEquals("JSON and CSV steps must agree", jsonSteps, csvSteps)
        assertEquals("All formats: steps = 12500", 12500, jsonSteps)
    }

    /**
     * Blood oxygen is stored as fraction (0.97) in JSON but as percent (97) in frontmatter/CSV.
     */
    @Test
    fun crossFormat_bloodOxygen_scaleConsistency() {
        val data = ExportFixtures.fullDay
        // JSON: fraction
        val j = parseJson(data)
        val jsonFraction = j["vitals"]!!.jsonObject["bloodOxygenAvg"]!!.toString().toDouble()
        // JSON percent alias
        val jsonPct = j["vitals"]!!.jsonObject["bloodOxygenPercent"]!!.toString().toDouble()
        // Frontmatter: whole-number percent
        val fmPct = parseBases(data)["blood_oxygen"]?.toInt()
        // CSV: percent
        val csvRow = csvRowFor("Vitals", "Blood Oxygen Avg", data)
        val csvPct = csvRow!![3].toDouble()

        assertEquals("JSON bloodOxygenAvg should be fraction 0.97", 0.97, jsonFraction, 0.001)
        assertEquals("JSON bloodOxygenPercent should be 97.0", 97.0, jsonPct, 0.01)
        assertEquals("FM blood_oxygen should be 97", 97, fmPct)
        assertEquals("CSV Blood Oxygen Avg should be ~97", 97.0, csvPct, 0.01)
    }

    /**
     * Sleep duration in JSON (seconds) vs frontmatter (hours) vs CSV (seconds).
     */
    @Test
    fun crossFormat_sleepDuration_scaleConsistency() {
        val data = ExportFixtures.fullDay
        // fullDay totalDuration = 7h45m = 27900s = 7.75h
        val j = parseJson(data)
        val jsonSecs = j["sleep"]!!.jsonObject["totalDuration"]!!.toString().toDouble()

        val fmHours = parseBases(data)["sleep_total_hours"]?.toDouble()

        val csvRow = csvRowFor("Sleep", "Total Duration", data)
        val csvSecs = csvRow!![3].toDouble()

        assertEquals("JSON sleep seconds = 27900", 27900.0, jsonSecs, 1.0)
        assertEquals("FM sleep hours ≈ 7.75", 7.75, fmHours!!, 0.02)
        assertEquals("CSV sleep seconds = JSON sleep seconds", jsonSecs, csvSecs, 1.0)
    }

    /**
     * HRV appears in JSON, frontmatter, and CSV under aligned keys/labels.
     */
    @Test
    fun crossFormat_hrv_consistent() {
        val data = ExportFixtures.fullDay
        // JSON: heart.hrv
        val jsonHrv = parseJson(data)["heart"]!!.jsonObject["hrv"]!!.toString().toDouble()
        // FM: hrv_ms
        val fmHrv = parseBases(data)["hrv_ms"]?.toDouble()
        // CSV: Heart,HRV
        val csvHrv = csvRowFor("Heart", "HRV", data)!![3].toDouble()

        assertEquals("JSON hrv = 42.0", 42.0, jsonHrv, 0.01)
        assertEquals("FM hrv_ms ≈ 42.0", 42.0, fmHrv!!, 0.01)
        assertEquals("CSV HRV = 42.0", 42.0, csvHrv, 0.01)
    }

    /**
     * VO2 Max: default JSON emits under iOS-canonical `activity.vo2Max` only;
     * CSV emits `Activity,Cardio Fitness (VO2 Max)`.
     */
    @Test
    fun crossFormat_vo2Max_placement() {
        val data = ExportFixtures.fullDay
        val j = parseJson(data)
        // JSON: must be under activity (T0-10)
        val actVo2 = j["activity"]!!.jsonObject["vo2Max"]!!.toString().toDouble()
        // JSON: mobility.vo2Max is now an opt-in Android compatibility key.
        val mobVo2 = j["mobility"]?.jsonObject?.get("vo2Max")
        // FM: vo2_max
        val fmVo2 = parseBases(data)["vo2_max"]?.toDouble()
        // CSV: Activity,Cardio Fitness (VO2 Max)
        val csvRow = csvRowFor("Activity", "Cardio Fitness (VO2 Max)", data)

        assertEquals("activity.vo2Max = 42.5", 42.5, actVo2, 0.01)
        assertNull("mobility.vo2Max should be omitted by default", mobVo2)
        assertEquals("FM vo2_max = 42.5", 42.5, fmVo2!!, 0.01)
        assertNotNull("CSV Activity,Cardio Fitness (VO2 Max) must be present (T1-11)", csvRow)
    }
}
