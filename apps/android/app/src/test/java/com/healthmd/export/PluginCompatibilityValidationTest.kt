package com.healthmd.export

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.io.File

/**
 * End-to-end plugin compatibility validation.
 *
 * Simulates the exact lookup patterns from each obsidian-health-md parser:
 *  - src/parsers/json-parser.ts     → passthrough + direct field access
 *  - src/parsers/markdown-parser.ts → flat key lookups in YAML frontmatter
 *  - src/parsers/csv-parser.ts      → category+metric label lookups
 *
 * Each test documents whether Android output satisfies the plugin parser, and if not,
 * whether the gap is pre-existing (iOS has the same gap) or Android-specific.
 *
 * Sample files are written to docs/export-contract/samples/ for manual inspection.
 */
class PluginCompatibilityValidationTest {

    private lateinit var jsonExporter: JsonExporter
    private lateinit var basesExporter: ObsidianBasesExporter
    private lateinit var csvExporter: CsvExporter

    @Before
    fun setUp() {
        jsonExporter = JsonExporter()
        basesExporter = ObsidianBasesExporter()
        csvExporter = CsvExporter()
    }

    // ── Helpers (mirrors plugin parser logic) ─────────────────────────────────────────────────

    /** Mirrors json-parser.ts: returns the parsed JSON object if type+date are present. */
    private fun pluginParseJson(content: String): JsonObject? {
        return try {
            val parsed = Json.parseToJsonElement(content).jsonObject
            val type = parsed["type"]?.jsonPrimitive?.content
            val date = parsed["date"]?.jsonPrimitive?.content
            if (type == "health-data" && date != null) parsed else null
        } catch (e: Exception) {
            null
        }
    }

    /** Mirrors csv-parser.ts: case-insensitive category+metric lookup, returns numeric value. */
    private fun csvGetNum(csv: String, category: String, metric: String): Double? {
        val lines = csv.lines().filter { it.isNotBlank() }.drop(1)
        val row = lines.firstOrNull { line ->
            val parts = line.split(",")
            parts.size >= 5 &&
                parts[1].trim().lowercase() == category.lowercase() &&
                parts[2].trim().lowercase() == metric.lowercase()
        } ?: return null
        return row.split(",")[3].trim().toDoubleOrNull()
    }

    private fun csvGetStr(csv: String, category: String, metric: String): String? {
        val lines = csv.lines().filter { it.isNotBlank() }.drop(1)
        val row = lines.firstOrNull { line ->
            val parts = line.split(",")
            parts.size >= 5 &&
                parts[1].trim().lowercase() == category.lowercase() &&
                parts[2].trim().lowercase() == metric.lowercase()
        } ?: return null
        return row.split(",")[3].trim()
    }

    /** Mirrors markdown-parser.ts: get numeric value from YAML frontmatter. */
    private fun fmGetNum(bases: String, key: String): Double? {
        val fm = parseBases(bases)
        return fm[key]?.toDoubleOrNull()
    }

    private fun fmGetStr(bases: String, key: String): String? = parseBases(bases)[key]

    private fun parseBases(output: String): Map<String, String> {
        val result = mutableMapOf<String, String>()
        var inside = false
        for (line in output.lines()) {
            val t = line.trim()
            if (t == "---") { if (!inside) { inside = true; continue } else break }
            if (!inside) continue
            val c = t.indexOf(':'); if (c < 0) continue
            result[t.substring(0, c).trim()] = t.substring(c + 1).trim()
        }
        return result
    }

    /** Write sample file to docs/export-contract/samples/ if the docs dir exists. */
    private fun writeSample(filename: String, content: String) {
        val startDir = System.getProperty("user.dir") ?: return
        var dir: File? = File(startDir).absoluteFile
        while (dir != null) {
            val target = File(dir, "docs/export-contract/samples")
            if (target.parentFile.exists()) {
                target.mkdirs()
                File(target, filename).writeText(content)
                return
            }
            dir = dir.parentFile
        }
    }

    // ── JSON parser compatibility ─────────────────────────────────────────────────────────────

    @Test
    fun json_pluginParsesAndroidOutput_notNull() {
        // json-parser.ts only checks type="health-data" and date
        val output = jsonExporter.export(ExportFixtures.fullDayGranular, includeGranularData = true)
        writeSample("android-full-day-granular.json", output)
        val parsed = pluginParseJson(output)
        assertNotNull("Plugin JSON parser must accept Android output", parsed)
    }

    @Test
    fun json_pluginParsesPartialDay_notNull() {
        val output = jsonExporter.export(ExportFixtures.partialDay)
        writeSample("android-partial-day.json", output)
        assertNotNull(pluginParseJson(output))
    }

    @Test
    fun json_pluginParsesEmptyDay_notNull() {
        val output = jsonExporter.export(ExportFixtures.emptyDay)
        writeSample("android-empty-day.json", output)
        assertNotNull("Empty day still has type+date, plugin must accept it", pluginParseJson(output))
    }

    @Test
    fun json_sleepStages_pluginRequiredFields() {
        // Plugin reads: sleep.sleepStages[].stage, .startDate, .endDate, .durationSeconds
        val output = jsonExporter.export(ExportFixtures.fullDayGranular, includeGranularData = true)
        val parsed = pluginParseJson(output)!!
        val sleepStr = parsed["sleep"].toString()
        assertTrue("sleepStages must be present (plugin reads this array)", sleepStr.contains("sleepStages"))
        assertTrue("stage field required by plugin", sleepStr.contains("\"stage\""))
        assertTrue("startDate required by plugin (renderer.ts sleep-schedule)", sleepStr.contains("\"startDate\""))
        assertTrue("endDate required by plugin", sleepStr.contains("\"endDate\""))
        assertTrue("durationSeconds required by plugin", sleepStr.contains("\"durationSeconds\""))
        assertTrue("startDate must be ISO 8601 (plugin parses as Date)", sleepStr.contains("T"))
    }

    @Test
    fun json_heartSamples_pluginRequiredFields() {
        // Plugin reads: heart.heartRateSamples[].timestamp, .value
        val output = jsonExporter.export(ExportFixtures.fullDayGranular, includeGranularData = true)
        val parsed = pluginParseJson(output)!!
        val heartStr = parsed["heart"].toString()
        assertTrue("heartRateSamples required by heart-terrain.ts", heartStr.contains("heartRateSamples"))
        assertTrue("timestamp field required (plugin uses Date.parse)", heartStr.contains("\"timestamp\""))
        assertTrue("value field required (plugin reads .value)", heartStr.contains("\"value\""))
        assertFalse("bpm key must not exist (T0-05)", heartStr.contains("\"bpm\""))
    }

    @Test
    fun json_hrvSamples_pluginRequiredFields() {
        val output = jsonExporter.export(ExportFixtures.fullDayGranular, includeGranularData = true)
        val parsed = pluginParseJson(output)!!
        val heartStr = parsed["heart"].toString()
        assertTrue("hrvSamples required by hrv-trend.ts", heartStr.contains("hrvSamples"))
        assertFalse("ms key must not exist (T0-06)", heartStr.contains("\"ms\""))
    }

    @Test
    fun json_vitalsSamples_pluginRequiredFields() {
        // Plugin reads: vitals.bloodOxygenSamples[].value, .timestamp
        //               vitals.respiratoryRateSamples[].value, .timestamp
        val output = jsonExporter.export(ExportFixtures.fullDayGranular, includeGranularData = true)
        val parsed = pluginParseJson(output)!!
        val vitalsStr = parsed["vitals"].toString()
        assertTrue("bloodOxygenSamples required by oxygen-river.ts", vitalsStr.contains("bloodOxygenSamples"))
        assertTrue("respiratoryRateSamples required by breathing-wave.ts", vitalsStr.contains("respiratoryRateSamples"))
        assertFalse("percent key must not exist (T0-07)", vitalsStr.contains("\"percent\""))
        assertFalse("breathsPerMin key must not exist (T0-09)", vitalsStr.contains("breathsPerMin"))
    }

    @Test
    fun json_activityVo2Max_underActivityCategory() {
        // Plugin trend-tile reads: d.activity?.vo2Max
        val output = jsonExporter.export(ExportFixtures.fullDay)
        val parsed = pluginParseJson(output)!!
        val act = parsed["activity"]?.jsonObject
        assertNotNull("activity category must be present", act)
        assertNotNull("activity.vo2Max required by trend-tile.ts (T0-10)", act!!["vo2Max"])
        assertEquals(42.5, act["vo2Max"]!!.jsonPrimitive.double, 0.01)
    }

    @Test
    fun json_vitalsAliases_forPluginSummaryCard() {
        // Plugin summary-card.ts reads: d.vitals?.bloodOxygenAvg ?? d.vitals?.bloodOxygenPercent
        //                                d.vitals?.respiratoryRateAvg ?? d.vitals?.respiratoryRate
        val output = jsonExporter.export(ExportFixtures.fullDay)
        val parsed = pluginParseJson(output)!!
        val vitals = parsed["vitals"]!!.jsonObject
        assertNotNull("bloodOxygenAvg required by summary-card.ts", vitals["bloodOxygenAvg"])
        assertNotNull("bloodOxygenPercent fallback alias required", vitals["bloodOxygenPercent"])
        assertNotNull("respiratoryRateAvg required by summary-card.ts", vitals["respiratoryRateAvg"])
        assertNotNull("respiratoryRate alias fallback required", vitals["respiratoryRate"])
    }

    // ── Markdown/Bases parser compatibility ───────────────────────────────────────────────────

    @Test
    fun bases_fullDay_writeSample() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        writeSample("android-full-day.md", output)
        assertTrue("Sample was generated", output.startsWith("---"))
    }

    @Test
    fun bases_pluginReadsSteps() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        val v = fmGetNum(output, "steps")
        assertEquals("Plugin reads 'steps' from FM — must be 12500", 12500.0, v ?: 0.0, 0.01)
    }

    @Test
    fun bases_pluginReadsWalkingRunningKm() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads 'walking_running_km'", fmGetNum(output, "walking_running_km"))
    }

    @Test
    fun bases_pluginReadsActiveCalories() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads 'active_calories'", fmGetNum(output, "active_calories"))
    }

    @Test
    fun bases_pluginReadsExerciseMinutes() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads 'exercise_minutes'", fmGetNum(output, "exercise_minutes"))
    }

    @Test
    fun bases_pluginReadsVo2Max() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertEquals("Plugin reads 'vo2_max'", 42.5, fmGetNum(output, "vo2_max") ?: 0.0, 0.01)
    }

    @Test
    fun bases_pluginReadsRestingHeartRate() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertEquals("Plugin reads 'resting_heart_rate'", 58.0,
            fmGetNum(output, "resting_heart_rate") ?: 0.0, 0.01)
    }

    @Test
    fun bases_pluginReadsHrvMs() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertEquals("Plugin reads 'hrv_ms'", 42.0,
            fmGetNum(output, "hrv_ms") ?: 0.0, 0.01)
    }

    @Test
    fun bases_pluginReadsSleepTotalHours() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        val v = fmGetNum(output, "sleep_total_hours")
        assertNotNull("Plugin reads 'sleep_total_hours'", v)
        assertEquals("sleep_total_hours ≈ 7.75h", 7.75, v ?: 0.0, 0.02)
    }

    @Test
    fun bases_pluginReadsSleepCoreHours() {
        // markdown-parser.ts line: const coreH = getNum(fm, "sleep_core_hours");
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads 'sleep_core_hours' (T1-06 fix)", fmGetNum(output, "sleep_core_hours"))
    }

    @Test
    fun bases_pluginReadsSleepBedtimeWake() {
        // markdown-parser.ts: getStr(fm, "sleep_bedtime"), getStr(fm, "sleep_wake")
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads 'sleep_bedtime' (T1-02 fix)", fmGetStr(output, "sleep_bedtime"))
        assertNotNull("Plugin reads 'sleep_wake' (T1-02 fix)", fmGetStr(output, "sleep_wake"))
    }

    @Test
    fun bases_pluginReadsRespiratoryRate() {
        // markdown-parser.ts: getNum(fm, "respiratory_rate")
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads 'respiratory_rate' alias (T1-05/T1-07 fix)",
            fmGetNum(output, "respiratory_rate"))
    }

    @Test
    fun bases_pluginReadsBloodOxygen() {
        // markdown-parser.ts: getNum(fm, "blood_oxygen") ?? getNum(fm, "blood_oxygen_avg")
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads 'blood_oxygen' alias (T1-05/T1-07 fix)",
            fmGetNum(output, "blood_oxygen"))
        assertNotNull("Plugin reads 'blood_oxygen_avg' fallback (T1-07 fix)",
            fmGetNum(output, "blood_oxygen_avg"))
    }

    @Test
    fun bases_pluginReadsWalkingSpeed() {
        val output = basesExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads 'walking_speed'", fmGetNum(output, "walking_speed"))
    }

    // ── CSV parser compatibility ───────────────────────────────────────────────────────────────

    @Test
    fun csv_fullDay_writeSample() {
        val output = csvExporter.export(ExportFixtures.fullDayGranular, includeGranularData = true)
        writeSample("android-full-day-granular.csv", output)
        assertTrue("CSV sample generated", output.contains("Date,Category"))
    }

    @Test
    fun csv_pluginReadsSteps() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertEquals("Plugin reads Activity,Steps", 12500.0,
            csvGetNum(csv, "Activity", "Steps")!!, 0.01)
    }

    @Test
    fun csv_pluginReadsWalkingRunningDistance() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        // Plugin handles meters > 100 by converting to km
        val v = csvGetNum(csv, "Activity", "Walking Running Distance")
        assertNotNull("Plugin reads Activity,Walking Running Distance (meters)", v)
        assertTrue("Distance > 100 (meters, plugin converts to km)", v!! > 100)
    }

    @Test
    fun csv_pluginReadsActiveCalories() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads Activity,Active Calories",
            csvGetNum(csv, "Activity", "Active Calories"))
    }

    @Test
    fun csv_pluginReadsExerciseMinutes() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads Activity,Exercise Minutes",
            csvGetNum(csv, "Activity", "Exercise Minutes"))
    }

    @Test
    fun csv_pluginReadsFlightsClimbed() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads Activity,Flights Climbed (T1-10 fix)",
            csvGetNum(csv, "Activity", "Flights Climbed"))
    }

    @Test
    fun csv_pluginReadsRestingHeartRate() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertEquals("Plugin reads Heart,Resting Heart Rate", 58.0,
            csvGetNum(csv, "Heart", "Resting Heart Rate")!!, 0.01)
    }

    @Test
    fun csv_pluginReadsAverageHeartRate() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads Heart,Average Heart Rate",
            csvGetNum(csv, "Heart", "Average Heart Rate"))
    }

    @Test
    fun csv_pluginReadsHrv() {
        // Plugin: getNum(rows, "Heart", "HRV") — T1-12 fix
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertEquals("Plugin reads Heart,HRV (T1-12 fix)", 42.0,
            csvGetNum(csv, "Heart", "HRV")!!, 0.01)
    }

    @Test
    fun csv_pluginReadsSleepTotalDuration() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        val v = csvGetNum(csv, "Sleep", "Total Duration")
        assertNotNull("Plugin reads Sleep,Total Duration", v)
        assertEquals("Total Duration in seconds = 27900", 27900.0, v ?: 0.0, 1.0)
    }

    @Test
    fun csv_pluginReadsSleepDeepRem() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads Sleep,Deep Sleep", csvGetNum(csv, "Sleep", "Deep Sleep"))
        assertNotNull("Plugin reads Sleep,REM Sleep", csvGetNum(csv, "Sleep", "REM Sleep"))
    }

    @Test
    fun csv_pluginReadsSleepCoreSleep() {
        // Plugin: coreSleep: getNum(rows, "Sleep", "Core Sleep") ?? 0
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads Sleep,Core Sleep (T1-09 fix)",
            csvGetNum(csv, "Sleep", "Core Sleep"))
    }

    @Test
    fun csv_pluginReadsSleepBedtimeWake() {
        // Plugin: bedtime: getString(rows, "Sleep", "Bedtime")
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads Sleep,Bedtime (T1-02 fix)", csvGetStr(csv, "Sleep", "Bedtime"))
        assertNotNull("Plugin reads Sleep,Wake Time (T1-02 fix)", csvGetStr(csv, "Sleep", "Wake Time"))
    }

    @Test
    fun csv_pluginReadsWalkingSpeed() {
        val csv = csvExporter.export(ExportFixtures.fullDay)
        assertNotNull("Plugin reads Mobility,Walking Speed",
            csvGetNum(csv, "Mobility", "Walking Speed"))
    }

    // ── Known pre-existing gaps (both iOS and Android) ────────────────────────────────────────

    /**
     * These are pre-existing gaps where the plugin CSV parser expects labels that neither
     * iOS nor Android uses in practice. The plugin's CSV parser is slightly stale.
     * No action required — document for awareness.
     */
    @Test
    fun csv_knownGap_vo2MaxNotReadFromCsv() {
        // Plugin reads Activity,VO2 Max — we emit Activity,Cardio Fitness (VO2 Max) (iOS parity).
        // VO2 is correctly read from JSON (activity.vo2Max). This CSV gap is pre-existing on iOS too.
        val csv = csvExporter.export(ExportFixtures.fullDay)
        val pluginVo2 = csvGetNum(csv, "Activity", "VO2 Max")
        assertNull("KNOWN GAP (pre-existing, iOS same): CSV plugin can't read VO2 Max " +
            "because we use iOS label 'Cardio Fitness (VO2 Max)' not plugin's 'VO2 Max'. " +
            "Plugin reads VO2 correctly from JSON (activity.vo2Max).", pluginVo2)
    }

    @Test
    fun csv_knownGap_basalEnergyNotReadFromCsv() {
        // Plugin reads Activity,Basal Energy Burned — we emit Activity,Basal Energy (iOS parity).
        val csv = csvExporter.export(ExportFixtures.fullDay)
        val v = csvGetNum(csv, "Activity", "Basal Energy Burned")
        assertNull("KNOWN GAP (pre-existing, iOS same): Plugin can't read Basal Energy from CSV. " +
            "No visualization currently depends on CSV basal energy.", v)
    }

    @Test
    fun csv_knownGap_respiratoryRateNotReadFromCsv() {
        // Plugin reads Vitals,Respiratory Rate — we emit Vitals,Respiratory Rate Avg (iOS parity).
        val csv = csvExporter.export(ExportFixtures.fullDay)
        val v = csvGetNum(csv, "Vitals", "Respiratory Rate")
        assertNull("KNOWN GAP (pre-existing, iOS same): Plugin reads 'Respiratory Rate' but " +
            "both iOS and Android emit 'Respiratory Rate Avg'. Plugin reads resp rate from JSON.", v)
    }

    @Test
    fun csv_knownGap_bloodOxygenNotReadFromCsv() {
        // Plugin reads Vitals,Blood Oxygen — we emit Vitals,Blood Oxygen Avg (iOS parity).
        val csv = csvExporter.export(ExportFixtures.fullDay)
        val v = csvGetNum(csv, "Vitals", "Blood Oxygen")
        assertNull("KNOWN GAP (pre-existing, iOS same): Plugin reads 'Blood Oxygen' but " +
            "both iOS and Android emit 'Blood Oxygen Avg'. Plugin reads SpO2 from JSON.", v)
    }
}
