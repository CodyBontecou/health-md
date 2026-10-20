package com.healthmd.direct

import kotlinx.coroutines.flow.collectLatest

import com.healthmd.direct.protocol.AgentBridgeErrorCode
import com.healthmd.direct.protocol.AgentBridgeException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.takeWhile
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Native controller worker only. The factory opens existing storage; no health/metadata sampling,
 * key/store/grant creation, wire route or detached/unowned coroutine is introduced here. */
internal object AgentBridgeNativeCatalogPublisher {
    /** Native-only refresh; a failed/suspended sampler never reopens older cached readiness. */
    suspend fun refresh(lifecycle: AgentBridgeNativeCatalogLifecycle, peer: AgentBridgeExportAuthenticatedPeer,
        sample: suspend () -> AgentBridgeNativePlanningFacts,
        loadStore: () -> AgentBridgeExportAuthorityStore): AgentBridgeNativeCatalogPublication {
        val caller = currentCoroutineContext()
        caller.ensureActive()
        val started = lifecycle.beginSample()
        try {
            val original = peer.requireCurrent()
            caller.ensureActive()
            val facts = sample()
            caller.ensureActive()
            if (peer.requireCurrent() != original) fail(AgentBridgeErrorCode.PERMISSION_REQUIRED)
            caller.ensureActive()
            val accepted = lifecycle.observe(facts, started)
            return publish(lifecycle, peer, accepted, loadStore)
        } catch (failure: Exception) {
            runCatching { lifecycle.observeNativeChange() }
            caller.ensureActive()
            throw failure
        }
    }

    suspend fun publish(lifecycle: AgentBridgeNativeCatalogLifecycle, peer: AgentBridgeExportAuthenticatedPeer,
        sample: AgentBridgeNativeCatalogLifecycle.Sample? = null, loadStore: () -> AgentBridgeExportAuthorityStore): AgentBridgeNativeCatalogPublication {
        val caller = currentCoroutineContext()
        caller.ensureActive()
        try {
            val (publication, original) = withContext(Dispatchers.IO) {
                val worker = currentCoroutineContext()
                worker.ensureActive()
                val original = peer.requireCurrent()
                worker.ensureActive()
                fun requireOwner() {
                    worker.ensureActive()
                    caller.ensureActive()
                    if (peer.requireCurrent() != original) fail(AgentBridgeErrorCode.PERMISSION_REQUIRED)
                    worker.ensureActive()
                    caller.ensureActive()
                }
                val store = loadStore()
                lifecycle.publish(store, original.sourceInstallationId, ::requireOwner, sample) to original
            }
            caller.ensureActive()
            if (peer.requireCurrent() != original) fail(AgentBridgeErrorCode.PERMISSION_REQUIRED)
            caller.ensureActive()
            if (lifecycle.currentPublication() != publication) fail(AgentBridgeErrorCode.BINDING_CHANGED)
            caller.ensureActive()
            return publication
        } catch (failure: Exception) {
            runCatching { lifecycle.observeNativeChange() } // May have crossed rename/fsync; retain pending.
            // The synchronous private store maps unknown exceptions to fixed errors. Preserve actual
            // coroutine cancellation rather than exposing that mapped storage error as its outcome.
            caller.ensureActive()
            throw failure
        }
    }

    private fun fail(code: AgentBridgeErrorCode): Nothing = throw AgentBridgeException(code)
}


/** Serial child of the native service scope. Native events coalesce behind in-flight SDK/store
 * work; failures wait for another event, and scope cancellation permanently closes this owner. */
internal class AgentBridgeNativeCatalogRefresh(
    scope: CoroutineScope,
    private val lifecycle: AgentBridgeNativeCatalogLifecycle,
    refresh: suspend () -> Unit,
) : AutoCloseable {
    private val events = lifecycle.claimRefreshEvents()
    private val job = scope.launch(Dispatchers.IO, start = CoroutineStart.LAZY) {
        try {
            events.takeWhile { it != null }.collect {
                currentCoroutineContext().ensureActive()
                try { refresh() }
                catch (failure: CancellationException) { throw failure }
                catch (_: Exception) { runCatching { lifecycle.observeNativeChange() } }
            }
        } finally { lifecycle.stop() }
    }
    // A canceled parent can prevent the body from starting, so finally alone is insufficient.
    init { job.invokeOnCompletion { lifecycle.stop() } }
    fun start() { job.start() }
    override fun close() { job.cancel(); lifecycle.stop() }
}


/** Native owner signal only. The foreground service supplies existing dependencies;
 * the wire handler never runs SDK/store work. The collectLatest child owns its refresh
 * controller, so replacement/registration close cannot leave a sampler running. */
internal class AgentBridgeNativeCatalogAdmissionOwner(
    val lifecycle: AgentBridgeNativeCatalogLifecycle,
    val start: (kotlinx.coroutines.CoroutineScope) -> Unit,
)

internal class AgentBridgeNativeCatalogAdmission(scope: kotlinx.coroutines.CoroutineScope,
    owners: kotlinx.coroutines.flow.Flow<AgentBridgeNativeCatalogAdmissionOwner?>) : AutoCloseable {
    private val job = scope.launch(kotlinx.coroutines.Dispatchers.IO) {
        owners.collectLatest { owner ->
            if (owner != null) kotlinx.coroutines.coroutineScope {
                try {
                    owner.lifecycle.beginSample()
                    owner.start(this)
                    kotlinx.coroutines.awaitCancellation()
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    throw cancelled
                } catch (_: Exception) {
                    owner.lifecycle.stop()
                } finally {
                    owner.lifecycle.stop()
                }
            }
        }
    }
    override fun close() { job.cancel() }
}
