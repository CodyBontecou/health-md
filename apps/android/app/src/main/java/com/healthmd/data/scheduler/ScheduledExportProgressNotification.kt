package com.healthmd.data.scheduler

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.healthmd.HealthMdApplication
import com.healthmd.R
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.navigation.NavDestination
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle
import java.util.UUID

/**
 * The ongoing scheduled-export notification. It starts indeterminate, then shows "N of M days
 * exported. Current date: …" with a determinate bar as the exporter reports each day. Cancel
 * export stays available throughout. It never contains health values.
 */
internal object ScheduledExportProgressNotification {
    /** Days before the notification is refreshed again; avoids notification rate limiting. */
    private const val MIN_UPDATE_INTERVAL_MILLIS = 750L

    fun build(
        context: Context,
        workId: UUID,
        notificationId: Int,
        current: Int = 0,
        total: Int = 0,
        dateString: String? = null,
    ): Notification {
        val openAppIntent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_START_ROUTE, NavDestination.SCHEDULE.route)
        }
        val contentIntent = PendingIntent.getActivity(
            context,
            notificationId,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(context, HealthMdApplication.EXPORT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_save)
            .setContentTitle(context.getString(R.string.export_progress_title))
            .setContentText(progressText(context, current, total, dateString))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentIntent)
            .setOnlyAlertOnce(true)
            .addAction(
                0,
                context.getString(R.string.action_cancel_export),
                ScheduledExportCancelReceiver.pendingIntent(context, workId),
            )
            .apply {
                // Indeterminate until the exporter reports its first day; Cancel stays available.
                if (total > 0) setProgress(total, current.coerceIn(0, total), false) else setProgress(0, 0, true)
            }
            .setOngoing(true)
            .build()
    }

    internal fun progressText(context: Context, current: Int, total: Int, dateString: String?): String {
        if (total <= 0) return context.getString(R.string.automatic_export_subtitle)
        val date = dateString?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
            ?.format(
                DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
                    .withLocale(context.resources.configuration.locales[0]),
            )
        return if (date != null) {
            context.resources.getQuantityString(
                R.plurals.export_progress_state_days_with_date, total, current, total, date,
            )
        } else {
            context.resources.getQuantityString(R.plurals.export_progress_state_days, total, current, total)
        }
    }

    /** An exporter progress callback that refreshes the worker's foreground notification. */
    fun updater(context: Context, workId: UUID): (Int, Int, String) -> Unit {
        val notificationId = ScheduledExportCancellationCoordinator.foregroundNotificationID(workId)
        var lastUpdate = 0L
        return { current, total, dateString ->
            val now = System.currentTimeMillis()
            if (current >= total || now - lastUpdate >= MIN_UPDATE_INTERVAL_MILLIS) {
                lastUpdate = now
                if (canPost(context)) {
                    runCatching {
                        context.getSystemService(NotificationManager::class.java).notify(
                            notificationId,
                            build(context, workId, notificationId, current, total, dateString),
                        )
                    }
                }
            }
        }
    }

    private fun canPost(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
}
