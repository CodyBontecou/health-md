package com.healthmd.direct

import com.healthmd.direct.protocol.AgentBridgeErrorCode
import com.healthmd.direct.protocol.AgentBridgeException
import java.util.concurrent.locks.ReentrantLock
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.ensureActive

/** Native observer state only. The owner records metadata before scheduling publication; readers
 * reject until that exact observation commits. Does not register SDK events, spawn unowned tasks,
 * initialize stores/keys, or grant consent. Fresh SDK sampling remains the native owner's duty. */
internal class AgentBridgeNativeCatalogLifecycle {
    /** Native-only ticket, retaining exact owner identity across suspended SDK sampling. */
    class Sample internal constructor(internal val owner: AgentBridgeNativeCatalogLifecycle, internal val generation: Long)
    private val refreshEvents = kotlinx.coroutines.flow.MutableStateFlow<Long?>(0L)
    private var refreshClaimed = false
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
    private val initialPublication = kotlinx.coroutines.CompletableDeferred<Unit>()

    /** One collector per accepted owner; initial state catches events preceding registration. */
    fun claimRefreshEvents(): kotlinx.coroutines.flow.StateFlow<Long?> = synchronized(lock) {
        requireAvailable()
        if (refreshClaimed) fail(AgentBridgeErrorCode.BUSY)
        refreshClaimed = true
        refreshEvents.asStateFlow()
    }

    /** Native events wake deferred refresh only after latching the pending generation. Failures
     * use observeNativeChange instead, avoiding self-scheduled retries against unavailable storage. */
    fun recordNativeEvent() = synchronized(lock) {
        requireAvailable()
        advance()
        refreshEvents.value = generation
    }

    fun beginSample(): Sample = synchronized(lock) {
        requireAvailable()
        Sample(this, generation)
    }

    fun observe(value: AgentBridgeNativePlanningFacts, sampledDuring: Sample): Sample = synchronized(lock) {
        requireAvailable()
        if (sampledDuring.owner !== this || sampledDuring.generation != generation) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        observe(value)
        Sample(this, generation)
    }

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

    /** Local original-owner liveness only. Pending catalog refresh conveys no read authority. */
    fun requireActiveOwner() = synchronized(lock) { requireAvailable() }

    fun stop() {
        synchronized(lock) { stopped = true; refreshEvents.value = null }
        initialPublication.completeExceptionally(AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED))
    }

    /** Wait for this exact native owner's first publication attempt. No sampling, storage
     * opening, owner renewal or retry is triggered by a waiting receiver. */
    suspend fun awaitInitialPublication(): AgentBridgeNativeCatalogPublication {
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        synchronized(lock) { requireAvailable() }
        initialPublication.await()
        kotlinx.coroutines.currentCoroutineContext().ensureActive()
        return currentPublication()
    }

    fun failInitialPublication() {
        initialPublication.completeExceptionally(AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED))
    }

    fun completeInitialPublication(publication: AgentBridgeNativeCatalogPublication) {
        if (currentPublication() != publication) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        initialPublication.complete(Unit)
    }

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
        requireOwner: () -> Unit = {}, sample: Sample? = null): AgentBridgeNativeCatalogPublication {
        // ReentrantLock.tryLock alone admits same-thread recursion; reject that explicitly too.
        if (publisher.isHeldByCurrentThread || !publisher.tryLock()) fail(AgentBridgeErrorCode.BUSY)
        try {
            requireOwner()
            val captured = synchronized(lock) {
                requireAvailable()
                if (sample != null && (sample.owner !== this || sample.generation != generation)) fail(AgentBridgeErrorCode.BINDING_CHANGED)
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


/** Process-local native issuer event. Payload-free callbacks only invalidate/schedule; no SDK,
 * key or issuer reads run here. Exact close fences even a previously captured registration. */
internal object AgentBridgeNativeAuthorityChanges {
    private val observers = java.util.concurrent.CopyOnWriteArrayList<Registration>()
    private class Registration(private val listener: () -> Unit) : AutoCloseable {
        private var active = true
        fun signal() = synchronized(this) { if (active) listener() }
        override fun close() {
            synchronized(this) { active = false }
            observers.remove(this)
        }
    }
    fun observe(listener: () -> Unit): AutoCloseable = Registration(listener).also { observers.add(it) }
    private fun post() { observers.forEach { runCatching { it.signal() } } }
    /** The caller already passed native authorization. Emit after locks unwind, including an
     * ambiguous failed write; never for initial authorization denial or ordinary store reads. */
    fun <T> mutation(operation: () -> T): T = try { operation() } finally { post() }
}
