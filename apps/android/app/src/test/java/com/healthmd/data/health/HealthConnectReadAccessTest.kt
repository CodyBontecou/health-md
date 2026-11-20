package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import com.healthmd.R
import com.healthmd.presentation.settings.healthConnectStatusLabel
import org.junit.Test

class HealthConnectReadAccessTest {
    private val steps = "android.permission.health.READ_STEPS"
    private val heartRate = "android.permission.health.READ_HEART_RATE"
    private val sleep = "android.permission.health.READ_SLEEP"
    private val requested = setOf(steps, heartRate, sleep)

    @Test
    fun `every requested grant is all`() {
        val access = HealthConnectReadAccess(requested, requested + "android.permission.health.READ_HEALTH_DATA_HISTORY")

        assertThat(access.state).isEqualTo(HealthConnectReadAccessState.ALL)
        assertThat(access.grantedCount).isEqualTo(3)
        assertThat(access.missing).isEmpty()
    }

    @Test
    fun `a single grant is partial, not allowed`() {
        val access = HealthConnectReadAccess(requested, setOf(steps))

        assertThat(access.state).isEqualTo(HealthConnectReadAccessState.PARTIAL)
        assertThat(access.grantedCount).isEqualTo(1)
        assertThat(access.missing).containsExactly(heartRate, sleep)
    }

    @Test
    fun `no requested grant is none, even with unrelated grants`() {
        assertThat(HealthConnectReadAccess(requested, emptySet()).state).isEqualTo(HealthConnectReadAccessState.NONE)
        assertThat(HealthConnectReadAccess(requested, setOf("android.permission.health.READ_HEALTH_DATA_IN_BACKGROUND")).state)
            .isEqualTo(HealthConnectReadAccessState.NONE)
        assertThat(HealthConnectReadAccess.NONE.state).isEqualTo(HealthConnectReadAccessState.NONE)
    }

    @Test
    fun `settings label matches each state`() {
        assertThat(healthConnectStatusLabel(HealthConnectReadAccessState.ALL)).isEqualTo(R.string.settings_status_allowed)
        assertThat(healthConnectStatusLabel(HealthConnectReadAccessState.PARTIAL))
            .isEqualTo(R.string.settings_status_partly_allowed)
        assertThat(healthConnectStatusLabel(HealthConnectReadAccessState.NONE)).isEqualTo(R.string.settings_status_not_allowed)
    }
}
