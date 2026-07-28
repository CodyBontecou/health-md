package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ActivityIntensityEntry
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.NutritionData
import com.healthmd.domain.model.NutritionMealEntry
import org.junit.Test
import java.time.LocalDate
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import kotlin.time.Duration.Companion.seconds

class RangeCompatibilityMergerTest {
    @Test
    fun rangeDetailedEntriesMatchFallbackShapeAndRetainAggregates() {
        val date = LocalDate.of(2026, 7, 10)
        val time = LocalDateTime.of(2026, 7, 10, 12, 0)
        val exactStart = ExactSourceTimestamp.from(Instant.parse("2026-07-10T06:15:00.123456789Z"), ZoneOffset.ofHoursMinutes(5, 45))
        val exactEnd = ExactSourceTimestamp.from(Instant.parse("2026-07-10T06:30:00.123456789Z"), ZoneOffset.ofHoursMinutes(5, 45))
        val identity = ExactSourceIdentity(nativeId = "native-record", origin = "health_connect")
        val meal = NutritionMealEntry(
            time,
            time.plusMinutes(15),
            dietaryEnergy = 0.0,
            exactStartTime = exactStart,
            exactEndTime = exactEnd,
            identity = identity,
        )
        val intensity = ActivityIntensityEntry(
            time,
            time,
            0.seconds,
            "moderate",
            exactStartTime = exactStart,
            exactEndTime = exactStart,
            identity = identity,
        )
        val aggregate = HealthData(
            date = date,
            nutrition = NutritionData(protein = 25.0),
            activity = ActivityData(steps = 0),
        )

        val ranged = aggregate
            .withRangeCompatibilityEntries(nutritionMeals = listOf(meal))
            .withRangeCompatibilityEntries(activityIntensityEntries = listOf(intensity))

        assertThat(ranged.nutrition.protein).isEqualTo(25.0)
        assertThat(ranged.nutrition.meals).containsExactly(meal)
        assertThat(ranged.activity.steps).isEqualTo(0)
        assertThat(ranged.activity.activityIntensityEntries).containsExactly(intensity)
        assertThat(ranged.nutrition.meals.single().exactStartTime?.nano).isEqualTo(123_456_789)
        assertThat(ranged.activity.activityIntensityEntries.single().identity).isEqualTo(identity)
        assertThat(ranged.hasAnyData).isTrue()
    }
}
