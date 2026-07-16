package com.healthmd.data.health

import com.healthmd.domain.model.ActivityIntensityEntry
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.NutritionMealEntry

/** Keeps range reads aligned with the detailed records returned by the single-day fallback. */
internal fun HealthData.withRangeCompatibilityEntries(
    nutritionMeals: List<NutritionMealEntry>? = null,
    activityIntensityEntries: List<ActivityIntensityEntry>? = null,
): HealthData = copy(
    nutrition = nutritionMeals?.let { nutrition.copy(meals = it) } ?: nutrition,
    activity = activityIntensityEntries?.let { activity.copy(activityIntensityEntries = it) } ?: activity,
)
