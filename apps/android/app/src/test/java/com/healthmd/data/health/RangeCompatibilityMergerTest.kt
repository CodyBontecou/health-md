package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ActivityIntensityEntry
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.NutritionData
import com.healthmd.domain.model.NutritionMealEntry
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.time.Duration.Companion.seconds

class RangeCompatibilityMergerTest {
    @Test
    fun rangeDetailedEntriesMatchFallbackShapeAndRetainAggregates() {
        val date = LocalDate.of(2026, 7, 10)
        val time = LocalDateTime.of(2026, 7, 10, 12, 0)
        val meal = NutritionMealEntry(time, time.plusMinutes(15), dietaryEnergy = 0.0)
        val intensity = ActivityIntensityEntry(time, time, 0.seconds, "moderate")
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
        assertThat(ranged.hasAnyData).isTrue()
    }
}
