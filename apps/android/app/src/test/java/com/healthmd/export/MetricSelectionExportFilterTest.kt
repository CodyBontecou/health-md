package com.healthmd.export

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.MetricSelectionState
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class MetricSelectionExportFilterTest {
    private val jsonExporter = JsonExporter()
    private val csvExporter = CsvExporter()
    private val basesExporter = ObsidianBasesExporter()

    @Test
    fun disabledSteps_areOmittedFromAllFormats() {
        val selection = MetricSelectionState().copy(
            enabledMetrics = MetricSelectionState().enabledMetrics - "steps",
        )
        val filtered = ExportFixtures.fullDay.filtered(selection)

        val json = Json.parseToJsonElement(jsonExporter.export(filtered)).jsonObject
        val activity = json["activity"]?.jsonObject
        assertNotNull("Activity should remain because other activity metrics are enabled", activity)
        assertNull("Disabled steps must be omitted from JSON", activity!!["steps"])

        val bases = basesExporter.export(filtered)
        assertFalse("Disabled steps must be omitted from frontmatter", bases.contains("\nsteps:"))

        val csv = csvExporter.export(filtered)
        assertFalse("Disabled steps must be omitted from CSV", csv.contains(",Activity,Steps,"))
        assertTrue("Other activity rows should still export", csv.contains(",Activity,Active Calories,"))
    }

    @Test
    fun disabledSleepStage_removesAggregateAndGranularStageRows() {
        val selection = MetricSelectionState().copy(
            enabledMetrics = MetricSelectionState().enabledMetrics - "sleep_deep",
        )
        val filtered = ExportFixtures.fullDayGranular.filtered(selection)

        val json = jsonExporter.export(filtered, includeGranularData = true)
        assertFalse("Disabled deep sleep aggregate must be omitted", json.contains("deepSleep"))
        assertFalse("Disabled deep sleep stage samples must be omitted", json.contains("\"stage\": \"deep\""))
        assertTrue("Other sleep stages should remain", json.contains("\"stage\": \"rem\""))

        val csv = csvExporter.export(filtered, includeGranularData = true)
        assertFalse("Disabled deep sleep CSV aggregate must be omitted", csv.contains(",Sleep,Deep Sleep,"))
        assertFalse("Disabled deep sleep granular row must be omitted", csv.contains("deep ("))
    }

    @Test
    fun disabledVitalsSample_removesAggregateAndGranularSampleRows() {
        val data = ExportFixtures.fullDayGranular.copy(
            vitals = ExportFixtures.fullDayGranular.vitals.copy(
                bloodGlucoseAvg = 100.0,
                bloodGlucoseMin = 90.0,
                bloodGlucoseMax = 110.0,
            ),
        )
        val selection = MetricSelectionState().copy(
            enabledMetrics = MetricSelectionState().enabledMetrics - "blood_glucose",
        )
        val filtered = data.filtered(selection)

        val json = jsonExporter.export(filtered, includeGranularData = true)
        assertFalse("Disabled glucose aggregate must be omitted", json.contains("bloodGlucose"))
        assertFalse("Disabled glucose samples must be omitted", json.contains("bloodGlucoseSamples"))

        val csv = csvExporter.export(filtered, includeGranularData = true)
        assertFalse("Disabled glucose aggregate must be omitted from CSV", csv.contains("Blood Glucose Avg"))
        assertFalse("Disabled glucose samples must be omitted from CSV", csv.contains("Blood Glucose Sample"))
    }

    @Test
    fun enabledCategoryWithSomeMetricsDisabled_keepsEnabledMetricsOnly() {
        val selection = MetricSelectionState().copy(
            enabledMetrics = MetricSelectionState().enabledMetrics - setOf("active_calories", "distance"),
        )
        val filtered = ExportFixtures.partialDay.filtered(selection)
        val csv = csvExporter.export(filtered)

        assertTrue("Steps should remain enabled", csv.contains(",Activity,Steps,8500,"))
        assertFalse("Active calories should be disabled", csv.contains(",Activity,Active Calories,"))
        assertFalse("Distance should be disabled", csv.contains(",Activity,Walking Running Distance,"))
    }
}
