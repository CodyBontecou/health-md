package com.healthmd.widget.refresh

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.BackoffPolicy
import androidx.work.CoroutineWorker
import androidx.work.Data
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.await
import androidx.work.workDataOf
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.CancellationException
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class HealthWidgetRefreshScheduler @Inject constructor(
    private val workManager: WorkManager,
    private val instances: HealthWidgetInstanceRegistry,
) {

    suspend fun reconcile() {
        val requirements = instances.requirements()
        if (!requirements.hasAny) {
            cancel()
            return
        }
        // Keep one low-frequency privacy pulse while widgets exist. Without optional background
        // access the worker never reads Health Connect; it only reconciles revocations/staleness.
        val request = PeriodicWorkRequestBuilder<HealthWidgetRefreshWorker>(
            PERIODIC_INTERVAL_MINUTES,
            TimeUnit.MINUTES,
        )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(WORK_TAG)
            .build()
        workManager.enqueueUniquePeriodicWork(
            PERIODIC_WORK_NAME,
            ExistingPeriodicWorkPolicy.KEEP,
            request,
        )
    }

    fun enqueueImmediate() {
        if (!instances.hasWidgets()) return
        workManager.enqueueUniqueWork(
            IMMEDIATE_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            oneTimeRequest(),
        )
    }

    /** Retries a failed final-instance cache deletion without requiring a widget to remain. */
    fun enqueueCleanup(deletedAppWidgetIds: Set<Int> = emptySet()) {
        workManager.enqueueUniqueWork(
            CLEANUP_WORK_NAME,
            ExistingWorkPolicy.REPLACE,
            oneTimeRequest(
                workDataOf(
                    CLEANUP_ONLY_KEY to true,
                    CLEANUP_DELETED_IDS_KEY to deletedAppWidgetIds.toIntArray(),
                ),
            ),
        )
    }

    suspend fun cancel() {
        listOf(
            workManager.cancelUniqueWork(PERIODIC_WORK_NAME),
            workManager.cancelUniqueWork(IMMEDIATE_WORK_NAME),
            workManager.cancelUniqueWork(CLEANUP_WORK_NAME),
        ).forEach { operation -> operation.await() }
    }

    private fun oneTimeRequest(inputData: Data = Data.EMPTY) =
        OneTimeWorkRequestBuilder<HealthWidgetRefreshWorker>()
            .setInputData(inputData)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(WORK_TAG)
            .build()

    companion object {
        const val PERIODIC_WORK_NAME = "health-widget-periodic-refresh-v1"
        const val IMMEDIATE_WORK_NAME = "health-widget-immediate-refresh-v1"
        const val CLEANUP_WORK_NAME = "health-widget-cleanup-v1"
        const val WORK_TAG = "health-widget-refresh"
        const val CLEANUP_ONLY_KEY = "health-widget-cleanup-only"
        const val CLEANUP_DELETED_IDS_KEY = "health-widget-cleanup-deleted-ids"
        const val PERIODIC_INTERVAL_MINUTES = 30L
    }
}

@HiltWorker
class HealthWidgetRefreshWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val coordinator: HealthWidgetRefreshCoordinator,
    private val scheduler: HealthWidgetRefreshScheduler,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        if (inputData.getBoolean(HealthWidgetRefreshScheduler.CLEANUP_ONLY_KEY, false)) {
            val deletedAppWidgetIds = inputData
                .getIntArray(HealthWidgetRefreshScheduler.CLEANUP_DELETED_IDS_KEY)
                ?.toSet()
                .orEmpty()
            return try {
                coordinator.deleteSnapshotIfNoWidgets(deletedAppWidgetIds)
                Result.success()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // Privacy cleanup is intentionally unbounded; a later retry keeps the original
                // callback IDs and never falls through to a Health Connect refresh.
                Result.retry()
            }
        }

        val refreshResult = try {
            coordinator.refresh(HealthWidgetRefreshOrigin.BACKGROUND)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            HealthWidgetRefreshResult.RETRY
        }
        if (
            refreshResult != HealthWidgetRefreshResult.RETRY &&
            refreshResult != HealthWidgetRefreshResult.CLEANUP_RETRY
        ) {
            try {
                scheduler.reconcile()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // The periodic pulse will reconcile again; do not discard a successful refresh.
            }
        }
        return when (refreshResult) {
            HealthWidgetRefreshResult.RETRY -> {
                if (runAttemptCount < MAX_ATTEMPTS) Result.retry() else Result.success()
            }
            HealthWidgetRefreshResult.CLEANUP_RETRY -> Result.retry()
            HealthWidgetRefreshResult.UPDATED,
            HealthWidgetRefreshResult.NO_DATA,
            HealthWidgetRefreshResult.NO_WIDGETS,
            HealthWidgetRefreshResult.PERMISSION_REQUIRED,
            HealthWidgetRefreshResult.HEALTH_CONNECT_UNAVAILABLE,
            HealthWidgetRefreshResult.BEFORE_FIRST_UNLOCK -> Result.success()
        }
    }

    private companion object {
        const val MAX_ATTEMPTS = 3
    }
}
