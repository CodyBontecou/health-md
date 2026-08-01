package com.healthmd.presentation.schedule

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class ScheduleHealthProviderAccessTest {
    @Test
    fun directHealthConnectSelectionRequiresBackgroundAccess() {
        assertThat(
            requiresHealthConnectBackgroundAccess(
                selectedProviderId = "health_connect",
                connectedProviderIds = setOf("health_connect"),
            )
        ).isTrue()
    }

    @Test
    fun cloudOnlySelectionDoesNotPromptForHealthConnectAccess() {
        assertThat(
            requiresHealthConnectBackgroundAccess(
                selectedProviderId = "oura",
                connectedProviderIds = setOf("oura"),
            )
        ).isFalse()
    }

    @Test
    fun allConnectedOnlyRequiresAccessWhenHealthConnectIsIncluded() {
        assertThat(
            requiresHealthConnectBackgroundAccess(
                selectedProviderId = "all_connected",
                connectedProviderIds = setOf("oura", "health_connect"),
            )
        ).isTrue()
        assertThat(
            requiresHealthConnectBackgroundAccess(
                selectedProviderId = "all_connected",
                connectedProviderIds = setOf("oura", "fitbit"),
            )
        ).isFalse()
    }
}
