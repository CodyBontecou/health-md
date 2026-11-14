package com.healthmd.direct

import com.healthmd.domain.billing.FreemiumPolicy
import com.healthmd.domain.repository.NativeExportEligibilitySettings
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.catch
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.onStart
import kotlinx.coroutines.launch

/** Native service-owned observations only. Sampling never collects preferences, refreshes billing,
 * queries health or grants execution/resume authority. Errors remain closed until a new owner. */
internal class AgentBridgeNativeExportEligibility(
    private val settings: Flow<NativeExportEligibilitySettings?>,
    private val unlocked: StateFlow<Boolean>,
    private val included: Boolean,
    private val changed: () -> Unit,
) : AutoCloseable {
    private val lock = Any()
    private var started = false
    private var closed = false
    private var observation: NativeExportEligibilitySettings? = null
    private var billingObservation: Boolean? = null
    private var eligible = false
    private var job: Job? = null

    fun start(scope: CoroutineScope) {
        synchronized(lock) { check(!started && !closed); started = true }
        val launched = scope.launch(start = CoroutineStart.UNDISPATCHED) {
            try {
                if (included) {
                    publish(null, false)
                    awaitCancellation() // Still bind included access to this native owner's lifetime.
                } else {
                    val observedSettings = settings.catch { error ->
                        if (error is CancellationException) throw error
                        emit(null) // Unknown quota cannot become a fresh free allowance.
                    }.onStart { emit(null) } // Known billing access need not await private quota storage.
                    combine(observedSettings, unlocked) { value, billing -> value to billing }
                        .collect { (value, billing) -> publish(value, billing) }
                }
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // No fallback preferences or billing refresh, and no private storage error logging.
            } finally {
                close()
            }
        }
        synchronized(lock) { job = launched; if (closed) launched.cancel() }
    }

    fun current(): Boolean = synchronized(lock) {
        // A billing emission may be queued behind the native observer. Do not sample stale access.
        started && !closed && eligible && (included || billingObservation == unlocked.value)
    }

    private fun publish(value: NativeExportEligibilitySettings?, billing: Boolean) = synchronized(lock) {
        if (closed) return@synchronized
        if (observation == value && billingObservation == billing) return@synchronized
        observation = value
        billingObservation = billing
        eligible = included || billing || (value != null && value.freeExportsUsed >= 0 &&
            FreemiumPolicy.canExport(value.purchased || billing, value.freeExportsUsed))
        changed() // Latch each observed quota/purchase transition before returning to the collector.
    }

    override fun close() = synchronized(lock) {
        if (!closed) {
            closed = true
            eligible = false
            changed()
            job?.cancel()
        }
    }
}
