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
class InteractiveRouteConsent internal constructor() : AbstractCoroutineContextElement(Key) {
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
 * Wire-format contract: the emitted stream keeps the exact record order [readPage] produced
 * (Health Connect's ascending start-time order), because the raw snapshot validator enforces
 * canonical v1 record order. Records are therefore streamed until the first consent-required
 * session appears, and the suffix from that record onward is buffered until the consent round
 * resolves so a granted route can be merged in place. Denied or skipped sessions keep their
 * original `consent_required` mapping and the export never fails because of a denial.
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
    // Buffered suffix: native record paired with its already-mapped RawRecord.
    val buffered = mutableListOf<Pair<ExerciseSessionRecord, RawRecord>>()
    val consentCandidates = mutableListOf<PendingExerciseRouteConsent>()
    val seenSessionIds = mutableSetOf<String>()
    var emitted = 0L

    suspend fun emit(record: RawRecord) {
        emitRecord(record)
        emitted++
    }

    var token: String? = null
    do {
        val (records, nextToken) = readPage(token)
        for (native in records) {
            val mapped = mapper(native)
            // The provider query may be broader than the request; enforce v1 half-open semantics.
            if (!mapped.isInHalfOpenRange(request, RawRangeBehavior.OVERLAP)) continue
            val requiresConsent = native.exerciseRouteResult is ExerciseRouteResult.ConsentRequired
            if (interactive && requiresConsent && seenSessionIds.add(native.metadata.id)) {
                consentCandidates += PendingExerciseRouteConsent(
                    sessionId = native.metadata.id,
                    sessionStartTime = native.startTime,
                    sessionEndTime = native.endTime,
                )
                buffered += native to mapped
            } else if (consentCandidates.isNotEmpty()) {
                // Keep canonical order: once one session awaits consent, hold the suffix.
                buffered += native to mapped
            } else {
                emit(mapped)
            }
        }
        token = nextToken
    } while (!token.isNullOrBlank())

    if (buffered.isNotEmpty()) {
        val granted = try {
            gateway.requestRoutes(consentCandidates)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            // A consent failure must never fail the export; fall back to consent_required.
            emptyMap()
        }
        for ((native, mapped) in buffered) {
            val route = granted[native.metadata.id]
            val merged = if (route != null && native.exerciseRouteResult is ExerciseRouteResult.ConsentRequired) {
                try {
                    mapper(native.withGrantedExerciseRoute(route))
                } catch (_: IllegalArgumentException) {
                    // Health Connect validates granted routes against the session window; a
                    // route that cannot be rebuilt keeps its consent_required mapping instead
                    // of failing the export.
                    mapped
                }
            } else {
                mapped
            }
            emit(merged)
        }
    }
    return emitted
}
