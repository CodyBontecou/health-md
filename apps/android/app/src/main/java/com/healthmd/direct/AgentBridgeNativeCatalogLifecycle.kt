package com.healthmd.direct

import com.healthmd.direct.protocol.AgentBridgeErrorCode
import com.healthmd.direct.protocol.AgentBridgeException
import java.util.concurrent.locks.ReentrantLock

/** Native observer state only. The owner records metadata before scheduling publication; readers
 * reject until that exact observation commits. Does not register SDK events, spawn unowned tasks,
 * initialize stores/keys, or grant consent. Fresh SDK sampling remains the native owner's duty. */
internal class AgentBridgeNativeCatalogLifecycle {
    private val lock = Any()
    private val publisher = ReentrantLock()
    private var facts: AgentBridgeNativePlanningFacts? = null
    private var generation = 0L
    private var publishedGeneration: Long? = null
    private var publication: AgentBridgeNativeCatalogPublication? = null
    // A new native owner cannot prove the old owner published its final observation. Advance
    // once rather than accepting an old unexecuted plan. Durable job resume has a separate journal.
    private var observedChange = true
    private var stopped = false
    private var exhausted = false

    fun observe(value: AgentBridgeNativePlanningFacts) = synchronized(lock) {
        requireAvailable()
        // Detach caller-owned mutable collections before retaining native metadata.
        val detached = value.copy(availableNativeMetricIds = value.availableNativeMetricIds.toSet())
        if (facts != detached) {
            if (facts != null) advance()
            facts = detached
        }
    }

    /** Actual native notification, including A→B→A coalesced before deferred SDK sampling. */
    fun observeNativeChange() = synchronized(lock) { requireAvailable(); advance() }

    fun stop() = synchronized(lock) { stopped = true }

    fun currentFacts(): AgentBridgeNativePlanningFacts = synchronized(lock) {
        requireAvailable()
        if (publishedGeneration != generation) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        val value = facts ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
        value.copy(availableNativeMetricIds = value.availableNativeMetricIds.toSet())
    }

    /** Exact return-side revision fence across worker suspension, including equal-facts ABA. */
    fun currentPublication(): AgentBridgeNativeCatalogPublication = synchronized(lock) {
        requireAvailable()
        if (publishedGeneration != generation) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        publication ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
    }

    /** The native owner calls on a worker; the real store enforces the main-looper rejection. */
    fun publish(store: AgentBridgeExportAuthorityStore, sourceInstallationId: String,
        requireOwner: () -> Unit = {}): AgentBridgeNativeCatalogPublication {
        // ReentrantLock.tryLock alone admits same-thread recursion; reject that explicitly too.
        if (publisher.isHeldByCurrentThread || !publisher.tryLock()) fail(AgentBridgeErrorCode.BUSY)
        try {
            requireOwner()
            val captured = synchronized(lock) {
                requireAvailable()
                Triple(generation, observedChange, facts ?: fail(AgentBridgeErrorCode.BINDING_CHANGED))
            }
            val publication = store.publishNativeCatalog(sourceInstallationId, captured.second) {
                requireOwner()
                synchronized(lock) {
                    requireAvailable()
                    if (generation != captured.first || facts != captured.third) fail(AgentBridgeErrorCode.BINDING_CHANGED)
                    captured.third
                }
            }
            requireOwner()
            synchronized(lock) {
                requireAvailable()
                if (generation != captured.first || facts != captured.third) fail(AgentBridgeErrorCode.BINDING_CHANGED)
                this.publication = publication
                publishedGeneration = captured.first
                observedChange = false
            }
            return publication
        } finally { publisher.unlock() }
    }

    private fun advance() {
        if (generation == Long.MAX_VALUE) { exhausted = true; fail(AgentBridgeErrorCode.BUSY) }
        generation++
        observedChange = true
    }
    private fun requireAvailable() {
        if (stopped) fail(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        if (exhausted) fail(AgentBridgeErrorCode.BUSY)
    }
    private fun fail(code: AgentBridgeErrorCode): Nothing = throw AgentBridgeException(code)
}
