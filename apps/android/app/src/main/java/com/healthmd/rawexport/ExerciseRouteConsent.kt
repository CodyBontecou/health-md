package com.healthmd.rawexport

import androidx.health.connect.client.records.ExerciseRoute
import androidx.health.connect.client.records.ExerciseRouteResult
import androidx.health.connect.client.records.ExerciseSessionRecord
import java.time.Instant
import kotlin.coroutines.AbstractCoroutineContextElement
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext

/**
 * A third-party exercise session whose route Health Connect reports as
 * [ExerciseRouteResult.ConsentRequired]. Health Connect deliberately gates routes written by
 * other apps behind a per-session, user-initiated consent grant that cannot be requested through
 * the ordinary permission flow.
 */
data class PendingExerciseRouteConsent(
    val sessionId: String,
    val sessionStartTime: Instant,
    val sessionEndTime: Instant,
)

/**
 * Requests per-session exercise route consent and returns the granted routes keyed by session id.
 * Sessions the user denied, dismissed, or that a bounded prompt policy skipped are absent from
 * the result; callers must keep reporting `route.state=consent_required` for them.
 *
 * Implementations must never throw for a denied or unavailable surface; a denial is simply an
 * empty or partial result so an export always completes.
 */
fun interface ExerciseRouteConsentGateway {
    suspend fun requestRoutes(sessions: List<PendingExerciseRouteConsent>): Map<String, ExerciseRoute>
}

/** Non-interactive default: no route can be consented, so every session stays `consent_required`. */
object NoExerciseRouteConsentGateway : ExerciseRouteConsentGateway {
    override suspend fun requestRoutes(sessions: List<PendingExerciseRouteConsent>): Map<String, ExerciseRoute> = emptyMap()
}

/**
 * Marks the current coroutine as an interactive, user-visible export run that is allowed to
 * launch Health Connect's per-session route consent UI. Only manual export actions started from
 * the app UI install this element. Scheduled exports, automation receivers, the direct CLI
 * protocol, and background jobs never carry it, so they deterministically keep reporting
 * `route.state=consent_required` with empty locations.
 */
class InteractiveRouteConsent internal constructor(
    private val maximumPrompts: Int = ExerciseRouteConsentCoordinator.MAX_PROMPTS_PER_EXPORT,
) : AbstractCoroutineContextElement(Key) {
    private val promptedSessionIds = linkedSetOf<String>()

    /** Atomically reserves one of this export run's globally shared prompt slots. */
    @Synchronized
    internal fun reservePrompt(sessionId: String): Boolean {
        if (sessionId in promptedSessionIds || promptedSessionIds.size >= maximumPrompts) return false
        promptedSessionIds += sessionId
        return true
    }

    companion object Key : CoroutineContext.Key<InteractiveRouteConsent>
}

/**
 * Runs [block] with [InteractiveRouteConsent] installed. Health Connect route consent prompts
 * may only appear inside this scope.
 */
suspend fun <T> withInteractiveRouteConsent(block: suspend () -> T): T =
    withContext(InteractiveRouteConsent()) { block() }

/** True when the current coroutine is an interactive export run that may prompt for route consent. */
fun CoroutineContext.allowsInteractiveRouteConsent(): Boolean = this[InteractiveRouteConsent] != null

/**
 * Rebuilds a session with a route granted through Health Connect's per-session consent flow so
 * the pinned mapper serializes it exactly like a natively returned
 * [ExerciseRouteResult.Data] record.
 */
internal fun ExerciseSessionRecord.withGrantedExerciseRoute(route: ExerciseRoute): ExerciseSessionRecord =
    ExerciseSessionRecord(
        startTime = startTime,
        startZoneOffset = startZoneOffset,
        endTime = endTime,
        endZoneOffset = endZoneOffset,
        metadata = metadata,
        exerciseType = exerciseType,
        title = title,
        notes = notes,
        segments = segments,
        laps = laps,
        exerciseRoute = route,
        plannedExerciseSessionId = plannedExerciseSessionId,
    )

/**
 * Reads exercise sessions page by page and, when this run is interactive
 * ([allowsInteractiveRouteConsent]) and routes are requested, asks the gateway to consent the
 * sessions Health Connect reported as [ExerciseRouteResult.ConsentRequired] and merges each
 * granted route into the exported record.
 *
 * The pinned SDK (androidx.health.connect:connect-client:1.2.0-alpha02) exposes consent only
 * through the per-session `ExerciseRouteRequestContract`; it has no batched flow, so the
 * coordinator's own bounded prompt policy keeps a huge session count from producing an
 * unbounded dialog sequence.
 *
 * Wire-format contract: the emitted stream keeps the exact record order [readPage] produced.
 * Interactive reads use two bounded passes: the first retains only the newest prompt candidates,
 * then the second maps and emits every page. This avoids retaining an unbounded suffix after the
 * first consent-required record while preserving canonical output order. Denied or skipped
 * sessions keep their original `consent_required` mapping and never fail the export.
 *
 * [readPage] returns one page of native records plus the next page token (null/blank for the
 * final page) so this path stays unit-testable without a bound Health Connect client.
 */
internal suspend fun emitExerciseSessionsWithRouteConsent(
    request: RawSnapshotRequest,
    gateway: ExerciseRouteConsentGateway,
    readPage: suspend (pageToken: String?) -> Pair<List<ExerciseSessionRecord>, String?>,
    mapper: (ExerciseSessionRecord) -> RawRecord,
    emitRecord: suspend (RawRecord) -> Unit,
): Long {
    val interactive = currentCoroutineContext().allowsInteractiveRouteConsent()
    val consentCandidates = mutableListOf<PendingExerciseRouteConsent>()

    fun retainNewest(candidate: PendingExerciseRouteConsent) {
        val duplicateIndex = consentCandidates.indexOfFirst { it.sessionId == candidate.sessionId }
        if (duplicateIndex >= 0) {
            if (candidate.sessionStartTime > consentCandidates[duplicateIndex].sessionStartTime) {
                consentCandidates[duplicateIndex] = candidate
            }
            return
        }
        consentCandidates += candidate
        consentCandidates.sortWith(
            compareByDescending<PendingExerciseRouteConsent> { it.sessionStartTime }.thenBy { it.sessionId },
        )
        if (consentCandidates.size > ExerciseRouteConsentCoordinator.MAX_PROMPTS_PER_EXPORT) {
            consentCandidates.removeAt(consentCandidates.lastIndex)
        }
    }

    // Pass one is metadata-only and bounded to the newest possible prompt batch.
    if (interactive) {
        var token: String? = null
        do {
            val (records, nextToken) = readPage(token)
            currentCoroutineContext().ensureActive()
            for (native in records) {
                if (native.startTime < Instant.ofEpochSecond(request.endTime.epochSecond, request.endTime.nano.toLong()) &&
                    native.endTime > Instant.ofEpochSecond(request.startTime.epochSecond, request.startTime.nano.toLong()) &&
                    native.exerciseRouteResult is ExerciseRouteResult.ConsentRequired
                ) {
                    retainNewest(
                        PendingExerciseRouteConsent(
                            sessionId = native.metadata.id,
                            sessionStartTime = native.startTime,
                            sessionEndTime = native.endTime,
                        ),
                    )
                }
            }
            token = nextToken
        } while (!token.isNullOrBlank())
    }

    val granted = if (consentCandidates.isEmpty()) {
        emptyMap()
    } else {
        try {
            gateway.requestRoutes(consentCandidates)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            emptyMap()
        }
    }

    // Pass two is the only emission pass, so output remains canonical without suffix buffering.
    var emitted = 0L
    var token: String? = null
    do {
        val (records, nextToken) = readPage(token)
        currentCoroutineContext().ensureActive()
        for (native in records) {
            val mapped = mapper(native)
            if (!mapped.isInHalfOpenRange(request, RawRangeBehavior.OVERLAP)) continue
            val route = granted[native.metadata.id]
            val merged = if (route != null && native.exerciseRouteResult is ExerciseRouteResult.ConsentRequired) {
                try {
                    mapper(native.withGrantedExerciseRoute(route))
                } catch (_: IllegalArgumentException) {
                    mapped
                }
            } else {
                mapped
            }
            emitRecord(merged)
            emitted++
        }
        token = nextToken
    } while (!token.isNullOrBlank())
    return emitted
}
