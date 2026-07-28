package com.healthmd.data.scheduler

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

/** Inexact fallback used when the user has not granted exact-alarm special access. */
@HiltWorker
class ScheduledExportTriggerWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val exportScheduler: ExportScheduler,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val occurrence = ScheduledExportOccurrence.fromWorkData(inputData) ?: return Result.failure()
        return try {
            exportScheduler.handleOccurrence(occurrence, expedited = true)
            Result.success()
        } catch (_: Exception) {
            if (runAttemptCount < MAX_ATTEMPTS) Result.retry() else Result.failure()
        }
    }

    private companion object {
        const val MAX_ATTEMPTS = 3
    }
}
