package com.healthmd.domain.render

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import com.healthmd.domain.exportengine.AndroidWakeDateSourceProjection
import com.healthmd.domain.model.HealthDataFields
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

/**
 * #353: in "Morning ends" Bases notes each native frontmatter block follows the Format → Custom
 * switches of the fields that own its records, while the records stay in CSV and the Markdown
 * body. Apple applies the same table in WakeDateNativeFrontmatterOwners.swift.
 */
class NativeBasesFrontmatterOwnershipTest {
    private val date = "2026-11-01"
    private val adapter = HealthMdRenderInputAdapter

    private fun root(text: String) = Json.parseToJsonElement(text).jsonObject
    private fun off(vararg keys: String): (String) -> Boolean = { it !in keys }

    /** Bases frontmatter lines per block key. */
    private fun bases(details: JsonObject): Map<String, List<String>> =
        details.getValue("bases_frontmatter_blocks").jsonArray.associate { block ->
            block.jsonObject.getValue("key").jsonPrimitive.content to
                block.jsonObject.getValue("lines").jsonArray.map { it.jsonPrimitive.content }
        }

    private fun csvRows(details: JsonObject) = details.getValue("csv_rows").jsonArray.size
    private fun markdownBlocks(details: JsonObject) = details.getValue("markdown_blocks").jsonArray.size

    @Test
    fun quantityLinesFollowEachSeriesOwners() {
        val source = root("""{"heart":{"heartRateSamples":[{"timestamp":"2026-11-01T01:00:00Z","value":61.5}]},
            "vitals":{"bloodOxygenSamples":[{"timestamp":"2026-11-01T01:00:00Z","value":0.97}]}}""")
        val selected = listOf("average_heart_rate", "heart_rate_min", "heart_rate_max", "blood_oxygen")
        val shown = adapter.quantityDetails(source, date, selected)
        assertThat(bases(shown).getValue("native_quantity_details")).hasSize(2)

        // One heart rate field still on keeps its samples.
        val oneOn = adapter.quantityDetails(source, date, selected, off("heart_rate_min", "heart_rate_max"))
        assertThat(bases(oneOn).getValue("native_quantity_details")).hasSize(2)

        val heartOff = adapter.quantityDetails(source, date, selected,
            off("average_heart_rate", "heart_rate_min", "heart_rate_max"))
        val lines = bases(heartOff).getValue("native_quantity_details")
        assertThat(lines).hasSize(1)
        assertThat(lines.single()).contains("blood_oxygen")

        val allOff = adapter.quantityDetails(source, date, selected) { false }
        assertThat(bases(allOff)).isEmpty()
        assertThat(csvRows(allOff)).isEqualTo(csvRows(shown))
        assertThat(markdownBlocks(allOff)).isEqualTo(markdownBlocks(shown))
    }

    @Test
    fun sleepStageAndSessionLinesFollowTheirFields() {
        val stages = root("""{"s":[{"stage":"deep","startDate":"2026-11-01T01:00:00Z","endDate":"2026-11-01T01:10:00Z"},
            {"stage":"rem","startDate":"2026-11-01T01:10:00Z","endDate":"2026-11-01T01:20:00Z"}]}""").getValue("s").jsonArray
        val sessions = root("""{"s":[{"startTimeISO":"2026-11-01T01:00:00Z","endTimeISO":"2026-11-01T02:00:00Z"}]}""").getValue("s").jsonArray
        val selected = listOf("sleep_deep_hours", "sleep_rem_hours", "sleep_total_hours", "sleep_in_bed_hours")

        val shown = adapter.sleepDetails(stages, sessions, date, selected)
        assertThat(bases(shown).keys).containsExactly("sleep_stage_details", "sleep_session_details")

        val deepOff = adapter.sleepDetails(stages, sessions, date, selected, off("sleep_deep_hours"))
        val stageLines = bases(deepOff).getValue("sleep_stage_details")
        assertThat(stageLines).hasSize(1)
        assertThat(stageLines.single()).contains("\"rem\"")

        // A block with no lines left is omitted rather than written as an empty key.
        val stagesOff = adapter.sleepDetails(stages, sessions, date, selected, off("sleep_deep_hours", "sleep_rem_hours"))
        assertThat(bases(stagesOff).keys).containsExactly("sleep_session_details")
        val sessionsOff = adapter.sleepDetails(stages, sessions, date, selected, off("sleep_total_hours", "sleep_in_bed_hours"))
        assertThat(bases(sessionsOff).keys).containsExactly("sleep_stage_details")
        val allOff = adapter.sleepDetails(stages, sessions, date, selected) { false }
        assertThat(bases(allOff)).isEmpty()
        assertThat(csvRows(allOff)).isEqualTo(csvRows(shown))
        assertThat(markdownBlocks(allOff)).isEqualTo(markdownBlocks(shown))
    }

    @Test
    fun bloodPressurePairNeedsBothFields() {
        val source = root("""{"vitals":{"bloodPressureSamples":[{"timestamp":"2026-11-01T01:00:00Z","systolic":118,"diastolic":76}]}}""")
        val selected = listOf("blood_pressure_systolic", "blood_pressure_diastolic")
        assertThat(bases(adapter.bloodPressureDetails(source, date, selected)).keys).containsExactly("native_correlation_details")
        for (key in selected) {
            val details = adapter.bloodPressureDetails(source, date, selected, off(key))
            assertWithMessage(key).that(bases(details)).isEmpty()
            assertWithMessage(key).that(csvRows(details)).isEqualTo(1)
        }
    }

    @Test
    fun activityLinesFollowTheirField() {
        fun clock(iso: String) = """{"epochSecond":${java.time.Instant.parse(iso).epochSecond},"nano":0,"iso8601":"$iso"}"""
        val source = root("""{"activity":{"stepSamples":[{"timestamp":"2026-11-01T01:00:00Z","value":42,
            "exactTime":${clock("2026-11-01T01:00:00Z")},"exactEndTime":${clock("2026-11-01T01:05:00Z")}}]}}""")
        val selected = listOf("steps")
        assertThat(bases(adapter.activityDetails(source, date, selected)).getValue("native_activity_details")).hasSize(1)
        val hidden = adapter.activityDetails(source, date, selected, off("steps"))
        assertThat(bases(hidden)).isEmpty()
        assertThat(csvRows(hidden)).isEqualTo(1)
    }

    @Test
    fun workoutBlockShowsWhileAnyWorkoutFieldIsOn() {
        val source = root("""{"workouts":[{"startTimeISO":"2026-11-01T01:00:00Z","endTimeISO":"2026-11-01T01:30:00Z"}]}""")
        val selected = listOf("workout_count", "workout_minutes", "workouts")
        assertThat(bases(adapter.workoutDetails(source, date, selected)).keys).containsExactly("native_workout_details")
        assertThat(bases(adapter.workoutDetails(source, date, selected, off("workout_count", "workouts"))).keys)
            .containsExactly("native_workout_details")
        val hidden = adapter.workoutDetails(source, date, selected) { !(it == "workouts" || it.startsWith("workout_")) }
        assertThat(bases(hidden)).isEmpty()
        assertThat(csvRows(hidden)).isEqualTo(1)
        assertThat(markdownBlocks(hidden)).isEqualTo(1)
    }

    @Test
    fun remainingRecordOwnersAreRealFieldsAndGateTheirLines() {
        for ((field, owners) in AndroidWakeDateSourceProjection.remainingDetailOwners) {
            assertWithMessage(field).that(owners).isNotEmpty()
            assertWithMessage(field).that(HealthDataFields.allKeys).containsAtLeastElementsIn(owners)
        }
        val source = root("""{"time_context":{"calendar_timezone":"UTC"},
            "nutrition":{"meals":[{"startTimeISO":"2026-11-01T01:00:00Z","endTimeISO":"2026-11-01T01:30:00Z","protein":20}]},
            "vitals":{"skinTemperatureDeltas":[{"timestamp":"2026-11-01T01:00:00Z","value":0.25}]}}""")
        val shown = AndroidWakeDateSourceProjection.remainingNativeDetails(source, date)
        assertThat(bases(shown).getValue("native_android_record_details")).hasSize(2)
        val mealsOff = AndroidWakeDateSourceProjection.remainingNativeDetails(source, date) {
            it !in AndroidWakeDateSourceProjection.remainingDetailOwners.getValue("meals")
        }
        val lines = bases(mealsOff).getValue("native_android_record_details")
        assertThat(lines).hasSize(1)
        assertThat(lines.single()).contains("skinTemperatureDeltas")
        val allOff = AndroidWakeDateSourceProjection.remainingNativeDetails(source, date) { false }
        assertThat(bases(allOff)).isEmpty()
        assertThat(csvRows(allOff)).isEqualTo(2)
    }
}
