package com.healthmd.presentation.export

import android.os.Handler
import android.os.Looper
import androidx.activity.result.ActivityResultLauncher
import com.healthmd.rawexport.ExerciseRouteConsentCoordinator
import com.healthmd.rawexport.PendingExerciseRouteConsent
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * Thin Activity Result launch surface. The coordinator, not this composition-scoped object, owns
 * the pending request and continuation so rotation/rebinding cannot detach a result from its run.
 *
 * Health capture runs off the main thread, so a consent request can arrive on a worker thread.
 * Activity Result launches are always performed on the main thread; a worker waits (bounded)
 * only for the hand-off, never for the user's decision.
 */
class LauncherExerciseRouteConsentSurface : ExerciseRouteConsentCoordinator.Surface {

    @Volatile
    private var launcher: ActivityResultLauncher<String>? = null

    fun bind(launcher: ActivityResultLauncher<String>) {
        this.launcher = launcher
    }

    override fun launchRouteRequest(session: PendingExerciseRouteConsent): Boolean {
        val mainLooper = Looper.getMainLooper()
        if (Looper.myLooper() == mainLooper) return launchOnMain(session)
        val launched = AtomicBoolean(false)
        val handedOff = CountDownLatch(1)
        val posted = Handler(mainLooper).post {
            try {
                launched.set(launchOnMain(session))
            } finally {
                handedOff.countDown()
            }
        }
        if (!posted) return false
        return try {
            handedOff.await(MAIN_HANDOFF_TIMEOUT_MS, TimeUnit.MILLISECONDS) && launched.get()
        } catch (_: InterruptedException) {
            Thread.currentThread().interrupt()
            false
        }
    }

    private fun launchOnMain(session: PendingExerciseRouteConsent): Boolean {
        val boundLauncher = launcher ?: return false
        return try {
            boundLauncher.launch(session.sessionId)
            true
        } catch (_: Exception) {
            false
        }
    }

    private companion object {
        const val MAIN_HANDOFF_TIMEOUT_MS = 10_000L
    }
}
