package com.healthmd.data.scheduler

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

/** Private exact-alarm entry point. Export work itself remains durable in WorkManager. */
@AndroidEntryPoint
class ScheduledExportAlarmReceiver : BroadcastReceiver() {
    @Inject lateinit var exportScheduler: ExportScheduler

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ExportScheduler.ACTION_SCHEDULED_EXPORT_ALARM) return
        val occurrence = ScheduledExportOccurrence.fromIntent(intent) ?: return
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                exportScheduler.handleOccurrence(occurrence, expedited = true)
            } catch (_: Exception) {
                runCatching { exportScheduler.reconcile() }
            } finally {
                pendingResult.finish()
            }
        }
    }
}
