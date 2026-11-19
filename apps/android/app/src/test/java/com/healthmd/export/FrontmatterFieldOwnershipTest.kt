package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.MetricSelectionState
import kotlinx.serialization.json.Json
import org.junit.Test

/**
 * Format → Custom (the frontmatter field switches) decides which properties go into
 * frontmatter, for every category including workouts (#353). The per-note field list
 * (metric selection) decides which data is collected; it is not a second frontmatter switch.
 */
class FrontmatterFieldOwnershipTest {
    private val markdown = MarkdownExporter()
    private val bases = ObsidianBasesExporter()

    private val workoutKeys = HealthDataFields.allKeys.filter { it.isWorkoutKey() }

    private fun String.isWorkoutKey() =
        this == "workouts" || startsWith("workout_") || startsWith("planned_workout")

    private fun frontmatterKeys(output: String): List<String> {
        val lines = output.lines()
        check(lines.first() == "---")
        return lines.drop(1).takeWhile { it != "---" }
            .filter { it.isNotEmpty() && !it.first().isWhitespace() && ':' in it }
            .map { it.substringBefore(':') }
    }

    private fun withDisabled(keys: Collection<String>) = FormatCustomization(
        frontmatterConfig = FrontmatterConfiguration(
            fields = FrontmatterConfiguration.defaultFields.map {
                if (it.originalKey in keys) it.copy(isEnabled = false) else it
            },
        ),
    )

    @Test
    fun workoutNote_hasWorkoutPropertiesByDefault() {
        val data = ExportFixtures.fullDay.filtered(MetricSelectionState())
        assertThat(data.workouts).isNotEmpty()
        for (output in listOf(markdown.export(data), bases.export(data))) {
            assertThat(frontmatterKeys(output)).containsAtLeast("workout_count", "workout_minutes", "workouts")
        }
    }

    @Test
    fun workoutFieldsSwitchedOffInFormatCustom_leaveNoWorkoutFrontmatter() {
        assertThat(workoutKeys).containsAtLeast("workout_count", "workouts", "planned_workout_count")
        // The workouts metric stays on: the data is still collected and shown in the body.
        val data = ExportFixtures.fullDay.filtered(MetricSelectionState())
        val customization = withDisabled(workoutKeys)

        val note = markdown.export(data, customization = customization)
        val properties = bases.export(data, customization)
        for ((name, output) in listOf("markdown" to note, "bases" to properties)) {
            assertWithMessage("$name frontmatter keys")
                .that(frontmatterKeys(output).filter { it.isWorkoutKey() })
                .isEmpty()
            assertWithMessage("$name keeps other properties")
                .that(frontmatterKeys(output)).contains("steps")
        }
        assertWithMessage("the body still lists the collected workout").that(note).contains("Workouts")
    }

    @Test
    fun oneWorkoutFieldSwitchedOff_removesOnlyThatProperty() {
        val data = ExportFixtures.fullDay.filtered(MetricSelectionState())
        val keys = frontmatterKeys(markdown.export(data, customization = withDisabled(listOf("workout_calories"))))
        assertThat(keys).doesNotContain("workout_calories")
        assertThat(keys).contains("workout_count")
    }

    @Test
    fun workoutsMetricOff_collectsNoWorkoutData_soNoWorkoutFrontmatter() {
        val selection = MetricSelectionState().copy(
            enabledMetrics = MetricSelectionState().enabledMetrics - "workouts",
        )
        val data = ExportFixtures.fullDay.filtered(selection)
        assertThat(data.workouts).isEmpty()
        for (output in listOf(markdown.export(data), bases.export(data))) {
            assertThat(frontmatterKeys(output).filter { it.isWorkoutKey() }).isEmpty()
        }
    }

    /** Migration: a configuration saved by an older version keeps its exact output. */
    @Test
    fun legacySavedConfiguration_keepsExistingOutput() {
        // Older versions saved only the fields they knew; one was switched off.
        val legacy = Json { ignoreUnknownKeys = true }.decodeFromString(
            FrontmatterConfiguration.serializer(),
            """{"fields":[{"originalKey":"steps","customKey":"steps","isEnabled":false},""" +
                """{"originalKey":"workout_count","customKey":"workout_count","isEnabled":true}]}""",
        )
        val expanded = withDisabled(listOf("steps"))
        val data = ExportFixtures.fullDay.filtered(MetricSelectionState())

        assertThat(markdown.export(data, customization = FormatCustomization(frontmatterConfig = legacy)))
            .isEqualTo(markdown.export(data, customization = expanded))
        assertThat(bases.export(data, FormatCustomization(frontmatterConfig = legacy)))
            .isEqualTo(bases.export(data, expanded))
        val keys = frontmatterKeys(bases.export(data, FormatCustomization(frontmatterConfig = legacy)))
        assertThat(keys).doesNotContain("steps")
        assertThat(keys).containsAtLeast("workout_count", "workout_minutes")
    }
}
