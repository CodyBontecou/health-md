package com.healthmd.data.scheduler

import androidx.work.*
import java.util.concurrent.TimeUnit
import javax.inject.Inject

class ExportScheduler @Inject constructor(
    private val workManager: WorkManager,
) {
    fun scheduleDaily() {
        val request = PeriodicWorkRequestBuilder<ExportWorker>(1, TimeUnit.DAYS)
            .setConstraints(
                Constraints.Builder()
                    .setRequiresBatteryNotLow(true)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .build()

        workManager.enqueueUniquePeriodicWork(
            ExportWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    fun scheduleWeekly() {
        val request = PeriodicWorkRequestBuilder<ExportWorker>(7, TimeUnit.DAYS)
            .setConstraints(
                Constraints.Builder()
                    .setRequiresBatteryNotLow(true)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .build()

        workManager.enqueueUniquePeriodicWork(
            ExportWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
    }

    fun cancel() {
        workManager.cancelUniqueWork(ExportWorker.WORK_NAME)
    }
}
