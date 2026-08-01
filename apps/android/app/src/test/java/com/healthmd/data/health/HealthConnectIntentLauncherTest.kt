package com.healthmd.data.health

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class HealthConnectIntentLauncherTest {
    @Test
    fun android13UsesOfficialSettingsActionBeforePlayStoreFallbacks() {
        assertThat(healthConnectSettingsTargets(sdkInt = 33)).containsExactly(
            HealthConnectIntentTarget.HEALTH_CONNECT_SETTINGS,
            HealthConnectIntentTarget.PLAY_STORE_APP,
            HealthConnectIntentTarget.PLAY_STORE_WEB,
        ).inOrder()
    }

    @Test
    fun android14UsesOnlyTheDocumentedHealthConnectSettingsAction() {
        assertThat(healthConnectSettingsTargets(sdkInt = 34)).containsExactly(
            HealthConnectIntentTarget.HEALTH_CONNECT_SETTINGS,
        )
    }

    @Test
    fun permissionResultsDistinguishDeniedPartialAndCompleteGrants() {
        val requested = setOf("steps", "heart_rate")

        assertThat(grantedAnyRequestedHealthPermission(requested, emptySet())).isFalse()
        assertThat(grantedAnyRequestedHealthPermission(requested, setOf("steps"))).isTrue()
        assertThat(grantedAllRequestedHealthPermissions(requested, setOf("steps"))).isFalse()
        assertThat(grantedAllRequestedHealthPermissions(requested, requested)).isTrue()
    }

    @Test
    fun permissionLaunchReportsEmptyAndThrowingRequestsAsFailures() {
        assertThat(tryLaunchHealthConnectPermissions(emptySet()) { }).isFalse()
        assertThat(
            tryLaunchHealthConnectPermissions(setOf("android.permission.health.READ_STEPS")) {
                error("permission activity unavailable")
            }
        ).isFalse()
    }

    @Test
    fun permissionLaunchReportsSuccessfulDispatch() {
        var launched = emptySet<String>()
        val permissions = setOf("android.permission.health.READ_STEPS")

        val result = tryLaunchHealthConnectPermissions(permissions) { launched = it }

        assertThat(result).isTrue()
        assertThat(launched).isEqualTo(permissions)
    }
}
