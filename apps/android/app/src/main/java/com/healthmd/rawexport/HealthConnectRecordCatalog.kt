package com.healthmd.rawexport

import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import kotlin.reflect.KClass

@JvmInline
value class RawFeatureGate(val feature: Int)

enum class RawPagePolicy { STANDARD, HIGH_CARDINALITY }

data class HealthConnectRecordDescriptor<T : Record>(
    val recordClass: KClass<T>,
    val wireType: String,
    val readPermission: String,
    val featureGate: RawFeatureGate? = null,
    val metricIds: Set<String>,
    val pagePolicy: RawPagePolicy = RawPagePolicy.STANDARD,
    val changeEligible: Boolean = true,
    val mapper: ((T) -> RawRecord)?,
) {
    @Suppress("UNCHECKED_CAST")
    internal fun mapUntyped(record: Record): RawRecord? = mapper?.invoke(record as T)
}

/**
 * Closed catalog for every native Record currently permissioned by HealthConnectManager.
 * Additions are deliberately explicit: an absent mapper produces mapper_missing, never reflection.
 */
object HealthConnectRecordCatalog {
    private inline fun <reified T : Record> entry(
        wireType: String,
        vararg metricIds: String,
        feature: Int? = null,
        pagePolicy: RawPagePolicy = RawPagePolicy.STANDARD,
        noinline mapper: ((T) -> RawRecord)? = { RawHealthConnectMapper.map(it, wireType) },
    ) = HealthConnectRecordDescriptor(
        recordClass = T::class,
        wireType = wireType,
        readPermission = HealthPermission.getReadPermission(T::class),
        featureGate = feature?.let(::RawFeatureGate),
        metricIds = metricIds.toSet(),
        pagePolicy = pagePolicy,
        mapper = mapper,
    )

    val records: List<HealthConnectRecordDescriptor<out Record>> = listOf(
        entry<StepsRecord>("steps", "steps", pagePolicy = RawPagePolicy.HIGH_CARDINALITY),
        entry<HeartRateRecord>("heart_rate", "avg_hr", "min_hr", "max_hr", pagePolicy = RawPagePolicy.HIGH_CARDINALITY),
        entry<SleepSessionRecord>("sleep_session", "sleep_total", "sleep_deep", "sleep_rem", "sleep_light", "sleep_awake", "sleep_in_bed"),
        entry<ExerciseSessionRecord>("exercise_session", "exercise_minutes", "cycling_distance", "swimming_distance", "swimming_strokes", "wheelchair_distance", "downhill_snow_distance", "walking_hr", "running_speed", "running_power", "workouts"),
        entry<DistanceRecord>("distance", "distance", "cycling_distance", "swimming_distance", "wheelchair_distance", "downhill_snow_distance"),
        entry<ActiveCaloriesBurnedRecord>("active_calories_burned", "active_calories"),
        entry<TotalCaloriesBurnedRecord>("total_calories_burned", "total_calories"),
        entry<BasalMetabolicRateRecord>("basal_metabolic_rate", "basal_calories"),
        entry<BloodPressureRecord>("blood_pressure", "bp_systolic", "bp_diastolic"),
        entry<BloodGlucoseRecord>("blood_glucose", "blood_glucose"),
        entry<BodyFatRecord>("body_fat", "body_fat"),
        entry<BodyTemperatureRecord>("body_temperature", "body_temp"),
        entry<HeightRecord>("height", "height", "bmi"),
        entry<WeightRecord>("weight", "weight", "bmi"),
        entry<OxygenSaturationRecord>("oxygen_saturation", "blood_oxygen"),
        entry<RespiratoryRateRecord>("respiratory_rate", "respiratory_rate"),
        entry<HeartRateVariabilityRmssdRecord>("heart_rate_variability_rmssd", "hrv"),
        entry<NutritionRecord>("nutrition", "dietary_energy", "protein", "carbs", "fat", "saturated_fat", "monounsaturated_fat", "polyunsaturated_fat", "unsaturated_fat", "trans_fat", "fiber", "sugar", "sodium", "potassium", "calcium", "iron", "magnesium", "zinc", "phosphorus", "iodine", "selenium", "copper", "manganese", "chromium", "molybdenum", "chloride", "vitamin_a", "vitamin_b6", "vitamin_b12", "vitamin_c", "vitamin_d", "vitamin_e", "vitamin_k", "thiamin", "riboflavin", "niacin", "folate", "folic_acid", "pantothenic_acid", "biotin", "cholesterol", "caffeine", "energy_from_fat", "nutrition_meals"),
        entry<HydrationRecord>("hydration", "water"),
        entry<FloorsClimbedRecord>("floors_climbed", "flights_climbed"),
        entry<LeanBodyMassRecord>("lean_body_mass", "lean_mass"),
        entry<RestingHeartRateRecord>("resting_heart_rate", "resting_hr"),
        entry<SpeedRecord>("speed", "walking_speed", "running_speed", pagePolicy = RawPagePolicy.HIGH_CARDINALITY),
        entry<Vo2MaxRecord>("vo2_max", "vo2_max"),
        entry<ElevationGainedRecord>("elevation_gained", "elevation_gained"),
        entry<WheelchairPushesRecord>("wheelchair_pushes", "wheelchair_pushes"),
        entry<PowerRecord>("power", "power_avg", "power_max", "running_power", pagePolicy = RawPagePolicy.HIGH_CARDINALITY),
        entry<BasalBodyTemperatureRecord>("basal_body_temperature", "basal_body_temp"),
        entry<BodyWaterMassRecord>("body_water_mass", "body_water_mass"),
        entry<BoneMassRecord>("bone_mass", "bone_mass"),
        entry<SkinTemperatureRecord>("skin_temperature", "skin_temperature", feature = HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE, pagePolicy = RawPagePolicy.HIGH_CARDINALITY),
        entry<CervicalMucusRecord>("cervical_mucus", "cervical_mucus"),
        entry<IntermenstrualBleedingRecord>("intermenstrual_bleeding", "intermenstrual_bleeding"),
        entry<MenstruationFlowRecord>("menstruation_flow", "menstrual_flow"),
        entry<MenstruationPeriodRecord>("menstruation_period", "menstruation_periods", "menstruation_period_days"),
        entry<OvulationTestRecord>("ovulation_test", "ovulation_test"),
        entry<SexualActivityRecord>("sexual_activity", "sexual_activity"),
        entry<CyclingPedalingCadenceRecord>("cycling_pedaling_cadence", "cycling_cadence", pagePolicy = RawPagePolicy.HIGH_CARDINALITY),
        entry<StepsCadenceRecord>("steps_cadence", "steps_cadence", pagePolicy = RawPagePolicy.HIGH_CARDINALITY),
        entry<MindfulnessSessionRecord>("mindfulness_session", "mindful_minutes", "mindful_sessions", feature = HealthConnectFeatures.FEATURE_MINDFULNESS_SESSION),
        entry<PlannedExerciseSessionRecord>("planned_exercise_session", "planned_workouts", feature = HealthConnectFeatures.FEATURE_PLANNED_EXERCISE),
        entry<ActivityIntensityRecord>("activity_intensity", "activity_intensity_minutes", feature = HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY),
    )

    val permissionedRecordClasses: Set<KClass<out Record>> = records.map { it.recordClass }.toSet()
    val readPermissions: Set<String> = records.map { it.readPermission }.toSet()

    fun selected(metricIds: Set<String>): List<HealthConnectRecordDescriptor<out Record>> =
        records.filter { descriptor -> descriptor.metricIds.any(metricIds::contains) }
}
