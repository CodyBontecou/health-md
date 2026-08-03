package com.healthmd.widget.data

import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import com.healthmd.data.health.HealthConnectFeatureAvailability
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.WidgetDataRequirements
import javax.inject.Inject
import kotlin.reflect.KClass

object WidgetHealthPermissionPolicy {
    fun foregroundPermissions(requirements: WidgetDataRequirements): Set<String> = buildSet {
        if (requirements.activity) {
            add(HealthPermission.getReadPermission(StepsRecord::class))
            add(HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class))
            add(HealthPermission.getReadPermission(ExerciseSessionRecord::class))
        }
        if (requirements.sleep) {
            add(HealthPermission.getReadPermission(SleepSessionRecord::class))
        }
        if (requirements.heart) {
            add(HealthPermission.getReadPermission(HeartRateRecord::class))
            add(HealthPermission.getReadPermission(RestingHeartRateRecord::class))
            add(HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class))
        }
    }

    fun kindsWithoutAnyGrantedPermission(
        kinds: Set<HealthWidgetKind>,
        grantedPermissions: Set<String>,
    ): Set<HealthWidgetKind> = kinds.filterTo(linkedSetOf()) { kind ->
        foregroundPermissions(WidgetDataRequirements.forKind(kind))
            .none { it in grantedPermissions }
    }

    fun readSelection(
        requirements: WidgetDataRequirements,
        grantedPermissions: Set<String>,
    ): HealthConnectWidgetReadSelection = HealthConnectWidgetReadSelection(
        steps = requirements.activity && StepsRecord::class.readPermission() in grantedPermissions,
        activeCalories = requirements.activity &&
            ActiveCaloriesBurnedRecord::class.readPermission() in grantedPermissions,
        exerciseSessions = requirements.activity &&
            ExerciseSessionRecord::class.readPermission() in grantedPermissions,
        sleepSessions = requirements.sleep &&
            SleepSessionRecord::class.readPermission() in grantedPermissions,
        heartRate = requirements.heart && HeartRateRecord::class.readPermission() in grantedPermissions,
        restingHeartRate = requirements.heart &&
            RestingHeartRateRecord::class.readPermission() in grantedPermissions,
        hrvRmssd = requirements.heart &&
            HeartRateVariabilityRmssdRecord::class.readPermission() in grantedPermissions,
    )

    private fun KClass<out Record>.readPermission(): String =
        HealthPermission.getReadPermission(this)
}

data class WidgetHealthPermissionStatus(
    val requestedForegroundPermissions: Set<String>,
    val grantedForegroundPermissions: Set<String>,
    val missingForegroundPermissions: Set<String>,
    val backgroundPermissions: Set<String>,
    val backgroundAvailability: HealthConnectFeatureAvailability,
    val backgroundGranted: Boolean,
) {
    val hasAnyForegroundPermission: Boolean
        get() = requestedForegroundPermissions.isNotEmpty() && grantedForegroundPermissions.isNotEmpty()

    val hasAllForegroundPermissions: Boolean
        get() = requestedForegroundPermissions.isNotEmpty() && missingForegroundPermissions.isEmpty()

    val canRefreshInBackground: Boolean
        get() = hasAllForegroundPermissions &&
            backgroundAvailability == HealthConnectFeatureAvailability.AVAILABLE &&
            backgroundPermissions.isNotEmpty() &&
            backgroundGranted
}

class WidgetHealthPermissionManager @Inject constructor(
    private val healthConnectManager: HealthConnectManager,
) {
    fun foregroundPermissions(requirements: WidgetDataRequirements): Set<String> =
        WidgetHealthPermissionPolicy.foregroundPermissions(requirements)

    fun backgroundPermissions(): Set<String> =
        healthConnectManager.permissionPlan().backgroundReadPermissions

    suspend fun status(requirements: WidgetDataRequirements): WidgetHealthPermissionStatus {
        val requestedForeground = foregroundPermissions(requirements)
        val permissionPlan = healthConnectManager.permissionPlan()
        val granted = healthConnectManager.getGrantedPermissions()
        val grantedForeground = requestedForeground.intersect(granted)
        val backgroundPermissions = permissionPlan.backgroundReadPermissions
        return WidgetHealthPermissionStatus(
            requestedForegroundPermissions = requestedForeground,
            grantedForegroundPermissions = grantedForeground,
            missingForegroundPermissions = requestedForeground - granted,
            backgroundPermissions = backgroundPermissions,
            backgroundAvailability = permissionPlan.backgroundReadAvailability,
            backgroundGranted = backgroundPermissions.isNotEmpty() &&
                granted.containsAll(backgroundPermissions),
        )
    }
}
