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
    private fun nativeFacts(f: AgentBridgeExportPlanningFixture) = AgentBridgeNativePlanningFacts(
        setOf("steps"), f.peer.sourceInstallationId, "UTC",
        AgentBridgeDiscoveryConfigurationProtection.LOCKED, AgentBridgeDiscoveryNativeGrants.SATISFIED,
        AgentBridgeDiscoveryEntitlement.SATISFIED, true, true)

    private fun lifecycle(f: AgentBridgeExportPlanningFixture) = AgentBridgeNativeCatalogLifecycle().also {
        it.observe(nativeFacts(f))
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

    @Test fun authorityGrantAndRevokeInvalidateSameOwnerAfterStoreUnlock() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f); val peer = WorkerPeer(f.peer); val facts = nativeFacts(f)
            val first = AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            val observation = AgentBridgeNativeAuthorityChanges.observe { lifecycle.recordNativeEvent() }
            try {
                withContext(Dispatchers.IO) { f.store.putDelegation(f.native, f.delegation(), 0) }
                expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
                val next = AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
                assertThat(next.revision).isEqualTo(first.revision + 1)
                withContext(Dispatchers.IO) { f.store.revoke(f.native, f.peer, f.delegation().authorityId, 1) }
                assertThat(withContext(Dispatchers.IO) { f.store.access { it!!.state.grants.single().revoked } }).isTrue()
                expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
                assertThat(AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }.revision).isEqualTo(next.revision + 1)
                assertThat(lifecycle.currentFacts()).isEqualTo(facts)
            } finally { observation.close(); lifecycle.stop() }
        }
    }

    @Test fun authoritySetupAndFailedAuthorizedWriteEmitButDeniedAttemptDoesNot() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f); val peer = WorkerPeer(f.peer); val facts = nativeFacts(f)
            AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            val observation = AgentBridgeNativeAuthorityChanges.observe { lifecycle.recordNativeEvent() }
            try {
                AgentBridgeExportPlanningFixture().use { fresh ->
                    fresh.native.allowed = false
                    expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { withContext(Dispatchers.IO) { fresh.store.initialize(fresh.native) } }
                    assertThat(lifecycle.currentFacts()).isEqualTo(facts)
                    fresh.native.allowed = true
                    withContext(Dispatchers.IO) { fresh.store.initialize(fresh.native) }
                    expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
                }
                AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
                f.native.allowed = false
                expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { withContext(Dispatchers.IO) { f.store.putDelegation(f.native, f.delegation(), 0) } }
                assertThat(lifecycle.currentFacts()).isEqualTo(facts)
                f.native.allowed = true
                expect(AgentBridgeErrorCode.REVISION_CONFLICT) { withContext(Dispatchers.IO) { f.store.putDelegation(f.native, f.delegation(), 9) } }
                assertThat(withContext(Dispatchers.IO) { f.store.access { it!!.state.grants.size } }).isEqualTo(0)
                expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
            } finally { observation.close(); lifecycle.stop() }
        }
    }

    @Test fun authorityReadsPublicationAndClosedRegistrationDoNotInvalidateOrRevive() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f); val peer = WorkerPeer(f.peer); val facts = nativeFacts(f)
            val first = AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            val observation = AgentBridgeNativeAuthorityChanges.observe { lifecycle.recordNativeEvent() }
            try {
                withContext(Dispatchers.IO) { f.store.access { it!!.state } }
                assertThat(AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }).isEqualTo(first)
                observation.close(); observation.close()
                withContext(Dispatchers.IO) { f.store.putDelegation(f.native, f.delegation(), 0) }
                assertThat(lifecycle.currentFacts()).isEqualTo(facts)
                lifecycle.stop()
                withContext(Dispatchers.IO) { f.store.revoke(f.native, f.peer, f.delegation().authorityId, 1) }
                expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.currentFacts() }
            } finally { observation.close(); lifecycle.stop() }
        }
    }

    @Test fun initialReadinessWaitsForColdOwnedPublicationWithoutStartingOrCancelingIt() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); val peer = WorkerPeer(f.peer)
            val facts = nativeFacts(f); val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
            val owners = kotlinx.coroutines.flow.MutableStateFlow<AgentBridgeNativeCatalogAdmissionOwner?>(null)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val admission = AgentBridgeNativeCatalogAdmission(scope, owners)
            val ready = async(start = CoroutineStart.UNDISPATCHED) { withTimeout(3000) { lifecycle.awaitInitialPublication() } }
            try {
                assertThat(ready.isCompleted).isFalse()
                assertThat(peer.checks.get()).isEqualTo(0)
                val canceled = async(start = CoroutineStart.UNDISPATCHED) { lifecycle.awaitInitialPublication() }
                canceled.cancelAndJoin()
                assertThat(canceled.isCancelled).isTrue()
                owners.value = AgentBridgeNativeCatalogAdmissionOwner(lifecycle) { child ->
                    AgentBridgeNativeCatalogRefresh(child, lifecycle) {
                        AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, {
                            entered.complete(Unit); release.await(); facts
                        }) { f.store }
                    }.start()
                }
                withTimeout(3000) { entered.await() }
                assertThat(ready.isCompleted).isFalse()
                expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
                release.complete(Unit)
                assertThat(ready.await()).isEqualTo(lifecycle.currentPublication())
                admission.close()
                withTimeout(3000) { scope.coroutineContext.job.children.forEach { it.join() } }
                expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.awaitInitialPublication() }
            } finally {
                ready.cancelAndJoin(); admission.close(); scope.cancel(); scope.coroutineContext.job.join()
            }
        }
    }

    @Test fun initialReadinessFailureRejectsWithoutWaitingForAnotherNativeEvent() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); val peer = WorkerPeer(f.peer)
            val ready = async(start = CoroutineStart.UNDISPATCHED) {
                runCatching { withTimeout(3000) { lifecycle.awaitInitialPublication() } }
            }
            expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) {
                AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, {
                    throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
                }) { throw AssertionError("A failed sample cannot open issuer storage") }
            }
            assertThat((ready.await().exceptionOrNull() as AgentBridgeException).code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED)
            // A later event cannot revive this session's failed initial admission.
            AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, { nativeFacts(f) }) { f.store }
            expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.awaitInitialPublication() }
            lifecycle.stop()
            expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.awaitInitialPublication() }
        }
    }

    @Test fun initialReadinessRejectsNativeSetupFailureBeforePublisherEntry() = runBlocking {
        val lifecycle = AgentBridgeNativeCatalogLifecycle()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val ready = async(start = CoroutineStart.UNDISPATCHED) {
            runCatching { withTimeout(3000) { lifecycle.awaitInitialPublication() } }
        }
        val controller = AgentBridgeNativeCatalogRefresh(scope, lifecycle) {
            throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        }
        try {
            controller.start()
            assertThat((ready.await().exceptionOrNull() as AgentBridgeException).code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED)
        } finally { ready.cancelAndJoin(); controller.close(); scope.cancel(); scope.coroutineContext.job.join() }
    }

    @Test fun admissionPublishesWithOwnedChildAndCloseCancelsIt() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f); val peer = WorkerPeer(f.peer)
            val facts = nativeFacts(f)
            val published = CompletableDeferred<Unit>(); val ended = CompletableDeferred<Unit>()
            val owners = kotlinx.coroutines.flow.MutableStateFlow<AgentBridgeNativeCatalogAdmissionOwner?>(null)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val admission = AgentBridgeNativeCatalogAdmission(scope, owners)
            try {
                owners.value = AgentBridgeNativeCatalogAdmissionOwner(lifecycle) { child ->
                    AgentBridgeNativeCatalogRefresh(child, lifecycle) {
                        try {
                            AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, { facts }) { f.store }
                            published.complete(Unit)
                            awaitCancellation()
                        } finally { ended.complete(Unit) }
                    }.start()
                }
                withTimeout(3000) { published.await() }
                assertThat(lifecycle.currentFacts()).isEqualTo(facts)
                admission.close()
                withTimeout(3000) { ended.await() }
                expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.beginSample() }
            } finally { admission.close(); scope.cancel(); scope.coroutineContext.job.join() }
        }
    }

    @Test fun admissionReplacementCancelsSuspendedOldOwnerBeforeFreshPublication() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val old = lifecycle(f); val current = lifecycle(f); val peer = WorkerPeer(f.peer)
            val facts = nativeFacts(f)
            val entered = CompletableDeferred<Unit>(); val ended = CompletableDeferred<Unit>(); val published = CompletableDeferred<Unit>()
            val owners = kotlinx.coroutines.flow.MutableStateFlow<AgentBridgeNativeCatalogAdmissionOwner?>(null)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val admission = AgentBridgeNativeCatalogAdmission(scope, owners)
            val oldReady = async(start = CoroutineStart.UNDISPATCHED) {
                runCatching { withTimeout(3000) { old.awaitInitialPublication() } }
            }
            try {
                owners.value = AgentBridgeNativeCatalogAdmissionOwner(old) { child ->
                    AgentBridgeNativeCatalogRefresh(child, old) {
                        try { entered.complete(Unit); awaitCancellation() } finally { ended.complete(Unit) }
                    }.start()
                }
                withTimeout(3000) { entered.await() }
                owners.value = AgentBridgeNativeCatalogAdmissionOwner(current) { child ->
                    AgentBridgeNativeCatalogRefresh(child, current) {
                        AgentBridgeNativeCatalogPublisher.refresh(current, peer, { facts }) { f.store }
                        published.complete(Unit)
                    }.start()
                }
                withTimeout(3000) { ended.await(); published.await() }
                assertThat((oldReady.await().exceptionOrNull() as AgentBridgeException).code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED)
                assertThat(current.awaitInitialPublication()).isEqualTo(current.currentPublication())
                expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { old.beginSample() }
                assertThat(current.currentFacts()).isEqualTo(facts)
            } finally { admission.close(); scope.cancel(); scope.coroutineContext.job.join() }
        }
    }

    @Test fun admissionRejectsStoppedOwnerAndContinuesWithNextNativeIdentity() = runBlocking {
        val stopped = AgentBridgeNativeCatalogLifecycle().also { it.stop() }
        val fresh = AgentBridgeNativeCatalogLifecycle()
        val owners = kotlinx.coroutines.flow.MutableStateFlow<AgentBridgeNativeCatalogAdmissionOwner?>(null)
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
        val admitted = CompletableDeferred<Unit>()
        val admission = AgentBridgeNativeCatalogAdmission(scope, owners)
        try {
            owners.value = AgentBridgeNativeCatalogAdmissionOwner(stopped) { throw AssertionError("Closed owner entered SDK") }
            delay(150)
            owners.value = AgentBridgeNativeCatalogAdmissionOwner(fresh) { admitted.complete(Unit) }
            withTimeout(3000) { admitted.await() }
            admission.close()
        } finally { admission.close(); scope.cancel(); scope.coroutineContext.job.join() }
        expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { fresh.beginSample() }
    }

    @Test fun controllerSerializesAndCoalescesEventsAcrossActualPublication() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            val facts = lifecycle.currentFacts()
            val entered = CompletableDeferred<Unit>(); val release = CompletableDeferred<Unit>()
            val published = CompletableDeferred<Unit>()
            val calls = AtomicInteger()
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val controller = AgentBridgeNativeCatalogRefresh(scope, lifecycle) {
                AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, {
                    if (calls.incrementAndGet() == 1) { entered.complete(Unit); release.await() }
                    facts
                }) { f.store }
                published.complete(Unit)
            }
            try {
                controller.start()
                withTimeout(3000) { entered.await() }
                lifecycle.recordNativeEvent(); lifecycle.recordNativeEvent()
                expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
                expect(AgentBridgeErrorCode.BUSY) { lifecycle.claimRefreshEvents() }
                assertThat(calls.get()).isEqualTo(1)
                release.complete(Unit)
                withTimeout(3000) { published.await() }
                delay(150) // A duplicate queued event would create an unwanted third SDK sample.
                assertThat(calls.get()).isEqualTo(2)
                assertThat(lifecycle.currentFacts()).isEqualTo(facts)
            } finally { controller.close(); scope.cancel() }
        }
    }

    @Test fun controllerFailureWaitsForNativeEventWithoutSelfRetry() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f); val peer = WorkerPeer(f.peer)
            AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            val facts = lifecycle.currentFacts()
            val failed = CompletableDeferred<Unit>(); val published = CompletableDeferred<Unit>()
            val calls = AtomicInteger()
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val controller = AgentBridgeNativeCatalogRefresh(scope, lifecycle) {
                if (calls.incrementAndGet() == 1) { failed.complete(Unit); throw AgentBridgeException(AgentBridgeErrorCode.BUSY) }
                AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, { facts }) { f.store }
                published.complete(Unit)
            }
            try {
                controller.start()
                withTimeout(3000) { failed.await() }
                delay(150)
                assertThat(calls.get()).isEqualTo(1)
                expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
                lifecycle.recordNativeEvent()
                withTimeout(3000) { published.await() }
                assertThat(calls.get()).isEqualTo(2)
                assertThat(lifecycle.currentFacts()).isEqualTo(facts)
            } finally { controller.close(); scope.cancel() }
        }
    }

    @Test fun controllerScopeCancellationAndClosePermanentlyStopNativeOwner() = runBlocking {
        for (cancelScope in listOf(false, true)) {
            val lifecycle = AgentBridgeNativeCatalogLifecycle()
            val entered = CompletableDeferred<Unit>(); val ended = CompletableDeferred<Unit>()
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            val controller = AgentBridgeNativeCatalogRefresh(scope, lifecycle) {
                try { entered.complete(Unit); awaitCancellation() }
                finally { ended.complete(Unit) }
            }
            try {
                controller.start()
                withTimeout(3000) { entered.await() }
                if (cancelScope) scope.coroutineContext.job.cancelAndJoin() else controller.close()
                withTimeout(3000) { ended.await() }
                expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.beginSample() }
                expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.recordNativeEvent() }
                controller.start() // Job.start never renews a canceled child.
            } finally { controller.close(); scope.cancel() }
        }
        val closed = AgentBridgeNativeCatalogLifecycle()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default).also { it.cancel() }
        val controller = AgentBridgeNativeCatalogRefresh(scope, closed) { throw AssertionError("Canceled scope sampled SDK") }
        controller.start()
        expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { closed.beginSample() }
    }

    @Test fun refreshComposesNativeMetadataAndPreservesUnchangedPublication() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = AgentBridgeNativeCatalogLifecycle()
            val peer = WorkerPeer(f.peer)
            val metadata = com.healthmd.data.health.HealthConnectNativePlanningMetadata(true, setOf("steps"), true, "a".repeat(64), emptySet())
            val facts = metadata.planningFacts(f.peer.sourceInstallationId, "UTC",
                AgentBridgeDiscoveryConfigurationProtection.LOCKED, AgentBridgeDiscoveryEntitlement.REQUIRED, true, true)
            val first = AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, { yield(); facts }) { f.store }
            assertThat(lifecycle.currentFacts()).isEqualTo(facts)
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            val next = AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, { facts }) { f.store }
            assertThat(next).isEqualTo(first)
            assertThat(Files.readAllBytes(file)).isEqualTo(before)
        }
    }

    @Test fun failedStaleOrRevokedSamplerCannotOpenIssuerOrReuseCache() = runBlocking {
        for (outcome in listOf("failed", "event", "revoked")) AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            val facts = lifecycle.currentFacts()
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            val code = when(outcome) { "failed" -> AgentBridgeErrorCode.BUSY; "event" -> AgentBridgeErrorCode.BINDING_CHANGED; else -> AgentBridgeErrorCode.PERMISSION_REQUIRED }
            expect(code) {
                AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, {
                    yield()
                    when(outcome) {
                        "failed" -> throw AgentBridgeException(AgentBridgeErrorCode.BUSY)
                        "event" -> lifecycle.observeNativeChange()
                        "revoked" -> peer.allowed.set(false)
                    }
                    facts
                }) { throw AssertionError("Rejected sampler opened issuer storage") }
            }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
            assertThat(Files.readAllBytes(file)).isEqualTo(before)
        }
    }

    @Test fun refreshCancellationRejectsBeforeStoreAndBeforePreCancelledSampler() = runBlocking {
        for (duringSample in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = lifecycle(f)
            val peer = WorkerPeer(f.peer)
            AgentBridgeNativeCatalogPublisher.publish(lifecycle, peer) { f.store }
            val facts = lifecycle.currentFacts()
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
            try {
                val task = scope.async {
                    if (!duringSample) currentCoroutineContext().job.cancel()
                    AgentBridgeNativeCatalogPublisher.refresh(lifecycle, peer, {
                        assertThat(duringSample).isTrue()
                        currentCoroutineContext().job.cancel()
                        facts
                    }) { throw AssertionError("Canceled refresh opened issuer storage") }
                }
                try { task.await(); throw AssertionError("Canceled refresh returned success") }
                catch (_: CancellationException) { }
                if (duringSample) f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentPublication() }
                else assertThat(lifecycle.currentFacts()).isEqualTo(facts)
            } finally { scope.cancel() }
        }
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
