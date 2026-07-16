package com.healthmd.data.health

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.feature.ExperimentalPersonalHealthRecordApi
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_HISTORY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_ALLERGIES_INTOLERANCES
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_CONDITIONS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_LABORATORY_RESULTS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_MEDICATIONS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PERSONAL_DETAILS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PRACTITIONER_DETAILS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PREGNANCY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_PROCEDURES
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_SOCIAL_HISTORY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_VACCINES
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_VISITS
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_MEDICAL_DATA_VITAL_SIGNS
import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadMedicalResourcesInitialRequest
import androidx.health.connect.client.request.ReadMedicalResourcesPageRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.units.TemperatureDelta
import androidx.health.connect.client.time.TimeRangeFilter
import com.healthmd.R
import com.healthmd.data.isHealthConnectRateLimit
import com.healthmd.domain.model.*
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import com.healthmd.domain.model.BloodPressureSample
import com.healthmd.domain.model.SleepStageEntry
import com.healthmd.domain.model.TimestampedSample
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.Period
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.reflect.KClass
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.minutes

@OptIn(ExperimentalPersonalHealthRecordApi::class)
class HealthConnectManager(
    private val context: Context,
    sharedClient: HealthConnectClient? = null,
) {
    private val healthConnectClient by lazy { sharedClient ?: HealthConnectClient.getOrCreate(context) }

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
        HealthPermission.getReadPermission(PlannedExerciseSessionRecord::class),
        HealthPermission.getReadPermission(ActivityIntensityRecord::class),
        PERMISSION_READ_MEDICAL_DATA_ALLERGIES_INTOLERANCES,
        PERMISSION_READ_MEDICAL_DATA_CONDITIONS,
        PERMISSION_READ_MEDICAL_DATA_LABORATORY_RESULTS,
        PERMISSION_READ_MEDICAL_DATA_MEDICATIONS,
        PERMISSION_READ_MEDICAL_DATA_PERSONAL_DETAILS,
        PERMISSION_READ_MEDICAL_DATA_PRACTITIONER_DETAILS,
        PERMISSION_READ_MEDICAL_DATA_PREGNANCY,
        PERMISSION_READ_MEDICAL_DATA_PROCEDURES,
        PERMISSION_READ_MEDICAL_DATA_SOCIAL_HISTORY,
        PERMISSION_READ_MEDICAL_DATA_VACCINES,
        PERMISSION_READ_MEDICAL_DATA_VISITS,
        PERMISSION_READ_MEDICAL_DATA_VITAL_SIGNS,
    )

    // Additional access required for WorkManager-driven scheduled exports.
    val backgroundReadPermissions = setOf(PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)

    // Additional access required for manual exports that include data older than 30 days.
    val historicalReadPermissions = setOf(PERMISSION_READ_HEALTH_DATA_HISTORY)

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
        return isFeatureAvailable(HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND)
    }

    private fun isFeatureAvailable(feature: Int): Boolean = try {
        healthConnectClient.features.getFeatureStatus(feature) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
    } catch (_: Exception) {
        false
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
     * Large manual exports can include days outside Health Connect's default
     * 30-day historical window, so they need the dedicated history permission.
     */
    suspend fun hasHistoricalReadPermission(): Boolean = try {
        PERMISSION_READ_HEALTH_DATA_HISTORY in healthConnectClient.permissionController.getGrantedPermissions()
    } catch (_: Exception) {
        false
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
            val plannedWorkoutsDeferred = async { fetchPlannedWorkouts(timeRange) }
            val medicalResourcesDeferred = async { fetchMedicalResources() }

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
                plannedWorkouts = plannedWorkoutsDeferred.await(),
                medicalResources = medicalResourcesDeferred.await(),
            )
        }
    }

    /**
     * Fetches a multi-day export window with Health Connect range APIs.
     *
     * The goal is to keep 30/90/all-time exports away from the old N days x N categories
     * call pattern. Aggregatable metrics are read as daily period groups; high-cardinality
     * records are read once per chunk with pagination and then grouped into [HealthData].
     */
    suspend fun fetchHealthDataRange(
        dates: List<LocalDate>,
        selection: DataTypeSelection,
        includeGranularData: Boolean,
    ): List<HealthData> {
        if (dates.isEmpty()) return emptyList()

        val requestedDates = dates.toSet()
        val dataByDate = dates.associateWith { HealthData(it) }.toMutableMap()
        val sortedDates = requestedDates.sorted()
        val chunkDays = if (includeGranularData) GRANULAR_READ_CHUNK_DAYS else RANGE_READ_CHUNK_DAYS

        for (chunk in sortedDates.chunked(chunkDays)) {
            val startDate = chunk.first()
            val endExclusive = chunk.last().plusDays(1)
            val localRange = TimeRangeFilter.between(
                startDate.atStartOfDay(),
                endExclusive.atStartOfDay(),
            )
            val instantRange = TimeRangeFilter.between(
                startDate.atStartOfDay(ZoneId.systemDefault()).toInstant(),
                endExclusive.atStartOfDay(ZoneId.systemDefault()).toInstant(),
            )
            val chunkDates = chunk.toSet()

            applyActivityAggregates(dataByDate, chunkDates, localRange, selection)
            applyHeartAggregates(dataByDate, chunkDates, localRange, selection)
            applyVitalsAggregates(dataByDate, chunkDates, localRange, selection)
            applyBodyAggregates(dataByDate, chunkDates, localRange, selection)
            applyNutritionAggregates(dataByDate, chunkDates, localRange, selection)
            applyMobilityAggregates(dataByDate, chunkDates, localRange, selection)

            if (selection.sleep) {
                applySleepRange(dataByDate, chunkDates, instantRange, includeGranularData)
            }
            if (selection.activity || selection.workouts || selection.heart || selection.mobility) {
                applyExerciseRange(dataByDate, chunkDates, instantRange, selection, includeGranularData)
            }
            if (selection.activity && includeGranularData) {
                applyStepSamplesRange(dataByDate, chunkDates, instantRange)
                applyActivityIntensityRange(dataByDate, chunkDates, instantRange)
            }
            if (selection.heart) {
                applyHeartRangeReads(dataByDate, chunkDates, instantRange, includeGranularData)
            }
            if (selection.vitals) {
                applyVitalsRangeReads(dataByDate, chunkDates, instantRange, includeGranularData)
            }
            if (selection.body) {
                applyBodyRangeReads(dataByDate, chunkDates, instantRange)
            }
            if (selection.nutrition && includeGranularData) {
                applyNutritionMealRange(dataByDate, chunkDates, instantRange)
            }
            if (selection.reproductiveHealth) {
                applyReproductiveRangeReads(dataByDate, chunkDates, instantRange)
            }
            if (selection.mindfulness) {
                applyMindfulnessRange(dataByDate, chunkDates, instantRange)
            }
            if (selection.plannedWorkouts) {
                applyPlannedWorkoutRange(dataByDate, chunkDates, instantRange)
            }
            if (selection.medicalResources) {
                val medicalResources = fetchMedicalResources()
                if (medicalResources.hasData) {
                    for (date in chunkDates) {
                        dataByDate.update(date) { current -> current.copy(medicalResources = medicalResources) }
                    }
                }
            }
            if (selection.mobility) {
                applyMobilityRangeReads(dataByDate, chunkDates, instantRange)
            }
        }

        return dates.map { date -> dataByDate[date]?.filtered(selection) ?: HealthData(date) }
    }

    // MARK: - Private fetch methods

    private suspend fun applyActivityAggregates(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        selection: DataTypeSelection,
    ) {
        if (!selection.activity) return

        val metrics = buildSet<AggregateMetric<*>> {
            add(StepsRecord.COUNT_TOTAL)
            add(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
            add(TotalCaloriesBurnedRecord.ENERGY_TOTAL)
            add(BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL)
            add(FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL)
            add(DistanceRecord.DISTANCE_TOTAL)
            add(ElevationGainedRecord.ELEVATION_GAINED_TOTAL)
            add(WheelchairPushesRecord.COUNT_TOTAL)
            if (isFeatureAvailable(HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY)) {
                add(ActivityIntensityRecord.MODERATE_DURATION_TOTAL)
                add(ActivityIntensityRecord.VIGOROUS_DURATION_TOTAL)
                add(ActivityIntensityRecord.INTENSITY_MINUTES_TOTAL)
            }
        }

        for ((date, result) in aggregateByDay(metrics, timeRange, requestedDates)) {
            dataByDate.update(date) { current ->
                current.copy(
                    activity = current.activity.copy(
                        steps = result[StepsRecord.COUNT_TOTAL]?.toInt(),
                        activeCalories = result[ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL]?.inKilocalories,
                        totalCalories = result[TotalCaloriesBurnedRecord.ENERGY_TOTAL]?.inKilocalories,
                        basalEnergyBurned = result[BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL]?.inKilocalories,
                        flightsClimbed = result[FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL]?.toInt(),
                        walkingRunningDistance = result[DistanceRecord.DISTANCE_TOTAL]?.inMeters,
                        elevationGained = result[ElevationGainedRecord.ELEVATION_GAINED_TOTAL]?.inMeters,
                        wheelchairPushes = result[WheelchairPushesRecord.COUNT_TOTAL]?.toInt(),
                        moderateActivityMinutes = (result[ActivityIntensityRecord.MODERATE_DURATION_TOTAL] as? java.time.Duration)?.toMinutes()?.toDouble(),
                        vigorousActivityMinutes = (result[ActivityIntensityRecord.VIGOROUS_DURATION_TOTAL] as? java.time.Duration)?.toMinutes()?.toDouble(),
                        activityIntensityMinutes = (result[ActivityIntensityRecord.INTENSITY_MINUTES_TOTAL] as? java.time.Duration)?.toMinutes()?.toInt(),
                    )
                )
            }
        }
    }

    private suspend fun applyHeartAggregates(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        selection: DataTypeSelection,
    ) {
        if (!selection.heart) return

        val metrics = setOf<AggregateMetric<*>>(
            HeartRateRecord.BPM_AVG,
            HeartRateRecord.BPM_MIN,
            HeartRateRecord.BPM_MAX,
            RestingHeartRateRecord.BPM_AVG,
        )

        for ((date, result) in aggregateByDay(metrics, timeRange, requestedDates)) {
            dataByDate.update(date) { current ->
                current.copy(
                    heart = current.heart.copy(
                        restingHeartRate = result[RestingHeartRateRecord.BPM_AVG]?.toDouble(),
                        averageHeartRate = result[HeartRateRecord.BPM_AVG]?.toDouble(),
                        heartRateMin = result[HeartRateRecord.BPM_MIN]?.toDouble(),
                        heartRateMax = result[HeartRateRecord.BPM_MAX]?.toDouble(),
                    )
                )
            }
        }
    }

    private suspend fun applyVitalsAggregates(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        selection: DataTypeSelection,
    ) {
        if (!selection.vitals) return

        val metrics = setOf<AggregateMetric<*>>(
            BloodPressureRecord.SYSTOLIC_AVG,
            BloodPressureRecord.SYSTOLIC_MIN,
            BloodPressureRecord.SYSTOLIC_MAX,
            BloodPressureRecord.DIASTOLIC_AVG,
            BloodPressureRecord.DIASTOLIC_MIN,
            BloodPressureRecord.DIASTOLIC_MAX,
            SkinTemperatureRecord.TEMPERATURE_DELTA_AVG,
        )

        for ((date, result) in aggregateByDay(metrics, timeRange, requestedDates)) {
            dataByDate.update(date) { current ->
                current.copy(
                    vitals = current.vitals.copy(
                        bloodPressureSystolicAvg = result[BloodPressureRecord.SYSTOLIC_AVG]?.inMillimetersOfMercury,
                        bloodPressureSystolicMin = result[BloodPressureRecord.SYSTOLIC_MIN]?.inMillimetersOfMercury,
                        bloodPressureSystolicMax = result[BloodPressureRecord.SYSTOLIC_MAX]?.inMillimetersOfMercury,
                        bloodPressureDiastolicAvg = result[BloodPressureRecord.DIASTOLIC_AVG]?.inMillimetersOfMercury,
                        bloodPressureDiastolicMin = result[BloodPressureRecord.DIASTOLIC_MIN]?.inMillimetersOfMercury,
                        bloodPressureDiastolicMax = result[BloodPressureRecord.DIASTOLIC_MAX]?.inMillimetersOfMercury,
                        skinTemperatureDelta = result[SkinTemperatureRecord.TEMPERATURE_DELTA_AVG]?.inCelsius,
                    )
                )
            }
        }
    }

    private suspend fun applyBodyAggregates(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        selection: DataTypeSelection,
    ) {
        if (!selection.body) return

        val metrics = setOf<AggregateMetric<*>>(
            WeightRecord.WEIGHT_AVG,
            HeightRecord.HEIGHT_AVG,
        )

        for ((date, result) in aggregateByDay(metrics, timeRange, requestedDates)) {
            val weight = result[WeightRecord.WEIGHT_AVG]?.inKilograms
            val height = result[HeightRecord.HEIGHT_AVG]?.inMeters
            dataByDate.update(date) { current ->
                current.copy(
                    body = current.body.copy(
                        weight = weight,
                        height = height,
                        bmi = if (weight != null && height != null && height > 0) {
                            weight / (height * height)
                        } else {
                            current.body.bmi
                        },
                    )
                )
            }
        }
    }

    private suspend fun applyNutritionAggregates(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        selection: DataTypeSelection,
    ) {
        if (!selection.nutrition) return

        val metrics = setOf<AggregateMetric<*>>(
            NutritionRecord.ENERGY_TOTAL,
            NutritionRecord.ENERGY_FROM_FAT_TOTAL,
            NutritionRecord.PROTEIN_TOTAL,
            NutritionRecord.TOTAL_CARBOHYDRATE_TOTAL,
            NutritionRecord.TOTAL_FAT_TOTAL,
            NutritionRecord.DIETARY_FIBER_TOTAL,
            NutritionRecord.SUGAR_TOTAL,
            NutritionRecord.SODIUM_TOTAL,
            NutritionRecord.CAFFEINE_TOTAL,
            NutritionRecord.CHOLESTEROL_TOTAL,
            NutritionRecord.SATURATED_FAT_TOTAL,
            NutritionRecord.MONOUNSATURATED_FAT_TOTAL,
            NutritionRecord.POLYUNSATURATED_FAT_TOTAL,
            NutritionRecord.UNSATURATED_FAT_TOTAL,
            NutritionRecord.TRANS_FAT_TOTAL,
            NutritionRecord.POTASSIUM_TOTAL,
            NutritionRecord.CALCIUM_TOTAL,
            NutritionRecord.IRON_TOTAL,
            NutritionRecord.MAGNESIUM_TOTAL,
            NutritionRecord.ZINC_TOTAL,
            NutritionRecord.PHOSPHORUS_TOTAL,
            NutritionRecord.IODINE_TOTAL,
            NutritionRecord.SELENIUM_TOTAL,
            NutritionRecord.COPPER_TOTAL,
            NutritionRecord.MANGANESE_TOTAL,
            NutritionRecord.CHROMIUM_TOTAL,
            NutritionRecord.MOLYBDENUM_TOTAL,
            NutritionRecord.CHLORIDE_TOTAL,
            NutritionRecord.VITAMIN_A_TOTAL,
            NutritionRecord.VITAMIN_B6_TOTAL,
            NutritionRecord.VITAMIN_B12_TOTAL,
            NutritionRecord.VITAMIN_C_TOTAL,
            NutritionRecord.VITAMIN_D_TOTAL,
            NutritionRecord.VITAMIN_E_TOTAL,
            NutritionRecord.VITAMIN_K_TOTAL,
            NutritionRecord.THIAMIN_TOTAL,
            NutritionRecord.RIBOFLAVIN_TOTAL,
            NutritionRecord.NIACIN_TOTAL,
            NutritionRecord.FOLATE_TOTAL,
            NutritionRecord.FOLIC_ACID_TOTAL,
            NutritionRecord.PANTOTHENIC_ACID_TOTAL,
            NutritionRecord.BIOTIN_TOTAL,
            HydrationRecord.VOLUME_TOTAL,
        )

        for ((date, result) in aggregateByDay(metrics, timeRange, requestedDates)) {
            dataByDate.update(date) { current ->
                current.copy(
                    nutrition = current.nutrition.copy(
                        dietaryEnergy = result[NutritionRecord.ENERGY_TOTAL]?.inKilocalories,
                        energyFromFat = result[NutritionRecord.ENERGY_FROM_FAT_TOTAL]?.inKilocalories,
                        protein = result[NutritionRecord.PROTEIN_TOTAL]?.inGrams,
                        carbohydrates = result[NutritionRecord.TOTAL_CARBOHYDRATE_TOTAL]?.inGrams,
                        fat = result[NutritionRecord.TOTAL_FAT_TOTAL]?.inGrams,
                        fiber = result[NutritionRecord.DIETARY_FIBER_TOTAL]?.inGrams,
                        sugar = result[NutritionRecord.SUGAR_TOTAL]?.inGrams,
                        sodium = result[NutritionRecord.SODIUM_TOTAL]?.inGrams?.times(1000),
                        water = result[HydrationRecord.VOLUME_TOTAL]?.inLiters,
                        caffeine = result[NutritionRecord.CAFFEINE_TOTAL]?.inGrams?.times(1000),
                        cholesterol = result[NutritionRecord.CHOLESTEROL_TOTAL]?.inGrams?.times(1000),
                        saturatedFat = result[NutritionRecord.SATURATED_FAT_TOTAL]?.inGrams,
                        monounsaturatedFat = result[NutritionRecord.MONOUNSATURATED_FAT_TOTAL]?.inGrams,
                        polyunsaturatedFat = result[NutritionRecord.POLYUNSATURATED_FAT_TOTAL]?.inGrams,
                        unsaturatedFat = result[NutritionRecord.UNSATURATED_FAT_TOTAL]?.inGrams,
                        transFat = result[NutritionRecord.TRANS_FAT_TOTAL]?.inGrams,
                        potassium = result[NutritionRecord.POTASSIUM_TOTAL]?.inGrams?.times(1000),
                        calcium = result[NutritionRecord.CALCIUM_TOTAL]?.inGrams?.times(1000),
                        iron = result[NutritionRecord.IRON_TOTAL]?.inGrams?.times(1000),
                        magnesium = result[NutritionRecord.MAGNESIUM_TOTAL]?.inGrams?.times(1000),
                        zinc = result[NutritionRecord.ZINC_TOTAL]?.inGrams?.times(1000),
                        phosphorus = result[NutritionRecord.PHOSPHORUS_TOTAL]?.inGrams?.times(1000),
                        iodine = result[NutritionRecord.IODINE_TOTAL]?.inGrams?.times(1_000_000),
                        selenium = result[NutritionRecord.SELENIUM_TOTAL]?.inGrams?.times(1_000_000),
                        copper = result[NutritionRecord.COPPER_TOTAL]?.inGrams?.times(1000),
                        manganese = result[NutritionRecord.MANGANESE_TOTAL]?.inGrams?.times(1000),
                        chromium = result[NutritionRecord.CHROMIUM_TOTAL]?.inGrams?.times(1_000_000),
                        molybdenum = result[NutritionRecord.MOLYBDENUM_TOTAL]?.inGrams?.times(1_000_000),
                        chloride = result[NutritionRecord.CHLORIDE_TOTAL]?.inGrams?.times(1000),
                        vitaminA = result[NutritionRecord.VITAMIN_A_TOTAL]?.inGrams?.times(1_000_000),
                        vitaminB6 = result[NutritionRecord.VITAMIN_B6_TOTAL]?.inGrams?.times(1000),
                        vitaminB12 = result[NutritionRecord.VITAMIN_B12_TOTAL]?.inGrams?.times(1_000_000),
                        vitaminC = result[NutritionRecord.VITAMIN_C_TOTAL]?.inGrams?.times(1000),
                        vitaminD = result[NutritionRecord.VITAMIN_D_TOTAL]?.inGrams?.times(1_000_000),
                        vitaminE = result[NutritionRecord.VITAMIN_E_TOTAL]?.inGrams?.times(1000),
                        vitaminK = result[NutritionRecord.VITAMIN_K_TOTAL]?.inGrams?.times(1_000_000),
                        thiamin = result[NutritionRecord.THIAMIN_TOTAL]?.inGrams?.times(1000),
                        riboflavin = result[NutritionRecord.RIBOFLAVIN_TOTAL]?.inGrams?.times(1000),
                        niacin = result[NutritionRecord.NIACIN_TOTAL]?.inGrams?.times(1000),
                        folate = result[NutritionRecord.FOLATE_TOTAL]?.inGrams?.times(1_000_000),
                        folicAcid = result[NutritionRecord.FOLIC_ACID_TOTAL]?.inGrams?.times(1_000_000),
                        pantothenicAcid = result[NutritionRecord.PANTOTHENIC_ACID_TOTAL]?.inGrams?.times(1000),
                        biotin = result[NutritionRecord.BIOTIN_TOTAL]?.inGrams?.times(1_000_000),
                    )
                )
            }
        }
    }

    private suspend fun applyMobilityAggregates(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        selection: DataTypeSelection,
    ) {
        if (!selection.mobility) return

        val metrics = setOf<AggregateMetric<*>>(
            SpeedRecord.SPEED_AVG,
            CyclingPedalingCadenceRecord.RPM_AVG,
            CyclingPedalingCadenceRecord.RPM_MAX,
            StepsCadenceRecord.RATE_AVG,
            StepsCadenceRecord.RATE_MAX,
            PowerRecord.POWER_AVG,
            PowerRecord.POWER_MAX,
        )

        for ((date, result) in aggregateByDay(metrics, timeRange, requestedDates)) {
            dataByDate.update(date) { current ->
                current.copy(
                    mobility = current.mobility.copy(
                        walkingSpeed = result[SpeedRecord.SPEED_AVG]?.inMetersPerSecond,
                        cyclingCadenceAvg = result[CyclingPedalingCadenceRecord.RPM_AVG],
                        cyclingCadenceMax = result[CyclingPedalingCadenceRecord.RPM_MAX],
                        stepsCadenceAvg = result[StepsCadenceRecord.RATE_AVG],
                        stepsCadenceMax = result[StepsCadenceRecord.RATE_MAX],
                        powerAvg = result[PowerRecord.POWER_AVG]?.inWatts,
                        powerMax = result[PowerRecord.POWER_MAX]?.inWatts,
                    )
                )
            }
        }
    }

    private suspend fun applySleepRange(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        includeGranularData: Boolean,
    ) {
        val zone = ZoneId.systemDefault()
        val records = readRecordsOrEmpty(SleepSessionRecord::class, timeRange)
        val sleepByDate = mutableMapOf<LocalDate, SleepAccumulator>()

        for (session in records) {
            val date = session.endTime.atZone(zone).toLocalDate()
            if (date !in requestedDates) continue

            val accumulator = sleepByDate.getOrPut(date) { SleepAccumulator() }
            val sessionStart = LocalDateTime.ofInstant(session.startTime, zone)
            val sessionEnd = LocalDateTime.ofInstant(session.endTime, zone)
            accumulator.totalMs += java.time.Duration.between(session.startTime, session.endTime).toMillis()
            accumulator.sessionStart = listOfNotNull(accumulator.sessionStart, sessionStart).minOrNull()
            accumulator.sessionEnd = listOfNotNull(accumulator.sessionEnd, sessionEnd).maxOrNull()
            accumulator.sessions += SleepSessionEntry(
                startTime = sessionStart,
                endTime = sessionEnd,
                title = session.title?.takeIf { it.isNotBlank() },
                notes = session.notes?.takeIf { it.isNotBlank() },
                source = session.metadata.dataOrigin.packageName,
                metadata = session.metadata.toExportMetadata(),
                exactStartTime = session.startTime.toExactSourceTimestamp(session.startZoneOffset),
                exactEndTime = session.endTime.toExactSourceTimestamp(session.endZoneOffset),
                identity = session.metadata.toExactSourceIdentity("sleep_session", session.startTime, session.endTime),
            )

            for (stage in session.stages) {
                val stageMs = java.time.Duration.between(stage.startTime, stage.endTime).toMillis()
                val stageName = when (stage.stage) {
                    SleepSessionRecord.STAGE_TYPE_DEEP -> {
                        accumulator.deepMs += stageMs
                        "deep"
                    }
                    SleepSessionRecord.STAGE_TYPE_REM -> {
                        accumulator.remMs += stageMs
                        "rem"
                    }
                    SleepSessionRecord.STAGE_TYPE_LIGHT -> {
                        accumulator.lightMs += stageMs
                        "light"
                    }
                    SleepSessionRecord.STAGE_TYPE_AWAKE -> {
                        accumulator.awakeMs += stageMs
                        "awake"
                    }
                    SleepSessionRecord.STAGE_TYPE_SLEEPING -> {
                        accumulator.lightMs += stageMs
                        "sleeping"
                    }
                    else -> "unknown"
                }
                if (includeGranularData) {
                    accumulator.stages += SleepStageEntry(
                        startTime = LocalDateTime.ofInstant(stage.startTime, zone),
                        endTime = LocalDateTime.ofInstant(stage.endTime, zone),
                        stage = stageName,
                        exactStartTime = stage.startTime.toExactSourceTimestamp(),
                        exactEndTime = stage.endTime.toExactSourceTimestamp(),
                        identity = session.metadata.toSyntheticChildIdentity("sleep_stage", session.metadata.id, stage.startTime, stage.endTime, stage.stage),
                    )
                }
            }
        }

        for ((date, accumulator) in sleepByDate) {
            dataByDate.update(date) { current ->
                current.copy(
                    sleep = SleepData(
                        totalDuration = accumulator.totalMs.milliseconds,
                        deepSleep = accumulator.deepMs.milliseconds,
                        remSleep = accumulator.remMs.milliseconds,
                        lightSleep = accumulator.lightMs.milliseconds,
                        awakeTime = accumulator.awakeMs.milliseconds,
                        inBedTime = accumulator.totalMs.milliseconds,
                        stages = accumulator.stages.sortedBy { it.startTime },
                        sessions = accumulator.sessions.sortedBy { it.startTime },
                        sessionStart = accumulator.sessionStart,
                        sessionEnd = accumulator.sessionEnd,
                    )
                )
            }
        }
    }

    private suspend fun applyExerciseRange(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        selection: DataTypeSelection,
        includeGranularData: Boolean,
    ) {
        val zone = ZoneId.systemDefault()
        val sessionsByDate = readRecordsOrEmpty(ExerciseSessionRecord::class, timeRange)
            .groupBy { it.startTime.atZone(zone).toLocalDate() }
        if (sessionsByDate.isEmpty()) return

        val sources = WorkoutSourceRecords(
            distanceRecords = readRecordsOrEmpty(DistanceRecord::class, timeRange),
            calorieRecords = readRecordsOrEmpty(ActiveCaloriesBurnedRecord::class, timeRange),
            heartRateRecords = if (selection.workouts || selection.heart) readRecordsOrEmpty(HeartRateRecord::class, timeRange) else emptyList(),
            speedRecords = if (selection.workouts || selection.mobility) readRecordsOrEmpty(SpeedRecord::class, timeRange) else emptyList(),
            cyclingCadenceRecords = if (selection.workouts || selection.mobility) readRecordsOrEmpty(CyclingPedalingCadenceRecord::class, timeRange) else emptyList(),
            stepsCadenceRecords = if (selection.workouts || selection.mobility) readRecordsOrEmpty(StepsCadenceRecord::class, timeRange) else emptyList(),
            powerRecords = if (selection.workouts || selection.mobility) readRecordsOrEmpty(PowerRecord::class, timeRange) else emptyList(),
            elevationRecords = readRecordsOrEmpty(ElevationGainedRecord::class, timeRange),
        )

        for ((date, sessions) in sessionsByDate) {
            if (date !in requestedDates) continue

            val workouts = sessions.map { buildWorkoutData(it, zone, sources, includeGranularData) }
            val minutes = sessions.sumOf {
                java.time.Duration.between(it.startTime, it.endTime).toMinutes().toDouble()
            }
            val swimmingWorkouts = workouts.filter { it.workoutType == WorkoutType.SWIMMING }
            val wheelchairWorkouts = workouts.filter { it.workoutType == WorkoutType.WHEELCHAIR }
            val snowWorkouts = workouts.filter { it.workoutType == WorkoutType.SNOW_SPORTS }
            val walkingHrValues = workouts
                .filter { it.workoutType == WorkoutType.WALKING }
                .mapNotNull { it.averageHeartRate }
            val runningWorkouts = workouts.filter { it.workoutType == WorkoutType.RUNNING }
            val runningSpeedValues = runningWorkouts.mapNotNull { it.averageSpeed }
            val runningPowerValues = runningWorkouts.mapNotNull { it.powerAvg }

            dataByDate.update(date) { current ->
                current.copy(
                    activity = if (selection.activity) {
                        current.activity.copy(
                            exerciseMinutes = if (minutes > 0) minutes else current.activity.exerciseMinutes,
                            swimmingDistance = swimmingWorkouts.mapNotNull { it.distance }.sumPositiveOrNull(),
                            swimmingStrokes = swimmingWorkouts.flatMap { it.segments }.mapNotNull { it.repetitions }.sum().takeIf { it > 0 },
                            wheelchairDistance = wheelchairWorkouts.mapNotNull { it.distance }.sumPositiveOrNull(),
                            downhillSnowSportsDistance = snowWorkouts.mapNotNull { it.distance }.sumPositiveOrNull(),
                        )
                    } else {
                        current.activity
                    },
                    heart = if (selection.heart && walkingHrValues.isNotEmpty()) {
                        current.heart.copy(walkingHeartRateAverage = walkingHrValues.average())
                    } else {
                        current.heart
                    },
                    mobility = if (selection.mobility) {
                        current.mobility.copy(
                            runningSpeed = runningSpeedValues.averageOrNull(),
                            runningPowerAvg = runningPowerValues.averageOrNull(),
                            runningPowerMax = runningPowerValues.maxOrNull(),
                        )
                    } else {
                        current.mobility
                    },
                    workouts = if (selection.workouts) workouts else current.workouts,
                )
            }
        }
    }

    private suspend fun applyStepSamplesRange(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
    ) {
        val zone = ZoneId.systemDefault()
        val samplesByDate = readRecordsOrEmpty(StepsRecord::class, timeRange)
            .groupBy { it.startTime.atZone(zone).toLocalDate() }
            .mapValues { (_, records) ->
                records.map {
                    TimestampedSample(
                        time = LocalDateTime.ofInstant(it.startTime, zone),
                        value = it.count.toDouble(),
                        source = it.metadata.dataOrigin.packageName,
                        metadata = it.metadata.toExportMetadata(),
                        exactTime = it.startTime.toExactSourceTimestamp(it.startZoneOffset),
                        exactEndTime = it.endTime.toExactSourceTimestamp(it.endZoneOffset),
                        identity = it.metadata.toExactSourceIdentity("steps", it.startTime, it.endTime, it.count),
                    )
                }.sortedBy { it.time }
            }

        for ((date, samples) in samplesByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.copy(activity = current.activity.copy(stepSamples = samples))
            }
        }
    }

    private suspend fun applyActivityIntensityRange(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
    ) {
        if (!isFeatureAvailable(HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY)) return
        val zone = ZoneId.systemDefault()
        val entriesByDate = readRecordsOrEmpty(ActivityIntensityRecord::class, timeRange)
            .groupBy { it.startTime.atZone(zone).toLocalDate() }
            .mapValues { (_, records) ->
                records.map { record ->
                    ActivityIntensityEntry(
                        startTime = LocalDateTime.ofInstant(record.startTime, zone),
                        endTime = LocalDateTime.ofInstant(record.endTime, zone),
                        duration = java.time.Duration.between(record.startTime, record.endTime).toMillis().milliseconds,
                        intensity = mapActivityIntensity(record.activityIntensityType),
                        source = record.metadata.dataOrigin.packageName,
                        metadata = record.metadata.toExportMetadata(),
                        exactStartTime = record.startTime.toExactSourceTimestamp(record.startZoneOffset),
                        exactEndTime = record.endTime.toExactSourceTimestamp(record.endZoneOffset),
                        identity = record.metadata.toExactSourceIdentity("activity_intensity", record.startTime, record.endTime),
                    )
                }.sortedBy { it.startTime }
            }

        for ((date, entries) in entriesByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.withRangeCompatibilityEntries(activityIntensityEntries = entries)
            }
        }
    }

    private suspend fun applyNutritionMealRange(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
    ) {
        val zone = ZoneId.systemDefault()
        val mealsByDate = readRecordsOrEmpty(NutritionRecord::class, timeRange)
            .groupBy { it.startTime.atZone(zone).toLocalDate() }
            .mapValues { (_, records) ->
                records.map { record ->
                    NutritionMealEntry(
                        startTime = LocalDateTime.ofInstant(record.startTime, zone),
                        endTime = LocalDateTime.ofInstant(record.endTime, zone),
                        name = record.name?.takeIf { it.isNotBlank() },
                        mealType = mapMealType(record.mealType),
                        dietaryEnergy = record.energy?.inKilocalories,
                        energyFromFat = record.energyFromFat?.inKilocalories,
                        protein = record.protein?.inGrams,
                        carbohydrates = record.totalCarbohydrate?.inGrams,
                        fat = record.totalFat?.inGrams,
                        source = record.metadata.dataOrigin.packageName,
                        metadata = record.metadata.toExportMetadata(),
                        exactStartTime = record.startTime.toExactSourceTimestamp(record.startZoneOffset),
                        exactEndTime = record.endTime.toExactSourceTimestamp(record.endZoneOffset),
                        identity = record.metadata.toExactSourceIdentity("nutrition_meal", record.startTime, record.endTime, record.name),
                    )
                }.sortedBy { it.startTime }
            }

        for ((date, meals) in mealsByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.withRangeCompatibilityEntries(nutritionMeals = meals)
            }
        }
    }

    private suspend fun applyHeartRangeReads(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        includeGranularData: Boolean,
    ) {
        val zone = ZoneId.systemDefault()

        val hrvByDate = readRecordsOrEmpty(HeartRateVariabilityRmssdRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in hrvByDate) {
            if (date !in requestedDates) continue
            val sorted = records.sortedBy { it.time }
            dataByDate.update(date) { current ->
                current.copy(
                    heart = current.heart.copy(
                        hrv = sorted.lastOrNull()?.heartRateVariabilityMillis,
                        hrvSamples = if (includeGranularData) {
                            sorted.map {
                                TimestampedSample(
                                    time = LocalDateTime.ofInstant(it.time, zone),
                                    value = it.heartRateVariabilityMillis,
                                    source = it.metadata.dataOrigin.packageName,
                                    metadata = it.metadata.toExportMetadata(),
                                    exactTime = it.time.toExactSourceTimestamp(it.zoneOffset),
                                    identity = it.metadata.toExactSourceIdentity("hrv", it.time, it.heartRateVariabilityMillis),
                                )
                            }
                        } else {
                            current.heart.hrvSamples
                        },
                    )
                )
            }
        }

        if (!includeGranularData) return

        val heartRateSamplesByDate = readRecordsOrEmpty(HeartRateRecord::class, timeRange)
            .flatMap { record ->
                record.samples.map { sample ->
                    TimestampedSample(
                        time = LocalDateTime.ofInstant(sample.time, zone),
                        value = sample.beatsPerMinute.toDouble(),
                        source = record.metadata.dataOrigin.packageName,
                        metadata = record.metadata.toExportMetadata(),
                        exactTime = sample.time.toExactSourceTimestamp(),
                        identity = record.metadata.toSyntheticChildIdentity("heart_rate_sample", record.metadata.id, sample.time, sample.beatsPerMinute),
                    )
                }
            }
            .groupBy { it.time.toLocalDate() }

        for ((date, samples) in heartRateSamplesByDate) {
            if (date !in requestedDates) continue
            val timestampedSamples = samples.sortedBy { it.time }
            val values = timestampedSamples.map { it.value }

            dataByDate.update(date) { current ->
                current.copy(
                    heart = current.heart.copy(
                        averageHeartRate = current.heart.averageHeartRate ?: values.averageOrNull(),
                        heartRateMin = current.heart.heartRateMin ?: values.minOrNull(),
                        heartRateMax = current.heart.heartRateMax ?: values.maxOrNull(),
                        samples = timestampedSamples,
                    )
                )
            }
        }
    }

    private suspend fun applyVitalsRangeReads(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
        includeGranularData: Boolean,
    ) {
        val zone = ZoneId.systemDefault()

        val respiratoryByDate = readRecordsOrEmpty(RespiratoryRateRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in respiratoryByDate) {
            if (date !in requestedDates) continue
            val values = records.map { it.rate }
            dataByDate.update(date) { current ->
                current.copy(
                    vitals = current.vitals.copy(
                        respiratoryRateAvg = values.averageOrNull(),
                        respiratoryRateMin = values.minOrNull(),
                        respiratoryRateMax = values.maxOrNull(),
                        respiratoryRateSamples = if (includeGranularData) {
                            records.map {
                                TimestampedSample(
                                    time = LocalDateTime.ofInstant(it.time, zone),
                                    value = it.rate,
                                    source = it.metadata.dataOrigin.packageName,
                                    metadata = it.metadata.toExportMetadata(),
                                    exactTime = it.time.toExactSourceTimestamp(it.zoneOffset),
                                    identity = it.metadata.toExactSourceIdentity("respiratory_rate", it.time, it.rate),
                                )
                            }.sortedBy { it.time }
                        } else {
                            current.vitals.respiratoryRateSamples
                        },
                    )
                )
            }
        }

        val oxygenByDate = readRecordsOrEmpty(OxygenSaturationRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in oxygenByDate) {
            if (date !in requestedDates) continue
            val values = records.map { it.percentage.value / 100.0 }
            dataByDate.update(date) { current ->
                current.copy(
                    vitals = current.vitals.copy(
                        bloodOxygenAvg = values.averageOrNull(),
                        bloodOxygenMin = values.minOrNull(),
                        bloodOxygenMax = values.maxOrNull(),
                        bloodOxygenSamples = if (includeGranularData) {
                            records.map {
                                TimestampedSample(
                                    time = LocalDateTime.ofInstant(it.time, zone),
                                    value = it.percentage.value,
                                    source = it.metadata.dataOrigin.packageName,
                                    metadata = it.metadata.toExportMetadata(),
                                    exactTime = it.time.toExactSourceTimestamp(it.zoneOffset),
                                    identity = it.metadata.toExactSourceIdentity("oxygen_saturation", it.time, it.percentage.value),
                                )
                            }.sortedBy { it.time }
                        } else {
                            current.vitals.bloodOxygenSamples
                        },
                    )
                )
            }
        }

        val bodyTemperatureByDate = readRecordsOrEmpty(BodyTemperatureRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in bodyTemperatureByDate) {
            if (date !in requestedDates) continue
            val values = records.map { it.temperature.inCelsius }
            dataByDate.update(date) { current ->
                current.copy(
                    vitals = current.vitals.copy(
                        bodyTemperatureAvg = values.averageOrNull(),
                        bodyTemperatureMin = values.minOrNull(),
                        bodyTemperatureMax = values.maxOrNull(),
                        bodyTemperatureSamples = if (includeGranularData) {
                            records.map {
                                TimestampedSample(
                                    time = LocalDateTime.ofInstant(it.time, zone),
                                    value = it.temperature.inCelsius,
                                    source = it.metadata.dataOrigin.packageName,
                                    metadata = it.metadata.toExportMetadata(),
                                    context = buildMap {
                                        mapBodyTemperatureLocation(it.measurementLocation)?.let { location -> put("measurement_location", location) }
                                    },
                                    exactTime = it.time.toExactSourceTimestamp(it.zoneOffset),
                                    identity = it.metadata.toExactSourceIdentity("body_temperature", it.time, it.temperature.inCelsius),
                                )
                            }.sortedBy { it.time }
                        } else {
                            current.vitals.bodyTemperatureSamples
                        },
                    )
                )
            }
        }

        val glucoseByDate = readRecordsOrEmpty(BloodGlucoseRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in glucoseByDate) {
            if (date !in requestedDates) continue
            val values = records.map { it.level.inMilligramsPerDeciliter }
            dataByDate.update(date) { current ->
                current.copy(
                    vitals = current.vitals.copy(
                        bloodGlucoseAvg = values.averageOrNull(),
                        bloodGlucoseMin = values.minOrNull(),
                        bloodGlucoseMax = values.maxOrNull(),
                        bloodGlucoseSamples = if (includeGranularData) {
                            records.map {
                                TimestampedSample(
                                    time = LocalDateTime.ofInstant(it.time, zone),
                                    value = it.level.inMilligramsPerDeciliter,
                                    source = it.metadata.dataOrigin.packageName,
                                    metadata = it.metadata.toExportMetadata(),
                                    context = buildMap {
                                        mapBloodGlucoseSpecimenSource(it.specimenSource)?.let { source -> put("specimen_source", source) }
                                        mapMealType(it.mealType)?.let { mealType -> put("meal_type", mealType) }
                                        mapBloodGlucoseRelationToMeal(it.relationToMeal)?.let { relation -> put("relation_to_meal", relation) }
                                    },
                                    exactTime = it.time.toExactSourceTimestamp(it.zoneOffset),
                                    identity = it.metadata.toExactSourceIdentity("blood_glucose", it.time, it.level.inMilligramsPerDeciliter),
                                )
                            }.sortedBy { it.time }
                        } else {
                            current.vitals.bloodGlucoseSamples
                        },
                    )
                )
            }
        }

        val basalBodyTemperatureByDate = readRecordsOrEmpty(BasalBodyTemperatureRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in basalBodyTemperatureByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.copy(
                    vitals = current.vitals.copy(
                        basalBodyTemperature = records.maxByOrNull { it.time }?.temperature?.inCelsius,
                        basalBodyTemperatureSamples = if (includeGranularData) {
                            records.map {
                                TimestampedSample(
                                    time = LocalDateTime.ofInstant(it.time, zone),
                                    value = it.temperature.inCelsius,
                                    source = it.metadata.dataOrigin.packageName,
                                    metadata = it.metadata.toExportMetadata(),
                                    context = buildMap {
                                        mapBodyTemperatureLocation(it.measurementLocation)?.let { location ->
                                            put("measurement_location", location)
                                        }
                                    },
                                    exactTime = it.time.toExactSourceTimestamp(it.zoneOffset),
                                    identity = it.metadata.toExactSourceIdentity("basal_body_temperature", it.time, it.temperature.inCelsius),
                                )
                            }.sortedBy { it.time }
                        } else {
                            current.vitals.basalBodyTemperatureSamples
                        },
                    )
                )
            }
        }

        if (!includeGranularData) return

        val pressureByDate = readRecordsOrEmpty(BloodPressureRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in pressureByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.copy(
                    vitals = current.vitals.copy(
                        bloodPressureSamples = records.map {
                            BloodPressureSample(
                                time = LocalDateTime.ofInstant(it.time, zone),
                                systolic = it.systolic.inMillimetersOfMercury,
                                diastolic = it.diastolic.inMillimetersOfMercury,
                                measurementLocation = mapBloodPressureLocation(it.measurementLocation),
                                bodyPosition = mapBloodPressureBodyPosition(it.bodyPosition),
                                source = it.metadata.dataOrigin.packageName,
                                metadata = it.metadata.toExportMetadata(),
                                exactTime = it.time.toExactSourceTimestamp(it.zoneOffset),
                                identity = it.metadata.toExactSourceIdentity("blood_pressure", it.time, it.systolic, it.diastolic),
                            )
                        }.sortedBy { it.time },
                    )
                )
            }
        }

        if (isFeatureAvailable(HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE)) {
            val skinByDate = readRecordsOrEmpty(SkinTemperatureRecord::class, timeRange)
                .groupBy { it.startTime.atZone(zone).toLocalDate() }
            for ((date, records) in skinByDate) {
                if (date !in requestedDates) continue
                val latest = records.maxByOrNull { it.endTime }
                val deltas = records.flatMap { record ->
                    record.deltas.map { delta ->
                        TimestampedSample(
                            time = LocalDateTime.ofInstant(delta.time, zone),
                            value = delta.delta.inCelsius,
                            source = record.metadata.dataOrigin.packageName,
                            metadata = record.metadata.toExportMetadata(),
                            context = buildMap {
                                mapSkinTemperatureLocation(record.measurementLocation)?.let { location ->
                                    put("measurement_location", location)
                                }
                                record.baseline?.inCelsius?.let { baseline ->
                                    put("baseline_celsius", baseline.toString())
                                }
                            },
                            exactTime = delta.time.toExactSourceTimestamp(),
                            identity = record.metadata.toSyntheticChildIdentity("skin_temperature_delta", record.metadata.id, delta.time, delta.delta.inCelsius),
                        )
                    }
                }.sortedBy { it.time }
                dataByDate.update(date) { current ->
                    current.copy(
                        vitals = current.vitals.copy(
                            skinTemperatureBaseline = latest?.baseline?.inCelsius
                                ?: current.vitals.skinTemperatureBaseline,
                            skinTemperatureDeltas = deltas,
                        )
                    )
                }
            }
        }
    }

    private suspend fun applyBodyRangeReads(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
    ) {
        val zone = ZoneId.systemDefault()

        val bodyFatByDate = readRecordsOrEmpty(BodyFatRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in bodyFatByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.copy(body = current.body.copy(bodyFatPercentage = records.maxByOrNull { it.time }?.percentage?.value))
            }
        }

        val leanMassByDate = readRecordsOrEmpty(LeanBodyMassRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in leanMassByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.copy(body = current.body.copy(leanBodyMass = records.maxByOrNull { it.time }?.mass?.inKilograms))
            }
        }

        val waterMassByDate = readRecordsOrEmpty(BodyWaterMassRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in waterMassByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.copy(body = current.body.copy(bodyWaterMass = records.maxByOrNull { it.time }?.mass?.inKilograms))
            }
        }

        val boneMassByDate = readRecordsOrEmpty(BoneMassRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in boneMassByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.copy(body = current.body.copy(boneMass = records.maxByOrNull { it.time }?.mass?.inKilograms))
            }
        }
    }

    private suspend fun applyReproductiveRangeReads(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
    ) {
        val zone = ZoneId.systemDefault()

        val periodByDate = readRecordsOrEmpty(MenstruationPeriodRecord::class, timeRange)
            .groupBy { it.startTime.atZone(zone).toLocalDate() }
        for ((date, records) in periodByDate) {
            if (date !in requestedDates) continue
            val entries = records.map { record ->
                MenstruationPeriodEntry(
                    startTime = LocalDateTime.ofInstant(record.startTime, zone),
                    endTime = LocalDateTime.ofInstant(record.endTime, zone),
                    duration = java.time.Duration.between(record.startTime, record.endTime).toMillis().milliseconds,
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    exactStartTime = record.startTime.toExactSourceTimestamp(record.startZoneOffset),
                    exactEndTime = record.endTime.toExactSourceTimestamp(record.endZoneOffset),
                    identity = record.metadata.toExactSourceIdentity("menstruation_period", record.startTime, record.endTime),
                )
            }.sortedBy { it.startTime }
            val totalMs = entries.sumOf { it.duration.inWholeMilliseconds }
            dataByDate.update(date) { current ->
                current.copy(
                    reproductiveHealth = current.reproductiveHealth.copy(
                        menstruationPeriodCount = entries.size.takeIf { it > 0 },
                        menstruationPeriodDuration = totalMs.milliseconds,
                        menstruationPeriods = entries,
                    )
                )
            }
        }

        val menstruationByDate = readRecordsOrEmpty(MenstruationFlowRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in menstruationByDate) {
            if (date !in requestedDates) continue
            val flow = records.maxByOrNull { it.time }?.let { record ->
                when (record.flow) {
                    MenstruationFlowRecord.FLOW_LIGHT -> "light"
                    MenstruationFlowRecord.FLOW_MEDIUM -> "medium"
                    MenstruationFlowRecord.FLOW_HEAVY -> "heavy"
                    else -> null
                }
            }
            dataByDate.update(date) { current ->
                current.copy(reproductiveHealth = current.reproductiveHealth.copy(menstrualFlow = flow))
            }
        }

        val mucusByDate = readRecordsOrEmpty(CervicalMucusRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in mucusByDate) {
            if (date !in requestedDates) continue
            val mucus = records.maxByOrNull { it.time }
            dataByDate.update(date) { current ->
                current.copy(
                    reproductiveHealth = current.reproductiveHealth.copy(
                        cervicalMucusAppearance = mucus?.let { record ->
                            when (record.appearance) {
                                CervicalMucusRecord.APPEARANCE_DRY -> "dry"
                                CervicalMucusRecord.APPEARANCE_STICKY -> "sticky"
                                CervicalMucusRecord.APPEARANCE_CREAMY -> "creamy"
                                CervicalMucusRecord.APPEARANCE_WATERY -> "watery"
                                CervicalMucusRecord.APPEARANCE_EGG_WHITE -> "egg white"
                                else -> null
                            }
                        },
                        cervicalMucusSensation = mucus?.let { record ->
                            when (record.sensation) {
                                CervicalMucusRecord.SENSATION_LIGHT -> "light"
                                CervicalMucusRecord.SENSATION_MEDIUM -> "medium"
                                CervicalMucusRecord.SENSATION_HEAVY -> "heavy"
                                else -> null
                            }
                        },
                    )
                )
            }
        }

        val ovulationByDate = readRecordsOrEmpty(OvulationTestRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in ovulationByDate) {
            if (date !in requestedDates) continue
            val result = records.maxByOrNull { it.time }?.let { record ->
                when (record.result) {
                    OvulationTestRecord.RESULT_POSITIVE -> "positive"
                    OvulationTestRecord.RESULT_HIGH -> "high"
                    OvulationTestRecord.RESULT_NEGATIVE -> "negative"
                    OvulationTestRecord.RESULT_INCONCLUSIVE -> "inconclusive"
                    else -> null
                }
            }
            dataByDate.update(date) { current ->
                current.copy(reproductiveHealth = current.reproductiveHealth.copy(ovulationTestResult = result))
            }
        }

        val bleedingByDate = readRecordsOrEmpty(IntermenstrualBleedingRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in bleedingByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.copy(
                    reproductiveHealth = current.reproductiveHealth.copy(
                        intermenstrualBleeding = records.isNotEmpty(),
                    )
                )
            }
        }

        val sexualActivityByDate = readRecordsOrEmpty(SexualActivityRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }
        for ((date, records) in sexualActivityByDate) {
            if (date !in requestedDates) continue
            val sexualActivity = records.maxByOrNull { it.time }
            dataByDate.update(date) { current ->
                current.copy(
                    reproductiveHealth = current.reproductiveHealth.copy(
                        sexualActivityRecorded = sexualActivity != null,
                        sexualActivityProtectionUsed = sexualActivity?.let { record ->
                            when (record.protectionUsed) {
                                SexualActivityRecord.PROTECTION_USED_PROTECTED -> "protected"
                                SexualActivityRecord.PROTECTION_USED_UNPROTECTED -> "unprotected"
                                else -> null
                            }
                        },
                    )
                )
            }
        }
    }

    private suspend fun applyMindfulnessRange(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
    ) {
        val zone = ZoneId.systemDefault()
        val sessionsByDate = readRecordsOrEmpty(MindfulnessSessionRecord::class, timeRange)
            .groupBy { it.startTime.atZone(zone).toLocalDate() }

        for ((date, sessions) in sessionsByDate) {
            if (date !in requestedDates) continue
            val totalMinutes = sessions.sumOf {
                java.time.Duration.between(it.startTime, it.endTime).toMinutes().toDouble()
            }
            val sessionEntries = sessions.map {
                MindfulnessSessionEntry(
                    startTime = LocalDateTime.ofInstant(it.startTime, zone),
                    endTime = LocalDateTime.ofInstant(it.endTime, zone),
                    sessionType = mapMindfulnessSessionType(it.mindfulnessSessionType),
                    title = it.title?.takeIf { title -> title.isNotBlank() },
                    notes = it.notes?.takeIf { notes -> notes.isNotBlank() },
                    source = it.metadata.dataOrigin.packageName,
                    metadata = it.metadata.toExportMetadata(),
                    exactStartTime = it.startTime.toExactSourceTimestamp(it.startZoneOffset),
                    exactEndTime = it.endTime.toExactSourceTimestamp(it.endZoneOffset),
                    identity = it.metadata.toExactSourceIdentity("mindfulness_session", it.startTime, it.endTime),
                )
            }.sortedBy { it.startTime }
            dataByDate.update(date) { current ->
                current.copy(
                    mindfulness = MindfulnessData(
                        mindfulnessMinutes = if (totalMinutes > 0) totalMinutes else null,
                        mindfulSessions = sessions.size.takeIf { it > 0 },
                        sessions = sessionEntries,
                    )
                )
            }
        }
    }

    private suspend fun applyMobilityRangeReads(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
    ) {
        val zone = ZoneId.systemDefault()
        val vo2ByDate = readRecordsOrEmpty(Vo2MaxRecord::class, timeRange)
            .groupBy { it.time.atZone(zone).toLocalDate() }

        for ((date, records) in vo2ByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current ->
                current.copy(
                    mobility = current.mobility.copy(
                        vo2Max = records.maxByOrNull { it.time }?.vo2MillilitersPerMinuteKilogram,
                        vo2MaxMeasurementMethod = records.maxByOrNull { it.time }?.let { mapVo2MeasurementMethod(it.measurementMethod) },
                    )
                )
            }
        }
    }

    private suspend fun aggregateByDay(
        metrics: Set<AggregateMetric<*>>,
        timeRange: TimeRangeFilter,
        requestedDates: Set<LocalDate>,
    ): List<Pair<LocalDate, AggregateValues>> {
        if (metrics.isEmpty()) return emptyList()

        return aggregateValuesByDay(metrics, timeRange, requestedDates)
            .map { (date, values) -> date to AggregateValues(values) }
            .sortedBy { it.first }
    }

    /**
     * Health Connect rejects an aggregate request if any metric in the set is not readable on
     * the device/account. A single missing/new Android 16 permission should not make unrelated
     * metrics (for example steps) look empty, so fall back by splitting the request and keep the
     * metrics that are readable.
     */
    private suspend fun aggregateValuesByDay(
        metrics: Set<AggregateMetric<*>>,
        timeRange: TimeRangeFilter,
        requestedDates: Set<LocalDate>,
    ): Map<LocalDate, Map<AggregateMetric<*>, Any>> {
        if (metrics.isEmpty()) return emptyMap()

        return try {
            healthConnectClient.aggregateGroupByPeriod(
                AggregateGroupByPeriodRequest(
                    metrics = metrics,
                    timeRangeFilter = timeRange,
                    timeRangeSlicer = Period.ofDays(1),
                )
            ).mapNotNull { group ->
                val date = group.startTime.toLocalDate()
                if (date !in requestedDates) return@mapNotNull null

                val values = metrics.mapNotNull { metric ->
                    group.result.aggregateValue(metric)?.let { metric to it }
                }.toMap()
                if (values.isEmpty()) null else date to values
            }.toMap()
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
            if (metrics.size == 1) return emptyMap()

            val metricList = metrics.toList()
            val midpoint = metricList.size / 2
            val left = aggregateValuesByDay(metricList.take(midpoint).toSet(), timeRange, requestedDates)
            val right = aggregateValuesByDay(metricList.drop(midpoint).toSet(), timeRange, requestedDates)
            mergeAggregateValues(left, right)
        }
    }

    private fun mergeAggregateValues(
        first: Map<LocalDate, Map<AggregateMetric<*>, Any>>,
        second: Map<LocalDate, Map<AggregateMetric<*>, Any>>,
    ): Map<LocalDate, Map<AggregateMetric<*>, Any>> {
        if (first.isEmpty()) return second
        if (second.isEmpty()) return first

        val merged = first.mapValues { it.value.toMutableMap() }.toMutableMap()
        for ((date, values) in second) {
            merged.getOrPut(date) { mutableMapOf() }.putAll(values)
        }
        return merged
    }

    @Suppress("UNCHECKED_CAST")
    private fun AggregationResult.aggregateValue(metric: AggregateMetric<*>): Any? =
        this[metric as AggregateMetric<Any>]

    private class AggregateValues(
        private val values: Map<AggregateMetric<*>, Any>,
    ) {
        @Suppress("UNCHECKED_CAST")
        operator fun <T : Any> get(metric: AggregateMetric<T>): T? = values[metric] as? T
    }

    private suspend fun <T : androidx.health.connect.client.records.Record> readRecordsOrEmpty(
        recordType: KClass<T>,
        timeRange: TimeRangeFilter,
    ): List<T> = try {
        readRecordsPaged(recordType, timeRange)
    } catch (e: Exception) {
        e.rethrowIfActionableExportFailure()
        emptyList()
    }

    private suspend fun <T : androidx.health.connect.client.records.Record> readRecordsPaged(
        recordType: KClass<T>,
        timeRange: TimeRangeFilter,
    ): List<T> {
        val records = mutableListOf<T>()
        var pageToken: String? = null

        do {
            val response = healthConnectClient.readRecords(
                ReadRecordsRequest(
                    recordType = recordType,
                    timeRangeFilter = timeRange,
                    ascendingOrder = true,
                    pageSize = READ_PAGE_SIZE,
                    pageToken = pageToken,
                )
            )
            records += response.records
            pageToken = response.pageToken
        } while (!pageToken.isNullOrEmpty())

        return records
    }

    private fun MutableMap<LocalDate, HealthData>.update(
        date: LocalDate,
        transform: (HealthData) -> HealthData,
    ) {
        this[date] = transform(this[date] ?: HealthData(date))
    }

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
            val sessionEntries = mutableListOf<SleepSessionEntry>()
            var sessionStart: LocalDateTime? = null
            var sessionEnd: LocalDateTime? = null

            for (session in response.records) {
                val start = LocalDateTime.ofInstant(session.startTime, zone)
                val end = LocalDateTime.ofInstant(session.endTime, zone)
                val sessionDurationMs = java.time.Duration.between(session.startTime, session.endTime).toMillis()
                totalMs += sessionDurationMs
                sessionStart = listOfNotNull(sessionStart, start).minOrNull()
                sessionEnd = listOfNotNull(sessionEnd, end).maxOrNull()
                sessionEntries += SleepSessionEntry(
                    startTime = start,
                    endTime = end,
                    title = session.title?.takeIf { it.isNotBlank() },
                    notes = session.notes?.takeIf { it.isNotBlank() },
                    source = session.metadata.dataOrigin.packageName,
                    metadata = session.metadata.toExportMetadata(),
                    exactStartTime = session.startTime.toExactSourceTimestamp(session.startZoneOffset),
                    exactEndTime = session.endTime.toExactSourceTimestamp(session.endZoneOffset),
                    identity = session.metadata.toExactSourceIdentity("sleep_session", session.startTime, session.endTime),
                )

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
                            exactStartTime = stage.startTime.toExactSourceTimestamp(),
                            exactEndTime = stage.endTime.toExactSourceTimestamp(),
                            identity = session.metadata.toSyntheticChildIdentity("sleep_stage", session.metadata.id, stage.startTime, stage.endTime, stage.stage),
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
                sessions = sessionEntries.sortedBy { it.startTime },
                sessionStart = sessionStart,
                sessionEnd = sessionEnd,
            )
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
            SleepData()
        }
    }

    private suspend fun fetchActivityData(timeRange: TimeRangeFilter): ActivityData {
        return try {
            val zone = ZoneId.systemDefault()
            val aggregateResponse = healthConnectClient.aggregate(
                AggregateRequest(
                    metrics = buildSet<AggregateMetric<*>> {
                        add(StepsRecord.COUNT_TOTAL)
                        add(ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL)
                        add(TotalCaloriesBurnedRecord.ENERGY_TOTAL)
                        add(FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL)
                        add(DistanceRecord.DISTANCE_TOTAL)
                        add(ElevationGainedRecord.ELEVATION_GAINED_TOTAL)
                        add(WheelchairPushesRecord.COUNT_TOTAL)
                        if (isFeatureAvailable(HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY)) {
                            add(ActivityIntensityRecord.MODERATE_DURATION_TOTAL)
                            add(ActivityIntensityRecord.VIGOROUS_DURATION_TOTAL)
                            add(ActivityIntensityRecord.INTENSITY_MINUTES_TOTAL)
                        }
                    },
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

            val distanceRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(DistanceRecord::class, timeRange)
            ).records
            fun distanceFor(vararg types: WorkoutType): Double? {
                val matchingSessions = exerciseSessions.records.filter { mapExerciseType(it.exerciseType) in types }
                if (matchingSessions.isEmpty()) return null
                return distanceRecords.filter { distance ->
                    matchingSessions.any { session -> distance.overlaps(session.startTime, session.endTime) }
                }.sumOf { it.distance.inMeters }.positiveOrNull()
            }
            val swimmingSessions = exerciseSessions.records.filter { mapExerciseType(it.exerciseType) == WorkoutType.SWIMMING }
            val swimmingStrokes = swimmingSessions
                .flatMap { it.segments }
                .mapNotNull { it.repetitions.takeIf { reps -> reps > 0 } }
                .sum()
                .takeIf { it > 0 }

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
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    exactTime = record.startTime.toExactSourceTimestamp(record.startZoneOffset),
                    exactEndTime = record.endTime.toExactSourceTimestamp(record.endZoneOffset),
                    identity = record.metadata.toExactSourceIdentity("steps", record.startTime, record.endTime, record.count),
                )
            }

            val intensityEntries = if (isFeatureAvailable(HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY)) {
                readRecordsOrEmpty(ActivityIntensityRecord::class, timeRange).map { record ->
                    ActivityIntensityEntry(
                        startTime = LocalDateTime.ofInstant(record.startTime, zone),
                        endTime = LocalDateTime.ofInstant(record.endTime, zone),
                        duration = java.time.Duration.between(record.startTime, record.endTime).toMillis().milliseconds,
                        intensity = mapActivityIntensity(record.activityIntensityType),
                        source = record.metadata.dataOrigin.packageName,
                        metadata = record.metadata.toExportMetadata(),
                        exactStartTime = record.startTime.toExactSourceTimestamp(record.startZoneOffset),
                        exactEndTime = record.endTime.toExactSourceTimestamp(record.endZoneOffset),
                        identity = record.metadata.toExactSourceIdentity("activity_intensity", record.startTime, record.endTime),
                    )
                }
            } else emptyList()

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
                moderateActivityMinutes = (aggregateResponse[ActivityIntensityRecord.MODERATE_DURATION_TOTAL] as? java.time.Duration)?.toMinutes()?.toDouble(),
                vigorousActivityMinutes = (aggregateResponse[ActivityIntensityRecord.VIGOROUS_DURATION_TOTAL] as? java.time.Duration)?.toMinutes()?.toDouble(),
                activityIntensityMinutes = (aggregateResponse[ActivityIntensityRecord.INTENSITY_MINUTES_TOTAL] as? java.time.Duration)?.toMinutes()?.toInt(),
                swimmingDistance = distanceFor(WorkoutType.SWIMMING),
                swimmingStrokes = swimmingStrokes,
                wheelchairDistance = distanceFor(WorkoutType.WHEELCHAIR),
                downhillSnowSportsDistance = distanceFor(WorkoutType.SNOW_SPORTS),
                stepSamples = stepSamples,
                activityIntensityEntries = intensityEntries,
            )
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
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
            val walkingSessions = healthConnectClient.readRecords(
                ReadRecordsRequest(ExerciseSessionRecord::class, timeRange)
            ).records.filter { mapExerciseType(it.exerciseType) == WorkoutType.WALKING }
            val allBpm = mutableListOf<Double>()
            val walkingBpm = mutableListOf<Double>()
            val hrSamples = mutableListOf<TimestampedSample>()
            for (record in hrRecords.records) {
                for (sample in record.samples) {
                    val bpm = sample.beatsPerMinute.toDouble()
                    allBpm.add(bpm)
                    if (walkingSessions.any { session -> sample.time.isWithin(session.startTime, session.endTime) }) {
                        walkingBpm.add(bpm)
                    }
                    hrSamples.add(
                        TimestampedSample(
                            time = LocalDateTime.ofInstant(sample.time, zone),
                            value = bpm,
                            source = record.metadata.dataOrigin.packageName,
                            metadata = record.metadata.toExportMetadata(),
                            exactTime = sample.time.toExactSourceTimestamp(),
                            identity = record.metadata.toSyntheticChildIdentity("heart_rate_sample", record.metadata.id, sample.time, sample.beatsPerMinute),
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
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    exactTime = record.time.toExactSourceTimestamp(record.zoneOffset),
                    identity = record.metadata.toExactSourceIdentity("hrv", record.time, record.heartRateVariabilityMillis),
                )
            }

            HeartData(
                restingHeartRate = restingHr,
                averageHeartRate = if (allBpm.isNotEmpty()) allBpm.average() else null,
                walkingHeartRateAverage = walkingBpm.averageOrNull(),
                hrv = hrv,
                heartRateMin = allBpm.minOrNull(),
                heartRateMax = allBpm.maxOrNull(),
                samples = hrSamples,
                hrvSamples = hrvSamples,
            )
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
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
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    exactTime = record.time.toExactSourceTimestamp(record.zoneOffset),
                    identity = record.metadata.toExactSourceIdentity("respiratory_rate", record.time, record.rate),
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
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    exactTime = record.time.toExactSourceTimestamp(record.zoneOffset),
                    identity = record.metadata.toExactSourceIdentity("oxygen_saturation", record.time, record.percentage.value),
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
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    context = buildMap {
                        mapBodyTemperatureLocation(record.measurementLocation)?.let { put("measurement_location", it) }
                    },
                    exactTime = record.time.toExactSourceTimestamp(record.zoneOffset),
                    identity = record.metadata.toExactSourceIdentity("body_temperature", record.time, record.temperature.inCelsius),
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
                    measurementLocation = mapBloodPressureLocation(record.measurementLocation),
                    bodyPosition = mapBloodPressureBodyPosition(record.bodyPosition),
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    exactTime = record.time.toExactSourceTimestamp(record.zoneOffset),
                    identity = record.metadata.toExactSourceIdentity("blood_pressure", record.time, record.systolic, record.diastolic),
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
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    context = buildMap {
                        mapBloodGlucoseSpecimenSource(record.specimenSource)?.let { put("specimen_source", it) }
                        mapMealType(record.mealType)?.let { put("meal_type", it) }
                        mapBloodGlucoseRelationToMeal(record.relationToMeal)?.let { put("relation_to_meal", it) }
                    },
                    exactTime = record.time.toExactSourceTimestamp(record.zoneOffset),
                    identity = record.metadata.toExactSourceIdentity("blood_glucose", record.time, record.level.inMilligramsPerDeciliter),
                )
            }

            // Basal body temperature
            val bbtRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(BasalBodyTemperatureRecord::class, timeRange)
            )
            val basalBodyTemp = bbtRecords.records.lastOrNull()?.temperature?.inCelsius
            val bbtSamples = bbtRecords.records.map { record ->
                TimestampedSample(
                    time = LocalDateTime.ofInstant(record.time, zone),
                    value = record.temperature.inCelsius,
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    context = buildMap {
                        mapBodyTemperatureLocation(record.measurementLocation)?.let { put("measurement_location", it) }
                    },
                    exactTime = record.time.toExactSourceTimestamp(record.zoneOffset),
                    identity = record.metadata.toExactSourceIdentity("basal_body_temperature", record.time, record.temperature.inCelsius),
                )
            }

            // Skin temperature (using aggregate)
            val skinTempAggregate = healthConnectClient.aggregate(
                AggregateRequest(
                    metrics = setOf(SkinTemperatureRecord.TEMPERATURE_DELTA_AVG),
                    timeRangeFilter = timeRange,
                )
            )
            val skinTempDelta = skinTempAggregate[SkinTemperatureRecord.TEMPERATURE_DELTA_AVG]?.inCelsius
            val skinTempRecords = if (isFeatureAvailable(HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE)) {
                readRecordsOrEmpty(SkinTemperatureRecord::class, timeRange)
            } else emptyList()
            val skinTempBaseline = skinTempRecords.mapNotNull { it.baseline?.inCelsius }.lastOrNull()
            val skinTempDeltas = skinTempRecords.flatMap { record ->
                record.deltas.map { delta ->
                    TimestampedSample(
                        time = LocalDateTime.ofInstant(delta.time, zone),
                        value = delta.delta.inCelsius,
                        source = record.metadata.dataOrigin.packageName,
                        metadata = record.metadata.toExportMetadata(),
                        context = buildMap {
                            mapSkinTemperatureLocation(record.measurementLocation)?.let { put("measurement_location", it) }
                            record.baseline?.inCelsius?.let { put("baseline_celsius", it.toString()) }
                        },
                        exactTime = delta.time.toExactSourceTimestamp(),
                        identity = record.metadata.toSyntheticChildIdentity("skin_temperature_delta", record.metadata.id, delta.time, delta.delta.inCelsius),
                    )
                }
            }

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
                skinTemperatureBaseline = skinTempBaseline,
                bloodOxygenSamples = o2Samples,
                bloodPressureSamples = bpSamples,
                bloodGlucoseSamples = bgSamples,
                respiratoryRateSamples = rrSamples,
                bodyTemperatureSamples = tempSamples,
                basalBodyTemperatureSamples = bbtSamples,
                skinTemperatureDeltas = skinTempDeltas,
            )
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
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
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
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
            var energyFromFat = 0.0
            var protein = 0.0
            var carbs = 0.0
            var fat = 0.0
            var fiber = 0.0
            var sugar = 0.0
            var sodium = 0.0
            var caffeine = 0.0
            var cholesterol = 0.0
            var saturatedFat = 0.0
            var monounsaturatedFat = 0.0
            var polyunsaturatedFat = 0.0
            var unsaturatedFat = 0.0
            var transFat = 0.0
            var potassium = 0.0
            var calcium = 0.0
            var iron = 0.0
            var magnesium = 0.0
            var zinc = 0.0
            var phosphorus = 0.0
            var iodine = 0.0
            var selenium = 0.0
            var copper = 0.0
            var manganese = 0.0
            var chromium = 0.0
            var molybdenum = 0.0
            var chloride = 0.0
            var vitaminA = 0.0
            var vitaminB6 = 0.0
            var vitaminB12 = 0.0
            var vitaminC = 0.0
            var vitaminD = 0.0
            var vitaminE = 0.0
            var vitaminK = 0.0
            var thiamin = 0.0
            var riboflavin = 0.0
            var niacin = 0.0
            var folate = 0.0
            var folicAcid = 0.0
            var pantothenicAcid = 0.0
            var biotin = 0.0
            var hasAny = false
            val zone = ZoneId.systemDefault()
            val meals = mutableListOf<NutritionMealEntry>()

            for (record in records.records) {
                hasAny = true
                record.energy?.let { energy += it.inKilocalories }
                record.energyFromFat?.let { energyFromFat += it.inKilocalories }
                record.protein?.let { protein += it.inGrams }
                record.totalCarbohydrate?.let { carbs += it.inGrams }
                record.totalFat?.let { fat += it.inGrams }
                record.dietaryFiber?.let { fiber += it.inGrams }
                record.sugar?.let { sugar += it.inGrams }
                record.sodium?.let { sodium += it.inGrams * 1000 } // convert g -> mg
                record.caffeine?.let { caffeine += it.inGrams * 1000 }
                record.cholesterol?.let { cholesterol += it.inGrams * 1000 }
                record.saturatedFat?.let { saturatedFat += it.inGrams }
                record.monounsaturatedFat?.let { monounsaturatedFat += it.inGrams }
                record.polyunsaturatedFat?.let { polyunsaturatedFat += it.inGrams }
                record.unsaturatedFat?.let { unsaturatedFat += it.inGrams }
                record.transFat?.let { transFat += it.inGrams }
                record.potassium?.let { potassium += it.inGrams * 1000 }
                record.calcium?.let { calcium += it.inGrams * 1000 }
                record.iron?.let { iron += it.inGrams * 1000 }
                record.magnesium?.let { magnesium += it.inGrams * 1000 }
                record.zinc?.let { zinc += it.inGrams * 1000 }
                record.phosphorus?.let { phosphorus += it.inGrams * 1000 }
                record.iodine?.let { iodine += it.inGrams * 1_000_000 }
                record.selenium?.let { selenium += it.inGrams * 1_000_000 }
                record.copper?.let { copper += it.inGrams * 1000 }
                record.manganese?.let { manganese += it.inGrams * 1000 }
                record.chromium?.let { chromium += it.inGrams * 1_000_000 }
                record.molybdenum?.let { molybdenum += it.inGrams * 1_000_000 }
                record.chloride?.let { chloride += it.inGrams * 1000 }
                record.vitaminA?.let { vitaminA += it.inGrams * 1_000_000 }
                record.vitaminB6?.let { vitaminB6 += it.inGrams * 1000 }
                record.vitaminB12?.let { vitaminB12 += it.inGrams * 1_000_000 }
                record.vitaminC?.let { vitaminC += it.inGrams * 1000 }
                record.vitaminD?.let { vitaminD += it.inGrams * 1_000_000 }
                record.vitaminE?.let { vitaminE += it.inGrams * 1000 }
                record.vitaminK?.let { vitaminK += it.inGrams * 1_000_000 }
                record.thiamin?.let { thiamin += it.inGrams * 1000 }
                record.riboflavin?.let { riboflavin += it.inGrams * 1000 }
                record.niacin?.let { niacin += it.inGrams * 1000 }
                record.folate?.let { folate += it.inGrams * 1_000_000 }
                record.folicAcid?.let { folicAcid += it.inGrams * 1_000_000 }
                record.pantothenicAcid?.let { pantothenicAcid += it.inGrams * 1000 }
                record.biotin?.let { biotin += it.inGrams * 1_000_000 }
                meals += NutritionMealEntry(
                    startTime = LocalDateTime.ofInstant(record.startTime, zone),
                    endTime = LocalDateTime.ofInstant(record.endTime, zone),
                    name = record.name?.takeIf { it.isNotBlank() },
                    mealType = mapMealType(record.mealType),
                    dietaryEnergy = record.energy?.inKilocalories,
                    energyFromFat = record.energyFromFat?.inKilocalories,
                    protein = record.protein?.inGrams,
                    carbohydrates = record.totalCarbohydrate?.inGrams,
                    fat = record.totalFat?.inGrams,
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    exactStartTime = record.startTime.toExactSourceTimestamp(record.startZoneOffset),
                    exactEndTime = record.endTime.toExactSourceTimestamp(record.endZoneOffset),
                    identity = record.metadata.toExactSourceIdentity("nutrition_meal", record.startTime, record.endTime, record.name),
                )
            }

            // Water (separate record type)
            val hydrationRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(HydrationRecord::class, timeRange)
            )
            val waterLiters = hydrationRecords.records.sumOf { it.volume.inLiters }

            if (!hasAny && hydrationRecords.records.isEmpty()) return NutritionData()
            fun hasValue(selector: (NutritionRecord) -> Any?): Boolean =
                records.records.any { record -> selector(record) != null }

            NutritionData(
                dietaryEnergy = energy.takeIf { hasValue { record -> record.energy } },
                protein = protein.takeIf { hasValue { record -> record.protein } },
                carbohydrates = carbs.takeIf { hasValue { record -> record.totalCarbohydrate } },
                fat = fat.takeIf { hasValue { record -> record.totalFat } },
                fiber = fiber.takeIf { hasValue { record -> record.dietaryFiber } },
                sugar = sugar.takeIf { hasValue { record -> record.sugar } },
                sodium = sodium.takeIf { hasValue { record -> record.sodium } },
                water = waterLiters.takeIf { hydrationRecords.records.isNotEmpty() },
                caffeine = caffeine.takeIf { hasValue { record -> record.caffeine } },
                cholesterol = cholesterol.takeIf { hasValue { record -> record.cholesterol } },
                saturatedFat = saturatedFat.takeIf { hasValue { record -> record.saturatedFat } },
                monounsaturatedFat = monounsaturatedFat.takeIf { hasValue { record -> record.monounsaturatedFat } },
                polyunsaturatedFat = polyunsaturatedFat.takeIf { hasValue { record -> record.polyunsaturatedFat } },
                unsaturatedFat = unsaturatedFat.takeIf { hasValue { record -> record.unsaturatedFat } },
                transFat = transFat.takeIf { hasValue { record -> record.transFat } },
                potassium = potassium.takeIf { hasValue { record -> record.potassium } },
                calcium = calcium.takeIf { hasValue { record -> record.calcium } },
                iron = iron.takeIf { hasValue { record -> record.iron } },
                magnesium = magnesium.takeIf { hasValue { record -> record.magnesium } },
                zinc = zinc.takeIf { hasValue { record -> record.zinc } },
                phosphorus = phosphorus.takeIf { hasValue { record -> record.phosphorus } },
                iodine = iodine.takeIf { hasValue { record -> record.iodine } },
                selenium = selenium.takeIf { hasValue { record -> record.selenium } },
                copper = copper.takeIf { hasValue { record -> record.copper } },
                manganese = manganese.takeIf { hasValue { record -> record.manganese } },
                chromium = chromium.takeIf { hasValue { record -> record.chromium } },
                molybdenum = molybdenum.takeIf { hasValue { record -> record.molybdenum } },
                chloride = chloride.takeIf { hasValue { record -> record.chloride } },
                vitaminA = vitaminA.takeIf { hasValue { record -> record.vitaminA } },
                vitaminB6 = vitaminB6.takeIf { hasValue { record -> record.vitaminB6 } },
                vitaminB12 = vitaminB12.takeIf { hasValue { record -> record.vitaminB12 } },
                vitaminC = vitaminC.takeIf { hasValue { record -> record.vitaminC } },
                vitaminD = vitaminD.takeIf { hasValue { record -> record.vitaminD } },
                vitaminE = vitaminE.takeIf { hasValue { record -> record.vitaminE } },
                vitaminK = vitaminK.takeIf { hasValue { record -> record.vitaminK } },
                thiamin = thiamin.takeIf { hasValue { record -> record.thiamin } },
                riboflavin = riboflavin.takeIf { hasValue { record -> record.riboflavin } },
                niacin = niacin.takeIf { hasValue { record -> record.niacin } },
                folate = folate.takeIf { hasValue { record -> record.folate } },
                folicAcid = folicAcid.takeIf { hasValue { record -> record.folicAcid } },
                pantothenicAcid = pantothenicAcid.takeIf { hasValue { record -> record.pantothenicAcid } },
                biotin = biotin.takeIf { hasValue { record -> record.biotin } },
                energyFromFat = energyFromFat.takeIf { hasValue { record -> record.energyFromFat } },
                meals = meals.sortedBy { it.startTime },
            )
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
            NutritionData()
        }
    }

    private suspend fun fetchMobilityData(timeRange: TimeRangeFilter): MobilityData {
        return try {
            val exerciseSessions = healthConnectClient.readRecords(
                ReadRecordsRequest(ExerciseSessionRecord::class, timeRange)
            ).records
            val runningSessions = exerciseSessions.filter { mapExerciseType(it.exerciseType) == WorkoutType.RUNNING }

            val speedRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(SpeedRecord::class, timeRange)
            )
            val allSpeedSamples = speedRecords.records.flatMap { it.samples }
            val avgSpeed = allSpeedSamples
                .map { it.speed.inMetersPerSecond }
                .averageOrNull()
            val runningSpeed = allSpeedSamples
                .filter { sample -> runningSessions.any { session -> sample.time.isWithin(session.startTime, session.endTime) } }
                .map { it.speed.inMetersPerSecond }
                .averageOrNull()

            val vo2Records = healthConnectClient.readRecords(
                ReadRecordsRequest(Vo2MaxRecord::class, timeRange)
            )
            val latestVo2 = vo2Records.records.lastOrNull()
            val vo2Max = latestVo2?.vo2MillilitersPerMinuteKilogram

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
            val allPowerSamples = powerRecords.records.flatMap { it.samples }
            val powerSamples = allPowerSamples.map { it.power.inWatts }
            val runningPowerSamples = allPowerSamples
                .filter { sample -> runningSessions.any { session -> sample.time.isWithin(session.startTime, session.endTime) } }
                .map { it.power.inWatts }

            MobilityData(
                walkingSpeed = avgSpeed,
                vo2Max = vo2Max,
                vo2MaxMeasurementMethod = latestVo2?.let { mapVo2MeasurementMethod(it.measurementMethod) },
                cyclingCadenceAvg = cyclingCadence,
                cyclingCadenceMax = cyclingCadenceRecords.records.flatMap { it.samples }.maxOfOrNull { it.revolutionsPerMinute },
                stepsCadenceAvg = stepsCadence,
                stepsCadenceMax = stepsCadenceRecords.records.flatMap { it.samples }.maxOfOrNull { it.rate },
                powerAvg = powerSamples.averageOrNull(),
                powerMax = powerSamples.maxOrNull(),
                runningSpeed = runningSpeed,
                runningPowerAvg = runningPowerSamples.averageOrNull(),
                runningPowerMax = runningPowerSamples.maxOrNull(),
            )
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
            MobilityData()
        }
    }

    private suspend fun fetchReproductiveHealthData(timeRange: TimeRangeFilter): ReproductiveHealthData {
        return try {
            val zone = ZoneId.systemDefault()
            val periodRecords = healthConnectClient.readRecords(
                ReadRecordsRequest(MenstruationPeriodRecord::class, timeRange)
            )
            val periodEntries = periodRecords.records.map { record ->
                MenstruationPeriodEntry(
                    startTime = LocalDateTime.ofInstant(record.startTime, zone),
                    endTime = LocalDateTime.ofInstant(record.endTime, zone),
                    duration = java.time.Duration.between(record.startTime, record.endTime).toMillis().milliseconds,
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    exactStartTime = record.startTime.toExactSourceTimestamp(record.startZoneOffset),
                    exactEndTime = record.endTime.toExactSourceTimestamp(record.endZoneOffset),
                    identity = record.metadata.toExactSourceIdentity("menstruation_period", record.startTime, record.endTime),
                )
            }.sortedBy { it.startTime }
            val periodDuration = periodEntries.sumOf { it.duration.inWholeMilliseconds }.milliseconds

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
                menstruationPeriodCount = periodEntries.size.takeIf { it > 0 },
                menstruationPeriodDuration = periodDuration,
                menstruationPeriods = periodEntries,
            )
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
            ReproductiveHealthData()
        }
    }

    private suspend fun fetchMindfulnessData(timeRange: TimeRangeFilter): MindfulnessData {
        return try {
            val records = healthConnectClient.readRecords(
                ReadRecordsRequest(MindfulnessSessionRecord::class, timeRange)
            )
            val zone = ZoneId.systemDefault()
            val totalMinutes = records.records.sumOf { session ->
                java.time.Duration.between(session.startTime, session.endTime).toMinutes().toDouble()
            }
            MindfulnessData(
                mindfulnessMinutes = if (totalMinutes > 0) totalMinutes else null,
                mindfulSessions = records.records.size.takeIf { it > 0 },
                sessions = records.records.map {
                    MindfulnessSessionEntry(
                        startTime = LocalDateTime.ofInstant(it.startTime, zone),
                        endTime = LocalDateTime.ofInstant(it.endTime, zone),
                        sessionType = mapMindfulnessSessionType(it.mindfulnessSessionType),
                        title = it.title?.takeIf { title -> title.isNotBlank() },
                        notes = it.notes?.takeIf { notes -> notes.isNotBlank() },
                        source = it.metadata.dataOrigin.packageName,
                        metadata = it.metadata.toExportMetadata(),
                        exactStartTime = it.startTime.toExactSourceTimestamp(it.startZoneOffset),
                        exactEndTime = it.endTime.toExactSourceTimestamp(it.endZoneOffset),
                        identity = it.metadata.toExactSourceIdentity("mindfulness_session", it.startTime, it.endTime),
                    )
                }.sortedBy { it.startTime },
            )
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
            MindfulnessData()
        }
    }

    private suspend fun applyPlannedWorkoutRange(
        dataByDate: MutableMap<LocalDate, HealthData>,
        requestedDates: Set<LocalDate>,
        timeRange: TimeRangeFilter,
    ) {
        val zone = ZoneId.systemDefault()
        val plansByDate = readPlannedWorkouts(timeRange)
            .groupBy { it.startTime.toLocalDate() }
        for ((date, plans) in plansByDate) {
            if (date !in requestedDates) continue
            dataByDate.update(date) { current -> current.copy(plannedWorkouts = plans.sortedBy { it.startTime }) }
        }
    }

    private suspend fun fetchPlannedWorkouts(timeRange: TimeRangeFilter): List<PlannedExerciseData> = try {
        readPlannedWorkouts(timeRange)
    } catch (e: Exception) {
        e.rethrowIfActionableExportFailure()
        emptyList()
    }

    private suspend fun readPlannedWorkouts(timeRange: TimeRangeFilter): List<PlannedExerciseData> {
        if (!isFeatureAvailable(HealthConnectFeatures.FEATURE_PLANNED_EXERCISE)) return emptyList()
        val zone = ZoneId.systemDefault()
        return readRecordsOrEmpty(PlannedExerciseSessionRecord::class, timeRange).map { record ->
            val identity = record.metadata.toExactSourceIdentity(
                "health_connect_planned_workout",
                record.exerciseType,
                record.startTime,
                record.endTime,
                record.title,
            )
            PlannedExerciseData(
                id = record.metadata.id.takeIf { it.isNotBlank() } ?: requireNotNull(identity.syntheticId),
                workoutType = mapExerciseType(record.exerciseType),
                startTime = LocalDateTime.ofInstant(record.startTime, zone),
                endTime = LocalDateTime.ofInstant(record.endTime, zone),
                duration = java.time.Duration.between(record.startTime, record.endTime).toMillis().milliseconds,
                hasExplicitTime = record.hasExplicitTime,
                exerciseTypeRaw = record.exerciseType,
                completedExerciseSessionId = record.completedExerciseSessionId?.takeIf { it.isNotBlank() },
                title = record.title?.takeIf { it.isNotBlank() },
                notes = record.notes?.takeIf { it.isNotBlank() },
                blockCount = record.blocks.size,
                stepCount = record.blocks.sumOf { it.steps.size },
                blockDescriptions = record.blocks.mapNotNull { it.description?.takeIf { description -> description.isNotBlank() } },
                metadata = record.metadata.toExportMetadata(),
                exactStartTime = record.startTime.toExactSourceTimestamp(record.startZoneOffset),
                exactEndTime = record.endTime.toExactSourceTimestamp(record.endZoneOffset),
                identity = identity,
            )
        }.sortedBy { it.startTime }
    }

    private suspend fun fetchMedicalResources(): MedicalResourcesData {
        return try {
            if (!isFeatureAvailable(HealthConnectFeatures.FEATURE_PERSONAL_HEALTH_RECORD)) return MedicalResourcesData()
            val resources = mutableListOf<MedicalResourceData>()
            for (type in medicalResourceTypes()) {
                var request: androidx.health.connect.client.request.ReadMedicalResourcesRequest = ReadMedicalResourcesInitialRequest(
                    medicalResourceType = type,
                    medicalDataSourceIds = emptySet(),
                    pageSize = READ_PAGE_SIZE,
                )
                while (true) {
                    val response = healthConnectClient.readMedicalResources(request)
                    resources += response.medicalResources.map { it.toMedicalResourceData() }
                    val nextToken = response.nextPageToken
                    if (nextToken.isNullOrBlank()) break
                    request = ReadMedicalResourcesPageRequest(pageToken = nextToken, pageSize = READ_PAGE_SIZE)
                }
            }
            MedicalResourcesData(
                resources = resources,
                countsByType = resources.groupingBy { it.type }.eachCount(),
            )
        } catch (_: Exception) {
            MedicalResourcesData()
        }
    }

    private fun MedicalResource.toMedicalResourceData(): MedicalResourceData = MedicalResourceData(
        type = mapMedicalResourceType(type),
        typeRaw = type,
        dataSourceId = dataSourceId,
        medicalResourceId = id.toString(),
        fhirVersion = fhirVersion.toString(),
        fhirResourceType = mapFhirResourceType(fhirResource.type),
        fhirResourceTypeRaw = fhirResource.type,
        fhirResourceId = fhirResource.id,
        fhirResourceJson = fhirResource.data,
    )

    private suspend fun fetchWorkouts(timeRange: TimeRangeFilter): List<WorkoutData> {
        return try {
            val response = healthConnectClient.readRecords(
                ReadRecordsRequest(ExerciseSessionRecord::class, timeRange)
            )

            val sources = WorkoutSourceRecords(
                distanceRecords = readRecordsOrEmpty(DistanceRecord::class, timeRange),
                calorieRecords = readRecordsOrEmpty(ActiveCaloriesBurnedRecord::class, timeRange),
                heartRateRecords = readRecordsOrEmpty(HeartRateRecord::class, timeRange),
                speedRecords = readRecordsOrEmpty(SpeedRecord::class, timeRange),
                cyclingCadenceRecords = readRecordsOrEmpty(CyclingPedalingCadenceRecord::class, timeRange),
                stepsCadenceRecords = readRecordsOrEmpty(StepsCadenceRecord::class, timeRange),
                powerRecords = readRecordsOrEmpty(PowerRecord::class, timeRange),
                elevationRecords = readRecordsOrEmpty(ElevationGainedRecord::class, timeRange),
            )

            response.records.map { session ->
                buildWorkoutData(session, ZoneId.systemDefault(), sources, includeGranularData = true)
            }
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
            emptyList()
        }
    }

    private fun buildWorkoutData(
        session: ExerciseSessionRecord,
        zone: ZoneId,
        sources: WorkoutSourceRecords,
        includeGranularData: Boolean,
    ): WorkoutData {
        val duration = java.time.Duration.between(session.startTime, session.endTime)
        val heartSamples = sources.heartRateRecords
            .flatMap { record -> record.samples.map { sample -> record to sample } }
            .filter { (_, sample) -> sample.time.isWithin(session.startTime, session.endTime) }
            .map { (record, sample) ->
                TimestampedSample(
                    LocalDateTime.ofInstant(sample.time, zone),
                    sample.beatsPerMinute.toDouble(),
                    source = record.metadata.dataOrigin.packageName,
                    metadata = record.metadata.toExportMetadata(),
                    exactTime = sample.time.toExactSourceTimestamp(),
                    identity = record.metadata.toSyntheticChildIdentity("heart_rate_sample", record.metadata.id, sample.time, sample.beatsPerMinute),
                )
            }.sortedBy { it.time }
        val speedSamples = sources.speedRecords
            .flatMap { record -> record.samples.map { sample -> record to sample } }
            .filter { (_, sample) -> sample.time.isWithin(session.startTime, session.endTime) }
            .map { (record, sample) ->
                TimestampedSample(
                    LocalDateTime.ofInstant(sample.time, zone), sample.speed.inMetersPerSecond,
                    source = record.metadata.dataOrigin.packageName, metadata = record.metadata.toExportMetadata(),
                    exactTime = sample.time.toExactSourceTimestamp(),
                    identity = record.metadata.toSyntheticChildIdentity("speed_sample", record.metadata.id, sample.time, sample.speed.inMetersPerSecond),
                )
            }.sortedBy { it.time }
        val cyclingCadenceSamples = sources.cyclingCadenceRecords
            .flatMap { record -> record.samples.map { sample -> record to sample } }
            .filter { (_, sample) -> sample.time.isWithin(session.startTime, session.endTime) }
            .map { (record, sample) ->
                TimestampedSample(
                    LocalDateTime.ofInstant(sample.time, zone), sample.revolutionsPerMinute,
                    source = record.metadata.dataOrigin.packageName, metadata = record.metadata.toExportMetadata(),
                    exactTime = sample.time.toExactSourceTimestamp(),
                    identity = record.metadata.toSyntheticChildIdentity("cycling_cadence_sample", record.metadata.id, sample.time, sample.revolutionsPerMinute),
                )
            }.sortedBy { it.time }
        val stepsCadenceSamples = sources.stepsCadenceRecords
            .flatMap { record -> record.samples.map { sample -> record to sample } }
            .filter { (_, sample) -> sample.time.isWithin(session.startTime, session.endTime) }
            .map { (record, sample) ->
                TimestampedSample(
                    LocalDateTime.ofInstant(sample.time, zone), sample.rate,
                    source = record.metadata.dataOrigin.packageName, metadata = record.metadata.toExportMetadata(),
                    exactTime = sample.time.toExactSourceTimestamp(),
                    identity = record.metadata.toSyntheticChildIdentity("steps_cadence_sample", record.metadata.id, sample.time, sample.rate),
                )
            }.sortedBy { it.time }
        val powerSamples = sources.powerRecords
            .flatMap { record -> record.samples.map { sample -> record to sample } }
            .filter { (_, sample) -> sample.time.isWithin(session.startTime, session.endTime) }
            .map { (record, sample) ->
                TimestampedSample(
                    LocalDateTime.ofInstant(sample.time, zone), sample.power.inWatts,
                    source = record.metadata.dataOrigin.packageName, metadata = record.metadata.toExportMetadata(),
                    exactTime = sample.time.toExactSourceTimestamp(),
                    identity = record.metadata.toSyntheticChildIdentity("power_sample", record.metadata.id, sample.time, sample.power.inWatts),
                )
            }.sortedBy { it.time }
        val elevationSamples = sources.elevationRecords
            .filter { it.overlaps(session.startTime, session.endTime) }
            .map { record ->
                TimestampedSample(
                    LocalDateTime.ofInstant(record.startTime, zone), record.elevation.inMeters,
                    source = record.metadata.dataOrigin.packageName, metadata = record.metadata.toExportMetadata(),
                    exactTime = record.startTime.toExactSourceTimestamp(record.startZoneOffset),
                    exactEndTime = record.endTime.toExactSourceTimestamp(record.endZoneOffset),
                    identity = record.metadata.toExactSourceIdentity("elevation", record.startTime, record.endTime, record.elevation.inMeters),
                )
            }.sortedBy { it.time }

        val distance = sources.distanceRecords
            .filter { it.overlaps(session.startTime, session.endTime) }
            .sumOf { it.distance.inMeters }
            .positiveOrNull()
        val calories = sources.calorieRecords
            .filter { it.overlaps(session.startTime, session.endTime) }
            .sumOf { it.energy.inKilocalories }
            .positiveOrNull()
        val routeResult = session.exerciseRouteResult
        val routeAccess = when (routeResult) {
            is ExerciseRouteResult.Data -> WorkoutRouteAccess.DATA
            is ExerciseRouteResult.ConsentRequired -> WorkoutRouteAccess.CONSENT_REQUIRED
            is ExerciseRouteResult.NoData -> WorkoutRouteAccess.NO_DATA
            else -> WorkoutRouteAccess.NO_DATA
        }
        val routePoints = (routeResult as? ExerciseRouteResult.Data)
            ?.exerciseRoute
            ?.route
            ?.map { location ->
                WorkoutRoutePointData(
                    time = LocalDateTime.ofInstant(location.time, zone),
                    latitude = location.latitude,
                    longitude = location.longitude,
                    altitude = location.altitude?.inMeters,
                    horizontalAccuracy = location.horizontalAccuracy?.inMeters,
                    verticalAccuracy = location.verticalAccuracy?.inMeters,
                    exactTime = location.time.toExactSourceTimestamp(),
                    identity = session.metadata.toSyntheticChildIdentity("workout_route_point", session.metadata.id, location.time, location.latitude, location.longitude),
                )
            }
            ?.sortedBy { it.time }
            ?: emptyList()
        val (routeElevationGain, routeElevationLoss) = routePoints.elevationGainLoss()
        val elevation = sources.elevationRecords
            .filter { it.overlaps(session.startTime, session.endTime) }
            .sumOf { it.elevation.inMeters }
            .positiveOrNull() ?: routeElevationGain
        val averageSpeed = speedSamples.map { it.value }.averageOrNull()
        val laps = session.laps.map { lap ->
            WorkoutLapData(
                startTime = LocalDateTime.ofInstant(lap.startTime, zone),
                endTime = LocalDateTime.ofInstant(lap.endTime, zone),
                length = lap.length?.inMeters,
                exactStartTime = lap.startTime.toExactSourceTimestamp(),
                exactEndTime = lap.endTime.toExactSourceTimestamp(),
                identity = session.metadata.toSyntheticChildIdentity("workout_lap", session.metadata.id, lap.startTime, lap.endTime, lap.length?.inMeters),
            )
        }
        val splits = routePoints.deriveDistanceSplits(heartSamples)
            .ifEmpty { laps.deriveLapSplits(heartSamples) }
        val workoutIdentity = session.metadata.toExactSourceIdentity(
            "health_connect_workout",
            session.exerciseType,
            session.startTime,
            session.endTime,
            session.title,
        )

        return WorkoutData(
            id = session.metadata.id.takeIf { it.isNotBlank() } ?: requireNotNull(workoutIdentity.syntheticId),
            workoutType = mapExerciseType(session.exerciseType),
            startTime = LocalDateTime.ofInstant(session.startTime, zone),
            endTime = LocalDateTime.ofInstant(session.endTime, zone),
            isIndoor = inferIsIndoor(session.exerciseType),
            metadata = session.serializedWorkoutMetadata(),
            duration = duration.toMillis().milliseconds,
            calories = calories,
            distance = distance,
            elevationGained = elevation,
            elevationLoss = routeElevationLoss,
            averageHeartRate = heartSamples.map { it.value }.averageOrNull(),
            heartRateMin = heartSamples.map { it.value }.minOrNull(),
            heartRateMax = heartSamples.map { it.value }.maxOrNull(),
            averageSpeed = averageSpeed,
            maxSpeed = speedSamples.map { it.value }.maxOrNull(),
            averagePaceSecondsPerKm = averageSpeed?.takeIf { it > 0 }?.let { 1000.0 / it },
            cyclingCadenceAvg = cyclingCadenceSamples.map { it.value }.averageOrNull(),
            cyclingCadenceMax = cyclingCadenceSamples.map { it.value }.maxOrNull(),
            stepsCadenceAvg = stepsCadenceSamples.map { it.value }.averageOrNull(),
            stepsCadenceMax = stepsCadenceSamples.map { it.value }.maxOrNull(),
            powerAvg = powerSamples.map { it.value }.averageOrNull(),
            powerMax = powerSamples.map { it.value }.maxOrNull(),
            laps = laps,
            segments = session.segments.map { segment ->
                WorkoutSegmentData(
                    startTime = LocalDateTime.ofInstant(segment.startTime, zone),
                    endTime = LocalDateTime.ofInstant(segment.endTime, zone),
                    type = mapSegmentType(segment.segmentType),
                    repetitions = segment.repetitions.takeIf { it > 0 },
                    exactStartTime = segment.startTime.toExactSourceTimestamp(),
                    exactEndTime = segment.endTime.toExactSourceTimestamp(),
                    identity = session.metadata.toSyntheticChildIdentity("workout_segment", session.metadata.id, segment.startTime, segment.endTime, segment.segmentType),
                )
            },
            splits = splits,
            routeAccess = routeAccess,
            route = if (includeGranularData) routePoints else emptyList(),
            heartRateSamples = if (includeGranularData) heartSamples else emptyList(),
            speedSamples = if (includeGranularData) speedSamples else emptyList(),
            cyclingCadenceSamples = if (includeGranularData) cyclingCadenceSamples else emptyList(),
            stepsCadenceSamples = if (includeGranularData) stepsCadenceSamples else emptyList(),
            powerSamples = if (includeGranularData) powerSamples else emptyList(),
            elevationSamples = if (includeGranularData) elevationSamples else emptyList(),
            exactStartTime = session.startTime.toExactSourceTimestamp(session.startZoneOffset),
            exactEndTime = session.endTime.toExactSourceTimestamp(session.endZoneOffset),
            identity = workoutIdentity,
            correlatedSourceIds = buildMap {
                fun putIds(key: String, ids: List<String>) {
                    if (ids.isNotEmpty()) put(key, ids.distinct().sorted())
                }
                putIds("distance", sources.distanceRecords.filter { it.overlaps(session.startTime, session.endTime) }.mapNotNull { it.metadata.id.takeIf(String::isNotBlank) })
                putIds("calories", sources.calorieRecords.filter { it.overlaps(session.startTime, session.endTime) }.mapNotNull { it.metadata.id.takeIf(String::isNotBlank) })
                putIds("heart_rate", sources.heartRateRecords.filter { record -> record.samples.any { it.time.isWithin(session.startTime, session.endTime) } }.mapNotNull { it.metadata.id.takeIf(String::isNotBlank) })
                putIds("speed", sources.speedRecords.filter { record -> record.samples.any { it.time.isWithin(session.startTime, session.endTime) } }.mapNotNull { it.metadata.id.takeIf(String::isNotBlank) })
                putIds("cycling_cadence", sources.cyclingCadenceRecords.filter { record -> record.samples.any { it.time.isWithin(session.startTime, session.endTime) } }.mapNotNull { it.metadata.id.takeIf(String::isNotBlank) })
                putIds("steps_cadence", sources.stepsCadenceRecords.filter { record -> record.samples.any { it.time.isWithin(session.startTime, session.endTime) } }.mapNotNull { it.metadata.id.takeIf(String::isNotBlank) })
                putIds("power", sources.powerRecords.filter { record -> record.samples.any { it.time.isWithin(session.startTime, session.endTime) } }.mapNotNull { it.metadata.id.takeIf(String::isNotBlank) })
                putIds("elevation", sources.elevationRecords.filter { it.overlaps(session.startTime, session.endTime) }.mapNotNull { it.metadata.id.takeIf(String::isNotBlank) })
            },
        )
    }

    private fun mapActivityIntensity(type: Int): String = when (type) {
        ActivityIntensityRecord.ACTIVITY_INTENSITY_TYPE_MODERATE -> "moderate"
        ActivityIntensityRecord.ACTIVITY_INTENSITY_TYPE_VIGOROUS -> "vigorous"
        else -> "unknown"
    }

    private fun mapMealType(type: Int): String? = when (type) {
        MealType.MEAL_TYPE_BREAKFAST -> "breakfast"
        MealType.MEAL_TYPE_LUNCH -> "lunch"
        MealType.MEAL_TYPE_DINNER -> "dinner"
        MealType.MEAL_TYPE_SNACK -> "snack"
        else -> null
    }

    private fun mapBloodGlucoseSpecimenSource(type: Int): String? = when (type) {
        BloodGlucoseRecord.SPECIMEN_SOURCE_INTERSTITIAL_FLUID -> "interstitial_fluid"
        BloodGlucoseRecord.SPECIMEN_SOURCE_CAPILLARY_BLOOD -> "capillary_blood"
        BloodGlucoseRecord.SPECIMEN_SOURCE_PLASMA -> "plasma"
        BloodGlucoseRecord.SPECIMEN_SOURCE_SERUM -> "serum"
        BloodGlucoseRecord.SPECIMEN_SOURCE_TEARS -> "tears"
        BloodGlucoseRecord.SPECIMEN_SOURCE_WHOLE_BLOOD -> "whole_blood"
        else -> null
    }

    private fun mapBloodGlucoseRelationToMeal(type: Int): String? = when (type) {
        BloodGlucoseRecord.RELATION_TO_MEAL_GENERAL -> "general"
        BloodGlucoseRecord.RELATION_TO_MEAL_FASTING -> "fasting"
        BloodGlucoseRecord.RELATION_TO_MEAL_BEFORE_MEAL -> "before_meal"
        BloodGlucoseRecord.RELATION_TO_MEAL_AFTER_MEAL -> "after_meal"
        else -> null
    }

    private fun mapBloodPressureLocation(type: Int): String? = when (type) {
        BloodPressureRecord.MEASUREMENT_LOCATION_LEFT_WRIST -> "left_wrist"
        BloodPressureRecord.MEASUREMENT_LOCATION_RIGHT_WRIST -> "right_wrist"
        BloodPressureRecord.MEASUREMENT_LOCATION_LEFT_UPPER_ARM -> "left_upper_arm"
        BloodPressureRecord.MEASUREMENT_LOCATION_RIGHT_UPPER_ARM -> "right_upper_arm"
        else -> null
    }

    private fun mapBloodPressureBodyPosition(type: Int): String? = when (type) {
        BloodPressureRecord.BODY_POSITION_STANDING_UP -> "standing"
        BloodPressureRecord.BODY_POSITION_SITTING_DOWN -> "sitting"
        BloodPressureRecord.BODY_POSITION_LYING_DOWN -> "lying_down"
        BloodPressureRecord.BODY_POSITION_RECLINING -> "reclining"
        else -> null
    }

    private fun mapBodyTemperatureLocation(type: Int): String? = when (type) {
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_ARMPIT -> "armpit"
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_FINGER -> "finger"
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_FOREHEAD -> "forehead"
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_MOUTH -> "mouth"
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_RECTUM -> "rectum"
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_TEMPORAL_ARTERY -> "temporal_artery"
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_TOE -> "toe"
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_EAR -> "ear"
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_WRIST -> "wrist"
        BodyTemperatureMeasurementLocation.MEASUREMENT_LOCATION_VAGINA -> "vagina"
        else -> null
    }

    private fun mapSkinTemperatureLocation(type: Int): String? = when (type) {
        SkinTemperatureRecord.MEASUREMENT_LOCATION_FINGER -> "finger"
        SkinTemperatureRecord.MEASUREMENT_LOCATION_TOE -> "toe"
        SkinTemperatureRecord.MEASUREMENT_LOCATION_WRIST -> "wrist"
        else -> null
    }

    private fun mapMindfulnessSessionType(type: Int): String? = when (type) {
        MindfulnessSessionRecord.MINDFULNESS_SESSION_TYPE_MEDITATION -> "meditation"
        MindfulnessSessionRecord.MINDFULNESS_SESSION_TYPE_BREATHING -> "breathing"
        MindfulnessSessionRecord.MINDFULNESS_SESSION_TYPE_MUSIC -> "music"
        MindfulnessSessionRecord.MINDFULNESS_SESSION_TYPE_MOVEMENT -> "movement"
        MindfulnessSessionRecord.MINDFULNESS_SESSION_TYPE_UNGUIDED -> "unguided"
        else -> null
    }

    private fun mapVo2MeasurementMethod(type: Int): String? = when (type) {
        Vo2MaxRecord.MEASUREMENT_METHOD_METABOLIC_CART -> "metabolic_cart"
        Vo2MaxRecord.MEASUREMENT_METHOD_HEART_RATE_RATIO -> "heart_rate_ratio"
        Vo2MaxRecord.MEASUREMENT_METHOD_COOPER_TEST -> "cooper_test"
        Vo2MaxRecord.MEASUREMENT_METHOD_MULTISTAGE_FITNESS_TEST -> "multistage_fitness_test"
        Vo2MaxRecord.MEASUREMENT_METHOD_ROCKPORT_FITNESS_TEST -> "rockport_fitness_test"
        Vo2MaxRecord.MEASUREMENT_METHOD_OTHER -> "other"
        else -> null
    }

    private fun medicalResourceTypes(): List<Int> = listOf(
        MedicalResource.MEDICAL_RESOURCE_TYPE_ALLERGIES_INTOLERANCES,
        MedicalResource.MEDICAL_RESOURCE_TYPE_CONDITIONS,
        MedicalResource.MEDICAL_RESOURCE_TYPE_LABORATORY_RESULTS,
        MedicalResource.MEDICAL_RESOURCE_TYPE_MEDICATIONS,
        MedicalResource.MEDICAL_RESOURCE_TYPE_PERSONAL_DETAILS,
        MedicalResource.MEDICAL_RESOURCE_TYPE_PRACTITIONER_DETAILS,
        MedicalResource.MEDICAL_RESOURCE_TYPE_PREGNANCY,
        MedicalResource.MEDICAL_RESOURCE_TYPE_PROCEDURES,
        MedicalResource.MEDICAL_RESOURCE_TYPE_SOCIAL_HISTORY,
        MedicalResource.MEDICAL_RESOURCE_TYPE_VACCINES,
        MedicalResource.MEDICAL_RESOURCE_TYPE_VISITS,
        MedicalResource.MEDICAL_RESOURCE_TYPE_VITAL_SIGNS,
    )

    private fun mapMedicalResourceType(type: Int): String = when (type) {
        MedicalResource.MEDICAL_RESOURCE_TYPE_ALLERGIES_INTOLERANCES -> "allergies_intolerances"
        MedicalResource.MEDICAL_RESOURCE_TYPE_CONDITIONS -> "conditions"
        MedicalResource.MEDICAL_RESOURCE_TYPE_LABORATORY_RESULTS -> "laboratory_results"
        MedicalResource.MEDICAL_RESOURCE_TYPE_MEDICATIONS -> "medications"
        MedicalResource.MEDICAL_RESOURCE_TYPE_PERSONAL_DETAILS -> "personal_details"
        MedicalResource.MEDICAL_RESOURCE_TYPE_PRACTITIONER_DETAILS -> "practitioner_details"
        MedicalResource.MEDICAL_RESOURCE_TYPE_PREGNANCY -> "pregnancy"
        MedicalResource.MEDICAL_RESOURCE_TYPE_PROCEDURES -> "procedures"
        MedicalResource.MEDICAL_RESOURCE_TYPE_SOCIAL_HISTORY -> "social_history"
        MedicalResource.MEDICAL_RESOURCE_TYPE_VACCINES -> "vaccines"
        MedicalResource.MEDICAL_RESOURCE_TYPE_VISITS -> "visits"
        MedicalResource.MEDICAL_RESOURCE_TYPE_VITAL_SIGNS -> "vital_signs"
        else -> "type_$type"
    }

    private fun mapFhirResourceType(type: Int): String = when (type) {
        FhirResource.FHIR_RESOURCE_TYPE_IMMUNIZATION -> "Immunization"
        FhirResource.FHIR_RESOURCE_TYPE_ALLERGY_INTOLERANCE -> "AllergyIntolerance"
        FhirResource.FHIR_RESOURCE_TYPE_OBSERVATION -> "Observation"
        FhirResource.FHIR_RESOURCE_TYPE_CONDITION -> "Condition"
        FhirResource.FHIR_RESOURCE_TYPE_PROCEDURE -> "Procedure"
        FhirResource.FHIR_RESOURCE_TYPE_MEDICATION -> "Medication"
        FhirResource.FHIR_RESOURCE_TYPE_MEDICATION_REQUEST -> "MedicationRequest"
        FhirResource.FHIR_RESOURCE_TYPE_MEDICATION_STATEMENT -> "MedicationStatement"
        FhirResource.FHIR_RESOURCE_TYPE_PATIENT -> "Patient"
        FhirResource.FHIR_RESOURCE_TYPE_PRACTITIONER -> "Practitioner"
        FhirResource.FHIR_RESOURCE_TYPE_PRACTITIONER_ROLE -> "PractitionerRole"
        FhirResource.FHIR_RESOURCE_TYPE_ENCOUNTER -> "Encounter"
        FhirResource.FHIR_RESOURCE_TYPE_LOCATION -> "Location"
        FhirResource.FHIR_RESOURCE_TYPE_ORGANIZATION -> "Organization"
        else -> "FHIR_$type"
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
        ExerciseSessionRecord.EXERCISE_TYPE_SNOWBOARDING,
        ExerciseSessionRecord.EXERCISE_TYPE_SNOWSHOEING -> WorkoutType.SNOW_SPORTS
        ExerciseSessionRecord.EXERCISE_TYPE_SURFING,
        ExerciseSessionRecord.EXERCISE_TYPE_WATER_POLO -> WorkoutType.WATER_SPORTS
        ExerciseSessionRecord.EXERCISE_TYPE_WHEELCHAIR -> WorkoutType.WHEELCHAIR
        ExerciseSessionRecord.EXERCISE_TYPE_MARTIAL_ARTS -> WorkoutType.MARTIAL_ARTS
        ExerciseSessionRecord.EXERCISE_TYPE_BOXING -> WorkoutType.BOXING
        ExerciseSessionRecord.EXERCISE_TYPE_ROCK_CLIMBING -> WorkoutType.CLIMBING
        ExerciseSessionRecord.EXERCISE_TYPE_STRETCHING -> WorkoutType.FLEXIBILITY
        else -> WorkoutType.OTHER
    }

    private fun List<Double>.averageOrNull(): Double? =
        if (isEmpty()) null else average()

    private fun Double.positiveOrNull(): Double? =
        if (this > 0.0) this else null

    private fun List<Double>.sumPositiveOrNull(): Double? =
        sum().positiveOrNull()

    private fun Instant.isWithin(start: Instant, end: Instant): Boolean =
        !isBefore(start) && !isAfter(end)

    private fun DistanceRecord.overlaps(start: Instant, end: Instant): Boolean =
        overlaps(startTime, endTime, start, end)

    private fun ActiveCaloriesBurnedRecord.overlaps(start: Instant, end: Instant): Boolean =
        overlaps(startTime, endTime, start, end)

    private fun ElevationGainedRecord.overlaps(start: Instant, end: Instant): Boolean =
        overlaps(startTime, endTime, start, end)

    private fun overlaps(recordStart: Instant, recordEnd: Instant, start: Instant, end: Instant): Boolean =
        recordStart.isBefore(end) && recordEnd.isAfter(start)

    private fun mapSegmentType(type: Int): String = when (type) {
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_SWIMMING_BACKSTROKE -> "swimming backstroke"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_SWIMMING_BREASTSTROKE -> "swimming breaststroke"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_SWIMMING_BUTTERFLY -> "swimming butterfly"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_SWIMMING_FREESTYLE -> "swimming freestyle"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_SWIMMING_MIXED -> "swimming mixed"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_SWIMMING_OPEN_WATER -> "swimming open water"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_SWIMMING_POOL -> "swimming pool"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_RUNNING,
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_RUNNING_TREADMILL -> "running"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_WALKING -> "walking"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_BIKING,
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_BIKING_STATIONARY -> "cycling"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_WHEELCHAIR -> "wheelchair"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_REST -> "rest"
        ExerciseSegment.EXERCISE_SEGMENT_TYPE_PAUSE -> "pause"
        else -> "segment $type"
    }

    private fun inferIsIndoor(type: Int): Boolean? = when (type) {
        ExerciseSessionRecord.EXERCISE_TYPE_RUNNING_TREADMILL,
        ExerciseSessionRecord.EXERCISE_TYPE_BIKING_STATIONARY,
        ExerciseSessionRecord.EXERCISE_TYPE_ROWING_MACHINE,
        ExerciseSessionRecord.EXERCISE_TYPE_STAIR_CLIMBING_MACHINE,
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_POOL -> true
        ExerciseSessionRecord.EXERCISE_TYPE_SWIMMING_OPEN_WATER -> false
        else -> null
    }

    private fun ExerciseSessionRecord.serializedWorkoutMetadata(): Map<String, String> = buildMap {
        put("exercise_type_raw", exerciseType.toString())
        title?.takeIf { it.isNotBlank() }?.let { put("title", it) }
        notes?.takeIf { it.isNotBlank() }?.let { put("notes", it) }
        plannedExerciseSessionId?.takeIf { it.isNotBlank() }?.let { put("planned_exercise_session_id", it) }
        metadata.id.takeIf { it.isNotBlank() }?.let { put("health_connect_id", it) }
        metadata.dataOrigin.packageName.takeIf { it.isNotBlank() }?.let { packageName ->
            put("data_origin_package", packageName)
            dataOriginProviderName(packageName)?.let { put("data_origin_provider", it) }
        }
        metadata.clientRecordId?.takeIf { it.isNotBlank() }?.let { put("client_record_id", it) }
        metadata.clientRecordVersion.takeIf { it > 0L }?.let { put("client_record_version", it.toString()) }
        metadata.lastModifiedTime.takeIf { it != Instant.EPOCH }?.let { put("last_modified_time", it.toString()) }
        put("recording_method", metadata.recordingMethodName())
        metadata.device?.let { device ->
            put("device_type", device.type.toString())
            device.manufacturer?.takeIf { it.isNotBlank() }?.let { put("device_manufacturer", it) }
            device.model?.takeIf { it.isNotBlank() }?.let { put("device_model", it) }
        }
    }

    private fun Instant.toExactSourceTimestamp(offset: ZoneOffset? = null): ExactSourceTimestamp =
        ExactSourceTimestamp.from(this, offset)

    private fun Metadata.toExactSourceIdentity(
        syntheticKind: String,
        vararg syntheticParts: Any?,
    ): ExactSourceIdentity {
        val stableNativeId = id.takeIf { it.isNotBlank() }
        val synthetic = if (stableNativeId == null) {
            deterministicRecordId(syntheticKind, *syntheticParts)
        } else null
        return ExactSourceIdentity(
            nativeId = stableNativeId,
            clientRecordId = clientRecordId?.takeIf { it.isNotBlank() },
            clientRecordVersion = clientRecordVersion.takeIf { it > 0L },
            origin = dataOrigin.packageName.takeIf { it.isNotBlank() },
            lastModified = lastModifiedTime.takeIf { it != Instant.EPOCH }?.toExactSourceTimestamp(),
            syntheticId = synthetic,
            isSynthetic = synthetic != null,
        )
    }

    private fun syntheticChildIdentity(kind: String, vararg parts: Any?): ExactSourceIdentity =
        ExactSourceIdentity(
            syntheticId = deterministicRecordId(kind, *parts),
            isSynthetic = true,
        )

    private fun Metadata.toSyntheticChildIdentity(kind: String, vararg parts: Any?): ExactSourceIdentity =
        ExactSourceIdentity(
            clientRecordId = clientRecordId?.takeIf { it.isNotBlank() },
            clientRecordVersion = clientRecordVersion.takeIf { it > 0L },
            origin = dataOrigin.packageName.takeIf { it.isNotBlank() },
            lastModified = lastModifiedTime.takeIf { it != Instant.EPOCH }?.toExactSourceTimestamp(),
            syntheticId = deterministicRecordId(kind, *parts),
            isSynthetic = true,
        )

    private fun Metadata.recordingMethodName(): String = when (recordingMethod) {
        Metadata.RECORDING_METHOD_ACTIVELY_RECORDED -> "actively_recorded"
        Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED -> "automatically_recorded"
        Metadata.RECORDING_METHOD_MANUAL_ENTRY -> "manual_entry"
        else -> "unknown"
    }

    private fun Metadata.toExportMetadata(): Map<String, String> = buildMap {
        id.takeIf { it.isNotBlank() }?.let { put("health_connect_id", it) }
        dataOrigin.packageName.takeIf { it.isNotBlank() }?.let { packageName ->
            put("data_origin_package", packageName)
            dataOriginProviderName(packageName)?.let { put("data_origin_provider", it) }
        }
        clientRecordId?.takeIf { it.isNotBlank() }?.let { put("client_record_id", it) }
        clientRecordVersion.takeIf { it > 0L }?.let { put("client_record_version", it.toString()) }
        lastModifiedTime.takeIf { it != Instant.EPOCH }?.let { put("last_modified_time", it.toString()) }
        put("recording_method", recordingMethodName())
        device?.let { device ->
            put("device_type", device.type.toString())
            device.manufacturer?.takeIf { it.isNotBlank() }?.let { put("device_manufacturer", it) }
            device.model?.takeIf { it.isNotBlank() }?.let { put("device_model", it) }
        }
    }

    private fun dataOriginProviderName(packageName: String): String? = when (packageName) {
        "com.google.android.apps.healthdata" -> "Health Connect"
        "com.sec.android.app.shealth" -> "Samsung Health"
        "com.huawei.health" -> "Huawei Health"
        "com.fitbit.FitbitMobile" -> "Fitbit"
        "com.garmin.android.apps.connectmobile" -> "Garmin Connect"
        "com.withings.wiscale2" -> "Withings"
        "com.ouraring.oura" -> "Oura"
        "fi.polar.polarflow" -> "Polar Flow"
        "com.whoop.android" -> "WHOOP"
        else -> null
    }

    private fun List<WorkoutRoutePointData>.elevationGainLoss(): Pair<Double?, Double?> {
        if (size < 2) return null to null
        var gain = 0.0
        var loss = 0.0
        var previousAltitude: Double? = null
        for (point in this) {
            val altitude = point.altitude ?: continue
            previousAltitude?.let { previous ->
                val delta = altitude - previous
                if (delta > 0) gain += delta else if (delta < 0) loss += -delta
            }
            previousAltitude = altitude
        }
        return gain.positiveOrNull() to loss.positiveOrNull()
    }

    private fun List<WorkoutRoutePointData>.deriveDistanceSplits(
        heartSamples: List<TimestampedSample>,
    ): List<WorkoutSplitData> {
        if (size < 2) return emptyList()
        val splits = mutableListOf<WorkoutSplitData>()
        var cumulativeMeters = 0.0
        var lastSplitMeters = 0.0
        var lastSplitTime = first().time
        var splitIndex = 1

        for (index in 1 until size) {
            val previous = this[index - 1]
            val current = this[index]
            cumulativeMeters += previous.distanceMetersTo(current)
            while (cumulativeMeters - lastSplitMeters >= WORKOUT_SPLIT_DISTANCE_METERS) {
                val splitEnd = current.time
                val duration = java.time.Duration.between(lastSplitTime, splitEnd)
                if (!duration.isNegative && !duration.isZero) {
                    splits += WorkoutSplitData(
                        index = splitIndex,
                        startTime = lastSplitTime,
                        endTime = splitEnd,
                        duration = duration.toMillis().milliseconds,
                        distance = WORKOUT_SPLIT_DISTANCE_METERS,
                        averageHeartRate = heartSamples.averageBetween(lastSplitTime, splitEnd),
                        exactStartTime = this[index - 1].exactTime,
                        exactEndTime = current.exactTime,
                        identity = syntheticChildIdentity("workout_split", first().identity?.syntheticId, splitIndex, this[index - 1].exactTime?.epochSecond, current.exactTime?.epochSecond),
                    )
                    splitIndex += 1
                }
                lastSplitMeters += WORKOUT_SPLIT_DISTANCE_METERS
                lastSplitTime = splitEnd
            }
        }

        return splits
    }

    private fun List<WorkoutLapData>.deriveLapSplits(
        heartSamples: List<TimestampedSample>,
    ): List<WorkoutSplitData> = mapIndexedNotNull { index, lap ->
        val duration = java.time.Duration.between(lap.startTime, lap.endTime)
        if (duration.isNegative || duration.isZero) return@mapIndexedNotNull null
        WorkoutSplitData(
            index = index + 1,
            startTime = lap.startTime,
            endTime = lap.endTime,
            duration = duration.toMillis().milliseconds,
            distance = lap.length,
            averageHeartRate = heartSamples.averageBetween(lap.startTime, lap.endTime),
            exactStartTime = lap.exactStartTime,
            exactEndTime = lap.exactEndTime,
            identity = syntheticChildIdentity("workout_split_from_lap", lap.identity?.syntheticId, index + 1),
        )
    }

    private fun List<TimestampedSample>.averageBetween(
        start: LocalDateTime,
        end: LocalDateTime,
    ): Double? = filter { !it.time.isBefore(start) && !it.time.isAfter(end) }
        .map { it.value }
        .averageOrNull()

    private fun WorkoutRoutePointData.distanceMetersTo(other: WorkoutRoutePointData): Double {
        val earthRadiusMeters = 6_371_000.0
        val lat1 = Math.toRadians(latitude)
        val lat2 = Math.toRadians(other.latitude)
        val dLat = Math.toRadians(other.latitude - latitude)
        val dLon = Math.toRadians(other.longitude - longitude)
        val a = sin(dLat / 2) * sin(dLat / 2) +
                cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2)
        return earthRadiusMeters * 2 * atan2(sqrt(a), sqrt(1 - a))
    }

    private data class WorkoutSourceRecords(
        val distanceRecords: List<DistanceRecord> = emptyList(),
        val calorieRecords: List<ActiveCaloriesBurnedRecord> = emptyList(),
        val heartRateRecords: List<HeartRateRecord> = emptyList(),
        val speedRecords: List<SpeedRecord> = emptyList(),
        val cyclingCadenceRecords: List<CyclingPedalingCadenceRecord> = emptyList(),
        val stepsCadenceRecords: List<StepsCadenceRecord> = emptyList(),
        val powerRecords: List<PowerRecord> = emptyList(),
        val elevationRecords: List<ElevationGainedRecord> = emptyList(),
    )

    private data class SleepAccumulator(
        var totalMs: Long = 0L,
        var deepMs: Long = 0L,
        var remMs: Long = 0L,
        var lightMs: Long = 0L,
        var awakeMs: Long = 0L,
        val stages: MutableList<SleepStageEntry> = mutableListOf(),
        val sessions: MutableList<SleepSessionEntry> = mutableListOf(),
        var sessionStart: LocalDateTime? = null,
        var sessionEnd: LocalDateTime? = null,
    )

    private companion object {
        const val RANGE_READ_CHUNK_DAYS = 30
        const val GRANULAR_READ_CHUNK_DAYS = 7
        const val READ_PAGE_SIZE = 1_000
        const val WORKOUT_SPLIT_DISTANCE_METERS = 1_000.0
    }
}

private fun Exception.rethrowIfActionableExportFailure() {
    if (isHealthConnectRateLimit() || isLikelyHealthConnectRateLimit() || isHistoricalOrBackgroundAccessFailure()) throw this
}

private fun Exception.isHistoricalOrBackgroundAccessFailure(): Boolean {
    if (this !is SecurityException) return false
    val message = message.orEmpty()
    return message.contains("history", ignoreCase = true) ||
        message.contains("historical", ignoreCase = true) ||
        message.contains("background", ignoreCase = true)
}
