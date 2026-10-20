package com.healthmd.data.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.StepsRecord
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.direct.planningFacts
import com.healthmd.direct.fingerprint
import com.healthmd.direct.protocol.*
import io.mockk.*
import java.io.IOException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test

/** Actual manager/permission-policy/record catalog; only Health Connect SDK calls intercepted.
 * Strict clients have no health-read, preview, quota, settings or credential implementations. */
class HealthConnectNativePlanningMetadataTest {
    private val context = mockk<Context>()
    private val client = mockk<HealthConnectClient>()
    private val features = mockk<HealthConnectFeatures>()
    private val permissions = mockk<PermissionController>()
    private val steps = HealthPermission.getReadPermission(StepsRecord::class)
    private val heart = HealthPermission.getReadPermission(HeartRateRecord::class)

    @Before fun setup() {
        mockkObject(HealthConnectClient.Companion)
        every { HealthConnectClient.getSdkStatus(context) } returns HealthConnectClient.SDK_AVAILABLE
        every { client.features } returns features
        every { features.getFeatureStatus(any()) } returns HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
        every { client.permissionController } returns permissions
        coEvery { permissions.getGrantedPermissions() } returns setOf(steps)
    }
    @After fun cleanup() { unmockkObject(HealthConnectClient.Companion) }
    private fun manager() = HealthConnectManager(context, client)

    @Test fun unavailableProviderNeverConstructsOrQueriesClientAndDoesNotInventGrantState() = runTest {
        every { HealthConnectClient.getSdkStatus(context) } returns HealthConnectClient.SDK_UNAVAILABLE
        val metadata = manager().nativePlanningMetadata()
        assertThat(metadata.providerAvailable).isFalse()
        assertThat(metadata.availableNativeMetricIds).isEmpty()
        assertThat(metadata.hasAnyForegroundReadPermission).isNull()
        assertThat(metadata.grantedPermissionsSha256).isNull()
        verify { client wasNot Called }
    }

    @Test fun availableMetadataUsesOnlyFeatureAndPermissionLookupsAndSamplesEachFeatureOnce() = runTest {
        val metadata = manager().nativePlanningMetadata()
        assertThat(metadata.providerAvailable).isTrue()
        assertThat(metadata.availableNativeMetricIds).containsExactlyElementsIn(HealthMetrics.allMetrics.map { it.id })
        assertThat(metadata.hasAnyForegroundReadPermission).isTrue()
        assertThat(metadata.grantedPermissionsSha256).matches("[0-9a-f]{64}")
        assertThat(metadata.failedFeatureChecks).isEmpty()
        verify { client.features }
        verify(exactly = 1) { client.permissionController }
        verify { features.getFeatureStatus(any()) }
        verify(exactly = 1) { features.getFeatureStatus(HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE) }
        coVerify(exactly = 1) { permissions.getGrantedPermissions() }
        confirmVerified(client, features, permissions)
    }

    @Test fun unavailableAndFailedRecordFeaturesOmitTheirMetricsWithoutInventingProviderAbsence() = runTest {
        every { features.getFeatureStatus(any()) } returns HealthConnectFeatures.FEATURE_STATUS_UNAVAILABLE
        every { features.getFeatureStatus(HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE) } throws IOException("synthetic")
        val metadata = manager().nativePlanningMetadata()
        assertThat(metadata.providerAvailable).isTrue()
        assertThat(metadata.availableNativeMetricIds).contains("steps")
        assertThat(metadata.availableNativeMetricIds).containsNoneOf("skin_temperature", "mindful_minutes", "planned_workouts", "activity_intensity_minutes")
        assertThat(metadata.failedFeatureChecks).containsExactly(HealthConnectFeatures.FEATURE_SKIN_TEMPERATURE)
        assertThat(metadata.hasAnyForegroundReadPermission).isTrue()
    }

    @Test fun failedPermissionLookupIsUnknownRatherThanGrantedOrExplicitlyDenied() = runTest {
        coEvery { permissions.getGrantedPermissions() } throws IOException("synthetic")
        val metadata = manager().nativePlanningMetadata()
        assertThat(metadata.providerAvailable).isTrue()
        assertThat(metadata.hasAnyForegroundReadPermission).isNull()
        assertThat(metadata.grantedPermissionsSha256).isNull()
        assertThat(metadata.availableNativeMetricIds).contains("steps")
    }

    @Test fun permissionDigestIsOrderIndependentButChangesForDifferentGrantsWithSameSummary() = runTest {
        var granted = linkedSetOf(steps, heart)
        coEvery { permissions.getGrantedPermissions() } answers { granted }
        val manager = manager()
        val first = manager.nativePlanningMetadata()
        granted = linkedSetOf(heart, steps)
        assertThat(manager.nativePlanningMetadata().grantedPermissionsSha256).isEqualTo(first.grantedPermissionsSha256)
        granted = linkedSetOf(heart)
        val changed = manager.nativePlanningMetadata()
        assertThat(changed.hasAnyForegroundReadPermission).isTrue()
        assertThat(first.hasAnyForegroundReadPermission).isTrue()
        assertThat(changed.grantedPermissionsSha256).isNotEqualTo(first.grantedPermissionsSha256)
        val source = "00000000-0000-4000-8000-000000000001"
        val beforeFacts = first.planningFacts(source, "UTC", AgentBridgeDiscoveryConfigurationProtection.LOCKED,
            AgentBridgeDiscoveryEntitlement.REQUIRED, true, true)
        val afterFacts = changed.planningFacts(source, "UTC", AgentBridgeDiscoveryConfigurationProtection.LOCKED,
            AgentBridgeDiscoveryEntitlement.REQUIRED, true, true)
        assertThat(beforeFacts.nativeGrants).isEqualTo(AgentBridgeDiscoveryNativeGrants.SATISFIED)
        assertThat(afterFacts.nativeGrants).isEqualTo(beforeFacts.nativeGrants)
        assertThat(afterFacts.entitlement).isEqualTo(AgentBridgeDiscoveryEntitlement.REQUIRED)
        assertThat(afterFacts.fingerprint(source)).isNotEqualTo(beforeFacts.fingerprint(source))
    }

    @Test fun cancellationIsPropagatedInsteadOfBeingReinterpretedAsUnknownPermission() = runTest {
        val cancellation = CancellationException("synthetic")
        coEvery { permissions.getGrantedPermissions() } throws cancellation
        var caught: CancellationException? = null
        try { manager().nativePlanningMetadata() } catch (error: CancellationException) { caught = error }
        assertThat(caught).isSameInstanceAs(cancellation)
    }

    @Test fun featureCancellationStopsBeforeAnyPermissionLookup() = runTest {
        val cancellation = CancellationException("synthetic feature cancellation")
        every { features.getFeatureStatus(any()) } throws cancellation
        var caught: CancellationException? = null
        try { manager().nativePlanningMetadata() } catch (error: CancellationException) { caught = error }
        assertThat(caught).isSameInstanceAs(cancellation)
        verify(exactly = 0) { client.permissionController }
        coVerify(exactly = 0) { permissions.getGrantedPermissions() }
    }

    @Test fun providerLossDuringPermissionLookupClearsAvailabilityAndGrantObservation() = runTest {
        every { HealthConnectClient.getSdkStatus(context) } returnsMany listOf(HealthConnectClient.SDK_AVAILABLE, HealthConnectClient.SDK_UNAVAILABLE)
        val metadata = manager().nativePlanningMetadata()
        assertThat(metadata.providerAvailable).isFalse()
        assertThat(metadata.availableNativeMetricIds).isEmpty()
        assertThat(metadata.hasAnyForegroundReadPermission).isNull()
        assertThat(metadata.grantedPermissionsSha256).isNull()
    }
}
