package com.healthmd.data.health

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregateMetric
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.feature.ExperimentalMindfulnessSessionApi
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_HISTORY
import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.TemperatureDelta
import androidx.health.connect.client.request.AggregateGroupByPeriodRequest
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
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
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.math.sqrt
import kotlin.reflect.KClass
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
            if (selection.reproductiveHealth) {
                applyReproductiveRangeReads(dataByDate, chunkDates, instantRange)
            }
            if (selection.mindfulness) {
                applyMindfulnessRange(dataByDate, chunkDates, instantRange)
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

        val metrics = setOf<AggregateMetric<*>>(
            StepsRecord.COUNT_TOTAL,
            ActiveCaloriesBurnedRecord.ACTIVE_CALORIES_TOTAL,
            TotalCaloriesBurnedRecord.ENERGY_TOTAL,
            BasalMetabolicRateRecord.BASAL_CALORIES_TOTAL,
            FloorsClimbedRecord.FLOORS_CLIMBED_TOTAL,
            DistanceRecord.DISTANCE_TOTAL,
            ElevationGainedRecord.ELEVATION_GAINED_TOTAL,
            WheelchairPushesRecord.COUNT_TOTAL,
        )

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
                        dietaryEnergy = result[NutritionRecord.ENERGY_TOTAL]?.inKilocalories?.positiveOrNull(),
                        protein = result[NutritionRecord.PROTEIN_TOTAL]?.inGrams?.positiveOrNull(),
                        carbohydrates = result[NutritionRecord.TOTAL_CARBOHYDRATE_TOTAL]?.inGrams?.positiveOrNull(),
                        fat = result[NutritionRecord.TOTAL_FAT_TOTAL]?.inGrams?.positiveOrNull(),
                        fiber = result[NutritionRecord.DIETARY_FIBER_TOTAL]?.inGrams?.positiveOrNull(),
                        sugar = result[NutritionRecord.SUGAR_TOTAL]?.inGrams?.positiveOrNull(),
                        sodium = result[NutritionRecord.SODIUM_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        water = result[HydrationRecord.VOLUME_TOTAL]?.inLiters?.positiveOrNull(),
                        caffeine = result[NutritionRecord.CAFFEINE_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        cholesterol = result[NutritionRecord.CHOLESTEROL_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        saturatedFat = result[NutritionRecord.SATURATED_FAT_TOTAL]?.inGrams?.positiveOrNull(),
                        monounsaturatedFat = result[NutritionRecord.MONOUNSATURATED_FAT_TOTAL]?.inGrams?.positiveOrNull(),
                        polyunsaturatedFat = result[NutritionRecord.POLYUNSATURATED_FAT_TOTAL]?.inGrams?.positiveOrNull(),
                        unsaturatedFat = result[NutritionRecord.UNSATURATED_FAT_TOTAL]?.inGrams?.positiveOrNull(),
                        transFat = result[NutritionRecord.TRANS_FAT_TOTAL]?.inGrams?.positiveOrNull(),
                        potassium = result[NutritionRecord.POTASSIUM_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        calcium = result[NutritionRecord.CALCIUM_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        iron = result[NutritionRecord.IRON_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        magnesium = result[NutritionRecord.MAGNESIUM_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        zinc = result[NutritionRecord.ZINC_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        phosphorus = result[NutritionRecord.PHOSPHORUS_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        iodine = result[NutritionRecord.IODINE_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        selenium = result[NutritionRecord.SELENIUM_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        copper = result[NutritionRecord.COPPER_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        manganese = result[NutritionRecord.MANGANESE_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        chromium = result[NutritionRecord.CHROMIUM_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        molybdenum = result[NutritionRecord.MOLYBDENUM_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        chloride = result[NutritionRecord.CHLORIDE_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        vitaminA = result[NutritionRecord.VITAMIN_A_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        vitaminB6 = result[NutritionRecord.VITAMIN_B6_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        vitaminB12 = result[NutritionRecord.VITAMIN_B12_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        vitaminC = result[NutritionRecord.VITAMIN_C_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        vitaminD = result[NutritionRecord.VITAMIN_D_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        vitaminE = result[NutritionRecord.VITAMIN_E_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        vitaminK = result[NutritionRecord.VITAMIN_K_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        thiamin = result[NutritionRecord.THIAMIN_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        riboflavin = result[NutritionRecord.RIBOFLAVIN_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        niacin = result[NutritionRecord.NIACIN_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        folate = result[NutritionRecord.FOLATE_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        folicAcid = result[NutritionRecord.FOLIC_ACID_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
                        pantothenicAcid = result[NutritionRecord.PANTOTHENIC_ACID_TOTAL]?.inGrams?.times(1000)?.positiveOrNull(),
                        biotin = result[NutritionRecord.BIOTIN_TOTAL]?.inGrams?.times(1_000_000)?.positiveOrNull(),
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
            StepsCadenceRecord.RATE_AVG,
            PowerRecord.POWER_AVG,
            PowerRecord.POWER_MAX,
        )

        for ((date, result) in aggregateByDay(metrics, timeRange, requestedDates)) {
            dataByDate.update(date) { current ->
                current.copy(
                    mobility = current.mobility.copy(
                        walkingSpeed = result[SpeedRecord.SPEED_AVG]?.inMetersPerSecond,
                        cyclingCadenceAvg = result[CyclingPedalingCadenceRecord.RPM_AVG],
                        stepsCadenceAvg = result[StepsCadenceRecord.RATE_AVG],
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
                    LocalDateTime.ofInstant(sample.time, zone) to sample.beatsPerMinute.toDouble()
                }
            }
            .groupBy { (time, _) -> time.toLocalDate() }

        for ((date, samples) in heartRateSamplesByDate) {
            if (date !in requestedDates) continue
            val timestampedSamples = samples.map { (time, bpm) ->
                TimestampedSample(time = time, value = bpm)
            }.sortedBy { it.time }
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
                                TimestampedSample(LocalDateTime.ofInstant(it.time, zone), it.rate)
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
                            )
                        }.sortedBy { it.time },
                    )
                )
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
                    )
                )
            }
        }
    }

    private suspend fun aggregateByDay(
        metrics: Set<AggregateMetric<*>>,
        timeRange: TimeRangeFilter,
        requestedDates: Set<LocalDate>,
    ): List<Pair<LocalDate, AggregationResult>> {
        if (metrics.isEmpty()) return emptyList()

        return try {
            healthConnectClient.aggregateGroupByPeriod(
                AggregateGroupByPeriodRequest(
                    metrics = metrics,
                    timeRangeFilter = timeRange,
                    timeRangeSlicer = Period.ofDays(1),
                )
            ).mapNotNull { group ->
                val date = group.startTime.toLocalDate()
                if (date in requestedDates) date to group.result else null
            }
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
            emptyList()
        }
    }

    private suspend fun <T : androidx.health.connect.client.records.Record> readRecordsOrEmpty(
        recordType: KClass<T>,
        timeRange: TimeRangeFilter,
    ): List<T> = try {
        readRecordsPaged(recordType, timeRange)
    } catch (e: Exception) {
        if (e.isLikelyHealthConnectRateLimit()) throw e
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
                swimmingDistance = distanceFor(WorkoutType.SWIMMING),
                swimmingStrokes = swimmingStrokes,
                wheelchairDistance = distanceFor(WorkoutType.WHEELCHAIR),
                downhillSnowSportsDistance = distanceFor(WorkoutType.SNOW_SPORTS),
                stepSamples = stepSamples,
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
                monounsaturatedFat = if (monounsaturatedFat > 0) monounsaturatedFat else null,
                polyunsaturatedFat = if (polyunsaturatedFat > 0) polyunsaturatedFat else null,
                unsaturatedFat = if (unsaturatedFat > 0) unsaturatedFat else null,
                transFat = if (transFat > 0) transFat else null,
                potassium = if (potassium > 0) potassium else null,
                calcium = if (calcium > 0) calcium else null,
                iron = if (iron > 0) iron else null,
                magnesium = if (magnesium > 0) magnesium else null,
                zinc = if (zinc > 0) zinc else null,
                phosphorus = if (phosphorus > 0) phosphorus else null,
                iodine = if (iodine > 0) iodine else null,
                selenium = if (selenium > 0) selenium else null,
                copper = if (copper > 0) copper else null,
                manganese = if (manganese > 0) manganese else null,
                chromium = if (chromium > 0) chromium else null,
                molybdenum = if (molybdenum > 0) molybdenum else null,
                chloride = if (chloride > 0) chloride else null,
                vitaminA = if (vitaminA > 0) vitaminA else null,
                vitaminB6 = if (vitaminB6 > 0) vitaminB6 else null,
                vitaminB12 = if (vitaminB12 > 0) vitaminB12 else null,
                vitaminC = if (vitaminC > 0) vitaminC else null,
                vitaminD = if (vitaminD > 0) vitaminD else null,
                vitaminE = if (vitaminE > 0) vitaminE else null,
                vitaminK = if (vitaminK > 0) vitaminK else null,
                thiamin = if (thiamin > 0) thiamin else null,
                riboflavin = if (riboflavin > 0) riboflavin else null,
                niacin = if (niacin > 0) niacin else null,
                folate = if (folate > 0) folate else null,
                folicAcid = if (folicAcid > 0) folicAcid else null,
                pantothenicAcid = if (pantothenicAcid > 0) pantothenicAcid else null,
                biotin = if (biotin > 0) biotin else null,
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
            val allPowerSamples = powerRecords.records.flatMap { it.samples }
            val powerSamples = allPowerSamples.map { it.power.inWatts }
            val runningPowerSamples = allPowerSamples
                .filter { sample -> runningSessions.any { session -> sample.time.isWithin(session.startTime, session.endTime) } }
                .map { it.power.inWatts }

            MobilityData(
                walkingSpeed = avgSpeed,
                vo2Max = vo2Max,
                cyclingCadenceAvg = cyclingCadence,
                stepsCadenceAvg = stepsCadence,
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
                    )
                }.sortedBy { it.startTime },
            )
        } catch (e: Exception) {
            e.rethrowIfActionableExportFailure()
            MindfulnessData()
        }
    }

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
            .flatMap { it.samples }
            .filter { it.time.isWithin(session.startTime, session.endTime) }
            .map { TimestampedSample(LocalDateTime.ofInstant(it.time, zone), it.beatsPerMinute.toDouble()) }
            .sortedBy { it.time }
        val speedSamples = sources.speedRecords
            .flatMap { it.samples }
            .filter { it.time.isWithin(session.startTime, session.endTime) }
            .map { TimestampedSample(LocalDateTime.ofInstant(it.time, zone), it.speed.inMetersPerSecond) }
            .sortedBy { it.time }
        val cyclingCadenceSamples = sources.cyclingCadenceRecords
            .flatMap { it.samples }
            .filter { it.time.isWithin(session.startTime, session.endTime) }
            .map { TimestampedSample(LocalDateTime.ofInstant(it.time, zone), it.revolutionsPerMinute) }
            .sortedBy { it.time }
        val stepsCadenceSamples = sources.stepsCadenceRecords
            .flatMap { it.samples }
            .filter { it.time.isWithin(session.startTime, session.endTime) }
            .map { TimestampedSample(LocalDateTime.ofInstant(it.time, zone), it.rate) }
            .sortedBy { it.time }
        val powerSamples = sources.powerRecords
            .flatMap { it.samples }
            .filter { it.time.isWithin(session.startTime, session.endTime) }
            .map { TimestampedSample(LocalDateTime.ofInstant(it.time, zone), it.power.inWatts) }
            .sortedBy { it.time }
        val elevationSamples = sources.elevationRecords
            .filter { it.overlaps(session.startTime, session.endTime) }
            .map { TimestampedSample(LocalDateTime.ofInstant(it.startTime, zone), it.elevation.inMeters) }
            .sortedBy { it.time }

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
            )
        }
        val splits = routePoints.deriveDistanceSplits(heartSamples)
            .ifEmpty { laps.deriveLapSplits(heartSamples) }

        return WorkoutData(
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
            stepsCadenceAvg = stepsCadenceSamples.map { it.value }.averageOrNull(),
            powerAvg = powerSamples.map { it.value }.averageOrNull(),
            powerMax = powerSamples.map { it.value }.maxOrNull(),
            laps = laps,
            segments = session.segments.map { segment ->
                WorkoutSegmentData(
                    startTime = LocalDateTime.ofInstant(segment.startTime, zone),
                    endTime = LocalDateTime.ofInstant(segment.endTime, zone),
                    type = mapSegmentType(segment.segmentType),
                    repetitions = segment.repetitions.takeIf { it > 0 },
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
        )
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
        metadata.dataOrigin.packageName.takeIf { it.isNotBlank() }?.let { put("data_origin_package", it) }
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

    private fun Metadata.recordingMethodName(): String = when (recordingMethod) {
        Metadata.RECORDING_METHOD_ACTIVELY_RECORDED -> "actively_recorded"
        Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED -> "automatically_recorded"
        Metadata.RECORDING_METHOD_MANUAL_ENTRY -> "manual_entry"
        else -> "unknown"
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
