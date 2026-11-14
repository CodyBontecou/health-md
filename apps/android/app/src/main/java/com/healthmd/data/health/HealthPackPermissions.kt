package com.healthmd.data.health

import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.ActivityIntensityRecord
import androidx.health.connect.client.records.BloodPressureRecord
import androidx.health.connect.client.records.BodyFatRecord
import androidx.health.connect.client.records.CervicalMucusRecord
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
import androidx.health.connect.client.records.RespiratoryRateRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SkinTemperatureRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.TotalCaloriesBurnedRecord
import androidx.health.connect.client.records.WeightRecord
import com.healthmd.domain.onboarding.HealthPack

/**
 * Health Connect read permissions behind each onboarding pack. The onboarding request asks only
 * for the selected packs' record types, intersected with what the installed provider can grant
 * ([HealthConnectPermissionPlan.foregroundPermissions]); background and history access are never
 * part of this request.
 */
object HealthPackPermissions {
    private fun read(vararg types: kotlin.reflect.KClass<out androidx.health.connect.client.records.Record>) =
        types.mapTo(LinkedHashSet()) { HealthPermission.getReadPermission(it) }

    fun declared(pack: HealthPack): Set<String> = when (pack) {
        HealthPack.SLEEP -> read(
            SleepSessionRecord::class, HeartRateVariabilityRmssdRecord::class,
            RestingHeartRateRecord::class, RespiratoryRateRecord::class, SkinTemperatureRecord::class,
        )
        HealthPack.ACTIVITY -> read(
            StepsRecord::class, ActiveCaloriesBurnedRecord::class, TotalCaloriesBurnedRecord::class,
            ExerciseSessionRecord::class, FloorsClimbedRecord::class, DistanceRecord::class,
            ElevationGainedRecord::class, ActivityIntensityRecord::class,
        )
        HealthPack.HEART -> read(HeartRateRecord::class, OxygenSaturationRecord::class, BloodPressureRecord::class)
        HealthPack.BODY -> read(WeightRecord::class, HeightRecord::class, BodyFatRecord::class, LeanBodyMassRecord::class)
        HealthPack.MIND -> read(MindfulnessSessionRecord::class)
        HealthPack.NUTRITION -> read(NutritionRecord::class, HydrationRecord::class)
        HealthPack.CYCLE -> read(
            MenstruationFlowRecord::class, MenstruationPeriodRecord::class, OvulationTestRecord::class,
            CervicalMucusRecord::class, IntermenstrualBleedingRecord::class,
        )
    }

    /** Requestable permissions for one pack on this provider. Empty means the pack is unavailable. */
    fun requestable(pack: HealthPack, plan: HealthConnectPermissionPlan): Set<String> =
        declared(pack).filterTo(LinkedHashSet()) { it in plan.foregroundPermissions }

    fun forPacks(packs: Set<HealthPack>, plan: HealthConnectPermissionPlan): Set<String> =
        packs.flatMapTo(LinkedHashSet()) { requestable(it, plan) }

    fun unavailablePacks(plan: HealthConnectPermissionPlan): Set<HealthPack> =
        HealthPack.entries.filterTo(LinkedHashSet()) { requestable(it, plan).isEmpty() }
}
