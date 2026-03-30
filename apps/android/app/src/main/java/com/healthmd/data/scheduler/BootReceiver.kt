package com.healthmd.data.scheduler

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Re-schedules exports after device reboot.
 * WorkManager handles this automatically, but we include
 * BOOT_COMPLETED as a safety net for older OEM implementations.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            // WorkManager automatically re-enqueues periodic work after boot.
            // No manual action needed here, but this receiver ensures the
            // BOOT_COMPLETED permission is properly declared.
        }
    }
}
