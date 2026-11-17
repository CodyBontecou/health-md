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
import timber.log.Timber

/** Restores the next one-shot alarm after system events that clear or invalidate alarms. */
@AndroidEntryPoint
class BootReceiver : BroadcastReceiver() {
    @Inject lateinit var exportScheduler: ExportScheduler
    @Inject lateinit var profileScheduler: ScheduledProfileScheduler

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action !in SUPPORTED_ACTIONS) return
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                // A failure must not crash the process (this runs on every boot and app update)
                // or skip re-arming scheduled profiles below. The next reconcile retries.
                runCatching {
                    exportScheduler.reconcile(
                        forceRecalculate = intent.action == Intent.ACTION_TIME_CHANGED ||
                            intent.action == Intent.ACTION_TIMEZONE_CHANGED,
                    )
                }.onFailure { error ->
                    Timber.e("Scheduled export reconcile failed after %s: %s", intent.action, error.javaClass.simpleName)
                }
                // Phase 6: re-arm every scheduled-profile entry after the same system events.
                runCatching {
                    profileScheduler.reconcile(
                        forceRecalculate = intent.action == Intent.ACTION_TIME_CHANGED ||
                            intent.action == Intent.ACTION_TIMEZONE_CHANGED,
                    )
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        val SUPPORTED_ACTIONS = setOf(
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            EXACT_ALARM_PERMISSION_STATE_CHANGED_ACTION,
        )
        const val EXACT_ALARM_PERMISSION_STATE_CHANGED_ACTION =
            "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
    }
}
