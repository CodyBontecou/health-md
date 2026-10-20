package com.healthmd.direct

import com.healthmd.direct.protocol.AgentBridgeErrorCode
import com.healthmd.direct.protocol.AgentBridgeException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/** Native controller worker only. The factory opens existing storage; no health/metadata sampling,
 * key/store/grant creation, wire route or detached/unowned coroutine is introduced here. */
internal object AgentBridgeNativeCatalogPublisher {
    suspend fun publish(lifecycle: AgentBridgeNativeCatalogLifecycle, peer: AgentBridgeExportAuthenticatedPeer,
        loadStore: () -> AgentBridgeExportAuthorityStore): AgentBridgeNativeCatalogPublication {
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
                lifecycle.publish(store, original.sourceInstallationId, ::requireOwner) to original
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
