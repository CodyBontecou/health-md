package com.healthmd.widget

import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.ActiveCaloriesBurnedRecord
import androidx.health.connect.client.records.ExerciseSessionRecord
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.HeartRateVariabilityRmssdRecord
import androidx.health.connect.client.records.RestingHeartRateRecord
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthConnectFeatureAvailability
import com.healthmd.widget.data.WidgetHealthPermissionPolicy
import com.healthmd.widget.data.WidgetHealthPermissionStatus
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.WidgetDataRequirements
import org.junit.Test

class WidgetHealthPermissionPolicyTest {
    @Test
    fun `summary requests exactly the seven displayed Health Connect record types`() {
        val permissions = WidgetHealthPermissionPolicy.foregroundPermissions(
            WidgetDataRequirements(activity = true, sleep = true, heart = true),
        )

        assertThat(permissions).containsExactly(
            HealthPermission.getReadPermission(StepsRecord::class),
            HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
            HealthPermission.getReadPermission(ExerciseSessionRecord::class),
            HealthPermission.getReadPermission(SleepSessionRecord::class),
            HealthPermission.getReadPermission(HeartRateRecord::class),
            HealthPermission.getReadPermission(RestingHeartRateRecord::class),
            HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class),
        )
    }

    @Test
    fun `permission gaps are tracked per installed widget kind`() {
        val granted = WidgetHealthPermissionPolicy.foregroundPermissions(
            WidgetDataRequirements(activity = true),
        )

        val missingKinds = WidgetHealthPermissionPolicy.kindsWithoutAnyGrantedPermission(
            kinds = setOf(HealthWidgetKind.ACTIVITY, HealthWidgetKind.HEART_RANGE),
            grantedPermissions = granted,
        )

        assertThat(missingKinds).containsExactly(HealthWidgetKind.HEART_RANGE)
    }

    @Test
    fun `read selection never probes denied record families`() {
        val selection = WidgetHealthPermissionPolicy.readSelection(
            requirements = WidgetDataRequirements(activity = true, sleep = true, heart = true),
            grantedPermissions = setOf(
                HealthPermission.getReadPermission(StepsRecord::class),
                HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class),
            ),
        )

        assertThat(selection.steps).isTrue()
        assertThat(selection.hrvRmssd).isTrue()
        assertThat(selection.activeCalories).isFalse()
        assertThat(selection.exerciseSessions).isFalse()
        assertThat(selection.sleepSessions).isFalse()
        assertThat(selection.heartRate).isFalse()
        assertThat(selection.restingHeartRate).isFalse()
        assertThat(selection.oxygenSaturation).isFalse()
    }

    @Test
    fun `phone widgets never request or select oxygen they do not display`() {
        val oxygen = HealthPermission.getReadPermission(OxygenSaturationRecord::class)
        val permissions = WidgetHealthPermissionPolicy.foregroundPermissions(
            WidgetDataRequirements(activity = true, sleep = true, heart = true),
        )
        val selection = WidgetHealthPermissionPolicy.readSelection(
            WidgetDataRequirements(activity = true, sleep = true, heart = true),
            grantedPermissions = permissions + oxygen,
        )

        assertThat(permissions).doesNotContain(oxygen)
        assertThat(selection.oxygenSaturation).isFalse()
    }

    @Test
    fun `background refresh requires every foreground permission`() {
        val status = WidgetHealthPermissionStatus(
            requestedForegroundPermissions = setOf("steps", "calories"),
            grantedForegroundPermissions = setOf("steps"),
            missingForegroundPermissions = setOf("calories"),
            backgroundPermissions = setOf("background"),
            backgroundAvailability = HealthConnectFeatureAvailability.AVAILABLE,
            backgroundGranted = true,
        )

        assertThat(status.hasAnyForegroundPermission).isTrue()
        assertThat(status.canRefreshInBackground).isFalse()
    }

    @Test
    fun `focused widgets do not request unrelated health records`() {
        assertThat(
            WidgetHealthPermissionPolicy.foregroundPermissions(
                WidgetDataRequirements(activity = true),
            )
        ).containsExactly(
            HealthPermission.getReadPermission(StepsRecord::class),
            HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class),
            HealthPermission.getReadPermission(ExerciseSessionRecord::class),
        )
        assertThat(
            WidgetHealthPermissionPolicy.foregroundPermissions(
                WidgetDataRequirements(sleep = true),
            )
        ).containsExactly(HealthPermission.getReadPermission(SleepSessionRecord::class))
    }
}
