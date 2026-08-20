package com.healthmd.data.scheduler

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dagger.Lazy
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

/**
 * Durable delayed fallback for one entry, mirroring the single scheduler's fallback trigger:
 * if the exact alarm never fired (Doze, alarm permission revoked, OEM killers), this one-time
 * WorkManager request admits the durable export work at the intended time.
 */
@HiltWorker
class ScheduledProfileTriggerWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val profileScheduler: Lazy<ScheduledProfileScheduler>,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val profileId = inputData.getString(INPUT_PROFILE_ID)?.takeIf { it.isNotBlank() }
            ?: return Result.failure()
        return try {
            profileScheduler.get().handleAlarm(profileId)
            Result.success()
        } catch (_: Exception) {
            Result.retry()
        }
    }

    companion object {
        const val INPUT_PROFILE_ID = "profile_id"
    }
}
