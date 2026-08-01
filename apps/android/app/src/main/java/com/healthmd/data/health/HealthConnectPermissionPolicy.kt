package com.healthmd.data.health

import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.feature.ExperimentalPersonalHealthRecordApi
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_HISTORY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND
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
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.ActivityIntensityRecord
import androidx.health.connect.client.records.BasalBodyTemperatureRecord
import androidx.health.connect.client.records.BasalMetabolicRateRecord
import androidx.health.connect.client.records.BloodGlucoseRecord
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.BodyTemperatureRecord
import androidx.health.connect.client.records.BodyWaterMassRecord
import androidx.health.connect.client.records.BoneMassRecord
import androidx.health.connect.client.records.CervicalMucusRecord
import androidx.health.connect.client.records.CyclingPedalingCadenceRecord
import androidx.health.connect.client.records.DistanceRecord
import androidx.health.connect.client.records.ElevationGainedRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.FloorsClimbedRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.HeightRecord
import androidx.health.connect.client.records.HydrationRecord
import androidx.health.connect.client.records.IntermenstrualBleedingRecord
import androidx.health.connect.client.records.LeanBodyMassRecord
import androidx.health.connect.client.records.MenstruationFlowRecord
import androidx.health.connect.client.records.MenstruationPeriodRecord
import androidx.health.connect.client.records.MindfulnessSessionRecord
import androidx.health.connect.client.records.NutritionRecord
import androidx.health.connect.client.records.OvulationTestRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.PlannedExerciseSessionRecord
import androidx.health.connect.client.records.PowerRecord
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SexualActivityRecord
import androidx.health.connect.client.records.SkinTemperatureRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.SpeedRecord
import androidx.health.connect.client.records.StepsCadenceRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.Vo2MaxRecord
import androidx.health.connect.client.records.WeightRecord
import androidx.health.connect.client.records.WheelchairPushesRecord

enum class HealthConnectFeatureAvailability {
    AVAILABLE,
    UNAVAILABLE,
    ERROR,
}

/** The permissions that can actually be requested from the installed Health Connect provider. */
data class HealthConnectPermissionPlan(
    val foregroundPermissions: Set<String>,
    val historicalReadPermissions: Set<String>,
    val backgroundReadPermissions: Set<String>,
    val historicalReadAvailability: HealthConnectFeatureAvailability,
    val backgroundReadAvailability: HealthConnectFeatureAvailability,
    val failedFeatureChecks: Set<Int> = emptySet(),
) {
    val featureStatusCheckFailed: Boolean
        get() = failedFeatureChecks.isNotEmpty()
}

/**
 * Builds permission requests from Health Connect feature availability.
 *
 * Newer record types remain declared in the manifest for compatible devices and Play review, but
 * they must not be sent to providers that cannot grant them (notably the Android 13 APK provider).
 */
@OptIn(ExperimentalPersonalHealthRecordApi::class)
object HealthConnectPermissionPolicy {
    private val alwaysAvailableForegroundPermissions = setOf(
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
        HealthPermission.getReadPermission(CervicalMucusRecord::class),
        HealthPermission.getReadPermission(IntermenstrualBleedingRecord::class),
        HealthPermission.getReadPermission(MenstruationFlowRecord::class),
        HealthPermission.getReadPermission(MenstruationPeriodRecord::class),
        HealthPermission.getReadPermission(OvulationTestRecord::class),
        HealthPermission.getReadPermission(SexualActivityRecord::class),
        HealthPermission.getReadPermission(CyclingPedalingCadenceRecord::class),
        HealthPermission.getReadPermission(StepsCadenceRecord::class),
    )

    private val skinTemperaturePermissions = setOf(
        HealthPermission.getReadPermission(SkinTemperatureRecord::class),
    )
    private val mindfulnessPermissions = setOf(
        HealthPermission.getReadPermission(MindfulnessSessionRecord::class),
    )
    private val plannedExercisePermissions = setOf(
        HealthPermission.getReadPermission(PlannedExerciseSessionRecord::class),
    )
    private val activityIntensityPermissions = setOf(
        HealthPermission.getReadPermission(ActivityIntensityRecord::class),
    )
    internal val medicalPermissions = setOf(
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

    fun create(isFeatureAvailable: (Int) -> Boolean): HealthConnectPermissionPlan =
        createWithAvailability { feature ->
            if (isFeatureAvailable(feature)) {
                HealthConnectFeatureAvailability.AVAILABLE
            } else {
                HealthConnectFeatureAvailability.UNAVAILABLE
            }
        }

    fun createWithAvailability(
        featureAvailability: (Int) -> HealthConnectFeatureAvailability,
    ): HealthConnectPermissionPlan {
        val features = listOf(
            HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE,
            HealthConnectFeatures.FEATURE_MINDFULNESS_SESSION,
            HealthConnectFeatures.FEATURE_PLANNED_EXERCISE,
            HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY,
            HealthConnectFeatures.FEATURE_PERSONAL_HEALTH_RECORD,
            HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY,
            HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND,
        )
        val availability = features.associateWith(featureAvailability)
        fun isAvailable(feature: Int): Boolean =
            availability[feature] == HealthConnectFeatureAvailability.AVAILABLE

        val foreground = buildSet {
            addAll(alwaysAvailableForegroundPermissions)
            if (isAvailable(HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE)) {
                addAll(skinTemperaturePermissions)
            }
            if (isAvailable(HealthConnectFeatures.FEATURE_MINDFULNESS_SESSION)) {
                addAll(mindfulnessPermissions)
            }
            if (isAvailable(HealthConnectFeatures.FEATURE_PLANNED_EXERCISE)) {
                addAll(plannedExercisePermissions)
            }
            if (isAvailable(HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY)) {
                addAll(activityIntensityPermissions)
            }
            if (isAvailable(HealthConnectFeatures.FEATURE_PERSONAL_HEALTH_RECORD)) {
                addAll(medicalPermissions)
            }
        }
        val historicalAvailability = availability.getValue(
            HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY
        )
        val backgroundAvailability = availability.getValue(
            HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND
        )

        return HealthConnectPermissionPlan(
            foregroundPermissions = foreground,
            historicalReadPermissions = if (
                historicalAvailability == HealthConnectFeatureAvailability.AVAILABLE
            ) {
                setOf(PERMISSION_READ_HEALTH_DATA_HISTORY)
            } else {
                emptySet()
            },
            backgroundReadPermissions = if (
                backgroundAvailability == HealthConnectFeatureAvailability.AVAILABLE
            ) {
                setOf(PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)
            } else {
                emptySet()
            },
            historicalReadAvailability = historicalAvailability,
            backgroundReadAvailability = backgroundAvailability,
            failedFeatureChecks = availability.filterValues {
                it == HealthConnectFeatureAvailability.ERROR
            }.keys,
        )
    }
}
