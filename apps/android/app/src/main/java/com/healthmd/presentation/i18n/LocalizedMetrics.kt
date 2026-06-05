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
    HealthMetricCategory.CYCLING -> R.string.metric_category_cycling
    HealthMetricCategory.HEARING -> R.string.metric_category_hearing
    HealthMetricCategory.MINDFULNESS -> R.string.metric_category_mindfulness
    HealthMetricCategory.REPRODUCTIVE -> R.string.metric_category_reproductive
    HealthMetricCategory.SYMPTOMS -> R.string.metric_category_symptoms
    HealthMetricCategory.MEDICATIONS -> R.string.metric_category_medications
    HealthMetricCategory.OTHER -> R.string.metric_category_other
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
    "swimming_distance" -> R.string.metric_name_swimming_distance
    "swimming_strokes" -> R.string.metric_name_swimming_strokes
    "wheelchair_distance" -> R.string.metric_name_wheelchair_distance
    "downhill_snow_distance" -> R.string.metric_name_downhill_snow_distance
    "resting_hr" -> R.string.metric_name_resting_hr
    "avg_hr" -> R.string.metric_name_avg_hr
    "walking_hr" -> R.string.metric_name_walking_hr
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
    "monounsaturated_fat" -> R.string.metric_name_monounsaturated_fat
    "polyunsaturated_fat" -> R.string.metric_name_polyunsaturated_fat
    "unsaturated_fat" -> R.string.metric_name_unsaturated_fat
    "trans_fat" -> R.string.metric_name_trans_fat
    "fiber" -> R.string.metric_name_fiber
    "sugar" -> R.string.metric_name_sugar
    "sodium" -> R.string.metric_name_sodium
    "potassium" -> R.string.metric_name_potassium
    "calcium" -> R.string.metric_name_calcium
    "iron" -> R.string.metric_name_iron
    "magnesium" -> R.string.metric_name_magnesium
    "zinc" -> R.string.metric_name_zinc
    "phosphorus" -> R.string.metric_name_phosphorus
    "iodine" -> R.string.metric_name_iodine
    "selenium" -> R.string.metric_name_selenium
    "copper" -> R.string.metric_name_copper
    "manganese" -> R.string.metric_name_manganese
    "chromium" -> R.string.metric_name_chromium
    "molybdenum" -> R.string.metric_name_molybdenum
    "chloride" -> R.string.metric_name_chloride
    "vitamin_a" -> R.string.metric_name_vitamin_a
    "vitamin_b6" -> R.string.metric_name_vitamin_b6
    "vitamin_b12" -> R.string.metric_name_vitamin_b12
    "vitamin_c" -> R.string.metric_name_vitamin_c
    "vitamin_d" -> R.string.metric_name_vitamin_d
    "vitamin_e" -> R.string.metric_name_vitamin_e
    "vitamin_k" -> R.string.metric_name_vitamin_k
    "thiamin" -> R.string.metric_name_thiamin
    "riboflavin" -> R.string.metric_name_riboflavin
    "niacin" -> R.string.metric_name_niacin
    "folate" -> R.string.metric_name_folate
    "folic_acid" -> R.string.metric_name_folic_acid
    "pantothenic_acid" -> R.string.metric_name_pantothenic_acid
    "biotin" -> R.string.metric_name_biotin
    "cholesterol" -> R.string.metric_name_cholesterol
    "water" -> R.string.metric_name_water
    "caffeine" -> R.string.metric_name_caffeine
    "walking_speed" -> R.string.metric_name_walking_speed
    "vo2_max" -> R.string.metric_name_vo2_max
    "cycling_cadence" -> R.string.metric_name_cycling_cadence
    "steps_cadence" -> R.string.metric_name_steps_cadence
    "power_avg" -> R.string.metric_name_power_avg
    "power_max" -> R.string.metric_name_power_max
    "running_speed" -> R.string.metric_name_running_speed
    "running_power" -> R.string.metric_name_running_power
    "audio_exposure" -> R.string.metric_name_audio_exposure
    "mindful_minutes" -> R.string.metric_name_mindful_minutes
    "mindful_sessions" -> R.string.metric_name_mindful_sessions
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
    ExportSource.RETRY -> stringResource(R.string.export_source_retry)
    ExportSource.SHORTCUT -> stringResource(R.string.export_source_shortcut)
    ExportSource.REMOTE -> stringResource(R.string.export_source_remote)
}
