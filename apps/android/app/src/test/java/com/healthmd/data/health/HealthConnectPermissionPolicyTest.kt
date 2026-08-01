@file:OptIn(androidx.health.connect.client.feature.ExperimentalPersonalHealthRecordApi::class)

package com.healthmd.data.health

import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_HISTORY
import androidx.health.connect.client.permission.HealthPermission.Companion.PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND
import androidx.health.connect.client.records.ActivityIntensityRecord
import androidx.health.connect.client.records.MindfulnessSessionRecord
import androidx.health.connect.client.records.PlannedExerciseSessionRecord
import androidx.health.connect.client.records.SkinTemperatureRecord
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class HealthConnectPermissionPolicyTest {
    @Test
    fun unavailableFeaturesAreExcludedFromEveryPermissionRequest() {
        val plan = HealthConnectPermissionPolicy.create { false }

        assertThat(plan.foregroundPermissions).doesNotContain(
            HealthPermission.getReadPermission(SkinTemperatureRecord::class)
        )
        assertThat(plan.foregroundPermissions).doesNotContain(
            HealthPermission.getReadPermission(MindfulnessSessionRecord::class)
        )
        assertThat(plan.foregroundPermissions).doesNotContain(
            HealthPermission.getReadPermission(PlannedExerciseSessionRecord::class)
        )
        assertThat(plan.foregroundPermissions).doesNotContain(
            HealthPermission.getReadPermission(ActivityIntensityRecord::class)
        )
        assertThat(plan.foregroundPermissions)
            .containsNoneIn(HealthConnectPermissionPolicy.medicalPermissions)
        assertThat(plan.historicalReadPermissions).isEmpty()
        assertThat(plan.backgroundReadPermissions).isEmpty()
        assertThat(plan.historicalReadAvailability)
            .isEqualTo(HealthConnectFeatureAvailability.UNAVAILABLE)
        assertThat(plan.backgroundReadAvailability)
            .isEqualTo(HealthConnectFeatureAvailability.UNAVAILABLE)
    }

    @Test
    fun eachRecordFeatureAddsOnlyItsSupportedPermission() {
        val features = setOf(
            HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE,
            HealthConnectFeatures.FEATURE_MINDFULNESS_SESSION,
            HealthConnectFeatures.FEATURE_PLANNED_EXERCISE,
            HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY,
        )
        val plan = HealthConnectPermissionPolicy.create { it in features }

        assertThat(plan.foregroundPermissions).containsAtLeast(
            HealthPermission.getReadPermission(SkinTemperatureRecord::class),
            HealthPermission.getReadPermission(MindfulnessSessionRecord::class),
            HealthPermission.getReadPermission(PlannedExerciseSessionRecord::class),
            HealthPermission.getReadPermission(ActivityIntensityRecord::class),
        )
        assertThat(plan.foregroundPermissions)
            .containsNoneIn(HealthConnectPermissionPolicy.medicalPermissions)
    }

    @Test
    fun personalHealthRecordFeatureAddsAllMedicalPermissionsAtomically() {
        val plan = HealthConnectPermissionPolicy.create {
            it == HealthConnectFeatures.FEATURE_PERSONAL_HEALTH_RECORD
        }

        assertThat(plan.foregroundPermissions)
            .containsAtLeastElementsIn(HealthConnectPermissionPolicy.medicalPermissions)
        assertThat(
            plan.foregroundPermissions.intersect(HealthConnectPermissionPolicy.medicalPermissions)
        ).hasSize(HealthConnectPermissionPolicy.medicalPermissions.size)
    }

    @Test
    fun featureLookupFailuresRemainDistinctFromUnsupportedFeatures() {
        val plan = HealthConnectPermissionPolicy.createWithAvailability { feature ->
            if (
                feature == HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY ||
                feature == HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND
            ) {
                HealthConnectFeatureAvailability.ERROR
            } else {
                HealthConnectFeatureAvailability.UNAVAILABLE
            }
        }

        assertThat(plan.historicalReadAvailability)
            .isEqualTo(HealthConnectFeatureAvailability.ERROR)
        assertThat(plan.backgroundReadAvailability)
            .isEqualTo(HealthConnectFeatureAvailability.ERROR)
        assertThat(plan.featureStatusCheckFailed).isTrue()
        assertThat(plan.historicalReadPermissions).isEmpty()
        assertThat(plan.backgroundReadPermissions).isEmpty()
    }

    @Test
    fun historyAndBackgroundPermissionsStaySeparateAndFeatureGated() {
        val plan = HealthConnectPermissionPolicy.create {
            it == HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_HISTORY ||
                it == HealthConnectFeatures.FEATURE_READ_HEALTH_DATA_IN_BACKGROUND
        }

        assertThat(plan.foregroundPermissions).doesNotContain(PERMISSION_READ_HEALTH_DATA_HISTORY)
        assertThat(plan.foregroundPermissions)
            .doesNotContain(PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)
        assertThat(plan.historicalReadPermissions)
            .containsExactly(PERMISSION_READ_HEALTH_DATA_HISTORY)
        assertThat(plan.backgroundReadPermissions)
            .containsExactly(PERMISSION_READ_HEALTH_DATA_IN_BACKGROUND)
        assertThat(plan.historicalReadAvailability)
            .isEqualTo(HealthConnectFeatureAvailability.AVAILABLE)
        assertThat(plan.backgroundReadAvailability)
            .isEqualTo(HealthConnectFeatureAvailability.AVAILABLE)
    }
}
