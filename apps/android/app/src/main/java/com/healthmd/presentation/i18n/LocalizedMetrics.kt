package com.healthmd.presentation.i18n

import androidx.annotation.StringRes
import androidx.compose.runtime.Composable
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.HealthMetricCategory
import com.healthmd.domain.model.HealthMetricDefinition

@StringRes
fun HealthMetricCategory.displayNameRes(): Int = when (this) {
    HealthMetricCategory.SLEEP -> R.string.metric_category_sleep
    HealthMetricCategory.ACTIVITY -> R.string.metric_category_activity
    HealthMetricCategory.HEART -> R.string.metric_category_heart
    HealthMetricCategory.RESPIRATORY -> R.string.metric_category_respiratory
    HealthMetricCategory.VITALS -> R.string.metric_category_vitals
    HealthMetricCategory.BODY -> R.string.metric_category_body
    HealthMetricCategory.NUTRITION -> R.string.metric_category_nutrition
    HealthMetricCategory.MOBILITY -> R.string.metric_category_mobility
    HealthMetricCategory.HEARING -> R.string.metric_category_hearing
    HealthMetricCategory.MINDFULNESS -> R.string.metric_category_mindfulness
    HealthMetricCategory.REPRODUCTIVE -> R.string.metric_category_reproductive
    HealthMetricCategory.SYMPTOMS -> R.string.metric_category_symptoms
    HealthMetricCategory.WORKOUTS -> R.string.metric_category_workouts
}

@Composable
fun HealthMetricCategory.localizedDisplayName(): String = stringResource(displayNameRes())

@StringRes
fun HealthMetricDefinition.displayNameRes(): Int = when (id) {
    "sleep_total" -> R.string.metric_name_sleep_total
    "sleep_deep" -> R.string.metric_name_sleep_deep
    "sleep_rem" -> R.string.metric_name_sleep_rem
    "sleep_light" -> R.string.metric_name_sleep_light
    "sleep_awake" -> R.string.metric_name_sleep_awake
    "sleep_in_bed" -> R.string.metric_name_sleep_in_bed
    "steps" -> R.string.metric_name_steps
    "active_calories" -> R.string.metric_name_active_calories
    "total_calories" -> R.string.metric_name_total_calories
    "basal_calories" -> R.string.metric_name_basal_calories
    "exercise_minutes" -> R.string.metric_name_exercise_minutes
    "flights_climbed" -> R.string.metric_name_flights_climbed
    "distance" -> R.string.metric_name_distance
    "cycling_distance" -> R.string.metric_name_cycling_distance
    "elevation_gained" -> R.string.metric_name_elevation_gained
    "wheelchair_pushes" -> R.string.metric_name_wheelchair_pushes
    "resting_hr" -> R.string.metric_name_resting_hr
    "avg_hr" -> R.string.metric_name_avg_hr
    "min_hr" -> R.string.metric_name_min_hr
    "max_hr" -> R.string.metric_name_max_hr
    "hrv" -> R.string.metric_name_hrv
    "respiratory_rate" -> R.string.metric_name_respiratory_rate
    "blood_oxygen" -> R.string.metric_name_blood_oxygen
    "body_temp" -> R.string.metric_name_body_temp
    "bp_systolic" -> R.string.metric_name_bp_systolic
    "bp_diastolic" -> R.string.metric_name_bp_diastolic
    "blood_glucose" -> R.string.metric_name_blood_glucose
    "basal_body_temp" -> R.string.metric_name_basal_body_temp
    "skin_temperature" -> R.string.metric_name_skin_temperature
    "weight" -> R.string.metric_name_weight
    "height" -> R.string.metric_name_height
    "bmi" -> R.string.metric_name_bmi
    "body_fat" -> R.string.metric_name_body_fat
    "lean_mass" -> R.string.metric_name_lean_mass
    "body_water_mass" -> R.string.metric_name_body_water_mass
    "bone_mass" -> R.string.metric_name_bone_mass
    "dietary_energy" -> R.string.metric_name_dietary_energy
    "protein" -> R.string.metric_name_protein
    "carbs" -> R.string.metric_name_carbs
    "fat" -> R.string.metric_name_fat
    "saturated_fat" -> R.string.metric_name_saturated_fat
    "fiber" -> R.string.metric_name_fiber
    "sugar" -> R.string.metric_name_sugar
    "sodium" -> R.string.metric_name_sodium
    "cholesterol" -> R.string.metric_name_cholesterol
    "water" -> R.string.metric_name_water
    "caffeine" -> R.string.metric_name_caffeine
    "walking_speed" -> R.string.metric_name_walking_speed
    "vo2_max" -> R.string.metric_name_vo2_max
    "cycling_cadence" -> R.string.metric_name_cycling_cadence
    "steps_cadence" -> R.string.metric_name_steps_cadence
    "power_avg" -> R.string.metric_name_power_avg
    "power_max" -> R.string.metric_name_power_max
    "audio_exposure" -> R.string.metric_name_audio_exposure
    "mindful_minutes" -> R.string.metric_name_mindful_minutes
    "menstrual_flow" -> R.string.metric_name_menstrual_flow
    "cervical_mucus" -> R.string.metric_name_cervical_mucus
    "ovulation_test" -> R.string.metric_name_ovulation_test
    "sexual_activity" -> R.string.metric_name_sexual_activity
    "intermenstrual_bleeding" -> R.string.metric_name_intermenstrual_bleeding
    "workouts" -> R.string.metric_name_workouts
    else -> R.string.metric_name_unknown
}

@Composable
fun HealthMetricDefinition.localizedDisplayName(): String = stringResource(displayNameRes())

@Composable
fun ExportSource.localizedDisplayName(): String = when (this) {
    ExportSource.MANUAL -> stringResource(R.string.export_source_manual)
    ExportSource.SCHEDULED -> stringResource(R.string.export_source_scheduled)
}
