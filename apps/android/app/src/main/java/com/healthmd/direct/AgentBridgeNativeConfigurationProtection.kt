package com.healthmd.direct

import com.healthmd.domain.repository.NativeConfigurationProtectionObservation
import com.healthmd.domain.repository.NativeConfigurationProtectionSource
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.launch

/** Service-owned native observations. Null is unknown; request sampling is memory-only. */
internal class AgentBridgeNativeConfigurationProtection(
    private val source: NativeConfigurationProtectionSource?,
    private val changed: () -> Unit,
) : AutoCloseable {
    private val lock = Any()
    private var started = false
    private var closed = false
    private var observation: NativeConfigurationProtectionObservation? = null
    private var subscription: AutoCloseable? = null
    private var job: Job? = null

    fun start(scope: CoroutineScope) {
        synchronized(lock) {
            check(!started && !closed)
            started = true
            subscription = source?.observeChanges { _ ->
                synchronized(lock) {
                    if (!closed) {
                        observation = null
                        changed() // Latch before native persistence; stale queued images cannot reopen.
                    }
                }
            }
        }
        val launched = scope.launch(start = CoroutineStart.UNDISPATCHED) {
            try {
                if (source == null) awaitCancellation()
                else source.observations.catch { error ->
                    if (error is CancellationException) throw error
                    emit(null)
                }.collect { value ->
                    synchronized(lock) {
                        if (!closed && (value == null || matchesCurrentRevision(value))) {
                            if (observation != value) {
                                observation = value
                                changed()
                            }
                        }
                    }
                }
            } finally {
                close()
            }
        }
        synchronized(lock) { job = launched; if (closed) launched.cancel() }
    }

    fun current(): Boolean? = synchronized(lock) {
        if (started && !closed) observation?.takeIf(::matchesCurrentRevision)?.enabled else null
    }

    private fun matchesCurrentRevision(value: NativeConfigurationProtectionObservation): Boolean {
        val expected = source?.currentRevision()
        return expected == null || value.revision == expected
    }

    override fun close() = synchronized(lock) {
        if (!closed) {
            closed = true
            observation = null
            subscription?.close()
            subscription = null
            changed()
            job?.cancel()
        }
    }
}
