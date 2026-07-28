package com.healthmd.domain.model

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.LocalDateTime
import kotlin.time.Duration.Companion.minutes
import kotlin.time.Duration.Companion.seconds

class HealthDataFidelityTest {
    private val time = LocalDateTime.of(2026, 7, 10, 12, 0)
    private val sample = TimestampedSample(time, 0.0)

    @Test
    fun sampleOnlyCategoriesReportData() {
        assertThat(ActivityData(stepSamples = listOf(sample)).hasData).isTrue()
        assertThat(HeartData(samples = listOf(sample)).hasData).isTrue()
        assertThat(HeartData(hrvSamples = listOf(sample)).hasData).isTrue()
        assertThat(VitalsData(bloodOxygenSamples = listOf(sample)).hasData).isTrue()
        assertThat(VitalsData(bloodPressureSamples = listOf(BloodPressureSample(time, 0.0, 0.0))).hasData).isTrue()
        assertThat(VitalsData(bloodGlucoseSamples = listOf(sample)).hasData).isTrue()
        assertThat(VitalsData(respiratoryRateSamples = listOf(sample)).hasData).isTrue()
        assertThat(VitalsData(bodyTemperatureSamples = listOf(sample)).hasData).isTrue()
        assertThat(VitalsData(basalBodyTemperatureSamples = listOf(sample)).hasData).isTrue()
    }

    @Test
    fun zeroValuedDetailedRecordsPreservePresence() {
        val intensity = ActivityIntensityEntry(
            startTime = time,
            endTime = time,
            duration = 0.seconds,
            intensity = "moderate",
        )
        val meal = NutritionMealEntry(
            startTime = time,
            endTime = time.plusMinutes(15),
            dietaryEnergy = 0.0,
            protein = 0.0,
        )

        assertThat(ActivityData(activityIntensityEntries = listOf(intensity)).hasData).isTrue()
        assertThat(NutritionData(meals = listOf(meal)).hasData).isTrue()
    }

    @Test
    fun exactSyntheticSourceIdentitiesAreDeterministicAndMarked() {
        val first = ExactSourceIdentity(
            syntheticId = deterministicRecordId("nested_sample", time, 72.0),
            isSynthetic = true,
        )
        val second = ExactSourceIdentity(
            syntheticId = deterministicRecordId("nested_sample", time, 72.0),
            isSynthetic = true,
        )
        assertThat(first).isEqualTo(second)
        assertThat(first.isSynthetic).isTrue()
        assertThat(first.nativeId).isNull()
    }

    @Test
    fun fallbackWorkoutIdentitiesAreDeterministicAndNativeIdsArePreserved() {
        val firstWorkout = WorkoutData(
            workoutType = WorkoutType.RUNNING,
            startTime = time,
            endTime = time.plusMinutes(30),
            duration = 30.minutes,
        )
        val sameWorkout = WorkoutData(
            workoutType = WorkoutType.RUNNING,
            startTime = time,
            endTime = time.plusMinutes(30),
            duration = 30.minutes,
        )
        val differentWorkout = WorkoutData(
            workoutType = WorkoutType.RUNNING,
            startTime = time.plusMinutes(1),
            endTime = time.plusMinutes(31),
            duration = 30.minutes,
        )
        assertThat(sameWorkout.id).isEqualTo(firstWorkout.id)
        assertThat(differentWorkout.id).isNotEqualTo(firstWorkout.id)
        assertThat(firstWorkout.copy(id = "native-workout-id").id).isEqualTo("native-workout-id")

        val firstPlan = PlannedExerciseData(
            workoutType = WorkoutType.CYCLING,
            startTime = time,
            endTime = time.plusMinutes(45),
            duration = 45.minutes,
            hasExplicitTime = true,
            exerciseTypeRaw = 8,
        )
        val samePlan = PlannedExerciseData(
            workoutType = WorkoutType.CYCLING,
            startTime = time,
            endTime = time.plusMinutes(45),
            duration = 45.minutes,
            hasExplicitTime = true,
            exerciseTypeRaw = 8,
        )
        assertThat(samePlan.id).isEqualTo(firstPlan.id)
        assertThat(firstPlan.copy(id = "native-plan-id").id).isEqualTo("native-plan-id")
    }
}
