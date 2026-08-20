package com.healthmd.rawexport

import androidx.health.connect.client.records.ExerciseRoute
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withTimeoutOrNull

/**
 * App-wide mediator for Health Connect's per-session exercise route consent.
 *
 * Health Connect returns [androidx.health.connect.client.records.ExerciseRouteResult.ConsentRequired]
 * for every exercise route written by another app, and the pinned SDK
 * (androidx.health.connect:connect-client:1.2.0-alpha02) only allows asking for that consent one
 * session at a time through `ExerciseRouteRequestContract` — there is no batched flow. The
 * coordinator therefore bounds a single export to [MAX_PROMPTS_PER_EXPORT] dialogs, preferring
 * the most recent sessions, and degrades to "no grants" whenever no interactive UI surface is
 * attached (scheduled exports, the direct CLI protocol, background jobs).
 *
 * Grants persist inside Health Connect per app and session: once a session is granted here, every
 * later read returns its route as inline data.
 */
@Singleton
class ExerciseRouteConsentCoordinator @Inject constructor() : ExerciseRouteConsentGateway {

    /** UI surface able to launch the Health Connect per-session consent activity. */
    interface Surface {
        /** Shows the consent prompt for one session; returns its granted route, or null when denied. */
        suspend fun requestRoute(session: PendingExerciseRouteConsent): ExerciseRoute?
    }

    @Volatile
    private var surface: Surface? = null

    fun attach(surface: Surface) {
        this.surface = surface
    }

    fun detach(surface: Surface) {
        if (this.surface === surface) this.surface = null
    }

    override suspend fun requestRoutes(sessions: List<PendingExerciseRouteConsent>): Map<String, ExerciseRoute> {
        val active = surface ?: return emptyMap()
        val candidates = sessions
            .distinctBy { it.sessionId }
            .sortedByDescending { it.sessionStartTime }
            .take(MAX_PROMPTS_PER_EXPORT)
        if (candidates.isEmpty()) return emptyMap()
        val granted = linkedMapOf<String, ExerciseRoute>()
        for (candidate in candidates) {
            // A cancelled export must stop prompting immediately.
            currentCoroutineContext().ensureActive()
            val route = try {
                withTimeoutOrNull(PROMPT_TIMEOUT_MS) { active.requestRoute(candidate) }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                // A broken surface must never fail the export; treat as a denial.
                null
            }
            if (route != null) granted[candidate.sessionId] = route
        }
        return granted
    }

    companion object {
        /**
         * Upper bound of consent dialogs for one export run. The pinned SDK has no batched
         * consent flow, so this bound is the only protection against an unbounded dialog
         * sequence for a huge third-party session count. Sessions beyond the bound stay
         * `consent_required`; re-running the export can consent the next bounded batch.
         */
        const val MAX_PROMPTS_PER_EXPORT = 10

        /** Safety timeout for one abandoned dialog so an export cannot hang forever. */
        internal const val PROMPT_TIMEOUT_MS = 5 * 60_000L
    }
}
