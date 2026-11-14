package com.healthmd.data.health

import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.MenstruationFlowRecord
import androidx.health.connect.client.records.MindfulnessSessionRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.onboarding.HealthPack
import org.junit.Test

class HealthPackPermissionsTest {
    private val fullPlan = HealthConnectPermissionPolicy.create { true }
    private val basicPlan = HealthConnectPermissionPolicy.create { false }

    @Test
    fun requestAsksOnlyForTheSelectedPacksForegroundTypes() {
        val request = HealthPackPermissions.forPacks(setOf(HealthPack.SLEEP, HealthPack.ACTIVITY), fullPlan)

        assertThat(request).contains(HealthPermission.getReadPermission(SleepSessionRecord::class))
        assertThat(request).contains(HealthPermission.getReadPermission(StepsRecord::class))
        assertThat(request).doesNotContain(HealthPermission.getReadPermission(MenstruationFlowRecord::class))
        // Background and history access are requested later, never with the pack request.
        assertThat(request).containsNoneIn(fullPlan.backgroundReadPermissions + fullPlan.historicalReadPermissions)
        assertThat(fullPlan.foregroundPermissions).containsAtLeastElementsIn(request)
    }

    @Test
    fun everyPackMapsToDeclaredForegroundPermissions() {
        HealthPack.entries.forEach { pack ->
            assertThat(HealthPackPermissions.requestable(pack, fullPlan)).isNotEmpty()
        }
    }

    @Test
    fun mindIsUnavailableWithoutTheMindfulnessFeature() {
        val mindfulness = HealthPermission.getReadPermission(MindfulnessSessionRecord::class)
        assertThat(HealthPackPermissions.requestable(HealthPack.MIND, basicPlan)).doesNotContain(mindfulness)
        assertThat(HealthPackPermissions.unavailablePacks(basicPlan)).containsExactly(HealthPack.MIND)

        val mindOnly = HealthConnectPermissionPolicy.create { it == HealthConnectFeatures.FEATURE_MINDFULNESS_SESSION }
        assertThat(HealthPackPermissions.unavailablePacks(mindOnly)).isEmpty()
    }
}
