package com.healthmd.data.scheduler

import android.annotation.SuppressLint
import android.app.ForegroundServiceStartNotAllowedException
import android.app.NotificationManager
import android.os.Build
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import timber.log.Timber

/**
 * Foreground promotion is an optimization for long exports, not admission authority.
 * Android can deny a service start when a delayed WorkManager fallback wakes a background app.
 * The already admitted worker may still run within WorkManager's ordinary execution budget;
 * its cancellation/checkpoint handling and permission checks must continue to run unchanged.
 */
@SuppressLint("MissingPermission") // Notification permission may be denied; export admission is separate.
internal suspend fun <T> CoroutineWorker.withScheduledExportForeground(
    info: ForegroundInfo,
    export: suspend () -> T,
): T {
    var fallbackNotifications: NotificationManager? = null
    try {
        try {
            setForeground(info)
        } catch (error: Exception) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S ||
                error !is ForegroundServiceStartNotAllowedException
            ) throw error
            currentCoroutineContext().ensureActive()
            Timber.w("Scheduled export foreground start denied; using bounded WorkManager execution")
            // Keep the same private, operation-scoped Cancel Export action without starting a service.
            fallbackNotifications = applicationContext.getSystemService(NotificationManager::class.java)
            try {
                fallbackNotifications?.notify(info.notificationId, info.notification)
            } catch (_: SecurityException) {
                // Revoking notifications must not grant or revoke health/destination authority.
                Timber.w("Scheduled export progress notification unavailable")
            }
        }
        return export()
    } finally {
        fallbackNotifications?.cancel(info.notificationId)
    }
}
