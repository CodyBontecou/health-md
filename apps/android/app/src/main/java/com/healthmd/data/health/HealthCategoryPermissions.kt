package com.healthmd.data.health

import androidx.health.connect.client.permission.HealthPermission
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
import androidx.health.connect.client.records.PowerRecord
import androidx.health.connect.client.records.Record
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
import com.healthmd.domain.model.HealthAccessCategory
import kotlin.reflect.KClass

/**
 * Health Connect read permissions behind each export category, matching the record types
 * [HealthConnectManager] reads for that category.
 */
object HealthCategoryPermissions {
    private fun read(vararg types: KClass<out Record>): Set<String> =
        types.mapTo(LinkedHashSet()) { HealthPermission.getReadPermission(it) }

    fun declared(category: HealthAccessCategory): Set<String> = when (category) {
        HealthAccessCategory.SLEEP -> read(SleepSessionRecord::class)
        HealthAccessCategory.ACTIVITY -> read(
            StepsRecord::class, ActiveCaloriesBurnedRecord::class, TotalCaloriesBurnedRecord::class,
            DistanceRecord::class, FloorsClimbedRecord::class, ElevationGainedRecord::class,
            ActivityIntensityRecord::class,
        )
        HealthAccessCategory.HEART -> read(
            HeartRateRecord::class, HeartRateVariabilityRmssdRecord::class, RestingHeartRateRecord::class,
        )
        HealthAccessCategory.VITALS -> read(
            OxygenSaturationRecord::class, RespiratoryRateRecord::class, BloodPressureRecord::class,
            BloodGlucoseRecord::class, BodyTemperatureRecord::class, BasalBodyTemperatureRecord::class,
            SkinTemperatureRecord::class,
        )
        HealthAccessCategory.BODY -> read(
            WeightRecord::class, HeightRecord::class, BodyFatRecord::class, LeanBodyMassRecord::class,
            BoneMassRecord::class, BodyWaterMassRecord::class, BasalMetabolicRateRecord::class,
        )
        HealthAccessCategory.NUTRITION -> read(NutritionRecord::class, HydrationRecord::class)
        HealthAccessCategory.MOBILITY -> read(
            Vo2MaxRecord::class, SpeedRecord::class, PowerRecord::class, StepsCadenceRecord::class,
            CyclingPedalingCadenceRecord::class,
        )
        HealthAccessCategory.REPRODUCTIVE_HEALTH -> read(
            MenstruationFlowRecord::class, MenstruationPeriodRecord::class, OvulationTestRecord::class,
            CervicalMucusRecord::class, IntermenstrualBleedingRecord::class, SexualActivityRecord::class,
        )
        HealthAccessCategory.MINDFULNESS -> read(MindfulnessSessionRecord::class)
        HealthAccessCategory.WORKOUTS -> read(ExerciseSessionRecord::class)
    }

    /** Permissions for [category] this provider can grant. Empty means the category is unavailable. */
    fun requestable(category: HealthAccessCategory, plan: HealthConnectPermissionPlan): Set<String> =
        declared(category).filterTo(LinkedHashSet()) { it in plan.foregroundPermissions }

    /**
     * Categories the provider can grant but for which no read permission is granted. Categories the
     * provider cannot grant at all are unavailable rather than blocked, and are not reported.
     */
    fun blocked(granted: Set<String>, plan: HealthConnectPermissionPlan): Set<HealthAccessCategory> =
        HealthAccessCategory.entries.filterTo(LinkedHashSet()) { category ->
            val requestable = requestable(category, plan)
            requestable.isNotEmpty() && requestable.none { it in granted }
        }
}
