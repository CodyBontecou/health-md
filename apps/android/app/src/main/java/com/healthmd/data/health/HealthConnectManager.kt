package com.healthmd.data.health

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.healthmd.domain.model.*
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes

class HealthConnectManager(private val context: Context) {

    private val healthConnectClient by lazy { HealthConnectClient.getOrCreate(context) }

    // All permissions we request
    val permissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(BasalMetabolicRateRecord::class),
        HealthPermission.getReadPermission(BloodPressureRecord::class),
        HealthPermission.getReadPermission(BloodGlucoseRecord::class),
        HealthPermission.getReadPermission(BodyFatRecord::class),
        HealthPermission.getReadPermission(BodyTemperatureRecord::class),
        HealthPermission.getReadPermission(HeightRecord::class),
        HealthPermission.getReadPermission(WeightRecord::class),
        HealthPermission.getReadPermission(OxygenSaturationRecord::class),
        HealthPermission.getReadPermission(RespiratoryRateRecord::class),
        HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class),
        HealthPermission.getReadPermission(NutritionRecord::class),
        HealthPermission.getReadPermission(HydrationRecord::class),
        HealthPermission.getReadPermission(FloorsClimbedRecord::class),
        HealthPermission.getReadPermission(LeanBodyMassRecord::class),
        HealthPermission.getReadPermission(RestingHeartRateRecord::class),
        HealthPermission.getReadPermission(SpeedRecord::class),
        HealthPermission.getReadPermission(Vo2MaxRecord::class),
    )

    /**
     * Check if Health Connect is available on this device.
     */
    fun isAvailable(): Boolean {
        val status = HealthConnectClient.getSdkStatus(context)
        return status == HealthConnectClient.SDK_AVAILABLE
    }

    /**
     * Check if Health Connect needs to be installed or updated.
     */
    fun needsInstall(): Boolean {
        val status = HealthConnectClient.getSdkStatus(context)
        return status == HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED
    }

    /**
     * Get an intent that opens Health Connect so the user can complete first-time
     * setup (accept terms, etc.) before permissions can be granted.
     * On Android 14+, Health Connect is built into the OS and opened via a settings action.
     * On older versions, it's a standalone Play Store app.
     */
    fun getOpenHealthConnectIntent(): Intent =
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Android 14+ — Health Connect is a system component
            Intent("android.health.connect.action.HEALTH_HOME_SETTINGS").apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        } else {
            // Android 9–13 — standalone app
            context.packageManager
                .getLaunchIntentForPackage("com.google.android.apps.healthdata")
                ?: getInstallIntent()
        }

    /**
     * Get the intent to install/update Health Connect from the Play Store.
     */
    fun getInstallIntent(): Intent {
        val uri = Uri.parse("market://details?id=com.google.android.apps.healthdata")
        return Intent(Intent.ACTION_VIEW, uri)
    }

    /**
     * Check if we have all required permissions.
     */
    suspend fun hasAllPermissions(): Boolean {
        val granted = healthConnectClient.permissionController.getGrantedPermissions()
        return permissions.all { it in granted }
    }

    /**
     * Get the permission request contract for use with ActivityResultLauncher.
     */
    fun getPermissionContract() = PermissionController.createRequestPermissionResultContract()

    /**
     * Returns a human-readable SDK status string for debugging.
     */
    fun getSdkStatusString(): String {
        val status = HealthConnectClient.getSdkStatus(context)
        return when (status) {
            HealthConnectClient.SDK_AVAILABLE -> "SDK_AVAILABLE ($status)"
            HealthConnectClient.SDK_UNAVAILABLE -> "SDK_UNAVAILABLE ($status)"
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "PROVIDER_UPDATE_REQUIRED ($status)"
            else -> "UNKNOWN ($status)"
        }
    }

    /**
     * Returns the set of currently granted permissions for debugging.
     */
    suspend fun getGrantedPermissions(): Set<String> = try {
        healthConnectClient.permissionController.getGrantedPermissions()
    } catch (_: Exception) {
        emptySet()
    }

    /**
     * Find the earliest date that has any health data in Health Connect.
     */
    suspend fun getEarliestDataDate(): LocalDate? {
        val zone = ZoneId.systemDefault()
        return try {
            val response = healthConnectClient.readRecords(
                ReadRecordsRequest(
                    recordType = StepsRecord::class,
                    timeRangeFilter = TimeRangeFilter.before(Instant.now()),
                    ascendingOrder = true,
                    pageSize = 1,
                )
            )
            response.records.firstOrNull()?.startTime
                ?.atZone(zone)
                ?.toLocalDate()
        } catch (_: Exception) {
            null
        }
    }

    /**
     * Fetch health data for a single date.
     */
    suspend fun fetchHealthData(date: LocalDate): HealthData {
        val zone = ZoneId.systemDefault()
        val startTime = date.atStartOfDay(zone).toInstant()
        val endTime = date.plusDays(1).atStartOfDay(zone).toInstant()
        val timeRange = TimeRangeFilter.between(startTime, endTime)

        return coroutineScope {
            val sleepDeferred = async { fetchSleepData(timeRange, date) }
            val activityDeferred = async { fetchActivityData(timeRange) }
            val heartDeferred = async { fetchHeartData(timeRange) }
            val vitalsDeferred = async { fetchVitalsData(timeRange) }
            val bodyDeferred = async { fetchBodyData(timeRange) }
            val nutritionDeferred = async { fetchNutritionData(timeRange) }
            val mobilityDeferred = async { fetchMobilityData(timeRange) }
            val workoutsDeferred = async { fetchWorkouts(timeRange) }

            HealthData(
                date = date,
                sleep = sleepDeferred.await(),
                activity = activityDeferred.await(),
                heart = heartDeferred.await(),
                vitals = vitalsDeferred.await(),
                body = bodyDeferred.await(),
                nutrition = nutritionDeferred.await(),
                mobility = mobilityDeferred.await(),
                workouts = workoutsDeferred.await(),
            )
        }
    }

    // MARK: - Private fetch methods

    private suspend fun fetchSleepData(timeRange: TimeRangeFilter, date: LocalDate): SleepData {
        return try {
            val response = healthConnectClient.readRecords(
                ReadRecordsRequest(SleepSessionRecord::class, timeRange)
            )

            var totalMs = 0L
            var deepMs = 0L
            var remMs = 0L
            var lightMs = 0L
            var awakeMs = 0L

            for (session in response.records) {
                val sessionDurationMs = java.time.Duration.between(session.startTime, session.endTime).toMillis()
                totalMs += sessionDurationMs

                for (stage in session.stages) {
                    val stageMs = java.time.Duration.between(stage.startTime, stage.endTime).toMillis()
                    when (stage.stage) {
                        SleepSessionRecord.STAGE_TYPE_DEEP -> deepMs += stageMs
                        SleepSessionRecord.STAGE_TYPE_REM -> remMs += stageMs
                        SleepSessionRecord.STAGE_TYPE_LIGHT -> lightMs += stageMs
                        SleepSessionRecord.STAGE_TYPE_AWAKE -> awakeMs += stageMs
                        SleepSessionRecord.STAGE_TYPE_SLEEPING -> lightMs += stageMs // generic -> light
                    }
                }
            }

            SleepData(
                totalDuration = totalMs.milliseconds,
                deepSleep = deepMs.milliseconds,
                remSleep = remMs.milliseconds,
                lightSleep = lightMs.milliseconds,
                awakeTime = awakeMs.milliseconds,
                inBedTime = totalMs.milliseconds, // approximate: total session time
            )
        } catch (_: Exception) {
            SleepData()
        }
    }

    private suspend fun fetchActivityData(timeRange: TimeRangeFilter): ActivityData {
        return try {
            val aggregateResponse = healthConnectClient.aggregate(
                AggregateRequest(
                    metrics = setOf(
                        StepsRecord.COUNT_TOTAL,
                        ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL,
                        FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL,
                        DistanceRecord.DISTANCE_TOTAL,
                    ),
                    timeRangeFilter = timeRange,
                )
            )

            // Exercise minutes: sum duration of all exercise sessions
            val exerciseSessions = healthConnectClient.readRecords(
                ReadRecordsRequest(ExerciseSessionRecord::class, timeRange)
            )
            val exerciseMinutes = exerciseSessions.records.sumOf { session ->
                java.time.Duration.between(session.startTime, session.endTime).toMinutes().toDouble()
            }

            // Basal metabolic rate - read samples and estimate daily total
            val bmrRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BasalMetabolicRateRecord::class, timeRange)
            )
            val basalEnergy = bmrRecords.records.lastOrNull()?.let { record ->
                // BMR is in kcal/day, just take the value
                record.basalMetabolicRate.inKilocaloriesPerDay
            }

            ActivityData(
                steps = aggregateResponse[StepsRecord.COUNT_TOTAL]?.toInt(),
                activeCalories = aggregateResponse[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories,
                exerciseMinutes = if (exerciseMinutes > 0) exerciseMinutes else null,
                flightsClimbed = aggregateResponse[FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL]?.toInt(),
                walkingRunningDistance = aggregateResponse[DistanceRecord.DISTANCE_TOTAL]?.inMeters,
                basalEnergyBurned = basalEnergy,
            )
        } catch (_: Exception) {
            ActivityData()
        }
    }

    private suspend fun fetchHeartData(timeRange: TimeRangeFilter): HeartData {
        return try {
            // Heart rate samples
            val hrRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(HeartRateRecord::class, timeRange)
            )
            val allBpm = hrRecords.records.flatMap { record ->
                record.samples.map { it.beatsPerMinute.toDouble() }
            }

            // Resting heart rate
            val restingHrRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(RestingHeartRateRecord::class, timeRange)
            )
            val restingHr = restingHrRecords.records.lastOrNull()?.beatsPerMinute?.toDouble()

            // HRV
            val hrvRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(HeartRateVariabilityRmssdRecord::class, timeRange)
            )
            val hrv = hrvRecords.records.lastOrNull()?.heartRateVariabilityMillis

            HeartData(
                restingHeartRate = restingHr,
                averageHeartRate = if (allBpm.isNotEmpty()) allBpm.average() else null,
                hrv = hrv,
                heartRateMin = allBpm.minOrNull(),
                heartRateMax = allBpm.maxOrNull(),
            )
        } catch (_: Exception) {
            HeartData()
        }
    }

    private suspend fun fetchVitalsData(timeRange: TimeRangeFilter): VitalsData {
        return try {
            // Respiratory rate
            val rrRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(RespiratoryRateRecord::class, timeRange)
            )
            val rrValues = rrRecords.records.map { it.rate }

            // Blood oxygen
            val o2Records = healthConnectClient.readRecords(
                ReadRecordsRequest(OxygenSaturationRecord::class, timeRange)
            )
            val o2Values = o2Records.records.map { it.percentage.value / 100.0 } // convert to 0-1

            // Body temperature
            val tempRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BodyTemperatureRecord::class, timeRange)
            )
            val tempValues = tempRecords.records.map { it.temperature.inCelsius }

            // Blood pressure
            val bpRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BloodPressureRecord::class, timeRange)
            )
            val sysValues = bpRecords.records.map { it.systolic.inMillimetersOfMercury }
            val diaValues = bpRecords.records.map { it.diastolic.inMillimetersOfMercury }

            // Blood glucose
            val bgRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BloodGlucoseRecord::class, timeRange)
            )
            val bgValues = bgRecords.records.map { it.level.inMilligramsPerDeciliter }

            VitalsData(
                respiratoryRateAvg = rrValues.averageOrNull(),
                respiratoryRateMin = rrValues.minOrNull(),
                respiratoryRateMax = rrValues.maxOrNull(),
                bloodOxygenAvg = o2Values.averageOrNull(),
                bloodOxygenMin = o2Values.minOrNull(),
                bloodOxygenMax = o2Values.maxOrNull(),
                bodyTemperatureAvg = tempValues.averageOrNull(),
                bodyTemperatureMin = tempValues.minOrNull(),
                bodyTemperatureMax = tempValues.maxOrNull(),
                bloodPressureSystolicAvg = sysValues.averageOrNull(),
                bloodPressureSystolicMin = sysValues.minOrNull(),
                bloodPressureSystolicMax = sysValues.maxOrNull(),
                bloodPressureDiastolicAvg = diaValues.averageOrNull(),
                bloodPressureDiastolicMin = diaValues.minOrNull(),
                bloodPressureDiastolicMax = diaValues.maxOrNull(),
                bloodGlucoseAvg = bgValues.averageOrNull(),
                bloodGlucoseMin = bgValues.minOrNull(),
                bloodGlucoseMax = bgValues.maxOrNull(),
            )
        } catch (_: Exception) {
            VitalsData()
        }
    }

    private suspend fun fetchBodyData(timeRange: TimeRangeFilter): BodyData {
        return try {
            val weightRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(WeightRecord::class, timeRange)
            )
            val weight = weightRecords.records.lastOrNull()?.weight?.inKilograms

            val heightRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(HeightRecord::class, timeRange)
            )
            val height = heightRecords.records.lastOrNull()?.height?.inMeters

            val bodyFatRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BodyFatRecord::class, timeRange)
            )
            val bodyFat = bodyFatRecords.records.lastOrNull()?.percentage?.value

            val leanMassRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(LeanBodyMassRecord::class, timeRange)
            )
            val leanMass = leanMassRecords.records.lastOrNull()?.mass?.inKilograms

            // Compute BMI if we have both weight and height
            val bmi = if (weight != null && height != null && height > 0) {
                weight / (height * height)
            } else null

            BodyData(
                weight = weight,
                bodyFatPercentage = bodyFat,
                height = height,
                bmi = bmi,
                leanBodyMass = leanMass,
            )
        } catch (_: Exception) {
            BodyData()
        }
    }

    private suspend fun fetchNutritionData(timeRange: TimeRangeFilter): NutritionData {
        return try {
            val records = healthConnectClient.readRecords(
                ReadRecordsRequest(NutritionRecord::class, timeRange)
            )

            // Sum all nutrition records for the day
            var energy = 0.0
            var protein = 0.0
            var carbs = 0.0
            var fat = 0.0
            var fiber = 0.0
            var sugar = 0.0
            var sodium = 0.0
            var caffeine = 0.0
            var cholesterol = 0.0
            var saturatedFat = 0.0
            var hasAny = false

            for (record in records.records) {
                hasAny = true
                record.energy?.let { energy += it.inKilocalories }
                record.protein?.let { protein += it.inGrams }
                record.totalCarbohydrate?.let { carbs += it.inGrams }
                record.totalFat?.let { fat += it.inGrams }
                record.dietaryFiber?.let { fiber += it.inGrams }
                record.sugar?.let { sugar += it.inGrams }
                record.sodium?.let { sodium += it.inGrams * 1000 } // convert g -> mg
                record.caffeine?.let { caffeine += it.inGrams * 1000 }
                record.cholesterol?.let { cholesterol += it.inGrams * 1000 }
                record.saturatedFat?.let { saturatedFat += it.inGrams }
            }

            // Water (separate record type)
            val hydrationRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(HydrationRecord::class, timeRange)
            )
            val waterLiters = hydrationRecords.records.sumOf { it.volume.inLiters }

            if (!hasAny && waterLiters == 0.0) return NutritionData()

            NutritionData(
                dietaryEnergy = if (energy > 0) energy else null,
                protein = if (protein > 0) protein else null,
                carbohydrates = if (carbs > 0) carbs else null,
                fat = if (fat > 0) fat else null,
                fiber = if (fiber > 0) fiber else null,
                sugar = if (sugar > 0) sugar else null,
                sodium = if (sodium > 0) sodium else null,
                water = if (waterLiters > 0) waterLiters else null,
                caffeine = if (caffeine > 0) caffeine else null,
                cholesterol = if (cholesterol > 0) cholesterol else null,
                saturatedFat = if (saturatedFat > 0) saturatedFat else null,
            )
        } catch (_: Exception) {
            NutritionData()
        }
    }

    private suspend fun fetchMobilityData(timeRange: TimeRangeFilter): MobilityData {
        return try {
            val speedRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(SpeedRecord::class, timeRange)
            )
            val avgSpeed = speedRecords.records
                .flatMap { it.samples }
                .map { it.speed.inMetersPerSecond }
                .averageOrNull()

            val vo2Records = healthConnectClient.readRecords(
                ReadRecordsRequest(Vo2MaxRecord::class, timeRange)
            )
            val vo2Max = vo2Records.records.lastOrNull()?.vo2MillilitersPerMinuteKilogram

            MobilityData(
                walkingSpeed = avgSpeed,
                vo2Max = vo2Max,
            )
        } catch (_: Exception) {
            MobilityData()
        }
    }

    private suspend fun fetchWorkouts(timeRange: TimeRangeFilter): List<WorkoutData> {
        return try {
            val response = healthConnectClient.readRecords(
                ReadRecordsRequest(ExerciseSessionRecord::class, timeRange)
            )

            response.records.map { session ->
                val duration = java.time.Duration.between(session.startTime, session.endTime)
                WorkoutData(
                    workoutType = mapExerciseType(session.exerciseType),
                    startTime = LocalDateTime.ofInstant(session.startTime, ZoneId.systemDefault()),
                    duration = duration.toMillis().milliseconds,
                    calories = null, // Would need separate ActiveCaloriesBurned query per session
                    distance = null, // Would need separate Distance query per session
                )
            }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun mapExerciseType(type: Int): WorkoutType = when (type) {
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING -> WorkoutType.RUNNING
        ExerciseSessionRecord.EXERCISE_TYPE_WALKING -> WorkoutType.WALKING
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING -> WorkoutType.CYCLING
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL,
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER -> WorkoutType.SWIMMING
        ExerciseSessionRecord.EXERCISE_TYPE_HIKING -> WorkoutType.HIKING
        ExerciseSessionRecord.EXERCISE_TYPE_YOGA -> WorkoutType.YOGA
        ExerciseSessionRecord.EXERCISE_TYPE_WEIGHTLIFTING -> WorkoutType.STRENGTH_TRAINING
        ExerciseSessionRecord.EXERCISE_TYPE_HIGH_INTENSITY_INTERVAL_TRAINING -> WorkoutType.HIIT
        ExerciseSessionRecord.EXERCISE_TYPE_ELLIPTICAL -> WorkoutType.ELLIPTICAL
        ExerciseSessionRecord.EXERCISE_TYPE_ROWING_MACHINE -> WorkoutType.ROWING
        ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING_MACHINE,
        ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING -> WorkoutType.STAIR_CLIMBING
        ExerciseSessionRecord.EXERCISE_TYPE_PILATES -> WorkoutType.PILATES
        ExerciseSessionRecord.EXERCISE_TYPE_DANCING -> WorkoutType.DANCE
        ExerciseSessionRecord.EXERCISE_TYPE_TENNIS -> WorkoutType.TENNIS
        ExerciseSessionRecord.EXERCISE_TYPE_BADMINTON -> WorkoutType.BADMINTON
        ExerciseSessionRecord.EXERCISE_TYPE_TABLE_TENNIS -> WorkoutType.TABLE_TENNIS
        ExerciseSessionRecord.EXERCISE_TYPE_GOLF -> WorkoutType.GOLF
        ExerciseSessionRecord.EXERCISE_TYPE_SOCCER -> WorkoutType.SOCCER
        ExerciseSessionRecord.EXERCISE_TYPE_BASKETBALL -> WorkoutType.BASKETBALL
        ExerciseSessionRecord.EXERCISE_TYPE_BASEBALL -> WorkoutType.BASEBALL
        ExerciseSessionRecord.EXERCISE_TYPE_SOFTBALL -> WorkoutType.SOFTBALL
        ExerciseSessionRecord.EXERCISE_TYPE_VOLLEYBALL -> WorkoutType.VOLLEYBALL
        ExerciseSessionRecord.EXERCISE_TYPE_FOOTBALL_AMERICAN -> WorkoutType.AMERICAN_FOOTBALL
        ExerciseSessionRecord.EXERCISE_TYPE_RUGBY -> WorkoutType.RUGBY
        ExerciseSessionRecord.EXERCISE_TYPE_ICE_HOCKEY -> WorkoutType.HOCKEY
        ExerciseSessionRecord.EXERCISE_TYPE_ICE_SKATING -> WorkoutType.SKATING
        ExerciseSessionRecord.EXERCISE_TYPE_SKIING,
        ExerciseSessionRecord.EXERCISE_TYPE_SNOWBOARDING -> WorkoutType.SNOW_SPORTS
        ExerciseSessionRecord.EXERCISE_TYPE_SURFING,
        ExerciseSessionRecord.EXERCISE_TYPE_WATER_POLO -> WorkoutType.WATER_SPORTS
        ExerciseSessionRecord.EXERCISE_TYPE_MARTIAL_ARTS -> WorkoutType.MARTIAL_ARTS
        ExerciseSessionRecord.EXERCISE_TYPE_BOXING -> WorkoutType.BOXING
        ExerciseSessionRecord.EXERCISE_TYPE_ROCK_CLIMBING -> WorkoutType.CLIMBING
        ExerciseSessionRecord.EXERCISE_TYPE_STRETCHING -> WorkoutType.FLEXIBILITY
        else -> WorkoutType.OTHER
    }

    private fun List<Double>.averageOrNull(): Double? =
        if (isEmpty()) null else average()
}
