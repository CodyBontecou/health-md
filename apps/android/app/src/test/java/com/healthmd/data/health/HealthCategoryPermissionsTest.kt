package com.healthmd.data.health

import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.StepsRecord
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthAccessCategory
import com.healthmd.presentation.export.ExportUiState
import org.junit.Test

class HealthCategoryPermissionsTest {
    private val sleep = HealthPermission.getReadPermission(SleepSessionRecord::class)
    private val steps = HealthPermission.getReadPermission(StepsRecord::class)
    private val heartRate = HealthPermission.getReadPermission(HeartRateRecord::class)

    private fun plan(foreground: Set<String>) = HealthConnectPermissionPlan(
        foregroundPermissions = foreground,
        historicalReadPermissions = emptySet(),
        backgroundReadPermissions = emptySet(),
        historicalReadAvailability = HealthConnectFeatureAvailability.AVAILABLE,
        backgroundReadAvailability = HealthConnectFeatureAvailability.AVAILABLE,
    )

    @Test
    fun `issue 220 - steps granted without sleep reports sleep as blocked`() {
        val blocked = HealthCategoryPermissions.blocked(
            granted = setOf(steps),
            plan = plan(setOf(sleep, steps, heartRate)),
        )

        assertThat(blocked).containsAtLeast(HealthAccessCategory.SLEEP, HealthAccessCategory.HEART)
        assertThat(blocked).doesNotContain(HealthAccessCategory.ACTIVITY)
    }

    @Test
    fun `categories the provider cannot grant are unavailable, not blocked`() {
        val blocked = HealthCategoryPermissions.blocked(granted = setOf(steps), plan = plan(setOf(steps)))

        assertThat(blocked).isEmpty()
    }

    @Test
    fun `full grant blocks nothing`() {
        val all = HealthAccessCategory.entries.flatMapTo(LinkedHashSet()) { HealthCategoryPermissions.declared(it) }

        assertThat(HealthCategoryPermissions.blocked(granted = all, plan = plan(all))).isEmpty()
    }

    @Test
    fun `export state reports only selected blocked categories while connected`() {
        val selection = DataTypeSelection().deselectAll().copy(sleep = true, activity = true)
        val state = ExportUiState(
            settings = ExportSettings(dataTypes = selection),
            hasPermissions = true,
            blockedReadCategories = setOf(HealthAccessCategory.SLEEP, HealthAccessCategory.HEART),
        )

        assertThat(state.missingAccessCategories).containsExactly(HealthAccessCategory.SLEEP)
        assertThat(state.copy(hasPermissions = false).missingAccessCategories).isEmpty()
        assertThat(
            state.copy(settings = ExportSettings(dataTypes = selection.copy(sleep = false))).missingAccessCategories
        ).isEmpty()
    }
}
