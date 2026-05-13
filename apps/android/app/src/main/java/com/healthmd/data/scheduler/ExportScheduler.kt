package com.healthmd.data.scheduler

import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import com.healthmd.domain.model.ScheduleCadenceUnit
import java.time.Duration
import java.time.LocalDateTime
import java.util.concurrent.TimeUnit
import javax.inject.Inject

class ExportScheduler @Inject constructor(
    private val workManager: WorkManager,
) {
    fun schedule(
        cadenceValue: Int,
        cadenceUnit: ScheduleCadenceUnit,
        hour: Int,
        minute: Int,
    ) {
        val normalizedValue = cadenceValue.coerceAtLeast(1)
        val (repeatValue, repeatUnit) = repeatInterval(normalizedValue, cadenceUnit)

        val requestBuilder = PeriodicWorkRequestBuilder<ExportWorker>(repeatValue, repeatUnit)
            .setConstraints(
                Constraints.Builder()
                    .setRequiresBatteryNotLow(true)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)

        initialDelayMillis(cadenceUnit, normalizedValue, hour, minute)?.let { delayMs ->
            requestBuilder.setInitialDelay(delayMs, TimeUnit.MILLISECONDS)
        }

        workManager.enqueueUniquePeriodicWork(
            ExportWorker.WORK_NAME,
            ExistingPeriodicWorkPolicy.CANCEL_AND_REENQUEUE,
            requestBuilder.build(),
        )
    }

    fun cancel() {
        workManager.cancelUniqueWork(ExportWorker.WORK_NAME)
    }

    private fun repeatInterval(
        value: Int,
        unit: ScheduleCadenceUnit,
    ): Pair<Long, TimeUnit> = when (unit) {
        ScheduleCadenceUnit.MINUTES -> Pair(value.coerceAtLeast(MIN_REPEAT_MINUTES).toLong(), TimeUnit.MINUTES)
        ScheduleCadenceUnit.HOURS -> Pair(value.toLong(), TimeUnit.HOURS)
        ScheduleCadenceUnit.DAYS -> Pair(value.toLong(), TimeUnit.DAYS)
        ScheduleCadenceUnit.WEEKS -> Pair((value * DAYS_PER_WEEK).toLong(), TimeUnit.DAYS)
    }

    private fun initialDelayMillis(
        unit: ScheduleCadenceUnit,
        cadenceValue: Int,
        hour: Int,
        minute: Int,
    ): Long? {
        if (unit != ScheduleCadenceUnit.DAYS && unit != ScheduleCadenceUnit.WEEKS) return null

        val now = LocalDateTime.now()
        var next = now
            .withHour(hour.coerceIn(0, 23))
            .withMinute(minute.coerceIn(0, 59))
            .withSecond(0)
            .withNano(0)

        if (!next.isAfter(now)) {
            next = when (unit) {
                ScheduleCadenceUnit.DAYS -> next.plusDays(cadenceValue.toLong())
                ScheduleCadenceUnit.WEEKS -> next.plusWeeks(cadenceValue.toLong())
                else -> next
            }
        }

        return Duration.between(now, next).toMillis().coerceAtLeast(0)
    }

    companion object {
        private const val DAYS_PER_WEEK = 7
        private const val MIN_REPEAT_MINUTES = 15
    }
}
