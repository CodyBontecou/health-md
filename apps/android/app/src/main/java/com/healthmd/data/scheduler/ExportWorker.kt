package com.healthmd.data.scheduler

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters
import com.healthmd.HealthMdApplication
import com.healthmd.R
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.navigation.NavDestination
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.flow.first
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
        val isPurchased = settingsRepository.isPurchased.first()
        val dates = scheduledDates(settings)
        val startDate = dates.first()
        val endDate = dates.last()

        if (!isPurchased) {
            val failureDetails = dates.map { FailedDateDetail(it, ExportFailureReason.PAYWALL_REQUIRED) }
            exportHistoryRepository.insertEntry(
                historyEntry(
                    settings = settings,
                    dates = dates,
                    result = ExportResult(0, dates.size, failureDetails),
                    failureReason = ExportFailureReason.PAYWALL_REQUIRED,
                    warning = applicationContext.getString(R.string.schedule_unlock_required_short),
                )
            )
            persistPendingRetryDates(dates, ExportFailureReason.PAYWALL_REQUIRED)
            showNotification(
                applicationContext.getString(R.string.export_notification_title_failed),
                applicationContext.getString(R.string.schedule_unlock_required_short),
                NavDestination.SCHEDULE.route,
                promptRecovery = true,
            )
            return Result.failure()
        }

        if (!healthRepository.hasBackgroundReadPermission()) {
            val failureDetails = dates.map { FailedDateDetail(it, ExportFailureReason.BACKGROUND_PERMISSION_DENIED) }
            exportHistoryRepository.insertEntry(
                ExportHistoryEntry(
                    timestamp = System.currentTimeMillis(),
                    source = ExportSource.SCHEDULED,
                    dateRangeStart = startDate,
                    dateRangeEnd = endDate,
                    successCount = 0,
                    totalCount = dates.size,
                    failureReason = ExportFailureReason.BACKGROUND_PERMISSION_DENIED,
                    failedDateDetails = failureDetails,
                    targetLabel = targetLabel(settings),
                    fileCount = 0,
                    warningSummary = applicationContext.getString(R.string.export_notification_background_permission_required),
                )
            )
            persistPendingRetryDates(dates, ExportFailureReason.BACKGROUND_PERMISSION_DENIED)
            showNotification(
                applicationContext.getString(R.string.export_notification_title_failed),
                applicationContext.getString(R.string.export_notification_background_permission_required),
                NavDestination.SCHEDULE.route,
                promptRecovery = true,
            )
            return Result.failure()
        }

        return try {
            val orchestrator = ExportOrchestrator(healthRepository, exportRepository)
            val result = orchestrator.exportDates(dates, settings)

            exportHistoryRepository.insertEntry(
                historyEntry(
                    settings = settings,
                    dates = dates,
                    result = result,
                    failureReason = result.primaryFailureReason,
                    warning = result.warningSummary(),
                )
            )

            persistPendingRetryDates(dates, result.failedDateDetails)

            val titleResId = when {
                result.isFullSuccess -> R.string.export_notification_title_complete
                result.isPartialSuccess -> R.string.export_notification_title_partial
                else -> R.string.export_notification_title_failed
            }
            showNotification(
                applicationContext.getString(titleResId),
                applicationContext.getString(
                    R.string.export_notification_message_days_exported,
                    result.successCount,
                    result.totalCount,
                    endDate,
                ),
                if (result.isFullSuccess) NavDestination.EXPORT.route else NavDestination.SCHEDULE.route,
                promptRecovery = !result.isFullSuccess,
            )

            if (result.successCount > 0) {
                Result.success()
            } else if (result.primaryFailureReason == ExportFailureReason.DEVICE_LOCKED) {
                Result.retry()
            } else if (result.primaryFailureReason == ExportFailureReason.BACKGROUND_PERMISSION_DENIED) {
                Result.failure()
            } else {
                if (runAttemptCount < 3) Result.retry() else Result.failure()
            }
        } catch (e: Exception) {
            persistPendingRetryDates(dates, ExportFailureReason.UNKNOWN)
            showNotification(
                applicationContext.getString(R.string.export_notification_title_failed),
                e.message ?: applicationContext.getString(R.string.export_notification_unknown_error),
                NavDestination.SCHEDULE.route,
                promptRecovery = true,
            )
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }

    private fun scheduledDates(settings: ExportSettings): List<LocalDate> =
        ScheduledExportPendingRequests.scheduledRunDates(settings)

    private suspend fun persistPendingRetryDates(
        attemptedDates: List<LocalDate>,
        failedDateDetails: List<FailedDateDetail>,
    ) {
        val latestSettings = settingsRepository.getExportSettings()
        settingsRepository.updateExportSettings(
            ScheduledExportPendingRequests.applyAttemptResult(
                settings = latestSettings,
                attemptedDates = attemptedDates,
                failedDateDetails = failedDateDetails,
            )
        )
    }

    private suspend fun persistPendingRetryDates(
        attemptedDates: List<LocalDate>,
        failureReason: ExportFailureReason,
    ) {
        val latestSettings = settingsRepository.getExportSettings()
        settingsRepository.updateExportSettings(
            ScheduledExportPendingRequests.recordFailedDates(
                settings = latestSettings,
                dates = attemptedDates,
                reason = failureReason,
            )
        )
    }

    private fun historyEntry(
        settings: ExportSettings,
        dates: List<LocalDate>,
        result: ExportResult,
        failureReason: ExportFailureReason?,
        warning: String?,
    ): ExportHistoryEntry = ExportHistoryEntry(
        timestamp = System.currentTimeMillis(),
        source = ExportSource.SCHEDULED,
        dateRangeStart = dates.first(),
        dateRangeEnd = dates.last(),
        successCount = result.successCount,
        totalCount = result.totalCount,
        failureReason = failureReason,
        failedDateDetails = result.failedDateDetails,
        targetLabel = targetLabel(settings),
        fileCount = result.successCount * settings.selectedExportFormats.size,
        warningSummary = warning,
    )

    private fun targetLabel(settings: ExportSettings): String = buildString {
        val subfolder = settings.subfolder.trim('/').takeIf { it.isNotBlank() }
        append(subfolder ?: applicationContext.getString(R.string.export_folder_root_label))
        settings.formatFolderPath(LocalDate.now().minusDays(1))?.takeIf { it.isNotBlank() }?.let {
            append("/").append(it.trim('/'))
        }
    }

    private fun ExportResult.warningSummary(): String? = when {
        isPartialSuccess -> "${failedDateDetails.size} failed date(s) pending retry"
        isFailure -> primaryFailureReason?.name
        else -> null
    }

    private fun showNotification(
        title: String,
        message: String,
        route: String,
        promptRecovery: Boolean = false,
    ) {
        if (!canPostNotifications()) return

        val openAppIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_START_ROUTE, route)
            putExtra(MainActivity.EXTRA_PROMPT_SCHEDULED_RECOVERY, promptRecovery)
        }
        val contentIntent = PendingIntent.getActivity(
            applicationContext,
            route.hashCode(),
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = NotificationCompat.Builder(applicationContext, HealthMdApplication.EXPORT_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_save)
            .setContentTitle(title)
            .setContentText(message)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .build()

        val manager = applicationContext.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val notificationId = (System.currentTimeMillis() and 0x7FFFFFFF.toLong()).toInt()
        manager.notify(notificationId, notification)
    }

    private fun canPostNotifications(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return ContextCompat.checkSelfPermission(
            applicationContext,
            Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        const val WORK_NAME = "health_export"
    }
}
