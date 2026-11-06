package com.healthmd.data.clinicsync

import android.Manifest
import android.app.Activity
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.healthmd.R
import com.healthmd.automation.AutomationReceiver
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.MainActivity
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.suspendCancellableCoroutine
import java.time.LocalDate
import javax.inject.Inject
import kotlin.coroutines.resume

/**
 * Runs the clinic profile through the app's explicit automation entrypoint, which resolves
 * the profile, restores its frozen settings, re-authorizes clinic access and records history.
 */
class AutomationClinicSyncExportLauncher @Inject constructor(
    @ApplicationContext private val context: Context,
    private val profiles: ExportProfileRepository,
) : ClinicSyncExportLauncher {
    override suspend fun exportClinicProfile(endpoint: String): ClinicSyncExportResult {
        val profile = profiles.getProfiles().firstOrNull {
            it.target == ExportTarget.API_ENDPOINT && it.apiEndpointUrl == endpoint
        } ?: return ClinicSyncExportResult.PROFILE_MISSING
        val today = LocalDate.now()
        val intent = Intent(context, AutomationReceiver::class.java)
            .setAction(AutomationReceiver.ACTION_EXPORT_RANGE)
            .putExtra(AutomationReceiver.EXTRA_START_DATE, today.minusDays(1).toString())
            .putExtra(AutomationReceiver.EXTRA_END_DATE, today.toString())
            .putExtra(AutomationReceiver.EXTRA_PROFILE, profile.id)
        val code = suspendCancellableCoroutine { continuation ->
            context.sendOrderedBroadcast(intent, null, object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    if (continuation.isActive) continuation.resume(resultCode)
                }
            }, null, Activity.RESULT_CANCELED, null, null)
        }
        return if (code == AutomationReceiver.RESULT_SUCCESS) ClinicSyncExportResult.SENT else ClinicSyncExportResult.FAILED
    }
}

class AndroidClinicSyncNotifier @Inject constructor(
    @ApplicationContext private val context: Context,
) : ClinicSyncNotifier {
    override fun canPostNotifications(): Boolean {
        val permitted = Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        return permitted && NotificationManagerCompat.from(context).areNotificationsEnabled()
    }

    override fun postRequest(wakeId: String) {
        val intent = Intent(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            .putExtra(MainActivity.EXTRA_CLINIC_SYNC_WAKE_ID, wakeId)
        val tap = PendingIntent.getActivity(context, REQUEST_NOTIFICATION_ID, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        post(REQUEST_NOTIFICATION_ID, context.getString(R.string.clinic_sync_request_body), tap)
    }

    override fun postResult(result: ClinicSyncExportResult) {
        NotificationManagerCompat.from(context).cancel(REQUEST_NOTIFICATION_ID)
        val body = when (result) {
            ClinicSyncExportResult.SENT -> R.string.clinic_sync_result_sent
            ClinicSyncExportResult.FAILED -> R.string.clinic_sync_result_failed
            ClinicSyncExportResult.PROFILE_MISSING -> R.string.clinic_sync_result_profile_missing
        }
        post(RESULT_NOTIFICATION_ID, context.getString(body), null)
    }

    private fun post(id: Int, body: String, tap: PendingIntent?) {
        if (!canPostNotifications()) return
        ensureChannel(context)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_sync)
            .setContentTitle(context.getString(R.string.app_name))
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .apply { tap?.let { setContentIntent(it) } }
            .build()
        try {
            NotificationManagerCompat.from(context).notify(id, notification)
        } catch (_: SecurityException) {
            // Permission revoked between the check and the post; nothing else to do.
        }
    }

    companion object {
        const val CHANNEL_ID = "clinic_sync_requests"
        private const val REQUEST_NOTIFICATION_ID = 41_001
        private const val RESULT_NOTIFICATION_ID = 41_002

        fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            context.getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(CHANNEL_ID, context.getString(R.string.clinic_sync_channel_name),
                    NotificationManager.IMPORTANCE_HIGH),
            )
        }
    }
}
