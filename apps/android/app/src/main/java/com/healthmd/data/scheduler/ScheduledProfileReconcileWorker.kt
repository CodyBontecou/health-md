package com.healthmd.data.scheduler

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import dagger.Lazy
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.util.UUID
import kotlinx.coroutines.CancellationException

/** Durable scheduling repair for an interrupted recovery discard; never admits an export. */
@HiltWorker
class ScheduledProfileReconcileWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val profileScheduler: Lazy<ScheduledProfileScheduler>,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result {
        val profileId = inputData.getString(INPUT_PROFILE_ID)?.takeIf { it.isNotBlank() }
            ?: return Result.failure()
        val generation = inputData.getLong(INPUT_RECOVERY_GENERATION, -1L)
        if (generation < 0L) return Result.failure()
        val oldExportIds = try {
            inputData.getStringArray(INPUT_OLD_EXPORT_WORK_IDS).orEmpty().map(UUID::fromString)
        } catch (_: IllegalArgumentException) {
            return Result.failure()
        }
        return try {
            profileScheduler.get().finishRecoveryDiscard(profileId, generation, oldExportIds)
            Result.success()
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            Result.retry()
        }
    }

    companion object {
        const val INPUT_PROFILE_ID = "profile_id"
        const val INPUT_RECOVERY_GENERATION = "recovery_generation"
        const val INPUT_OLD_EXPORT_WORK_IDS = "old_export_work_ids"
    }
}
