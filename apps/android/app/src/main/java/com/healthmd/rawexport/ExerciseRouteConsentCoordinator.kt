package com.healthmd.rawexport

import androidx.health.connect.client.records.ExerciseRoute
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull

/**
 * App-wide mediator for Health Connect's per-session exercise route consent.
 *
 * The Activity Result contract has no request identifier in its result. This coordinator therefore
 * owns the in-flight request across Activity/configuration recreation and never launches a second
 * request until the first result has been consumed. A timeout or cancellation abandons the request
 * but keeps its result slot occupied; a late result is drained and can never satisfy a newer run.
 */
@Singleton
class ExerciseRouteConsentCoordinator @Inject constructor() : ExerciseRouteConsentGateway {

    /** UI surface able to launch the Health Connect per-session consent activity. */
    interface Surface {
        /** Returns true only when the request was handed to an Activity Result launcher. */
        fun launchRouteRequest(session: PendingExerciseRouteConsent): Boolean
    }

    private data class DeliveredResult(val route: ExerciseRoute?)

    private data class ActiveRequest(
        val result: CompletableDeferred<DeliveredResult>,
        var abandoned: Boolean = false,
    )

    private sealed interface PromptOutcome {
        data object NotLaunched : PromptOutcome
        data class Completed(val route: ExerciseRoute?) : PromptOutcome
    }

    private val promptMutex = Mutex()

    @Volatile
    private var surface: Surface? = null

    private var activeRequest: ActiveRequest? = null

    fun attach(surface: Surface) {
        this.surface = surface
    }

    fun detach(surface: Surface) {
        if (this.surface === surface) this.surface = null
        // Do not complete or discard activeRequest. The Activity Result registry rebinds its
        // callback after configuration recreation while the ViewModel export coroutine survives.
    }

    /**
     * Delivers the single Activity Result contract result. There is intentionally no session
     * argument: the contract does not return one. Serialization plus the retained active slot is
     * what makes this association safe.
     */
    fun onRouteResult(route: ExerciseRoute?) {
        val completion = synchronized(this) {
            val active = activeRequest ?: return
            activeRequest = null
            if (active.abandoned) null else active.result
        }
        completion?.complete(DeliveredResult(route))
    }

    override suspend fun requestRoutes(sessions: List<PendingExerciseRouteConsent>): Map<String, ExerciseRoute> {
        val run = currentCoroutineContext()[InteractiveRouteConsent] ?: return emptyMap()
        val candidates = sessions
            .distinctBy { it.sessionId }
            .sortedWith(compareByDescending<PendingExerciseRouteConsent> { it.sessionStartTime }.thenBy { it.sessionId })
        if (candidates.isEmpty()) return emptyMap()

        return promptMutex.withLock {
            val granted = linkedMapOf<String, ExerciseRoute>()
            for (candidate in candidates) {
                currentCoroutineContext().ensureActive()
                val cached = run.grantedRoute(candidate.sessionId)
                if (cached != null) {
                    granted[candidate.sessionId] = cached
                    continue
                }
                if (!canLaunchPrompt() || !run.reservePrompt(candidate.sessionId)) continue
                when (val outcome = prompt(candidate)) {
                    PromptOutcome.NotLaunched -> Unit
                    is PromptOutcome.Completed -> outcome.route?.let { route ->
                        run.recordGrantedRoute(candidate.sessionId, route)
                        granted[candidate.sessionId] = route
                    }
                }
            }
            granted
        }
    }

    private fun canLaunchPrompt(): Boolean = surface != null && synchronized(this) { activeRequest == null }

    private suspend fun prompt(candidate: PendingExerciseRouteConsent): PromptOutcome {
        val activeSurface = surface ?: return PromptOutcome.NotLaunched
        val active = ActiveRequest(result = CompletableDeferred())
        synchronized(this) {
            // A timed-out/cancelled request remains here until its late result is drained.
            if (activeRequest != null || surface !== activeSurface) return PromptOutcome.NotLaunched
            activeRequest = active
        }

        val launched = try {
            activeSurface.launchRouteRequest(candidate)
        } catch (_: Exception) {
            false
        }
        if (!launched) {
            synchronized(this) {
                if (activeRequest === active) activeRequest = null
            }
            return PromptOutcome.NotLaunched
        }

        return try {
            val delivered = withTimeoutOrNull(PROMPT_TIMEOUT_MS) { active.result.await() }
            if (delivered == null) {
                abandon(active)
                PromptOutcome.Completed(null)
            } else {
                PromptOutcome.Completed(delivered.route)
            }
        } catch (cancelled: CancellationException) {
            abandon(active)
            throw cancelled
        } catch (_: Exception) {
            abandon(active)
            PromptOutcome.Completed(null)
        }
    }

    private fun abandon(request: ActiveRequest) {
        synchronized(this) {
            if (activeRequest === request) request.abandoned = true
        }
    }

    companion object {
        /** Global upper bound shared by every read in one interactive export run. */
        const val MAX_PROMPTS_PER_EXPORT = 10

        /** Safety timeout for one abandoned dialog so an export cannot hang forever. */
        internal const val PROMPT_TIMEOUT_MS = 5 * 60_000L
    }
}
