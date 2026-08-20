package com.healthmd.presentation.export

import androidx.activity.result.ActivityResultLauncher
import androidx.health.connect.client.records.ExerciseRoute
import com.healthmd.rawexport.ExerciseRouteConsentCoordinator
import com.healthmd.rawexport.PendingExerciseRouteConsent
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume

/**
 * [ExerciseRouteConsentCoordinator.Surface] backed by a Composition-registered
 * `ExerciseRouteRequestContract` launcher. The pinned Health Connect SDK
 * (connect-client 1.2.0-alpha02) returns the granted route directly from the contract result;
 * a null result is a denial and keeps the session exported as `consent_required`.
 *
 * This object is single-prompt: the coordinator serializes prompts, so exactly one continuation
 * is pending at a time. [close] denies any prompt still awaiting a result (for example when the
 * screen leaves composition mid-dialog) so the running export can finish without hanging.
 */
class LauncherExerciseRouteConsentSurface : ExerciseRouteConsentCoordinator.Surface {

    private var launcher: ActivityResultLauncher<String>? = null
    private var pendingResult: ((ExerciseRoute?) -> Unit)? = null

    /** Binds the launcher registered by the export screen; called once per composition. */
    fun bind(launcher: ActivityResultLauncher<String>) {
        this.launcher = launcher
    }

    /** Contract callback; resumes the pending prompt, if any. */
    fun onLaunchResult(route: ExerciseRoute?) {
        val callback = pendingResult
        pendingResult = null
        callback?.invoke(route)
    }

    override suspend fun requestRoute(session: PendingExerciseRouteConsent): ExerciseRoute? =
        suspendCancellableCoroutine { continuation ->
            val boundLauncher = launcher
            if (boundLauncher == null) {
                continuation.resume(null)
                return@suspendCancellableCoroutine
            }
            pendingResult = { route -> continuation.resume(route) }
            continuation.invokeOnCancellation { pendingResult = null }
            try {
                boundLauncher.launch(session.sessionId)
            } catch (_: Exception) {
                // An unavailable Health Connect activity must never hang the export.
                pendingResult = null
                continuation.resume(null)
            }
        }

    /** Denies any prompt that is still open so a leaving screen cannot deadlock an export. */
    fun close() {
        val callback = pendingResult
        pendingResult = null
        callback?.invoke(null)
    }
}
