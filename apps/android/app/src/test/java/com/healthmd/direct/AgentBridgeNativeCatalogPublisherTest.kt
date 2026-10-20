package com.healthmd.direct

import android.os.Looper
import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.*
import java.nio.file.Files
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import kotlinx.coroutines.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AgentBridgeNativeCatalogPublisherTest {
    private fun lifecycle(f: AgentBridgeExportPlanningFixture) = AgentBridgeNativeCatalogLifecycle().also {
        it.observe(AgentBridgeNativePlanningFacts(setOf("steps"), f.peer.sourceInstallationId, "UTC",
            AgentBridgeDiscoveryConfigurationProtection.LOCKED, AgentBridgeDiscoveryNativeGrants.SATISFIED,
            AgentBridgeDiscoveryEntitlement.SATISFIED, true, true))
    }

    private suspend fun expect(code: AgentBridgeErrorCode, block: suspend () -> Any?) {
        try { block(); throw AssertionError("Expected fixed native failure") }
        catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(code) }
    }

    private suspend fun finalCheckCount(): Int = AgentBridgeExportPlanningFixture().use { f ->
        f.store.initialize(f.native)
        val peer = WorkerPeer(f.peer)
        AgentBridgeNativeCatalogPublisher.publish(lifecycle(f), peer) { f.store }
        peer.checks.get()
    }

    @Test fun sampleRejectsEventsAcrossSuspensionAndWorkerAdmission() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            val first = AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            val facts = lifecycle.currentFacts()
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            val sampling = lifecycle.beginSample()
            yield()
            lifecycle.observeNativeChange()
            expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.observe(facts, sampling) }
            val accepted = lifecycle.observe(facts, lifecycle.beginSample())
            lifecycle.observeNativeChange()
            expect(AgentBridgeErrorCode.BINDING_CHANGED) {
                AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer, accepted) { f.store }
            }
            assertThat(Files.readAllBytes(file)).isEqualTo(before)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
            val fresh = lifecycle.observe(facts, lifecycle.beginSample())
            val next = AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer, fresh) { f.store }
            assertThat(next.revision).isGreaterThan(first.revision)
        }
    }

    @Test fun sampleBindsExactOwnerAndChangedFactsGeneration() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            AgentBridgeNativeCatalogPublisher.publish(lifecycle, WorkerPeer(f.peer)) { f.store }
            val facts = lifecycle.currentFacts()
            val ticket = lifecycle.beginSample()
            expect(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeNativeCatalogLifecycle().observe(facts, ticket) }
            lifecycle.observe(facts.copy(sourceCalendarTimezone = "Europe/London"), ticket)
            expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.observe(facts, ticket) }
            val stopped = lifecycle.beginSample()
            lifecycle.stop()
            expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.observe(facts, stopped) }
            expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.beginSample() }
        }
    }

    @Test fun workerUsesExistingStoreOffMainAndPreservesUnchangedPublication() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            val first = AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) {
                assertThat(Looper.myLooper()).isNotEqualTo(Looper.getMainLooper())
                f.store
            }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            val second = AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            assertThat(second).isEqualTo(first)
            assertThat(lifecycle.currentPublication()).isEqualTo(first)
            assertThat(Files.readAllBytes(file)).isEqualTo(before)
        }
    }

    @Test fun ownerRevocationAtRealStagedAndPostFsyncBoundariesSuppressesReturn() = runBlocking {
        for (afterSync in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            val root = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
            val file = root.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            val observed = AtomicBoolean()
            peer.onCheck = {
                val reached = if (afterSync) !Files.readAllBytes(file).contentEquals(before)
                    else Files.list(root).use { paths -> paths.anyMatch { it.fileName.toString().startsWith("pending-") } }
                if (reached) { observed.set(true); peer.allowed.set(false) }
            }
            expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) {
                AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            }
            assertThat(observed.get()).isTrue()
            assertThat(!Files.readAllBytes(file).contentEquals(before)).isEqualTo(afterSync)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
        }
    }

    @Test fun cancellationDuringKeyReadLeavesOldCachePendingAndPreservesCancellationOutcome() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            val entered = CountDownLatch(1)
            val release = CountDownLatch(1)
            f.keys.onLoad = { entered.countDown(); check(release.await(5, TimeUnit.SECONDS)) }
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val task = scope.async { AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store } }
            try {
                assertThat(entered.await(5, TimeUnit.SECONDS)).isTrue()
                task.cancel()
                release.countDown()
                try { task.await(); throw AssertionError("Canceled publication returned success") }
                catch (_: CancellationException) { }
                task.join()
                assertThat(Files.readAllBytes(file)).isEqualTo(before)
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
            } finally { release.countDown(); scope.cancel(); task.join() }
        }
    }

    @Test fun cancellationDuringFinalNativeTrustCallbackCannotReturnSuccess() = runBlocking {
        val count = finalCheckCount()
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            val job = SupervisorJob()
            val scope = CoroutineScope(job + Dispatchers.Default)
            val observed = AtomicBoolean()
            peer.onCheck = { if (it == count) { observed.set(true); job.cancel() } }
            val task = scope.async { AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store } }
            try {
                try { task.await(); throw AssertionError("Final native callback canceled but returned success") }
                catch (_: CancellationException) { }
                task.join()
                assertThat(observed.get()).isTrue()
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
            } finally { scope.cancel(); task.join() }
        }
    }

    @Test fun newerSameFactsABAPublicationDuringFinalTrustCallbackRejectsOldResult() = runBlocking(Dispatchers.Default) {
        val count = finalCheckCount()
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            val observed = AtomicBoolean()
            peer.onCheck = {
                if (it == count) {
                    observed.set(true)
                    lifecycle.observeNativeChange()
                    lifecycle.publish(f.store, f.peer.sourceInstallationId)
                }
            }
            expect(AgentBridgeErrorCode.BINDING_CHANGED) {
                AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            }
            assertThat(observed.get()).isTrue()
            assertThat(f.store.access { it?.state?.nativeCatalog?.revision }).isEqualTo(2)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
        }
    }

    @Test fun alreadyCancelledCallDoesNotReadPeerOrOpenStore() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            val peer = WorkerPeer(f.peer)
            val loads = AtomicInteger()
            val task = async(start = CoroutineStart.UNDISPATCHED) {
                currentCoroutineContext().cancel()
                AgentBridgeNativeCatalogPublisher.publish(lifecycle(f), peer) { loads.incrementAndGet(); f.store }
            }
            try { task.await(); throw AssertionError("Already canceled publication returned success") }
            catch (_: CancellationException) { }
            assertThat(loads.get()).isEqualTo(0)
            assertThat(peer.checks.get()).isEqualTo(0)
        }
    }

    @Test fun missingStoreCannotCreatePrivateRootOrReadKey() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            val lifecycle = lifecycle(f)
            expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) {
                AgentBridgeNativeCatalogPublisher.publish(lifecycle, WorkerPeer(f.peer)) { f.store }
            }
            assertThat(Files.exists(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
            assertThat(f.keys.calls).isEqualTo(0)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
        }
    }

    @Test fun finalNativePeerRebindingCannotReplaceThePinnedIdentity() = runBlocking {
        val count = finalCheckCount()
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            peer.onCheck = { if (it == count) peer.identity.set(f.peer.copy(hostInstallationId = AgentBridgeExportPlanningFixture.id(12))) }
            expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) {
                AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
        }
    }

    private class WorkerPeer(initial: AgentBridgePeer) : AgentBridgeExportAuthenticatedPeer() {
        val identity = AtomicReference(initial)
        val allowed = AtomicBoolean(true)
        val checks = AtomicInteger()
        @Volatile var onCheck: ((Int) -> Unit)? = null
        override fun requireCurrent(): AgentBridgePeer {
            val count = checks.incrementAndGet()
            onCheck?.invoke(count)
            if (!allowed.get()) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
            return identity.get()
        }
    }
}
