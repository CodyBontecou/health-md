package com.healthmd.data.scheduler

import android.app.NotificationManager
import android.content.Context
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.healthmd.HealthMdApplication
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import java.time.LocalDate

@HiltWorker
class ExportWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
    private val exportHistoryRepository: ExportHistoryRepository,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val settings = settingsRepository.getExportSettings()
        val yesterday = LocalDate.now().minusDays(1)

        return try {
            val orchestrator = ExportOrchestrator(healthRepository, exportRepository)
            val result = orchestrator.exportDates(listOf(yesterday), settings)

            // Record in history
            exportHistoryRepository.insertEntry(
                ExportHistoryEntry(
                    timestamp = System.currentTimeMillis(),
                    source = ExportSource.SCHEDULED,
                    dateRangeStart = yesterday,
                    dateRangeEnd = yesterday,
                    successCount = result.successCount,
                    totalCount = result.totalCount,
                    failureReason = result.primaryFailureReason,
                    failedDateDetails = result.failedDateDetails,
                )
            )

            // Show notification
            showNotification(
                if (result.isFullSuccess) "Export Complete"
                else "Export ${if (result.isPartialSuccess) "Partial" else "Failed"}",
                "${result.successCount}/${result.totalCount} days exported for $yesterday",
            )

            if (result.successCount > 0) Result.success() else {
                if (runAttemptCount < 3) Result.retry() else Result.failure()
            }
        } catch (e: Exception) {
            showNotification("Export Failed", e.message ?: "Unknown error")
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }

    private fun showNotification(title: String, message: String) {
        val notification = NotificationCompat.Builder(applicationContext, HealthMdApplication.EXPORT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_save)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setAutoCancel(true)
            .build()

        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(NOTIFICATION_ID, notification)
    }

    companion object {
        const val WORK_NAME = "health_export"
        private const val NOTIFICATION_ID = 1001
    }
}
