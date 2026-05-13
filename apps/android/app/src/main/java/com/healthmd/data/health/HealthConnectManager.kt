package com.healthmd.data.health

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.feature.ExperimentalMindfulnessSessionApi
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND
import androidx.health.connect.client.records.*
import androidx.health.connect.client.units.TemperatureDelta
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import com.healthmd.R
import com.healthmd.domain.model.*
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import com.healthmd.domain.model.BloodPressureSample
import com.healthmd.domain.model.SleepStageEntry
import com.healthmd.domain.model.TimestampedSample
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes

@OptIn(ExperimentalMindfulnessSessionApi::class)
class HealthConnectManager(private val context: Context) {

    private val healthConnectClient by lazy { HealthConnectClient.getOrCreate(context) }

    // All foreground Health Connect data permissions we request.
    val permissions = setOf(
        HealthPermission.getReadPermission(StepsRecord::class),
        HealthPermission.getReadPermission(HeartRateRecord::class),
        HealthPermission.getReadPermission(SleepSessionRecord::class),
        HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        HealthPermission.getReadPermission(DistanceRecord::class),
        HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
        HealthPermission.getReadPermission(TotalCaloriesBurnedRecord::class),
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
        HealthPermission.getReadPermission(ElevationGainedRecord::class),
        HealthPermission.getReadPermission(WheelchairPushesRecord::class),
        HealthPermission.getReadPermission(PowerRecord::class),
        HealthPermission.getReadPermission(BasalBodyTemperatureRecord::class),
        HealthPermission.getReadPermission(BodyWaterMassRecord::class),
        HealthPermission.getReadPermission(BoneMassRecord::class),
        HealthPermission.getReadPermission(SkinTemperatureRecord::class),
        HealthPermission.getReadPermission(CervicalMucusRecord::class),
        HealthPermission.getReadPermission(IntermenstrualBleedingRecord::class),
        HealthPermission.getReadPermission(MenstruationFlowRecord::class),
        HealthPermission.getReadPermission(MenstruationPeriodRecord::class),
        HealthPermission.getReadPermission(OvulationTestRecord::class),
        HealthPermission.getReadPermission(SexualActivityRecord::class),
        HealthPermission.getReadPermission(CyclingPedalingCadenceRecord::class),
        HealthPermission.getReadPermission(StepsCadenceRecord::class),
        HealthPermission.getReadPermission(MindfulnessSessionRecord::class),
    )

    // Additional access required for WorkManager-driven scheduled exports.
    val backgroundReadPermissions = setOf(PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)

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
     * Check if we have any health permissions granted.
     * We request many permissions but not all may be available on every device,
     * so we only require that at least one has been granted.
     */
    suspend fun hasAllPermissions(): Boolean {
        val granted = healthConnectClient.permissionController.getGrantedPermissions()
        return granted.any { it in permissions }
    }

    /**
     * Returns true when this Health Connect provider supports explicit background read access.
     */
    fun isBackgroundReadFeatureAvailable(): Boolean {
        if (!isAvailable()) return false
        return try {
            healthConnectClient.features.getFeatureStatus(
                HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND,
            ) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
        } catch (_: Exception) {
            false
        }
    }

    /**
     * Scheduled exports run from WorkManager, so Android 14+/newer Health Connect providers
     * require the dedicated background read permission in addition to data-type permissions.
     * If the provider does not expose the feature, there is no permission we can request.
     */
    suspend fun hasBackgroundReadPermission(): Boolean {
        if (!isBackgroundReadFeatureAvailable()) return true
        return try {
            PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND in healthConnectClient.permissionController.getGrantedPermissions()
        } catch (_: Exception) {
            false
        }
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
            HealthConnectClient.SDK_AVAILABLE -> context.getString(R.string.debug_sdk_status_available, status)
            HealthConnectClient.SDK_UNAVAILABLE -> context.getString(R.string.debug_sdk_status_unavailable, status)
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> context.getString(
                R.string.debug_sdk_status_update_required,
                status,
            )
            else -> context.getString(R.string.debug_sdk_status_unknown, status)
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
     * Returns true if the device is in the "Before First Unlock" (BFU) state —
     * i.e. the phone was rebooted and the user has not yet entered their PIN/password
     * for the first time. In this state the credential-encrypted (CE) storage is not
     * yet mounted, so Health Connect is inaccessible.
     *
     * NOTE: This is NOT the same as the screen being locked. Once the user unlocks
     * the device once after a reboot (AFU state), Health Connect remains accessible
     * even when the screen subsequently locks again.
     */
    fun isBeforeFirstUnlock(): Boolean {
        val um = context.getSystemService(Context.USER_SERVICE) as android.os.UserManager
        return !um.isUserUnlocked
    }

    /**
     * Fetch health data for a single date.
     * Throws [SecurityException] if Health Connect is inaccessible (e.g. device locked).
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
            val reproductiveDeferred = async { fetchReproductiveHealthData(timeRange) }
            val mindfulnessDeferred = async { fetchMindfulnessData(timeRange) }
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
                reproductiveHealth = reproductiveDeferred.await(),
                mindfulness = mindfulnessDeferred.await(),
                workouts = workoutsDeferred.await(),
            )
        }
    }

    // MARK: - Private fetch methods

    private suspend fun fetchSleepData(timeRange: TimeRangeFilter, date: LocalDate): SleepData {
        return try {
            val zone = ZoneId.systemDefault()
            val response = healthConnectClient.readRecords(
                ReadRecordsRequest(SleepSessionRecord::class, timeRange)
            )

            var totalMs = 0L
            var deepMs = 0L
            var remMs = 0L
            var lightMs = 0L
            var awakeMs = 0L
            val stageEntries = mutableListOf<SleepStageEntry>()

            for (session in response.records) {
                val sessionDurationMs = java.time.Duration.between(session.startTime, session.endTime).toMillis()
                totalMs += sessionDurationMs

                for (stage in session.stages) {
                    val stageMs = java.time.Duration.between(stage.startTime, stage.endTime).toMillis()
                    val stageName = when (stage.stage) {
                        SleepSessionRecord.STAGE_TYPE_DEEP -> { deepMs += stageMs; "deep" }
                        SleepSessionRecord.STAGE_TYPE_REM -> { remMs += stageMs; "rem" }
                        SleepSessionRecord.STAGE_TYPE_LIGHT -> { lightMs += stageMs; "light" }
                        SleepSessionRecord.STAGE_TYPE_AWAKE -> { awakeMs += stageMs; "awake" }
                        SleepSessionRecord.STAGE_TYPE_SLEEPING -> { lightMs += stageMs; "sleeping" }
                        else -> "unknown"
                    }
                    stageEntries.add(
                        SleepStageEntry(
                            startTime = LocalDateTime.ofInstant(stage.startTime, zone),
                            endTime = LocalDateTime.ofInstant(stage.endTime, zone),
                            stage = stageName,
                        )
                    )
                }
            }

            SleepData(
                totalDuration = totalMs.milliseconds,
                deepSleep = deepMs.milliseconds,
                remSleep = remMs.milliseconds,
                lightSleep = lightMs.milliseconds,
                awakeTime = awakeMs.milliseconds,
                inBedTime = totalMs.milliseconds, // approximate: total session time
                stages = stageEntries,
            )
        } catch (_: Exception) {
            SleepData()
        }
    }

    private suspend fun fetchActivityData(timeRange: TimeRangeFilter): ActivityData {
        return try {
            val zone = ZoneId.systemDefault()
            val aggregateResponse = healthConnectClient.aggregate(
                AggregateRequest(
                    metrics = setOf(
                        StepsRecord.COUNT_TOTAL,
                        ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL,
                        TotalCaloriesBurnedRecord.ENERGY_TOTAL,
                        FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL,
                        DistanceRecord.DISTANCE_TOTAL,
                        ElevationGainedRecord.ELEVATION_GAINED_TOTAL,
                        WheelchairPushesRecord.COUNT_TOTAL,
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

            // Per-interval step samples
            val stepsRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(StepsRecord::class, timeRange)
            )
            val stepSamples = stepsRecords.records.map { record ->
                TimestampedSample(
                    time = LocalDateTime.ofInstant(record.startTime, zone),
                    value = record.count.toDouble(),
                )
            }

            ActivityData(
                steps = aggregateResponse[StepsRecord.COUNT_TOTAL]?.toInt(),
                activeCalories = aggregateResponse[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories,
                totalCalories = aggregateResponse[TotalCaloriesBurnedRecord.ENERGY_TOTAL]?.inKilocalories,
                exerciseMinutes = if (exerciseMinutes > 0) exerciseMinutes else null,
                flightsClimbed = aggregateResponse[FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL]?.toInt(),
                walkingRunningDistance = aggregateResponse[DistanceRecord.DISTANCE_TOTAL]?.inMeters,
                basalEnergyBurned = basalEnergy,
                elevationGained = aggregateResponse[ElevationGainedRecord.ELEVATION_GAINED_TOTAL]?.inMeters,
                wheelchairPushes = aggregateResponse[WheelchairPushesRecord.COUNT_TOTAL]?.toInt(),
                stepSamples = stepSamples,
            )
        } catch (_: Exception) {
            ActivityData()
        }
    }

    private suspend fun fetchHeartData(timeRange: TimeRangeFilter): HeartData {
        return try {
            val zone = ZoneId.systemDefault()

            // Heart rate samples
            val hrRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(HeartRateRecord::class, timeRange)
            )
            val allBpm = mutableListOf<Double>()
            val hrSamples = mutableListOf<TimestampedSample>()
            for (record in hrRecords.records) {
                for (sample in record.samples) {
                    val bpm = sample.beatsPerMinute.toDouble()
                    allBpm.add(bpm)
                    hrSamples.add(
                        TimestampedSample(
                            time = LocalDateTime.ofInstant(sample.time, zone),
                            value = bpm,
                        )
                    )
                }
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
            val hrvSamples = hrvRecords.records.map { record ->
                TimestampedSample(
                    time = LocalDateTime.ofInstant(record.time, zone),
                    value = record.heartRateVariabilityMillis,
                )
            }

            HeartData(
                restingHeartRate = restingHr,
                averageHeartRate = if (allBpm.isNotEmpty()) allBpm.average() else null,
                hrv = hrv,
                heartRateMin = allBpm.minOrNull(),
                heartRateMax = allBpm.maxOrNull(),
                samples = hrSamples,
                hrvSamples = hrvSamples,
            )
        } catch (_: Exception) {
            HeartData()
        }
    }

    private suspend fun fetchVitalsData(timeRange: TimeRangeFilter): VitalsData {
        return try {
            val zone = ZoneId.systemDefault()

            // Respiratory rate
            val rrRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(RespiratoryRateRecord::class, timeRange)
            )
            val rrValues = rrRecords.records.map { it.rate }
            val rrSamples = rrRecords.records.map { record ->
                TimestampedSample(
                    time = LocalDateTime.ofInstant(record.time, zone),
                    value = record.rate,
                )
            }

            // Blood oxygen
            val o2Records = healthConnectClient.readRecords(
                ReadRecordsRequest(OxygenSaturationRecord::class, timeRange)
            )
            val o2Values = o2Records.records.map { it.percentage.value / 100.0 } // convert to 0-1
            val o2Samples = o2Records.records.map { record ->
                TimestampedSample(
                    time = LocalDateTime.ofInstant(record.time, zone),
                    value = record.percentage.value,
                )
            }

            // Body temperature
            val tempRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BodyTemperatureRecord::class, timeRange)
            )
            val tempValues = tempRecords.records.map { it.temperature.inCelsius }
            val tempSamples = tempRecords.records.map { record ->
                TimestampedSample(
                    time = LocalDateTime.ofInstant(record.time, zone),
                    value = record.temperature.inCelsius,
                )
            }

            // Blood pressure
            val bpRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BloodPressureRecord::class, timeRange)
            )
            val sysValues = bpRecords.records.map { it.systolic.inMillimetersOfMercury }
            val diaValues = bpRecords.records.map { it.diastolic.inMillimetersOfMercury }
            val bpSamples = bpRecords.records.map { record ->
                BloodPressureSample(
                    time = LocalDateTime.ofInstant(record.time, zone),
                    systolic = record.systolic.inMillimetersOfMercury,
                    diastolic = record.diastolic.inMillimetersOfMercury,
                )
            }

            // Blood glucose
            val bgRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BloodGlucoseRecord::class, timeRange)
            )
            val bgValues = bgRecords.records.map { it.level.inMilligramsPerDeciliter }
            val bgSamples = bgRecords.records.map { record ->
                TimestampedSample(
                    time = LocalDateTime.ofInstant(record.time, zone),
                    value = record.level.inMilligramsPerDeciliter,
                )
            }

            // Basal body temperature
            val bbtRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BasalBodyTemperatureRecord::class, timeRange)
            )
            val basalBodyTemp = bbtRecords.records.lastOrNull()?.temperature?.inCelsius

            // Skin temperature (using aggregate)
            val skinTempAggregate = healthConnectClient.aggregate(
                AggregateRequest(
                    metrics = setOf(SkinTemperatureRecord.TEMPERATURE_DELTA_AVG),
                    timeRangeFilter = timeRange,
                )
            )
            val skinTempDelta = skinTempAggregate[SkinTemperatureRecord.TEMPERATURE_DELTA_AVG]?.inCelsius

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
                basalBodyTemperature = basalBodyTemp,
                skinTemperatureDelta = skinTempDelta,
                bloodOxygenSamples = o2Samples,
                bloodPressureSamples = bpSamples,
                bloodGlucoseSamples = bgSamples,
                respiratoryRateSamples = rrSamples,
                bodyTemperatureSamples = tempSamples,
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

            val bodyWaterRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BodyWaterMassRecord::class, timeRange)
            )
            val bodyWaterMass = bodyWaterRecords.records.lastOrNull()?.mass?.inKilograms

            val boneMassRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BoneMassRecord::class, timeRange)
            )
            val boneMass = boneMassRecords.records.lastOrNull()?.mass?.inKilograms

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
                bodyWaterMass = bodyWaterMass,
                boneMass = boneMass,
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

            val cyclingCadenceRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(CyclingPedalingCadenceRecord::class, timeRange)
            )
            val cyclingCadence = cyclingCadenceRecords.records
                .flatMap { it.samples }
                .map { it.revolutionsPerMinute }
                .averageOrNull()

            val stepsCadenceRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(StepsCadenceRecord::class, timeRange)
            )
            val stepsCadence = stepsCadenceRecords.records
                .flatMap { it.samples }
                .map { it.rate }
                .averageOrNull()

            val powerRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(PowerRecord::class, timeRange)
            )
            val powerSamples = powerRecords.records.flatMap { it.samples }.map { it.power.inWatts }

            MobilityData(
                walkingSpeed = avgSpeed,
                vo2Max = vo2Max,
                cyclingCadenceAvg = cyclingCadence,
                stepsCadenceAvg = stepsCadence,
                powerAvg = powerSamples.averageOrNull(),
                powerMax = powerSamples.maxOrNull(),
            )
        } catch (_: Exception) {
            MobilityData()
        }
    }

    private suspend fun fetchReproductiveHealthData(timeRange: TimeRangeFilter): ReproductiveHealthData {
        return try {
            val menstruationRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(MenstruationFlowRecord::class, timeRange)
            )
            val menstrualFlow = menstruationRecords.records.lastOrNull()?.let { record ->
                when (record.flow) {
                    MenstruationFlowRecord.FLOW_LIGHT -> "light"
                    MenstruationFlowRecord.FLOW_MEDIUM -> "medium"
                    MenstruationFlowRecord.FLOW_HEAVY -> "heavy"
                    else -> null
                }
            }

            val cervicalMucusRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(CervicalMucusRecord::class, timeRange)
            )
            val cervicalMucus = cervicalMucusRecords.records.lastOrNull()
            val mucusAppearance = cervicalMucus?.let { record ->
                when (record.appearance) {
                    CervicalMucusRecord.APPEARANCE_DRY -> "dry"
                    CervicalMucusRecord.APPEARANCE_STICKY -> "sticky"
                    CervicalMucusRecord.APPEARANCE_CREAMY -> "creamy"
                    CervicalMucusRecord.APPEARANCE_WATERY -> "watery"
                    CervicalMucusRecord.APPEARANCE_EGG_WHITE -> "egg white"
                    else -> null
                }
            }
            val mucusSensation = cervicalMucus?.let { record ->
                when (record.sensation) {
                    CervicalMucusRecord.SENSATION_LIGHT -> "light"
                    CervicalMucusRecord.SENSATION_MEDIUM -> "medium"
                    CervicalMucusRecord.SENSATION_HEAVY -> "heavy"
                    else -> null
                }
            }

            val ovulationRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(OvulationTestRecord::class, timeRange)
            )
            val ovulationResult = ovulationRecords.records.lastOrNull()?.let { record ->
                when (record.result) {
                    OvulationTestRecord.RESULT_POSITIVE -> "positive"
                    OvulationTestRecord.RESULT_HIGH -> "high"
                    OvulationTestRecord.RESULT_NEGATIVE -> "negative"
                    OvulationTestRecord.RESULT_INCONCLUSIVE -> "inconclusive"
                    else -> null
                }
            }

            val intermenstrualRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(IntermenstrualBleedingRecord::class, timeRange)
            )
            val hasIntermenstrualBleeding = intermenstrualRecords.records.isNotEmpty()

            val sexualActivityRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(SexualActivityRecord::class, timeRange)
            )
            val sexualActivity = sexualActivityRecords.records.lastOrNull()
            val protectionUsed = sexualActivity?.let { record ->
                when (record.protectionUsed) {
                    SexualActivityRecord.PROTECTION_USED_PROTECTED -> "protected"
                    SexualActivityRecord.PROTECTION_USED_UNPROTECTED -> "unprotected"
                    else -> null
                }
            }

            ReproductiveHealthData(
                menstrualFlow = menstrualFlow,
                cervicalMucusAppearance = mucusAppearance,
                cervicalMucusSensation = mucusSensation,
                ovulationTestResult = ovulationResult,
                intermenstrualBleeding = hasIntermenstrualBleeding,
                sexualActivityRecorded = sexualActivity != null,
                sexualActivityProtectionUsed = protectionUsed,
            )
        } catch (_: Exception) {
            ReproductiveHealthData()
        }
    }

    private suspend fun fetchMindfulnessData(timeRange: TimeRangeFilter): MindfulnessData {
        return try {
            val records = healthConnectClient.readRecords(
                ReadRecordsRequest(MindfulnessSessionRecord::class, timeRange)
            )
            val totalMinutes = records.records.sumOf { session ->
                java.time.Duration.between(session.startTime, session.endTime).toMinutes().toDouble()
            }
            MindfulnessData(
                mindfulnessMinutes = if (totalMinutes > 0) totalMinutes else null,
            )
        } catch (_: Exception) {
            MindfulnessData()
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
