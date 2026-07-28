package com.healthmd.data.attribution

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton

/** Starts attribution discovery off the main thread and never lets it affect app startup. */
@Singleton
class CampaignAttributionInitializer @Inject constructor(
    private val orchestrator: CampaignAttributionOrchestrator,
) {
    private val started = AtomicBoolean(false)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun start() {
        if (!started.compareAndSet(false, true)) return
        scope.launch {
            try {
                orchestrator.processStartup()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // Never attach throwable details: an implementation error must not leak referrer data.
                Timber.w("Campaign attribution initialization failed safely")
            }
        }
    }
}
