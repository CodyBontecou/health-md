package com.healthmd.direct

import android.app.Activity
import org.robolectric.Robolectric
import android.content.Intent
import android.os.Looper
import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.*
import java.nio.file.Files
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.RuntimeEnvironment
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/** Actual ContextCompat registration/receiver/teardown in the SDK sandbox, plus real private issuer
 * publication. Synthetic broadcasts are not physical OS event or installed Service qualification. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AgentBridgeNativeCatalogBroadcastsTest {
    @Test fun activityReturnInvalidatesSynchronouslyAndUnregistersAtServiceTeardown() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val facts = AgentBridgeNativePlanningFacts(setOf("steps"), f.peer.sourceInstallationId, "UTC",
                AgentBridgeDiscoveryConfigurationProtection.LOCKED, AgentBridgeDiscoveryNativeGrants.SATISFIED,
                AgentBridgeDiscoveryEntitlement.SATISFIED, true, true)
            val lifecycle = AgentBridgeNativeCatalogLifecycle()
            lifecycle.observe(facts)
            val first = runBlocking(Dispatchers.IO) { lifecycle.publish(f.store, f.peer.sourceInstallationId) }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            val observations = java.util.concurrent.atomic.AtomicInteger()
            val events = AgentBridgeNativeCatalogActivityEvents(RuntimeEnvironment.getApplication()) {
                observations.incrementAndGet()
                lifecycle.recordNativeEvent()
            }
            val activity = Robolectric.buildActivity(Activity::class.java)
            try {
                activity.create().start().resume()
                assertThat(observations.get()).isEqualTo(1)
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
                assertThat(Files.readAllBytes(file)).isEqualTo(before)
                val next = runBlocking(Dispatchers.IO) { lifecycle.publish(f.store, f.peer.sourceInstallationId) }
                assertThat(next.revision).isEqualTo(first.revision + 1)
                activity.pause().resume() // Includes return after native settings/permissions review.
                assertThat(observations.get()).isEqualTo(2)
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
                runBlocking(Dispatchers.IO) { lifecycle.publish(f.store, f.peer.sourceInstallationId) }
                events.close(); events.close()
                activity.pause().resume()
                assertThat(observations.get()).isEqualTo(2)
                assertThat(lifecycle.currentFacts()).isEqualTo(facts)
            } finally { events.close(); activity.pause().stop().destroy(); lifecycle.stop() }
        }
    }

    @Test fun sdkBroadcastsInvalidateBeforeWorkerPublicationAndUnregisterAtOwnerTeardown() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val facts = AgentBridgeNativePlanningFacts(setOf("steps"), f.peer.sourceInstallationId, "UTC",
                AgentBridgeDiscoveryConfigurationProtection.LOCKED, AgentBridgeDiscoveryNativeGrants.SATISFIED,
                AgentBridgeDiscoveryEntitlement.SATISFIED, true, true)
            val lifecycle = AgentBridgeNativeCatalogLifecycle()
            lifecycle.observe(facts)
            val first = runBlocking(Dispatchers.IO) { lifecycle.publish(f.store, f.peer.sourceInstallationId) }
            val context = RuntimeEnvironment.getApplication()
            val broadcasts = AgentBridgeNativeCatalogBroadcasts(context, lifecycle::observeNativeChange)
            try {
                val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
                val before = Files.readAllBytes(file)
                context.sendBroadcast(Intent(Intent.ACTION_TIMEZONE_CHANGED))
                context.sendBroadcast(Intent(Intent.ACTION_USER_UNLOCKED))
                shadowOf(Looper.getMainLooper()).idle()
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
                assertThat(Files.readAllBytes(file)).isEqualTo(before)
                val next = runBlocking(Dispatchers.IO) { lifecycle.publish(f.store, f.peer.sourceInstallationId) }
                assertThat(next.revision).isEqualTo(first.revision + 1)
                assertThat(next.factsSha256).isEqualTo(first.factsSha256)
                broadcasts.close()
                broadcasts.close()
                context.sendBroadcast(Intent(Intent.ACTION_TIMEZONE_CHANGED))
                shadowOf(Looper.getMainLooper()).idle()
                assertThat(lifecycle.currentFacts()).isEqualTo(facts)
            } finally { broadcasts.close(); lifecycle.stop() }
        }
    }

    @Test fun ordinaryScreenLockAndUnrelatedBroadcastsDoNotRepresentFirstUnlock() {
        val context = RuntimeEnvironment.getApplication()
        var observations = 0
        AgentBridgeNativeCatalogBroadcasts(context) { observations++ }.use {
            context.sendBroadcast(Intent(Intent.ACTION_SCREEN_OFF))
            context.sendBroadcast(Intent("synthetic.unrelated"))
            shadowOf(Looper.getMainLooper()).idle()
            assertThat(observations).isEqualTo(0)
            context.sendBroadcast(Intent(Intent.ACTION_USER_UNLOCKED))
            shadowOf(Looper.getMainLooper()).idle()
            assertThat(observations).isEqualTo(1)
        }
    }
}
