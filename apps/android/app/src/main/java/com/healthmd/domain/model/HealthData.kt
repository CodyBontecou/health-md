package com.healthmd.domain.model

import kotlinx.serialization.Serializable
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.UUID
import kotlin.time.Duration
import kotlin.time.Duration.Companion.seconds

// MARK: - Granular Sample Types

@Serializable
data class TimestampedSample(
    @Serializable(with = LocalDateTimeSerializer::class)
    val time: LocalDateTime,
    val value: Double,
)

@Serializable
data class SleepStageEntry(
    @Serializable(with = LocalDateTimeSerializer::class)
    val startTime: LocalDateTime,
    @Serializable(with = LocalDateTimeSerializer::class)
    val endTime: LocalDateTime,
    val stage: String, // "deep", "rem", "light", "awake", "sleeping"
)

@Serializable
data class BloodPressureSample(
    @Serializable(with = LocalDateTimeSerializer::class)
    val time: LocalDateTime,
    val systolic: Double,
    val diastolic: Double,
)

// MARK: - Sleep Data

@Serializable
data class SleepData(
    @Serializable(with = DurationSerializer::class)
    val totalDuration: Duration = Duration.ZERO,
    @Serializable(with = DurationSerializer::class)
    val deepSleep: Duration = Duration.ZERO,
    @Serializable(with = DurationSerializer::class)
    val remSleep: Duration = Duration.ZERO,
    @Serializable(with = DurationSerializer::class)
    val lightSleep: Duration = Duration.ZERO,
    @Serializable(with = DurationSerializer::class)
    val awakeTime: Duration = Duration.ZERO,
    @Serializable(with = DurationSerializer::class)
    val inBedTime: Duration = Duration.ZERO,
    val stages: List<SleepStageEntry> = emptyList(),
    /** Optional: start of the first sleep interval (bedtime). Populated by HealthConnectManager. */
    @Serializable(with = LocalDateTimeSerializer::class)
    val sessionStart: LocalDateTime? = null,
    /** Optional: end of the last sleep interval (wake time). Populated by HealthConnectManager. */
    @Serializable(with = LocalDateTimeSerializer::class)
    val sessionEnd: LocalDateTime? = null,
) {
    val hasData: Boolean
        get() = totalDuration > Duration.ZERO || deepSleep > Duration.ZERO ||
                remSleep > Duration.ZERO || lightSleep > Duration.ZERO ||
                awakeTime > Duration.ZERO || inBedTime > Duration.ZERO ||
                stages.isNotEmpty() || sessionStart != null || sessionEnd != null
}

// MARK: - Activity Data

@Serializable
data class ActivityData(
    val steps: Int? = null,
    val activeCalories: Double? = null,
    val totalCalories: Double? = null,
    val exerciseMinutes: Double? = null,
    val flightsClimbed: Int? = null,
    val walkingRunningDistance: Double? = null, // meters
    val basalEnergyBurned: Double? = null,
    val cyclingDistance: Double? = null, // meters
    val elevationGained: Double? = null, // meters
    val wheelchairPushes: Int? = null,
    val stepSamples: List<TimestampedSample> = emptyList(),
) {
    val hasData: Boolean
        get() = steps != null || activeCalories != null || totalCalories != null ||
                exerciseMinutes != null || flightsClimbed != null ||
                walkingRunningDistance != null || basalEnergyBurned != null ||
                cyclingDistance != null || elevationGained != null ||
                wheelchairPushes != null
}

// MARK: - Heart Data

@Serializable
data class HeartData(
    val restingHeartRate: Double? = null,
    val averageHeartRate: Double? = null,
    val hrv: Double? = null, // milliseconds (RMSSD on Android)
    val heartRateMin: Double? = null,
    val heartRateMax: Double? = null,
    val samples: List<TimestampedSample> = emptyList(),
    val hrvSamples: List<TimestampedSample> = emptyList(),
) {
    val hasData: Boolean
        get() = restingHeartRate != null || averageHeartRate != null ||
                hrv != null || heartRateMin != null || heartRateMax != null
}

// MARK: - Vitals Data

@Serializable
data class VitalsData(
    // Respiratory Rate
    val respiratoryRateAvg: Double? = null,
    val respiratoryRateMin: Double? = null,
    val respiratoryRateMax: Double? = null,
    // Blood Oxygen / SpO2
    val bloodOxygenAvg: Double? = null, // percentage (0-1)
    val bloodOxygenMin: Double? = null,
    val bloodOxygenMax: Double? = null,
    // Body Temperature
    val bodyTemperatureAvg: Double? = null, // Celsius
    val bodyTemperatureMin: Double? = null,
    val bodyTemperatureMax: Double? = null,
    // Blood Pressure
    val bloodPressureSystolicAvg: Double? = null,
    val bloodPressureSystolicMin: Double? = null,
    val bloodPressureSystolicMax: Double? = null,
    val bloodPressureDiastolicAvg: Double? = null,
    val bloodPressureDiastolicMin: Double? = null,
    val bloodPressureDiastolicMax: Double? = null,
    // Blood Glucose
    val bloodGlucoseAvg: Double? = null, // mg/dL
    val bloodGlucoseMin: Double? = null,
    val bloodGlucoseMax: Double? = null,
    // Basal Body Temperature
    val basalBodyTemperature: Double? = null, // Celsius
    // Skin Temperature
    val skinTemperatureDelta: Double? = null, // Celsius (delta from baseline)
    // Granular samples
    val bloodOxygenSamples: List<TimestampedSample> = emptyList(),
    val bloodPressureSamples: List<BloodPressureSample> = emptyList(),
    val bloodGlucoseSamples: List<TimestampedSample> = emptyList(),
    val respiratoryRateSamples: List<TimestampedSample> = emptyList(),
    val bodyTemperatureSamples: List<TimestampedSample> = emptyList(),
) {
    val hasData: Boolean
        get() = respiratoryRateAvg != null || bloodOxygenAvg != null ||
                bodyTemperatureAvg != null || bloodPressureSystolicAvg != null ||
                bloodPressureDiastolicAvg != null || bloodGlucoseAvg != null ||
                basalBodyTemperature != null || skinTemperatureDelta != null
}

// MARK: - Body Data

@Serializable
data class BodyData(
    val weight: Double? = null, // kg
    val bodyFatPercentage: Double? = null,
    val height: Double? = null, // meters
    val bmi: Double? = null,
    val leanBodyMass: Double? = null, // kg
    val bodyWaterMass: Double? = null, // kg
    val boneMass: Double? = null, // kg
) {
    val hasData: Boolean
        get() = weight != null || bodyFatPercentage != null || height != null ||
                bmi != null || leanBodyMass != null || bodyWaterMass != null ||
                boneMass != null
}

// MARK: - Nutrition Data

@Serializable
data class NutritionData(
    val dietaryEnergy: Double? = null, // kcal
    val protein: Double? = null, // grams
    val carbohydrates: Double? = null, // grams
    val fat: Double? = null, // grams
    val fiber: Double? = null, // grams
    val sugar: Double? = null, // grams
    val sodium: Double? = null, // mg
    val water: Double? = null, // liters
    val caffeine: Double? = null, // mg
    val cholesterol: Double? = null, // mg
    val saturatedFat: Double? = null, // grams
) {
    val hasData: Boolean
        get() = dietaryEnergy != null || protein != null || carbohydrates != null ||
                fat != null || fiber != null || sugar != null || sodium != null ||
                water != null || caffeine != null || cholesterol != null || saturatedFat != null
}

// MARK: - Mobility Data

@Serializable
data class MobilityData(
    val walkingSpeed: Double? = null, // m/s
    val vo2Max: Double? = null, // mL/kg/min
    val cyclingCadenceAvg: Double? = null, // rpm
    val stepsCadenceAvg: Double? = null, // steps/min
    val powerAvg: Double? = null, // watts
    val powerMax: Double? = null, // watts
) {
    val hasData: Boolean
        get() = walkingSpeed != null || vo2Max != null || cyclingCadenceAvg != null ||
                stepsCadenceAvg != null || powerAvg != null || powerMax != null
}

// MARK: - Reproductive Health Data

@Serializable
data class ReproductiveHealthData(
    val menstrualFlow: String? = null, // light, medium, heavy
    val cervicalMucusAppearance: String? = null,
    val cervicalMucusSensation: String? = null,
    val ovulationTestResult: String? = null, // positive, high, negative, inconclusive
    val intermenstrualBleeding: Boolean = false,
    val sexualActivityRecorded: Boolean = false,
    val sexualActivityProtectionUsed: String? = null, // protected, unprotected
) {
    val hasData: Boolean
        get() = menstrualFlow != null || cervicalMucusAppearance != null ||
                cervicalMucusSensation != null || ovulationTestResult != null ||
                intermenstrualBleeding || sexualActivityRecorded
}

// MARK: - Mindfulness Data

@Serializable
data class MindfulnessData(
    val mindfulnessMinutes: Double? = null,
    /** Count of distinct mindfulness sessions recorded (null = not available from Health Connect). */
    val mindfulSessions: Int? = null,
) {
    val hasData: Boolean
        get() = mindfulnessMinutes != null || mindfulSessions != null
}

// MARK: - Workout Type

@Serializable
enum class WorkoutType {
    RUNNING,
    WALKING,
    CYCLING,
    SWIMMING,
    HIKING,
    YOGA,
    STRENGTH_TRAINING,
    CORE_TRAINING,
    HIIT,
    ELLIPTICAL,
    ROWING,
    STAIR_CLIMBING,
    PILATES,
    DANCE,
    COOLDOWN,
    MIXED_CARDIO,
    PICKLEBALL,
    TENNIS,
    BADMINTON,
    TABLE_TENNIS,
    GOLF,
    SOCCER,
    BASKETBALL,
    BASEBALL,
    SOFTBALL,
    VOLLEYBALL,
    AMERICAN_FOOTBALL,
    RUGBY,
    HOCKEY,
    LACROSSE,
    SKATING,
    SNOW_SPORTS,
    WATER_SPORTS,
    MARTIAL_ARTS,
    BOXING,
    KICKBOXING,
    WRESTLING,
    CLIMBING,
    JUMP_ROPE,
    FLEXIBILITY,
    OTHER,
}

// MARK: - Workout Data

@Serializable
data class WorkoutData(
    val id: String = UUID.randomUUID().toString(),
    val workoutType: WorkoutType,
    @Serializable(with = LocalDateTimeSerializer::class)
    val startTime: LocalDateTime,
    @Serializable(with = DurationSerializer::class)
    val duration: Duration,
    val calories: Double? = null,
    val distance: Double? = null, // meters
)

// MARK: - Complete Health Data

@Serializable
data class HealthData(
    @Serializable(with = LocalDateSerializer::class)
    val date: LocalDate,
    val sleep: SleepData = SleepData(),
    val activity: ActivityData = ActivityData(),
    val heart: HeartData = HeartData(),
    val vitals: VitalsData = VitalsData(),
    val body: BodyData = BodyData(),
    val nutrition: NutritionData = NutritionData(),
    val mobility: MobilityData = MobilityData(),
    val reproductiveHealth: ReproductiveHealthData = ReproductiveHealthData(),
    val mindfulness: MindfulnessData = MindfulnessData(),
    val workouts: List<WorkoutData> = emptyList(),
) {
    val hasAnyData: Boolean
        get() = sleep.hasData || activity.hasData || heart.hasData || vitals.hasData ||
                body.hasData || nutrition.hasData || mobility.hasData || workouts.isNotEmpty() ||
                reproductiveHealth.hasData || mindfulness.hasData

    fun filtered(selection: DataTypeSelection): HealthData = copy(
        sleep = if (selection.sleep) sleep else SleepData(),
        activity = if (selection.activity) activity else ActivityData(),
        heart = if (selection.heart) heart else HeartData(),
        vitals = if (selection.vitals) vitals else VitalsData(),
        body = if (selection.body) body else BodyData(),
        nutrition = if (selection.nutrition) nutrition else NutritionData(),
        mobility = if (selection.mobility) mobility else MobilityData(),
        reproductiveHealth = if (selection.reproductiveHealth) reproductiveHealth else ReproductiveHealthData(),
        mindfulness = if (selection.mindfulness) mindfulness else MindfulnessData(),
        workouts = if (selection.workouts) workouts else emptyList(),
    )

    /**
     * Applies the per-metric picker state to the already-fetched HealthData tree.
     *
     * Health Connect is fetched by broad record/category for efficiency, then this method removes
     * individual disabled metrics before any exporter, Daily Note Injection, or Individual Entry
     * Tracking sees the data. That keeps every output format aligned to the same metric selection.
     */
    fun filtered(selection: MetricSelectionState): HealthData {
        fun enabled(metricId: String): Boolean = selection.isEnabled(metricId)

        val filteredSleep = SleepData(
            totalDuration = if (enabled("sleep_total")) sleep.totalDuration else Duration.ZERO,
            deepSleep = if (enabled("sleep_deep")) sleep.deepSleep else Duration.ZERO,
            remSleep = if (enabled("sleep_rem")) sleep.remSleep else Duration.ZERO,
            lightSleep = if (enabled("sleep_light")) sleep.lightSleep else Duration.ZERO,
            awakeTime = if (enabled("sleep_awake")) sleep.awakeTime else Duration.ZERO,
            inBedTime = if (enabled("sleep_in_bed")) sleep.inBedTime else Duration.ZERO,
            stages = sleep.stages.filter { stage ->
                when (stage.stage.lowercase()) {
                    "deep" -> enabled("sleep_deep")
                    "rem" -> enabled("sleep_rem")
                    "light", "core", "sleeping" -> enabled("sleep_light")
                    "awake", "wake" -> enabled("sleep_awake")
                    else -> enabled("sleep_total")
                }
            },
            sessionStart = if (enabled("sleep_total") || enabled("sleep_in_bed")) sleep.sessionStart else null,
            sessionEnd = if (enabled("sleep_total") || enabled("sleep_in_bed")) sleep.sessionEnd else null,
        )

        val filteredActivity = ActivityData(
            steps = activity.steps.takeIf { enabled("steps") },
            activeCalories = activity.activeCalories.takeIf { enabled("active_calories") },
            totalCalories = activity.totalCalories.takeIf { enabled("total_calories") },
            exerciseMinutes = activity.exerciseMinutes.takeIf { enabled("exercise_minutes") },
            flightsClimbed = activity.flightsClimbed.takeIf { enabled("flights_climbed") },
            walkingRunningDistance = activity.walkingRunningDistance.takeIf { enabled("distance") },
            basalEnergyBurned = activity.basalEnergyBurned.takeIf { enabled("basal_calories") },
            cyclingDistance = activity.cyclingDistance.takeIf { enabled("cycling_distance") },
            elevationGained = activity.elevationGained.takeIf { enabled("elevation_gained") },
            wheelchairPushes = activity.wheelchairPushes.takeIf { enabled("wheelchair_pushes") },
            stepSamples = if (enabled("steps")) activity.stepSamples else emptyList(),
        )

        val filteredHeart = HeartData(
            restingHeartRate = heart.restingHeartRate.takeIf { enabled("resting_hr") },
            averageHeartRate = heart.averageHeartRate.takeIf { enabled("avg_hr") },
            hrv = heart.hrv.takeIf { enabled("hrv") },
            heartRateMin = heart.heartRateMin.takeIf { enabled("min_hr") },
            heartRateMax = heart.heartRateMax.takeIf { enabled("max_hr") },
            samples = if (enabled("avg_hr") || enabled("min_hr") || enabled("max_hr")) heart.samples else emptyList(),
            hrvSamples = if (enabled("hrv")) heart.hrvSamples else emptyList(),
        )

        val includeBloodPressureSamples = enabled("bp_systolic") && enabled("bp_diastolic")
        val filteredVitals = VitalsData(
            respiratoryRateAvg = vitals.respiratoryRateAvg.takeIf { enabled("respiratory_rate") },
            respiratoryRateMin = vitals.respiratoryRateMin.takeIf { enabled("respiratory_rate") },
            respiratoryRateMax = vitals.respiratoryRateMax.takeIf { enabled("respiratory_rate") },
            bloodOxygenAvg = vitals.bloodOxygenAvg.takeIf { enabled("blood_oxygen") },
            bloodOxygenMin = vitals.bloodOxygenMin.takeIf { enabled("blood_oxygen") },
            bloodOxygenMax = vitals.bloodOxygenMax.takeIf { enabled("blood_oxygen") },
            bodyTemperatureAvg = vitals.bodyTemperatureAvg.takeIf { enabled("body_temp") },
            bodyTemperatureMin = vitals.bodyTemperatureMin.takeIf { enabled("body_temp") },
            bodyTemperatureMax = vitals.bodyTemperatureMax.takeIf { enabled("body_temp") },
            bloodPressureSystolicAvg = vitals.bloodPressureSystolicAvg.takeIf { enabled("bp_systolic") },
            bloodPressureSystolicMin = vitals.bloodPressureSystolicMin.takeIf { enabled("bp_systolic") },
            bloodPressureSystolicMax = vitals.bloodPressureSystolicMax.takeIf { enabled("bp_systolic") },
            bloodPressureDiastolicAvg = vitals.bloodPressureDiastolicAvg.takeIf { enabled("bp_diastolic") },
            bloodPressureDiastolicMin = vitals.bloodPressureDiastolicMin.takeIf { enabled("bp_diastolic") },
            bloodPressureDiastolicMax = vitals.bloodPressureDiastolicMax.takeIf { enabled("bp_diastolic") },
            bloodGlucoseAvg = vitals.bloodGlucoseAvg.takeIf { enabled("blood_glucose") },
            bloodGlucoseMin = vitals.bloodGlucoseMin.takeIf { enabled("blood_glucose") },
            bloodGlucoseMax = vitals.bloodGlucoseMax.takeIf { enabled("blood_glucose") },
            basalBodyTemperature = vitals.basalBodyTemperature.takeIf { enabled("basal_body_temp") },
            skinTemperatureDelta = vitals.skinTemperatureDelta.takeIf { enabled("skin_temperature") },
            bloodOxygenSamples = if (enabled("blood_oxygen")) vitals.bloodOxygenSamples else emptyList(),
            bloodPressureSamples = if (includeBloodPressureSamples) vitals.bloodPressureSamples else emptyList(),
            bloodGlucoseSamples = if (enabled("blood_glucose")) vitals.bloodGlucoseSamples else emptyList(),
            respiratoryRateSamples = if (enabled("respiratory_rate")) vitals.respiratoryRateSamples else emptyList(),
            bodyTemperatureSamples = if (enabled("body_temp")) vitals.bodyTemperatureSamples else emptyList(),
        )

        val filteredBody = BodyData(
            weight = body.weight.takeIf { enabled("weight") },
            bodyFatPercentage = body.bodyFatPercentage.takeIf { enabled("body_fat") },
            height = body.height.takeIf { enabled("height") },
            bmi = body.bmi.takeIf { enabled("bmi") },
            leanBodyMass = body.leanBodyMass.takeIf { enabled("lean_mass") },
            bodyWaterMass = body.bodyWaterMass.takeIf { enabled("body_water_mass") },
            boneMass = body.boneMass.takeIf { enabled("bone_mass") },
        )

        val filteredNutrition = NutritionData(
            dietaryEnergy = nutrition.dietaryEnergy.takeIf { enabled("dietary_energy") },
            protein = nutrition.protein.takeIf { enabled("protein") },
            carbohydrates = nutrition.carbohydrates.takeIf { enabled("carbs") },
            fat = nutrition.fat.takeIf { enabled("fat") },
            fiber = nutrition.fiber.takeIf { enabled("fiber") },
            sugar = nutrition.sugar.takeIf { enabled("sugar") },
            sodium = nutrition.sodium.takeIf { enabled("sodium") },
            water = nutrition.water.takeIf { enabled("water") },
            caffeine = nutrition.caffeine.takeIf { enabled("caffeine") },
            cholesterol = nutrition.cholesterol.takeIf { enabled("cholesterol") },
            saturatedFat = nutrition.saturatedFat.takeIf { enabled("saturated_fat") },
        )

        val filteredMobility = MobilityData(
            walkingSpeed = mobility.walkingSpeed.takeIf { enabled("walking_speed") },
            vo2Max = mobility.vo2Max.takeIf { enabled("vo2_max") },
            cyclingCadenceAvg = mobility.cyclingCadenceAvg.takeIf { enabled("cycling_cadence") },
            stepsCadenceAvg = mobility.stepsCadenceAvg.takeIf { enabled("steps_cadence") },
            powerAvg = mobility.powerAvg.takeIf { enabled("power_avg") },
            powerMax = mobility.powerMax.takeIf { enabled("power_max") },
        )

        val filteredReproductiveHealth = ReproductiveHealthData(
            menstrualFlow = reproductiveHealth.menstrualFlow.takeIf { enabled("menstrual_flow") },
            cervicalMucusAppearance = reproductiveHealth.cervicalMucusAppearance.takeIf { enabled("cervical_mucus") },
            cervicalMucusSensation = reproductiveHealth.cervicalMucusSensation.takeIf { enabled("cervical_mucus") },
            ovulationTestResult = reproductiveHealth.ovulationTestResult.takeIf { enabled("ovulation_test") },
            intermenstrualBleeding = reproductiveHealth.intermenstrualBleeding && enabled("intermenstrual_bleeding"),
            sexualActivityRecorded = reproductiveHealth.sexualActivityRecorded && enabled("sexual_activity"),
            sexualActivityProtectionUsed = reproductiveHealth.sexualActivityProtectionUsed.takeIf { enabled("sexual_activity") },
        )

        val filteredMindfulness = MindfulnessData(
            mindfulnessMinutes = mindfulness.mindfulnessMinutes.takeIf { enabled("mindful_minutes") },
            mindfulSessions = mindfulness.mindfulSessions.takeIf { enabled("mindful_minutes") },
        )

        return copy(
            sleep = filteredSleep,
            activity = filteredActivity,
            heart = filteredHeart,
            vitals = filteredVitals,
            body = filteredBody,
            nutrition = filteredNutrition,
            mobility = filteredMobility,
            reproductiveHealth = filteredReproductiveHealth,
            mindfulness = filteredMindfulness,
            workouts = if (enabled("workouts")) workouts else emptyList(),
        )
    }
}

// MARK: - Data Type Selection

@Serializable
data class DataTypeSelection(
    val sleep: Boolean = true,
    val activity: Boolean = true,
    val heart: Boolean = true,
    val vitals: Boolean = true,
    val body: Boolean = true,
    val nutrition: Boolean = true,
    val mobility: Boolean = true,
    val reproductiveHealth: Boolean = true,
    val mindfulness: Boolean = true,
    val workouts: Boolean = true,
) {
    val hasAnySelected: Boolean
        get() = sleep || activity || heart || vitals || body || nutrition ||
                mobility || workouts || reproductiveHealth || mindfulness

    val enabledCount: Int
        get() = listOf(sleep, activity, heart, vitals, body, nutrition, mobility, workouts,
            reproductiveHealth, mindfulness).count { it }

    fun selectAll() = DataTypeSelection()

    fun deselectAll() = DataTypeSelection(
        sleep = false, activity = false, heart = false, vitals = false,
        body = false, nutrition = false, mobility = false, workouts = false,
        reproductiveHealth = false, mindfulness = false,
    )
}

fun DataTypeSelection.intersect(other: DataTypeSelection): DataTypeSelection = DataTypeSelection(
    sleep = sleep && other.sleep,
    activity = activity && other.activity,
    heart = heart && other.heart,
    vitals = vitals && other.vitals,
    body = body && other.body,
    nutrition = nutrition && other.nutrition,
    mobility = mobility && other.mobility,
    reproductiveHealth = reproductiveHealth && other.reproductiveHealth,
    mindfulness = mindfulness && other.mindfulness,
    workouts = workouts && other.workouts,
)

fun MetricSelectionState.toDataTypeSelection(): DataTypeSelection {
    fun anyEnabled(vararg metricIds: String): Boolean = metricIds.any { isEnabled(it) }

    return DataTypeSelection(
        sleep = anyEnabled(
            "sleep_total", "sleep_deep", "sleep_rem", "sleep_light", "sleep_awake", "sleep_in_bed",
        ),
        activity = anyEnabled(
            "steps", "active_calories", "total_calories", "basal_calories", "exercise_minutes",
            "flights_climbed", "distance", "cycling_distance", "elevation_gained", "wheelchair_pushes",
        ),
        heart = anyEnabled("resting_hr", "avg_hr", "min_hr", "max_hr", "hrv"),
        vitals = anyEnabled(
            "respiratory_rate", "blood_oxygen", "body_temp", "bp_systolic", "bp_diastolic",
            "blood_glucose", "basal_body_temp", "skin_temperature",
        ),
        body = anyEnabled("weight", "height", "bmi", "body_fat", "lean_mass", "body_water_mass", "bone_mass"),
        nutrition = anyEnabled(
            "dietary_energy", "protein", "carbs", "fat", "saturated_fat", "fiber", "sugar",
            "sodium", "cholesterol", "water", "caffeine",
        ),
        mobility = anyEnabled("walking_speed", "vo2_max", "cycling_cadence", "steps_cadence", "power_avg", "power_max"),
        reproductiveHealth = anyEnabled(
            "menstrual_flow", "cervical_mucus", "ovulation_test", "sexual_activity", "intermenstrual_bleeding",
        ),
        mindfulness = anyEnabled("mindful_minutes"),
        workouts = anyEnabled("workouts"),
    )
}
