package com.healthmd.data.scheduler

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import timber.log.Timber
import java.util.UUID

/** Private notification action receiver; no schedule setting, alarm, or unique work is touched. */
class ScheduledExportCancelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CANCEL_SCHEDULED_EXPORT) return
        val operationID = intent.getStringExtra(EXTRA_OPERATION_ID)
            ?.let { raw -> runCatching { UUID.fromString(raw) }.getOrNull() }
            ?: return
        val accepted = ScheduledExportCancellationCoordinator.requestCancellation(operationID)
        Timber.i(
            "Scheduled export cancellation requested operationId=%s accepted=%s",
            operationID,
            accepted,
        )
    }

    companion object {
        const val ACTION_CANCEL_SCHEDULED_EXPORT =
            "com.healthmd.android.action.CANCEL_SCHEDULED_EXPORT"
        const val EXTRA_OPERATION_ID = "operation_id"

        fun pendingIntent(context: Context, operationID: UUID): PendingIntent {
            val intent = Intent(context, ScheduledExportCancelReceiver::class.java).apply {
                action = ACTION_CANCEL_SCHEDULED_EXPORT
                data = Uri.parse("healthmd://scheduled-export/cancel/$operationID")
                putExtra(EXTRA_OPERATION_ID, operationID.toString())
            }
            return PendingIntent.getBroadcast(
                context,
                operationID.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
