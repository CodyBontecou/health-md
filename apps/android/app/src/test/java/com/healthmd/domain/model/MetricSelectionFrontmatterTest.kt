package com.healthmd.domain.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class MetricSelectionFrontmatterTest {

    private fun settings(selected: Set<String>, disabledKeys: Set<String> = emptySet()) = ExportSettings(
        metricSelection = MetricSelectionState(enabledMetrics = selected),
        formatCustomization = FormatCustomization(frontmatterConfig = FrontmatterConfiguration(
            fields = FrontmatterConfiguration.defaultFields.map { it.copy(isEnabled = it.originalKey !in disabledKeys) },
        )),
    )

    private fun ExportSettings.enabledKeys(): Set<String> =
        formatCustomization.frontmatterConfig.fields.filter { it.isEnabled }.map { it.originalKey }.toSet()

    @Test
    fun frontmatterKeysComeFromTheSharedRegistry() {
        assertThat(HealthDataFields.frontmatterKeys("steps")).containsExactly("steps")
        assertThat(HealthDataFields.frontmatterKeys("resting_hr")).containsExactly("resting_heart_rate")
        assertThat(HealthDataFields.frontmatterKeys("sleep_total"))
            .containsExactly("sleep_total_hours", "sleep_bedtime", "sleep_wake").inOrder()
        assertThat(HealthDataFields.frontmatterKeys("not_a_metric")).isEmpty()
        // Every catalog metric maps only to Format → Custom fields.
        val known = HealthDataFields.allKeys.toSet()
        HealthMetrics.allMetrics.forEach { metric ->
            assertThat(known).containsAtLeastElementsIn(HealthDataFields.frontmatterKeys(metric.id))
        }
    }

    @Test
    fun writesFrontmatterNeedsTheMetricAndAnEnabledField() {
        assertThat(settings(setOf("steps")).writesFrontmatter("steps")).isTrue()
        assertThat(settings(emptySet()).writesFrontmatter("steps")).isFalse()
        assertThat(settings(setOf("steps"), disabledKeys = setOf("steps")).writesFrontmatter("steps")).isFalse()
        // One enabled field of several is enough.
        val workoutKeys = HealthDataFields.frontmatterKeys("workouts")
        val trimmed = settings(setOf("workouts"), disabledKeys = workoutKeys.toSet() - "workout_count")
        assertThat(trimmed.writesFrontmatter("workouts")).isTrue()
        assertThat(settings(setOf("workouts"), disabledKeys = workoutKeys.toSet()).writesFrontmatter("workouts")).isFalse()
        // A field missing from an older saved list counts as on, as in export.
        val older = settings(setOf("steps")).let {
            it.copy(formatCustomization = it.formatCustomization.copy(
                frontmatterConfig = FrontmatterConfiguration(fields = emptyList()),
            ))
        }
        assertThat(older.writesFrontmatter("steps")).isTrue()
    }

    @Test
    fun selectingAMetricTurnsItsFieldsOnAndKeepsOtherTrims() {
        val workoutKeys = HealthDataFields.frontmatterKeys("workouts").toSet()
        val trimmedWorkouts = workoutKeys - "workout_count"
        val saved = settings(setOf("workouts"), disabledKeys = trimmedWorkouts + "steps" + "resting_heart_rate")

        val selected = saved.withMetricSelection(
            saved.metricSelection.copy(enabledMetrics = setOf("workouts", "steps")),
        )
        assertThat(selected.metricSelection.isEnabled("steps")).isTrue()
        assertThat(selected.enabledKeys()).contains("steps")
        // Workouts stayed selected: its Format → Custom trims are unchanged.
        assertThat(selected.enabledKeys()).containsNoneIn(trimmedWorkouts)
        // Metrics not newly selected are untouched.
        assertThat(selected.enabledKeys()).doesNotContain("resting_heart_rate")

        // Deselecting leaves fields alone.
        val deselected = selected.withMetricSelection(selected.metricSelection.copy(enabledMetrics = setOf("steps")))
        assertThat(deselected.formatCustomization).isEqualTo(selected.formatCustomization)
    }
}
