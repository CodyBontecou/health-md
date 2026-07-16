package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.ProviderFailureProvenance
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.time.Duration.Companion.minutes

class HealthDataMergerProvenanceTest {
    private val date = LocalDate.of(2026, 7, 10)

    @Test
    fun overlapFailuresAndProviderOrderingAreDeterministicAndHonest() {
        val merged = HealthDataMerger.mergeAllConnected(
            date = date,
            attemptedProviderIds = listOf("whoop", "fitbit", "fitbit", "health_connect"),
            successfulData = listOf(
                HealthDataMerger.ProviderData(
                    "whoop",
                    HealthData(date, activity = ActivityData(steps = 900), heart = HeartData(averageHeartRate = 75.0)),
                ),
                HealthDataMerger.ProviderData(
                    "fitbit",
                    HealthData(date, activity = ActivityData(steps = 1000)),
                ),
            ),
            failures = listOf(ProviderFailureProvenance("health_connect", "fetchHealthData", "IOException")),
        )

        // Provider ID ordering, not caller timing, determines source preference.
        assertThat(merged.activity.steps).isEqualTo(1000)
        val provenance = merged.compatibilityProvenance!!
        assertThat(provenance.providerIdsAttempted)
            .containsExactly("fitbit", "health_connect", "whoop").inOrder()
        assertThat(provenance.providerFailures.single().providerId).isEqualTo("health_connect")
        val activity = provenance.categorySelections.single { it.category == "activity" }
        assertThat(activity.chosenProviderId).isEqualTo("fitbit")
        assertThat(activity.omittedOverlappingProviderIds).containsExactly("whoop")
        assertThat(provenance.mergePolicyId).isEqualTo(HealthDataMerger.MERGE_POLICY_ID)
    }

    @Test
    fun providerLocalWorkoutIdsNeverCollideAcrossProviders() {
        val first = WorkoutData(
            id = "provider-local-1",
            workoutType = WorkoutType.RUNNING,
            startTime = LocalDateTime.of(2026, 7, 10, 8, 0),
            duration = 30.minutes,
        )
        val unrelatedSameId = first.copy(
            workoutType = WorkoutType.CYCLING,
            startTime = LocalDateTime.of(2026, 7, 10, 18, 0),
        )
        val merged = HealthDataMerger.mergeAllConnected(
            date,
            listOf("fitbit", "whoop"),
            listOf(
                HealthDataMerger.ProviderData("fitbit", HealthData(date, workouts = listOf(first))),
                HealthDataMerger.ProviderData("whoop", HealthData(date, workouts = listOf(unrelatedSameId))),
            ),
        )

        assertThat(merged.workouts).containsExactly(first, unrelatedSameId)
        assertThat(merged.compatibilityProvenance!!.workoutSources.map { it.providerId })
            .containsExactly("fitbit", "whoop").inOrder()
        assertThat(merged.compatibilityProvenance!!.workoutDedupeDecisions).isEmpty()
    }

    @Test
    fun sameSemanticWorkoutWithDifferentProviderIdsIsDedupedWithDecision() {
        val fitbit = WorkoutData(
            id = "fitbit-123",
            workoutType = WorkoutType.RUNNING,
            startTime = LocalDateTime.of(2026, 7, 10, 8, 0),
            endTime = LocalDateTime.of(2026, 7, 10, 8, 30),
            duration = 30.minutes,
        )
        val whoop = fitbit.copy(id = "whoop-999")
        val merged = HealthDataMerger.mergeAllConnected(
            date,
            listOf("whoop", "fitbit"),
            listOf(
                HealthDataMerger.ProviderData("whoop", HealthData(date, workouts = listOf(whoop))),
                HealthDataMerger.ProviderData("fitbit", HealthData(date, workouts = listOf(fitbit))),
            ),
        )

        assertThat(merged.workouts).containsExactly(fitbit)
        val decision = merged.compatibilityProvenance!!.workoutDedupeDecisions.single()
        assertThat(decision.keptProviderId).isEqualTo("fitbit")
        assertThat(decision.omittedProviderId).isEqualTo("whoop")
        assertThat(decision.reason).isEqualTo("cross_provider_semantic_fingerprint")
        assertThat(MarkdownExporter().export(merged)).contains(
            "omitted whoop:whoop-999 (cross_provider_semantic_fingerprint)"
        )
        assertThat(ObsidianBasesExporter().export(merged)).contains("reason=cross_provider_semantic_fingerprint")
    }

    @Test
    fun exportersDiscloseOnlyPresentAllConnectedProvenance() {
        val workout = WorkoutData(
            workoutType = WorkoutType.RUNNING,
            startTime = LocalDateTime.of(2026, 7, 10, 8, 0),
            duration = 30.minutes,
            correlatedSourceIds = mapOf("heart_rate" to listOf("hr-source-1")),
        )
        val merged = HealthDataMerger.mergeAllConnected(
            date,
            listOf("whoop", "fitbit"),
            listOf(HealthDataMerger.ProviderData("fitbit", HealthData(date, activity = ActivityData(steps = 10), workouts = listOf(workout)))),
            listOf(ProviderFailureProvenance("whoop", "fetchHealthData", "TimeoutException")),
        )
        val json = Json.parseToJsonElement(JsonExporter().export(merged)).jsonObject
        val provenance = json.getValue("metadata").jsonObject.getValue("provenance").jsonObject
        assertThat(provenance.getValue("mergePolicyId").jsonPrimitive.content).isEqualTo(HealthDataMerger.MERGE_POLICY_ID)
        assertThat(provenance.getValue("providerFailures").jsonArray).hasSize(1)
        assertThat(provenance.getValue("workoutDetailSources").jsonArray.single().jsonObject
            .getValue("sourceIdsByDetail").jsonObject.getValue("heart_rate").jsonArray.single().jsonPrimitive.content)
            .isEqualTo("hr-source-1")
        val markdown = MarkdownExporter().export(merged)
        assertThat(markdown).contains("All-connected provenance")
        assertThat(markdown).contains("attempted=fitbit,whoop")
        assertThat(markdown).contains("succeeded=fitbit")
        assertThat(markdown).contains("Workout sources")
        assertThat(CsvExporter().export(merged)).contains("Metadata,Merge Policy")
        val bases = ObsidianBasesExporter().export(merged)
        assertThat(bases).contains("healthmd_all_connected_providers_attempted")
        assertThat(bases).contains("healthmd_all_connected_providers_succeeded")
        assertThat(bases).contains("healthmd_all_connected_category_selections")
        assertThat(bases).contains("healthmd_all_connected_workout_sources")
        assertThat(bases).contains("healthmd_all_connected_workout_dedupe_decisions")

        val ordinary = HealthData(date, activity = ActivityData(steps = 10))
        assertThat(Json.parseToJsonElement(JsonExporter().export(ordinary)).jsonObject.containsKey("metadata")).isFalse()
        assertThat(MarkdownExporter().export(ordinary)).doesNotContain("All-connected provenance")
        assertThat(CsvExporter().export(ordinary)).doesNotContain("Metadata,Merge Policy")
        assertThat(ObsidianBasesExporter().export(ordinary)).doesNotContain("healthmd_all_connected_")
    }
}
