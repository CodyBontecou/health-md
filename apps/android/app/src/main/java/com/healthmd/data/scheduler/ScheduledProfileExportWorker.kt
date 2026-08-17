package com.healthmd.data.scheduler

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.healthmd.HealthMdApplication
import com.healthmd.R
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.ExportAwakeCoordinator
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.navigation.NavDestination
import com.healthmd.util.runCatchingCancellable
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.flow.first
import timber.log.Timber

/**
 * Executes one due occurrence for one scheduled export profile (Android phase-6 runtime).
 *
 * Deliberately simpler than the single-schedule [ExportWorker] admission machine: WorkManager
 * unique-work identity (`profile-export-<profileId>`) is the in-flight guard, backoff retries the
 * same durable operation ids, and catch-up math derives uncovered dates from the entry's
 * `lastSuccessEpochMillis`. Frozen output settings and fail-closed destination validation come
 * from the same [com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot] lifecycle.
 */
@HiltWorker
class ScheduledProfileExportWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val settingsRepository: SettingsRepository,
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val exportHistoryRepository: ExportHistoryRepository,
    private val apiEndpointExportRunner: APIEndpointExportRunner,
    private val profileRepository: ExportProfileRepository,
    private val entryStore: ScheduledProfileEntryStore,
    private val snapshotFactory: ScheduledProfileSnapshotFactory,
    private val profileScheduler: dagger.Lazy<ScheduledProfileScheduler>,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result {
        val profileId = inputData.getString(INPUT_PROFILE_ID)
        if (profileId.isNullOrBlank()) return Result.failure()

        val outcome = ExportAwakeCoordinator.shared.whileExporting {
            runForProfile(profileId)
        }

        // Always re-arm the next occurrence for this entry, even after failures:
        // catch-up math covers the gap via lastSuccessEpochMillis.
        runCatchingCancellable { profileScheduler.get().reconcile() }
        return outcome
    }

    override suspend fun getForegroundInfo(): ForegroundInfo {
        val openAppIntent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_START_ROUTE, NavDestination.SCHEDULE.route)
        }
        val contentIntent = PendingIntent.getActivity(
            applicationContext,
            FOREGROUND_NOTIFICATION_ID,
            openAppIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(
            applicationContext,
            HealthMdApplication.EXPORT_CHANNEL_ID,
        )
            .setSmallIcon(android.R.drawable.ic_menu_save)
            .setContentTitle(applicationContext.getString(R.string.export_progress_title))
            .setContentText(applicationContext.getString(R.string.automatic_export_subtitle))
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setContentIntent(contentIntent)
            .setOngoing(true)
            .build()
        val foregroundServiceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        } else 0
        return ForegroundInfo(FOREGROUND_NOTIFICATION_ID, notification, foregroundServiceType)
    }

    private suspend fun runForProfile(profileId: String): Result {
        val entry = entryStore.entry(profileId)
        if (entry == null || !entry.isEnabled) {
            Timber.i("Profile occurrence skipped: entry missing or disabled profileId=%s", profileId)
            return Result.success()
        }
        val profile = profileRepository.profileById(profileId)
        if (profile == null) {
            // Cross-platform rule: never run the wrong profile; disable the orphaned entry.
            Timber.w("Profile occurrence profile missing, disabling entry profileId=%s", profileId)
            entryStore.update(profileId) { it.copy(isEnabled = false) }
            return Result.success()
        }

        val nowMillis = System.currentTimeMillis()
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(entry, nowMillis)
            ?: return Result.success() // Nothing actionable (no boundary passed or fully caught up).

        val current = settingsRepository.getExportSettings()
        val settings = snapshotFactory.restoreForRun(profile, current, entry.lookbackDays)
        if (settings == null) {
            Timber.e("Profile snapshot invalid, disabling entry profileId=%s", profileId)
            recordHistory(
                profile = profile,
                dates = due.exportDates,
                result = ExportResult(
                    successCount = 0,
                    totalCount = due.exportDates.size,
                    failedDateDetails = due.exportDates.map {
                        FailedDateDetail(it, ExportFailureReason.UNKNOWN)
                    },
                ),
                failureReason = ExportFailureReason.UNKNOWN,
                warning = "profile_snapshot_invalid",
                operationId = operationId(profileId, due),
            )
            entryStore.update(profileId) { it.copy(isEnabled = false) }
            showFailureNotification(profile.name)
            return Result.failure()
        }

        val dates = due.exportDates
        val isPurchased = settingsRepository.isPurchased.first()
        if (!isPurchased) {
            // Scheduled automation is a purchased capability on Android; record and stop.
            recordHistory(
                profile = profile,
                dates = dates,
                result = ExportResult(
                    successCount = 0,
                    totalCount = dates.size,
                    failedDateDetails = dates.map { FailedDateDetail(it, ExportFailureReason.PAYWALL_REQUIRED) },
                ),
                failureReason = ExportFailureReason.PAYWALL_REQUIRED,
                warning = "schedule_unlock_required",
                operationId = operationId(profileId, due),
            )
            showFailureNotification(profile.name)
            return Result.failure()
        }

        val hasBackgroundRead = runCatchingCancellable {
            healthRepository.hasBackgroundReadPermission()
        }.getOrDefault(false)
        if (!hasBackgroundRead) {
            recordHistory(
                profile = profile,
                dates = dates,
                result = ExportResult(
                    successCount = 0,
                    totalCount = dates.size,
                    failedDateDetails = dates.map {
                        FailedDateDetail(it, ExportFailureReason.BACKGROUND_PERMISSION_DENIED)
                    },
                ),
                failureReason = ExportFailureReason.BACKGROUND_PERMISSION_DENIED,
                warning = "background_read_denied",
                operationId = operationId(profileId, due),
            )
            showFailureNotification(profile.name)
            return Result.failure()
        }

        val operationId = operationId(profileId, due)
        val target = profile.target
        val snapshotJson = profile.settingsSnapshotJson
        // Durable folder journals require a non-legacy engine pin (mirrors ExportWorker's
        // gating); legacy-pin profiles use the plain non-durable export path instead.
        val enginePin = settings.executionEnginePin
        val useDurableFolder =
            target == ExportTarget.DEVICE_FOLDER &&
                enginePin != null &&
                com.healthmd.domain.exportengine.AndroidDailyAggregateExportPlanner
                    .supportsNonLegacy(settings.copy(exportTarget = ExportTarget.DEVICE_FOLDER))
        val result = try {
            when (target) {
                ExportTarget.DEVICE_FOLDER ->
                    if (useDurableFolder) {
                        ExportOrchestrator(healthRepository, exportRepository)
                            .exportDatesDurably(
                                dates = dates,
                                settings = settings,
                                durableFolderOperationId = "profile-folder-$operationId",
                                durableSettingsSnapshotJson = snapshotJson,
                                requireExistingJournal = runAttemptCount > 0,
                            )
                    } else {
                        ExportOrchestrator(healthRepository, exportRepository)
                            .exportDates(dates, settings)
                    }.copy(target = ExportTarget.DEVICE_FOLDER)

                ExportTarget.API_ENDPOINT ->
                    apiEndpointExportRunner.exportDates(
                        dates = dates,
                        settings = settings.copy(exportTarget = ExportTarget.API_ENDPOINT),
                        durableOperationId = "profile-api-$operationId",
                        durableSettingsSnapshotJson = snapshotJson,
                    )
            }
        } catch (error: kotlinx.coroutines.CancellationException) {
            throw error
        } catch (error: Exception) {
            Timber.e(error, "Profile scheduled export failed profileId=%s", profileId)
            ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = dates.map { FailedDateDetail(it, ExportFailureReason.UNKNOWN) },
            )
        }

        recordHistory(
            profile = profile,
            dates = dates,
            result = result,
            failureReason = result.primaryFailureReason,
            warning = result.warningSummary(),
            operationId = operationId,
        )

        if (result.isFullSuccess) {
            entryStore.recordSuccess(profileId, fireAtMillis = due.fireAtMillis)
        }

        if (!result.isFullSuccess && !result.wasCancelled) {
            showFailureNotification(profile.name)
            return if (runAttemptCount < MAX_WORKER_ATTEMPTS) Result.retry() else Result.failure()
        }
        return Result.success()
    }

    private fun ExportResult.warningSummary(): String? = when {
        isPartialSuccess -> "${failedDateDetails.size} failed date(s) pending retry"
        isFailure -> primaryFailureReason?.name
        else -> null
    }

    private fun operationId(
        profileId: String,
        due: ScheduledProfileEntry.DueOccurrence,
    ): String = "$profileId-${due.fireAtMillis}"

    private suspend fun recordHistory(
        profile: ExportProfile,
        dates: List<java.time.LocalDate>,
        result: ExportResult,
        failureReason: ExportFailureReason?,
        warning: String?,
        operationId: String,
    ) {
        if (dates.isEmpty()) return
        runCatchingCancellable {
            exportHistoryRepository.insertEntry(
                ExportHistoryEntry(
                    timestamp = System.currentTimeMillis(),
                    source = ExportSource.SCHEDULED,
                    dateRangeStart = dates.first(),
                    dateRangeEnd = dates.last(),
                    successCount = result.successCount,
                    totalCount = result.totalCount,
                    failureReason = failureReason,
                    failedDateDetails = result.failedDateDetails,
                    target = profile.target,
                    targetLabel = "${profile.name}",
                    fileCount = result.artifactCount,
                    warningSummary = warning,
                    exportMode = result.exportMode,
                    reconciliationKey = "profile-$operationId",
                    profileName = profile.name,
                ),
            )
        }.onFailure { Timber.e(it, "Could not record profile export history") }
    }

    private fun showFailureNotification(profileName: String) {
        runCatching {
            val manager = applicationContext.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                manager.createNotificationChannel(
                    NotificationChannel(
                        HealthMdApplication.EXPORT_CHANNEL_ID,
                        applicationContext.getString(R.string.export_progress_title),
                        NotificationManager.IMPORTANCE_DEFAULT,
                    ),
                )
            }
            val openAppIntent = Intent(applicationContext, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
                putExtra(MainActivity.EXTRA_START_ROUTE, NavDestination.SCHEDULE.route)
            }
            val contentIntent = PendingIntent.getActivity(
                applicationContext,
                NOTIFICATION_REQUEST_CODE,
                openAppIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
            val notification = NotificationCompat.Builder(
                applicationContext,
                HealthMdApplication.EXPORT_CHANNEL_ID,
            )
                .setSmallIcon(android.R.drawable.ic_menu_save)
                .setContentTitle(
                    applicationContext.getString(R.string.export_notification_title_failed),
                )
                .setContentText(profileName)
                .setAutoCancel(true)
                .setContentIntent(contentIntent)
                .build()
            manager.notify(NOTIFICATION_REQUEST_CODE, notification)
        }
    }

    companion object {
        const val INPUT_PROFILE_ID = "profile_id"
        const val MAX_WORKER_ATTEMPTS = 3
        private const val NOTIFICATION_REQUEST_CODE = 6_100
        private const val FOREGROUND_NOTIFICATION_ID = 6_101
    }
}
