package com.healthmd.data.scheduler

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber
import javax.inject.Inject

/**
 * Per-profile exact-alarm entry point (phase 6). Durable export work itself runs in
 * WorkManager via [ScheduledProfileExportWorker]; this receiver only admits it.
 */
@AndroidEntryPoint
class ScheduledProfileAlarmReceiver : BroadcastReceiver() {
    @Inject lateinit var profileScheduler: ScheduledProfileScheduler

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ScheduledProfileScheduler.ACTION_PROFILE_SCHEDULE_ALARM) return
        val profileId = intent.getStringExtra(EXTRA_PROFILE_ID)?.takeIf { it.isNotBlank() } ?: return
        Timber.i("ScheduledProfileAlarmReceiver fired profileId=%s", profileId)
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                profileScheduler.handleAlarm(profileId)
            } catch (_: Exception) {
                runCatching { profileScheduler.reconcile() }
            } finally {
                pendingResult.finish()
            }
        }
    }

    companion object {
        const val EXTRA_PROFILE_ID = "profile_id"
    }
}
