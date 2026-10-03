package com.healthmd.presentation.export

import androidx.activity.result.ActivityResultLauncher
import com.healthmd.rawexport.ExerciseRouteConsentCoordinator
import com.healthmd.rawexport.PendingExerciseRouteConsent

/**
 * Thin Activity Result launch surface. The coordinator, not this composition-scoped object, owns
 * the pending request and continuation so rotation/rebinding cannot detach a result from its run.
 */
class LauncherExerciseRouteConsentSurface : ExerciseRouteConsentCoordinator.Surface {

    private var launcher: ActivityResultLauncher<String>? = null

    fun bind(launcher: ActivityResultLauncher<String>) {
        this.launcher = launcher
    }

    override fun launchRouteRequest(session: PendingExerciseRouteConsent): Boolean {
        val boundLauncher = launcher ?: return false
        return try {
            boundLauncher.launch(session.sessionId)
            true
        } catch (_: Exception) {
            false
        }
    }
}
