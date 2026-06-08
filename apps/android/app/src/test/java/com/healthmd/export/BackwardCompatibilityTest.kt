package com.healthmd.export

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.*
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes

/**
 * Backward-compatibility regression suite.
 *
 * Guards the Android compatibility aliases documented in
 * docs/export-contract/migration-plan.md §1b. These aliases are now opt-in through
 * FormatCustomization.includeAndroidCompatibilityKeys so default exports stay iOS-canonical.
 *
 * DUAL-WRITE ALIASES PROTECTED UNTIL v2.0:
 *  JSON  sleep.lightSleep / sleep.lightSleepFormatted   (alongside sleep.coreSleep)
 *  JSON  activity.wheelchairPushes                      (alongside activity.pushCount)
 *  JSON  mobility.vo2Max                                (alongside activity.vo2Max)
 *  FM    sleep_light_hours                              (alongside sleep_core_hours)
 *  CSV   Sleep,Light Sleep                              (alongside Sleep,Core Sleep)
 *  CSV   Mobility,VO2 Max                               (alongside Activity,Cardio Fitness (VO2 Max))
 */
class BackwardCompatibilityTest {

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

    private val androidCompatibilityCustomization = FormatCustomization(includeAndroidCompatibilityKeys = true)

    private fun parseJson(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
    ): JsonObject =
        Json.parseToJsonElement(json.export(data, customization = customization)).jsonObject

    private fun parseBases(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
    ): Map<String, String> {
        val result = mutableMapOf<String, String>()
        var inside = false
        for (line in bases.export(data, customization).lines()) {
            val t = line.trim()
            if (t == "---") { if (!inside) { inside = true; continue } else break }
            if (!inside) continue
            val c = t.indexOf(':'); if (c < 0) continue
            result[t.substring(0, c).trim()] = t.substring(c + 1).trim()
        }
        return result
    }

    private fun csvRows(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
    ): List<List<String>> =
        csv.export(data, customization = customization)
            .lines()
            .filter { it.isNotBlank() }
            .drop(1)
            .map { it.split(",") }

    private fun csvRowFor(
        category: String,
        metric: String,
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
    ): List<String>? =
        csvRows(data, customization).firstOrNull { it.size > 2 && it[1] == category && it[2] == metric }

    private val sleepData = SleepData(
        totalDuration = 7.hours + 30.minutes,
        lightSleep = 4.hours,
        deepSleep = 1.hours + 30.minutes,
        remSleep = 2.hours,
        sessionStart = ExportFixtures.referenceDateTime.minusHours(8),
        sessionEnd = ExportFixtures.referenceDateTime,
    )
    private val activityData = ActivityData(steps = 5000, wheelchairPushes = 3)
    private val mobilityData = MobilityData(vo2Max = 42.5, walkingSpeed = 1.4)

    // ── JSON backward-compat aliases ──────────────────────────────────────────────────────────

    @Test
    fun json_lightSleep_stillPresentAlongsideCoreSleep() {
        // Protected until v2.0: consumers using sleep.lightSleep must keep working
        val data = ExportFixtures.referenceDate.let {
            com.healthmd.domain.model.HealthData(date = it, sleep = sleepData)
        }
        val j = parseJson(data, androidCompatibilityCustomization)["sleep"]!!.jsonObject
        assertNotNull("sleep.lightSleep dual-write alias must remain until v2.0", j["lightSleep"])
        assertNotNull("sleep.lightSleepFormatted dual-write alias must remain until v2.0",
            j["lightSleepFormatted"])
        // New canonical key also present
        assertNotNull("sleep.coreSleep must be present", j["coreSleep"])
        // Values must be equal (same source data)
        assertEquals(j["lightSleep"]!!.jsonPrimitive.double,
            j["coreSleep"]!!.jsonPrimitive.double, 0.01)
    }

    @Test
    fun json_wheelchairPushes_stillPresentAlongsidePushCount() {
        // Protected until v2.0: consumers using activity.wheelchairPushes must keep working
        val data = com.healthmd.domain.model.HealthData(
            date = ExportFixtures.referenceDate, activity = activityData)
        val act = parseJson(data, androidCompatibilityCustomization)["activity"]!!.jsonObject
        assertNotNull("activity.wheelchairPushes dual-write alias must remain until v2.0",
            act["wheelchairPushes"])
        assertNotNull("activity.pushCount canonical key must be present", act["pushCount"])
        assertEquals(act["wheelchairPushes"]!!.jsonPrimitive.int,
            act["pushCount"]!!.jsonPrimitive.int)
    }

    @Test
    fun json_mobilityVo2Max_stillPresentAlongsideActivityVo2Max() {
        // Protected until v2.0: consumers reading mobility.vo2Max must keep working
        val data = com.healthmd.domain.model.HealthData(
            date = ExportFixtures.referenceDate, mobility = mobilityData)
        val j = parseJson(data, androidCompatibilityCustomization)
        val mobVo2 = j["mobility"]?.jsonObject?.get("vo2Max")?.jsonPrimitive?.double
        val actVo2 = j["activity"]?.jsonObject?.get("vo2Max")?.jsonPrimitive?.double
        assertNotNull("mobility.vo2Max dual-write alias must remain until v2.0", mobVo2)
        assertNotNull("activity.vo2Max canonical key must be present", actVo2)
        assertEquals("Both vo2Max values must be equal", mobVo2!!, actVo2!!, 0.01)
    }

    // ── Frontmatter backward-compat aliases ───────────────────────────────────────────────────

    @Test
    fun fm_sleepLightHours_stillPresentAlongsideCoreSleepHours() {
        // Protected until v2.0
        val data = com.healthmd.domain.model.HealthData(
            date = ExportFixtures.referenceDate, sleep = sleepData)
        val fm = parseBases(data, androidCompatibilityCustomization)
        assertNotNull("sleep_light_hours dual-write must remain until v2.0", fm["sleep_light_hours"])
        assertNotNull("sleep_core_hours canonical key must be present", fm["sleep_core_hours"])
        assertEquals("sleep_light_hours and sleep_core_hours must be equal",
            fm["sleep_light_hours"], fm["sleep_core_hours"])
    }

    // ── CSV backward-compat aliases ───────────────────────────────────────────────────────────

    @Test
    fun csv_lightSleepRow_stillPresentAlongsideCoreSleepRow() {
        // Protected until v2.0
        val data = com.healthmd.domain.model.HealthData(
            date = ExportFixtures.referenceDate, sleep = sleepData)
        val lightRow = csvRowFor("Sleep", "Light Sleep", data, androidCompatibilityCustomization)
        val coreRow = csvRowFor("Sleep", "Core Sleep", data, androidCompatibilityCustomization)
        assertNotNull("Sleep,Light Sleep dual-write must remain until v2.0", lightRow)
        assertNotNull("Sleep,Core Sleep canonical row must be present", coreRow)
        assertEquals("Light Sleep and Core Sleep values must be equal",
            lightRow!![3], coreRow!![3])
    }

    @Test
    fun csv_mobilityVo2Max_stillPresentAlongsideActivityVo2Max() {
        // Protected until v2.0
        val data = com.healthmd.domain.model.HealthData(
            date = ExportFixtures.referenceDate, mobility = mobilityData)
        val mobRow = csvRowFor("Mobility", "VO2 Max", data, androidCompatibilityCustomization)
        val actRow = csvRowFor("Activity", "Cardio Fitness (VO2 Max)", data, androidCompatibilityCustomization)
        assertNotNull("Mobility,VO2 Max dual-write must remain until v2.0", mobRow)
        assertNotNull("Activity,Cardio Fitness (VO2 Max) canonical row must be present", actRow)
    }

    // ── iOS-standard aliases protected indefinitely ───────────────────────────────────────────

    @Test
    fun json_vitalsBackwardCompatAliases_protectedIndefinitely() {
        // These are iOS-standard aliases; never removed
        val data = com.healthmd.domain.model.HealthData(
            date = ExportFixtures.referenceDate,
            vitals = VitalsData(
                respiratoryRateAvg = 15.0, bloodOxygenAvg = 0.97,
                bodyTemperatureAvg = 36.8, bloodPressureSystolicAvg = 120.0,
                bloodPressureDiastolicAvg = 80.0, bloodGlucoseAvg = 95.0,
            ),
        )
        val vitals = parseJson(data)["vitals"]!!.jsonObject
        assertNotNull("respiratoryRate alias (iOS standard)", vitals["respiratoryRate"])
        assertNotNull("bloodOxygen alias (iOS standard)", vitals["bloodOxygen"])
        assertNotNull("bodyTemperature alias (iOS standard)", vitals["bodyTemperature"])
        assertNotNull("bloodPressureSystolic alias (iOS standard)", vitals["bloodPressureSystolic"])
        assertNotNull("bloodPressureDiastolic alias (iOS standard)", vitals["bloodPressureDiastolic"])
        assertNotNull("bloodGlucose alias (iOS standard)", vitals["bloodGlucose"])
    }
}
