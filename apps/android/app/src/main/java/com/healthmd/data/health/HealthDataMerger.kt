package com.healthmd.data.health

import com.healthmd.domain.model.CategoryMergeProvenance
import com.healthmd.domain.model.CompatibilityProvenance
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.ProviderFailureProvenance
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutDedupeDecisionProvenance
import com.healthmd.domain.model.WorkoutDetailSourceProvenance
import com.healthmd.domain.model.WorkoutSourceProvenance
import java.time.LocalDate

/**
 * Conservative multi-provider merge.
 *
 * Daily aggregates are source-preferred instead of summed to avoid double-counting the same data
 * written by multiple ecosystems. Provider-local IDs are never compared across providers. Cross-
 * provider workout dedupe uses only a conservative semantic fingerprint and records every omitted
 * record and precedence choice in compatibility provenance.
 */
object HealthDataMerger {
    const val ALL_CONNECTED_PROVIDER_ID = "all_connected"
    const val MERGE_POLICY_ID = "healthmd.source_preferred.v2"

    data class ProviderData(val providerId: String, val data: HealthData)

    /** Legacy/internal convenience without provenance. */
    fun merge(date: LocalDate, dataSets: List<HealthData>): HealthData {
        if (dataSets.isEmpty()) return HealthData(date)
        return dataSets.reduce { left, right -> mergeTwo(left, right) }
    }

    fun mergeAllConnected(
        date: LocalDate,
        attemptedProviderIds: List<String>,
        successfulData: List<ProviderData>,
        failures: List<ProviderFailureProvenance> = emptyList(),
    ): HealthData {
        val orderedAttempts = attemptedProviderIds.distinct().sorted()
        val orderedData = successfulData.sortedBy { it.providerId }.distinctBy { it.providerId }
        val workoutMerge = mergeWorkouts(orderedData)
        val merged = merge(date, orderedData.map { it.data.copy(workouts = emptyList()) })
            .copy(workouts = workoutMerge.workouts)
        return merged.copy(
            compatibilityProvenance = CompatibilityProvenance(
                providerIdsAttempted = orderedAttempts,
                providerIdsSucceeded = orderedData.map { it.providerId },
                providerFailures = failures.sortedWith(compareBy({ it.providerId }, { it.operation }, { it.errorType })),
                categorySelections = categorySelections(orderedData),
                workoutDetailSources = merged.workouts
                    .filter { it.correlatedSourceIds.isNotEmpty() }
                    .sortedBy { it.id }
                    .map { workout ->
                        WorkoutDetailSourceProvenance(
                            workoutId = workout.id,
                            sourceIdsByDetail = workout.correlatedSourceIds.toSortedMap()
                                .mapValues { (_, ids) -> ids.distinct().sorted() },
                        )
                    },
                workoutSources = workoutMerge.sources,
                workoutDedupeDecisions = workoutMerge.decisions,
                mergePolicyId = MERGE_POLICY_ID,
            )
        )
    }

    private data class TaggedWorkout(val providerId: String, val workout: WorkoutData)
    private data class WorkoutMerge(
        val workouts: List<WorkoutData>,
        val sources: List<WorkoutSourceProvenance>,
        val decisions: List<WorkoutDedupeDecisionProvenance>,
    )

    private fun mergeWorkouts(dataSets: List<ProviderData>): WorkoutMerge {
        val retained = mutableListOf<TaggedWorkout>()
        val decisions = mutableListOf<WorkoutDedupeDecisionProvenance>()
        val providerIds = mutableMapOf<Pair<String, String>, TaggedWorkout>()
        val semantic = mutableMapOf<String, TaggedWorkout>()

        dataSets.forEach { provider ->
            provider.data.workouts.sortedWith(compareBy({ it.startTime }, { it.id })).forEach { workout ->
                val tagged = TaggedWorkout(provider.providerId, workout)
                val localId = workout.id.takeIf { it.isNotBlank() }
                val sameProvider = localId?.let { providerIds[provider.providerId to it] }
                val crossProvider = semantic[workout.semanticFingerprint()]
                    ?.takeIf { it.providerId != provider.providerId }
                val duplicate = sameProvider ?: crossProvider
                if (duplicate == null) {
                    retained += tagged
                    if (localId != null) providerIds[provider.providerId to localId] = tagged
                    semantic.putIfAbsent(workout.semanticFingerprint(), tagged)
                } else {
                    decisions += WorkoutDedupeDecisionProvenance(
                        keptProviderId = duplicate.providerId,
                        keptWorkoutId = duplicate.workout.id,
                        omittedProviderId = provider.providerId,
                        omittedWorkoutId = workout.id,
                        reason = if (sameProvider != null) {
                            "provider_qualified_id"
                        } else {
                            "cross_provider_semantic_fingerprint"
                        },
                    )
                }
            }
        }
        return WorkoutMerge(
            workouts = retained.map { it.workout },
            sources = retained.map {
                WorkoutSourceProvenance(
                    workoutId = it.workout.id,
                    providerId = it.providerId,
                    providerWorkoutId = it.workout.id,
                )
            },
            decisions = decisions,
        )
    }

    private fun WorkoutData.semanticFingerprint(): String = listOf(
        workoutType.name,
        startTime.toString(),
        endTime?.toString().orEmpty(),
        duration.inWholeNanoseconds.toString(),
        isIndoor?.toString().orEmpty(),
    ).joinToString("|")

    private fun categorySelections(dataSets: List<ProviderData>): List<CategoryMergeProvenance> {
        data class Category(
            val id: String,
            val unionWithDedupe: Boolean = false,
            val hasData: (HealthData) -> Boolean,
        )
        val categories = listOf(
            Category("sleep") { it.sleep.hasData },
            Category("activity") { it.activity.hasData },
            Category("heart") { it.heart.hasData },
            Category("vitals") { it.vitals.hasData },
            Category("body") { it.body.hasData },
            Category("nutrition") { it.nutrition.hasData },
            Category("mobility") { it.mobility.hasData },
            Category("reproductive_health") { it.reproductiveHealth.hasData },
            Category("mindfulness") { it.mindfulness.hasData },
            Category("workouts", unionWithDedupe = true) { it.workouts.isNotEmpty() },
            Category("planned_workouts", unionWithDedupe = true) { it.plannedWorkouts.isNotEmpty() },
            Category("medical_resources") { it.medicalResources.hasData },
        )
        return categories.mapNotNull { category ->
            val providers = dataSets.filter { category.hasData(it.data) }.map { it.providerId }
            if (providers.isEmpty()) null else CategoryMergeProvenance(
                category = category.id,
                chosenProviderId = providers.first(),
                omittedOverlappingProviderIds = if (category.unionWithDedupe) emptyList() else providers.drop(1),
            )
        }
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
