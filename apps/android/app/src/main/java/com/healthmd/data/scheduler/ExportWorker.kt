package com.healthmd.data.scheduler

import android.Manifest
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ForegroundInfo
import androidx.work.WorkerParameters
import com.healthmd.HealthMdApplication
import com.healthmd.R
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.ExportAwakeCoordinator
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.domain.exportengine.AndroidDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.MainActivity
import com.healthmd.rawexport.ExportMode
import com.healthmd.presentation.navigation.NavDestination
import com.healthmd.util.runCatchingCancellable
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.withLock
import java.nio.charset.StandardCharsets
import java.time.LocalDate
import java.util.UUID
import timber.log.Timber

@HiltWorker
class ExportWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
    private val exportHistoryRepository: ExportHistoryRepository,
    private val apiEndpointExportRunner: APIEndpointExportRunner,
    private val rawSnapshotExportRunner: RawSnapshotService,
    private val apiCredentialStore: APIExportCredentialStore,
    private val runCoordinator: ScheduledExportRunCoordinator,
    private val timeCalculator: ScheduledExportTimeCalculator,
) : CoroutineWorker(appContext, workerParams) {

    override suspend fun doWork(): Result = runCoordinator.mutex.withLock {
        ExportAwakeCoordinator.shared.whileExporting {
            doWorkExclusive()
        }
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
        val notification = NotificationCompat.Builder(applicationContext, HealthMdApplication.EXPORT_CHANNEL_ID)
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

    private suspend fun doWorkExclusive(): Result {
        val persistedSettings = settingsRepository.getExportSettings()
        val capturedOccurrence = ScheduledExportOccurrence.fromWorkData(inputData)
        if (
            capturedOccurrence == null &&
            (inputData.getString(INPUT_SCHEDULE_SIGNATURE) != null ||
                ScheduledExportOccurrence.hasDurableEnginePin(inputData) ||
                ScheduledExportOccurrence.hasDurableSettingsSnapshot(inputData))
        ) {
            // Present durable metadata is never discarded or reinterpreted as current settings on a
            // WorkManager retry/resume.
            return Result.failure()
        }
        val enginePin = capturedOccurrence?.enginePin
        val capturedSnapshot = capturedOccurrence?.settingsSnapshot
        val capturedSnapshotJson = capturedOccurrence?.configuration?.canonicalSettingsSnapshotJson
        val capturedTarget = capturedOccurrence?.configuration?.target
            ?: inputData.getString(INPUT_EXPORT_TARGET)
                ?.let { raw -> runCatching { ExportTarget.valueOf(raw) }.getOrNull() }
            ?: persistedSettings.scheduledExportTarget

        if (capturedOccurrence != null) {
            if (!persistedSettings.scheduleEnabled) return Result.success()
            if (persistedSettings.scheduledExportTarget != capturedTarget) return Result.success()
        }

        // Validate current credential/destination plumbing before restoring frozen output choices.
        val currentFingerprint = if (capturedTarget == ExportTarget.API_ENDPOINT) {
            apiCredentialStore.destinationFingerprint(persistedSettings.apiEndpointUrl)
        } else null
        val capturedFingerprint = capturedOccurrence?.configuration?.destinationFingerprint
            ?: inputData.getString(INPUT_DESTINATION_FINGERPRINT)?.takeIf { it.isNotBlank() }
        if (capturedTarget == ExportTarget.API_ENDPOINT &&
            capturedFingerprint != null && capturedFingerprint != currentFingerprint
        ) {
            // A newer schedule points at a different endpoint. Never let this stale worker send to it.
            return Result.success()
        }

        val restoredSettings = try {
            capturedSnapshot?.restoreOnto(persistedSettings) ?: persistedSettings
        } catch (_: Exception) {
            return Result.failure()
        }
        // An accepted occurrence keeps its frozen output settings and intended date window even if
        // mutable preferences or cadence/time are edited while WorkManager is starting it. Inject
        // renderer authority only after restoring the snapshot so it cannot inherit another pin.
        val settings = restoredSettings.copy(
            exportTarget = capturedTarget,
            scheduledExportTarget = capturedTarget,
            scheduleLookbackDays = capturedOccurrence?.configuration?.lookbackDays
                ?: persistedSettings.scheduleLookbackDays,
            scheduleDateWindow = capturedOccurrence?.configuration?.dateWindow
                ?: persistedSettings.scheduleDateWindow,
            executionEnginePin = enginePin,
            executionEngineAuthorityIsFrozen = true,
        )

        val intendedRunDates = if (capturedOccurrence != null) {
            val catchUpThroughMillis = inputData.getLong(
                INPUT_CATCH_UP_THROUGH_MILLIS,
                capturedOccurrence.triggerAtMillis,
            )
            timeCalculator.dueRunDates(capturedOccurrence, catchUpThroughMillis)
                .ifEmpty { listOf(capturedOccurrence.intendedLocalDate) }
        } else {
            listOfNotNull(
                inputData.getString(INPUT_INTENDED_RUN_LOCAL_DATE)
                    ?.let { raw -> runCatching { LocalDate.parse(raw) }.getOrNull() }
            )
        }
        val destinationFingerprint = capturedFingerprint ?: currentFingerprint
        val pendingApiOperationId = if (capturedTarget == ExportTarget.API_ENDPOINT) {
            ScheduledExportPendingRequests.pendingRequests(settings)
                .asSequence()
                .filter { it.exportTarget == ExportTarget.API_ENDPOINT }
                .filter { it.destinationFingerprint == destinationFingerprint }
                .filter { it.enginePin == enginePin }
                .filter {
                    it.settingsSnapshotJson == null ||
                        it.settingsSnapshotJson == capturedSnapshotJson
                }
                .mapNotNull { it.apiOperationId }
                .firstOrNull()
        } else null
        val durableApiOperationId = if (capturedTarget == ExportTarget.API_ENDPOINT) {
            pendingApiOperationId ?: id.toString()
        } else null
        val matchingFolderRequests = if (capturedTarget == ExportTarget.DEVICE_FOLDER) {
            ScheduledExportPendingRequests.pendingRequests(settings)
                .filter { it.exportTarget == ExportTarget.DEVICE_FOLDER }
                .filter { it.enginePin == enginePin }
                .filter {
                    it.settingsSnapshotJson == null ||
                        it.settingsSnapshotJson == capturedSnapshotJson
                }
        } else {
            emptyList()
        }
        val pendingFolderOperationId = matchingFolderRequests
            .mapNotNull { it.folderOperationId }
            .firstOrNull()
        val hasFreshFolderRetry = matchingFolderRequests.any { it.folderOperationId == null }
        val durableFolderOperationId = if (
            capturedTarget == ExportTarget.DEVICE_FOLDER &&
            enginePin != null &&
            capturedSnapshotJson != null &&
            AndroidDailyAggregateExportPlanner.supportsNonLegacy(
                settings.copy(exportTarget = ExportTarget.DEVICE_FOLDER),
            )
        ) {
            pendingFolderOperationId ?: buildString {
                append("folder-").append(capturedOccurrence?.id ?: id)
                if (hasFreshFolderRetry) append("-retry-").append(runAttemptCount)
            }
        } else null
        val isPurchased = settingsRepository.isPurchased.first()
        val dates = scheduledDates(
            settings,
            destinationFingerprint,
            intendedRunDates,
            enginePin,
            capturedSnapshotJson,
            durableApiOperationId,
            pendingApiOperationId != null,
            durableFolderOperationId,
            pendingFolderOperationId != null,
        )
        if (dates.isEmpty()) return Result.success()
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
            persistPendingRetryDates(
                dates,
                ExportFailureReason.PAYWALL_REQUIRED,
                settings.scheduledExportTarget,
                destinationFingerprint,
                enginePin,
                capturedSnapshotJson,
            )
            showNotification(
                applicationContext.getString(R.string.export_notification_title_failed),
                applicationContext.getString(R.string.schedule_unlock_required_short),
                NavDestination.SCHEDULE.route,
                promptRecovery = true,
            )
            return Result.failure()
        }

        if (capturedTarget == ExportTarget.DEVICE_FOLDER &&
            (enginePin != null || pendingFolderOperationId != null) &&
            durableFolderOperationId == null
        ) {
            val failureDetails = dates.map { date ->
                FailedDateDetail(date, ExportFailureReason.UNKNOWN)
            }
            val result = ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = failureDetails,
                target = ExportTarget.DEVICE_FOLDER,
            )
            exportHistoryRepository.insertEntry(
                historyEntry(
                    settings = settings,
                    dates = dates,
                    result = result,
                    failureReason = ExportFailureReason.UNKNOWN,
                    warning = null,
                ),
            )
            persistPendingRetryDates(
                attemptedDates = dates,
                failedDateDetails = failureDetails,
                target = ExportTarget.DEVICE_FOLDER,
                destinationFingerprint = destinationFingerprint,
                enginePin = enginePin,
                settingsSnapshotJson = capturedSnapshotJson,
            )
            return Result.failure()
        }

        val canResumeStoredFolder = durableFolderOperationId != null &&
            capturedSnapshotJson != null &&
            exportRepository.hasResumableDurableScheduledFolderOperation(
                operationId = durableFolderOperationId,
                dates = dates,
                settings = settings,
                settingsSnapshotJson = capturedSnapshotJson,
            )
        val backgroundPermissionResult = if (
            pendingApiOperationId == null && !canResumeStoredFolder
        ) {
            runCatchingCancellable {
                healthRepository.hasBackgroundReadPermission()
            }
        } else {
            kotlin.Result.success(true)
        }
        backgroundPermissionResult.exceptionOrNull()?.let { error ->
            Timber.e(error, "Unable to verify background health access for scheduled export")
        }
        if (!backgroundPermissionResult.getOrDefault(false)) {
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
                    target = settings.scheduledExportTarget,
                    targetLabel = targetLabel(settings, endDate),
                    fileCount = 0,
                    warningSummary = applicationContext.getString(R.string.export_notification_background_permission_required),
                    exportMode = settings.exportMode,
                )
            )
            persistPendingRetryDates(
                dates,
                ExportFailureReason.BACKGROUND_PERMISSION_DENIED,
                settings.scheduledExportTarget,
                destinationFingerprint,
                enginePin,
                capturedSnapshotJson,
            )
            showNotification(
                applicationContext.getString(R.string.export_notification_title_failed),
                applicationContext.getString(R.string.export_notification_background_permission_required),
                NavDestination.SCHEDULE.route,
                promptRecovery = true,
            )
            return Result.failure()
        }

        return try {
            val result = if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                rawSnapshotExportRunner.exportRange(
                    startDate = dates.first(),
                    endDate = dates.last(),
                    settings = settings,
                    target = settings.scheduledExportTarget,
                    expectedDestinationFingerprint = destinationFingerprint,
                )
            } else when (settings.scheduledExportTarget) {
                ExportTarget.DEVICE_FOLDER -> {
                    val orchestrator = ExportOrchestrator(healthRepository, exportRepository)
                    if (durableFolderOperationId != null && capturedSnapshotJson != null) {
                        orchestrator.exportDatesDurably(
                            dates = dates,
                            settings = settings,
                            durableFolderOperationId = durableFolderOperationId,
                            durableSettingsSnapshotJson = capturedSnapshotJson,
                            requireExistingJournal = pendingFolderOperationId != null ||
                                (runAttemptCount > 0 && !hasFreshFolderRetry),
                        )
                    } else {
                        orchestrator.exportDates(dates, settings)
                    }.copy(target = ExportTarget.DEVICE_FOLDER)
                }
                ExportTarget.API_ENDPOINT -> apiEndpointExportRunner.exportDates(
                    dates = dates,
                    settings = settings.copy(exportTarget = ExportTarget.API_ENDPOINT),
                    expectedDestinationFingerprint = destinationFingerprint,
                    durableOperationId = durableApiOperationId,
                    durableSettingsSnapshotJson = capturedSnapshotJson,
                )
            }

            exportHistoryRepository.insertEntry(
                historyEntry(
                    settings = settings,
                    dates = dates,
                    result = result,
                    failureReason = result.primaryFailureReason,
                    warning = result.warningSummary(),
                    reconciliationKey = scheduledReconciliationKey(
                        target = settings.scheduledExportTarget,
                        operationId = durableFolderOperationId ?: durableApiOperationId,
                        dates = dates,
                    ),
                )
            )

            val retryDetails = if (settings.exportMode == ExportMode.RAW_SNAPSHOT && !result.isFullSuccess) {
                // One raw action covers the whole range for every requested provider. Until every
                // artifact is complete, retain every attempted date rather than only startDate.
                val failure = result.failedDateDetails.firstOrNull() ?: FailedDateDetail(
                    dates.first(), ExportFailureReason.RAW_PARTIAL, "One or more raw provider artifacts are incomplete.",
                )
                dates.map { failure.copy(date = it) }
            } else {
                result.failedDateDetails
            }
            persistPendingRetryDates(
                dates,
                retryDetails,
                settings.scheduledExportTarget,
                destinationFingerprint,
                enginePin,
                capturedSnapshotJson,
                result.retryOperationIds,
                result.retryFolderOperationIds,
                result.freshCaptureRetryDates,
            )
            val allFailuresDetachedForFreshCapture = result.failedDateDetails.all { failure ->
                failure.date in result.freshCaptureRetryDates
            }
            if (durableApiOperationId != null &&
                result.retryOperationIds.isEmpty() &&
                !result.wasCancelled &&
                allFailuresDetachedForFreshCapture
            ) {
                apiEndpointExportRunner.discardCompletedDurableOperation(durableApiOperationId)
            }
            if (durableFolderOperationId != null &&
                result.retryFolderOperationIds.isEmpty() &&
                !result.wasCancelled &&
                allFailuresDetachedForFreshCapture
            ) {
                exportRepository.discardDurableScheduledFolderOperation(durableFolderOperationId)
            }

            val titleResId = when {
                result.isFullSuccess -> R.string.export_notification_title_complete
                result.isPartialSuccess -> R.string.export_notification_title_partial
                else -> R.string.export_notification_title_failed
            }
            showNotification(
                applicationContext.getString(titleResId),
                if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                    applicationContext.getString(
                        R.string.raw_snapshot_notification_message,
                        endDate,
                        applicationContext.getString(
                            if (result.isFullSuccess) R.string.raw_snapshot_status_complete else R.string.raw_snapshot_status_failed,
                        ),
                    )
                } else {
                    applicationContext.getString(
                        R.string.export_notification_message_days_exported,
                        result.successCount,
                        result.totalCount,
                        endDate,
                    )
                },
                if (result.isFullSuccess) NavDestination.EXPORT.route else NavDestination.SCHEDULE.route,
                promptRecovery = !result.isFullSuccess,
            )

            if (result.successCount > 0) {
                Result.success()
            } else if (result.primaryFailureReason == ExportFailureReason.DEVICE_LOCKED) {
                Result.retry()
            } else if (result.primaryFailureReason == ExportFailureReason.BACKGROUND_PERMISSION_DENIED) {
                Result.failure()
            } else if (shouldRetry(result) && runAttemptCount < 3) {
                Result.retry()
            } else {
                Result.failure()
            }
        } catch (error: kotlinx.coroutines.CancellationException) {
            throw error
        } catch (e: Exception) {
            persistPendingRetryDates(
                dates,
                ExportFailureReason.UNKNOWN,
                settings.scheduledExportTarget,
                destinationFingerprint,
                enginePin,
                capturedSnapshotJson,
                durableFolderOperationId,
            )
            showNotification(
                applicationContext.getString(R.string.export_notification_title_failed),
                e.message ?: applicationContext.getString(R.string.export_notification_unknown_error),
                NavDestination.SCHEDULE.route,
                promptRecovery = true,
            )
            if (runAttemptCount < 3) Result.retry() else Result.failure()
        }
    }

    private fun scheduledDates(
        settings: ExportSettings,
        destinationFingerprint: String?,
        intendedRunDates: List<LocalDate>,
        enginePin: ExportEnginePin?,
        settingsSnapshotJson: String?,
        apiOperationId: String?,
        resumeExistingApiOperation: Boolean,
        folderOperationId: String?,
        resumeExistingFolderOperation: Boolean,
    ): List<LocalDate> = ScheduledExportPendingRequests.scheduledRunDates(
        settings = settings,
        intendedRunDates = intendedRunDates.ifEmpty { listOf(LocalDate.now()) },
        destinationFingerprint = destinationFingerprint,
        enginePin = enginePin,
        settingsSnapshotJson = settingsSnapshotJson,
        apiOperationId = apiOperationId,
        resumeExistingApiOperation = resumeExistingApiOperation,
        folderOperationId = folderOperationId,
        resumeExistingFolderOperation = resumeExistingFolderOperation,
    )

    private suspend fun persistPendingRetryDates(
        attemptedDates: List<LocalDate>,
        failedDateDetails: List<FailedDateDetail>,
        target: ExportTarget,
        destinationFingerprint: String?,
        enginePin: ExportEnginePin?,
        settingsSnapshotJson: String?,
        apiOperationIds: Map<LocalDate, String> = emptyMap(),
        folderOperationIds: Map<LocalDate, String> = emptyMap(),
        freshCaptureRetryDates: Set<LocalDate> = emptySet(),
    ) {
        val latestSettings = settingsRepository.getExportSettings()
        settingsRepository.updateExportSettings(
            ScheduledExportPendingRequests.applyAttemptResult(
                settings = latestSettings,
                attemptedDates = attemptedDates,
                failedDateDetails = failedDateDetails,
                target = target,
                destinationFingerprint = destinationFingerprint,
                enginePin = enginePin,
                settingsSnapshotJson = settingsSnapshotJson,
                apiOperationIds = apiOperationIds,
                folderOperationIds = folderOperationIds,
                freshCaptureRetryDates = freshCaptureRetryDates,
            )
        )
    }

    private suspend fun persistPendingRetryDates(
        attemptedDates: List<LocalDate>,
        failureReason: ExportFailureReason,
        target: ExportTarget,
        destinationFingerprint: String?,
        enginePin: ExportEnginePin?,
        settingsSnapshotJson: String?,
        folderOperationId: String? = null,
    ) {
        val latestSettings = settingsRepository.getExportSettings()
        settingsRepository.updateExportSettings(
            ScheduledExportPendingRequests.recordFailedDates(
                settings = latestSettings,
                dates = attemptedDates,
                reason = failureReason,
                target = target,
                destinationFingerprint = destinationFingerprint,
                enginePin = enginePin,
                settingsSnapshotJson = settingsSnapshotJson,
                folderOperationIds = folderOperationId?.let { operationId ->
                    attemptedDates.associateWith { operationId }
                }.orEmpty(),
            )
        )
    }

    private fun historyEntry(
        settings: ExportSettings,
        dates: List<LocalDate>,
        result: ExportResult,
        failureReason: ExportFailureReason?,
        warning: String?,
        reconciliationKey: String? = null,
    ): ExportHistoryEntry = ExportHistoryEntry(
        timestamp = System.currentTimeMillis(),
        source = ExportSource.SCHEDULED,
        dateRangeStart = dates.first(),
        dateRangeEnd = dates.last(),
        successCount = result.successCount,
        totalCount = result.totalCount,
        failureReason = failureReason,
        failedDateDetails = result.failedDateDetails,
        target = settings.scheduledExportTarget,
        targetLabel = targetLabel(settings, dates.last()),
        fileCount = if (settings.scheduledExportTarget == ExportTarget.DEVICE_FOLDER) {
            when {
                settings.exportMode == ExportMode.RAW_SNAPSHOT -> result.artifactCount
                result.usesDurableFolderJournal -> result.artifactCount
                else -> result.successCount * settings.selectedExportFormats.size
            }
        } else 0,
        warningSummary = warning,
        exportMode = settings.exportMode,
        reconciliationKey = reconciliationKey,
    )

    private fun scheduledReconciliationKey(
        target: ExportTarget,
        operationId: String?,
        dates: List<LocalDate>,
    ): String? = operationId?.let { id ->
        val stable = buildString {
            append("healthmd-scheduled-history-v1\n")
            append(target.name).append('\n')
            append(id).append('\n')
            dates.forEach { date -> append(date).append('\n') }
        }
        "scheduled-${UUID.nameUUIDFromBytes(stable.toByteArray(StandardCharsets.UTF_8))}"
    }

    private fun targetLabel(settings: ExportSettings, date: LocalDate): String =
        if (settings.scheduledExportTarget == ExportTarget.API_ENDPOINT) {
            APIExportEndpoint.redactedDescription(settings.apiEndpointUrl)
        } else buildString {
            val subfolder = settings.subfolder.trim('/').takeIf { it.isNotBlank() }
            append(subfolder ?: applicationContext.getString(R.string.export_folder_root_label))
            settings.formatFolderPath(date)?.takeIf { it.isNotBlank() }?.let {
                append("/").append(it.trim('/'))
            }
        }

    private fun shouldRetry(result: ExportResult): Boolean = when (result.primaryFailureReason) {
        ExportFailureReason.DEVICE_LOCKED,
        ExportFailureReason.RATE_LIMITED,
        ExportFailureReason.NETWORK_ERROR -> true
        ExportFailureReason.API_REJECTED -> {
            val status = result.httpStatusCode
            status == 408 || status == 429 || (status != null && status >= 500)
        }
        ExportFailureReason.RAW_PARTIAL -> true
        else -> false
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
        const val INPUT_EXPORT_TARGET = ScheduledExportOccurrence.KEY_TARGET
        const val INPUT_DESTINATION_FINGERPRINT = ScheduledExportOccurrence.KEY_DESTINATION_FINGERPRINT
        const val INPUT_SCHEDULE_SIGNATURE = ScheduledExportOccurrence.KEY_SIGNATURE
        const val INPUT_INTENDED_RUN_AT_MILLIS = ScheduledExportOccurrence.KEY_TRIGGER_AT_MILLIS
        const val INPUT_CATCH_UP_THROUGH_MILLIS = ScheduledExportOccurrence.KEY_CATCH_UP_THROUGH_MILLIS
        const val INPUT_INTENDED_RUN_LOCAL_DATE = ScheduledExportOccurrence.KEY_INTENDED_LOCAL_DATE
        const val INPUT_INTENDED_ZONE_ID = ScheduledExportOccurrence.KEY_ZONE_ID
        private const val FOREGROUND_NOTIFICATION_ID = 6_042
    }
}
