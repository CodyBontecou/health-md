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
) {
    val hasData: Boolean
        get() = totalDuration > Duration.ZERO || deepSleep > Duration.ZERO ||
                remSleep > Duration.ZERO || lightSleep > Duration.ZERO ||
                awakeTime > Duration.ZERO || inBedTime > Duration.ZERO
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
) {
    val hasData: Boolean
        get() = mindfulnessMinutes != null
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
