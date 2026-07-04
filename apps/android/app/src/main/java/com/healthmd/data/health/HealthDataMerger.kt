package com.healthmd.data.health

import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WorkoutData
import java.time.LocalDate

/**
 * Conservative multi-provider merge.
 *
 * Daily aggregates are intentionally source-preferred instead of summed to avoid
 * double-counting the same steps/sleep/workouts written by multiple ecosystems.
 * Lists are deduped by stable ids/timestamps where available.
 */
object HealthDataMerger {
    const val ALL_CONNECTED_PROVIDER_ID = "all_connected"

    fun merge(date: LocalDate, dataSets: List<HealthData>): HealthData {
        if (dataSets.isEmpty()) return HealthData(date)
        return dataSets.reduce { left, right -> mergeTwo(left, right) }
    }

    private fun mergeTwo(left: HealthData, right: HealthData): HealthData = left.copy(
        sleep = if (left.sleep.hasData) left.sleep else right.sleep,
        activity = if (left.activity.hasData) left.activity else right.activity,
        heart = if (left.heart.hasData) left.heart else right.heart,
        vitals = if (left.vitals.hasData) left.vitals else right.vitals,
        body = if (left.body.hasData) left.body else right.body,
        nutrition = if (left.nutrition.hasData) left.nutrition else right.nutrition,
        mobility = if (left.mobility.hasData) left.mobility else right.mobility,
        reproductiveHealth = if (left.reproductiveHealth.hasData) left.reproductiveHealth else right.reproductiveHealth,
        mindfulness = if (left.mindfulness.hasData) left.mindfulness else right.mindfulness,
        workouts = (left.workouts + right.workouts).distinctBy { it.dedupeKey() },
        plannedWorkouts = (left.plannedWorkouts + right.plannedWorkouts).distinctBy { planned ->
            planned.id.ifBlank { "${planned.workoutType}:${planned.startTime}:${planned.endTime}" }
        },
        medicalResources = if (left.medicalResources.hasData) left.medicalResources else right.medicalResources,
    )

    private fun WorkoutData.dedupeKey(): String =
        id.ifBlank { "${workoutType}:${startTime}:${endTime}:${duration}" }
}
