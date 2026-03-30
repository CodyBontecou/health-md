package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class FrontmatterKeyStyle(val displayName: String, val description: String) {
    SNAKE_CASE("snake_case", "sleep_total_hours, active_calories"),
    CAMEL_CASE("camelCase", "sleepTotalHours, activeCalories");

    fun apply(originalKey: String): String = when (this) {
        SNAKE_CASE -> originalKey
        CAMEL_CASE -> toCamelCase(originalKey)
    }

    companion object {
        fun toCamelCase(snakeCase: String): String {
            val parts = snakeCase.split("_")
            if (parts.isEmpty()) return snakeCase
            return parts.first() + parts.drop(1).joinToString("") { part ->
                part.replaceFirstChar { it.uppercaseChar() }
            }
        }

        fun toSnakeCase(camelCase: String): String = buildString {
            for ((i, char) in camelCase.withIndex()) {
                if (char.isUpperCase()) {
                    if (i > 0) append('_')
                    append(char.lowercaseChar())
                } else {
                    append(char)
                }
            }
        }
    }
}

@Serializable
data class CustomFrontmatterField(
    val originalKey: String,
    val customKey: String = originalKey,
    val isEnabled: Boolean = true,
) {
    val outputKey: String
        get() = customKey.ifEmpty { originalKey }
}

@Serializable
data class FrontmatterConfiguration(
    val fields: List<CustomFrontmatterField> = defaultFields,
    val customFields: Map<String, String> = emptyMap(),
    val placeholderFields: List<String> = emptyList(),
    val includeDate: Boolean = true,
    val includeType: Boolean = true,
    val customDateKey: String = "date",
    val customTypeKey: String = "type",
    val customTypeValue: String = "health-data",
    val keyStyle: FrontmatterKeyStyle = FrontmatterKeyStyle.SNAKE_CASE,
) {
    fun outputKey(originalKey: String): String? {
        val field = fields.find { it.originalKey == originalKey } ?: return null
        if (!field.isEnabled) return null
        return field.outputKey
    }

    fun isFieldEnabled(originalKey: String): Boolean =
        fields.find { it.originalKey == originalKey }?.isEnabled ?: true

    fun withKeyStyle(style: FrontmatterKeyStyle): FrontmatterConfiguration = copy(
        keyStyle = style,
        fields = fields.map { it.copy(customKey = style.apply(it.originalKey)) },
    )

    companion object {
        val defaultFields: List<CustomFrontmatterField> = listOf(
            // Sleep
            CustomFrontmatterField("sleep_total_hours"),
            CustomFrontmatterField("sleep_deep_hours"),
            CustomFrontmatterField("sleep_rem_hours"),
            CustomFrontmatterField("sleep_light_hours"),
            CustomFrontmatterField("sleep_awake_hours"),
            CustomFrontmatterField("sleep_in_bed_hours"),
            // Activity
            CustomFrontmatterField("steps"),
            CustomFrontmatterField("active_calories"),
            CustomFrontmatterField("basal_calories"),
            CustomFrontmatterField("exercise_minutes"),
            CustomFrontmatterField("flights_climbed"),
            CustomFrontmatterField("walking_running_km"),
            CustomFrontmatterField("cycling_km"),
            // Heart
            CustomFrontmatterField("resting_heart_rate"),
            CustomFrontmatterField("average_heart_rate"),
            CustomFrontmatterField("heart_rate_min"),
            CustomFrontmatterField("heart_rate_max"),
            CustomFrontmatterField("hrv_ms"),
            // Vitals
            CustomFrontmatterField("respiratory_rate"),
            CustomFrontmatterField("blood_oxygen"),
            CustomFrontmatterField("body_temperature"),
            CustomFrontmatterField("blood_pressure_systolic"),
            CustomFrontmatterField("blood_pressure_diastolic"),
            CustomFrontmatterField("blood_glucose"),
            // Body
            CustomFrontmatterField("weight_kg"),
            CustomFrontmatterField("height_m"),
            CustomFrontmatterField("bmi"),
            CustomFrontmatterField("body_fat_percent"),
            CustomFrontmatterField("lean_body_mass_kg"),
            // Nutrition
            CustomFrontmatterField("dietary_calories"),
            CustomFrontmatterField("protein_g"),
            CustomFrontmatterField("carbohydrates_g"),
            CustomFrontmatterField("fat_g"),
            CustomFrontmatterField("saturated_fat_g"),
            CustomFrontmatterField("fiber_g"),
            CustomFrontmatterField("sugar_g"),
            CustomFrontmatterField("sodium_mg"),
            CustomFrontmatterField("cholesterol_mg"),
            CustomFrontmatterField("water_l"),
            CustomFrontmatterField("caffeine_mg"),
            // Mobility
            CustomFrontmatterField("walking_speed"),
            CustomFrontmatterField("vo2_max"),
            // Workouts
            CustomFrontmatterField("workout_count"),
            CustomFrontmatterField("workout_minutes"),
            CustomFrontmatterField("workout_calories"),
            CustomFrontmatterField("workout_distance_km"),
            CustomFrontmatterField("workouts"),
        )
    }
}
