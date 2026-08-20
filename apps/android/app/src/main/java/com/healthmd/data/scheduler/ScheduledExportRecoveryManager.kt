package com.healthmd.data.scheduler

import android.content.Context
import com.healthmd.R
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.ExportAwakeCoordinator
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.data.drive.GoogleDriveDestinationRunner
import com.healthmd.data.drive.GoogleDriveDestinationStore
import com.healthmd.data.drive.GoogleDriveExportOrchestrator
import com.healthmd.data.drive.GoogleDriveRunResult
import com.healthmd.data.drive.GoogleDriveSelectionStore
import com.healthmd.data.drive.toFailureReason
import com.healthmd.domain.exportengine.AndroidDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.EXPORT_FOLDER_ROOT_TARGET_LABEL
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.ExportMode
import kotlinx.coroutines.flow.first
import java.time.LocalDate
import java.nio.charset.StandardCharsets
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import dagger.hilt.android.qualifiers.ApplicationContext
import timber.log.Timber

@Singleton
class ScheduledExportRecoveryManager @Inject constructor(
    @ApplicationContext private val applicationContext: Context,
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
    private val exportHistoryRepository: ExportHistoryRepository,
    private val apiEndpointExportRunner: APIEndpointExportRunner? = null,
    private val rawSnapshotService: RawSnapshotService? = null,
    private val apiCredentialStore: APIExportCredentialStore? = null,
    private val runCoordinator: ScheduledExportRunCoordinator = ScheduledExportRunCoordinator(),
    private val googleDriveExportOrchestrator: GoogleDriveExportOrchestrator,
    private val googleDriveDestinationRunner: GoogleDriveDestinationRunner,
    private val googleDriveSelectionStore: GoogleDriveSelectionStore,
    private val googleDriveDestinationStore: GoogleDriveDestinationStore,
) {

    suspend fun inspectPendingRecovery(): ScheduledExportRecoveryStatus {
        val settings = settingsRepository.getExportSettings()
        val pendingDates = ScheduledExportPendingRequests.pendingDates(settings)

        if (pendingDates.isEmpty()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = emptyList(),
                blocker = ScheduledExportRecoveryBlocker.NO_PENDING_DATES,
            )
        }

        if (runCoordinator.mutex.isLocked) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.ALREADY_RUNNING,
            )
        }

        if (!settingsRepository.isPurchased.first()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.PAYWALL_REQUIRED,
            )
        }

        destinationBlocker(settings)?.let { blocker ->
            return ScheduledExportRecoveryStatus(pendingDates = pendingDates, blocker = blocker)
        }

        val canResumeStoredOperation = hasResumableStoredAPIRequest(settings) ||
            hasResumableStoredFolderRequest(settings)
        if (!canResumeStoredOperation && healthRepository.isBeforeFirstUnlock()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.DEVICE_LOCKED,
            )
        }

        if (!canResumeStoredOperation && !healthRepository.hasPermissions()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.HEALTH_PERMISSIONS_REQUIRED,
            )
        }

        return ScheduledExportRecoveryStatus(pendingDates = pendingDates)
    }

    suspend fun recoverPendingDates(): ScheduledExportRecoveryRunResult {
        if (!runCoordinator.mutex.tryLock()) {
            val settings = settingsRepository.getExportSettings()
            return ScheduledExportRecoveryRunResult(
                status = ScheduledExportRecoveryRunStatus.ALREADY_RUNNING,
                pendingDates = ScheduledExportPendingRequests.pendingDates(settings),
                blocker = ScheduledExportRecoveryBlocker.ALREADY_RUNNING,
            )
        }

        val awakeActivityId = ExportAwakeCoordinator.shared.beginActivity()
        return try {
            val status = inspectPendingRecoveryIgnoringLock()
            if (!status.canRecover) {
                return ScheduledExportRecoveryRunResult(
                    status = ScheduledExportRecoveryRunStatus.BLOCKED,
                    pendingDates = status.pendingDates,
                    blocker = status.blocker,
                )
            }

            val settings = settingsRepository.getExportSettings()
            val cutoff = LocalDate.now().minusDays(1)
            val pendingByTarget = ScheduledExportPendingRequests.pendingRequests(settings)
                .filter { !it.date.isAfter(cutoff) }
                .groupBy { request ->
                    PendingRecoveryOperation(
                        target = request.exportTarget,
                        destinationFingerprint = request.destinationFingerprint,
                        enginePin = request.enginePin,
                        settingsSnapshotJson = request.settingsSnapshotJson,
                        apiOperationId = request.apiOperationId,
                        folderOperationId = request.folderOperationId,
                        driveOperationId = request.driveOperationId,
                    )
                }

            var latestSettings = settings
            var totalSuccessCount = 0
            var totalCount = 0
            val allFailures = mutableListOf<FailedDateDetail>()

            for ((operation, requests) in pendingByTarget) {
                val target = operation.target
                val targetDates = requests.map { it.date }.distinct().sorted()
                val resumesStoredAPI = target == ExportTarget.API_ENDPOINT &&
                    operation.apiOperationId != null
                val destinationFingerprint = operation.destinationFingerprint
                val enginePin = operation.enginePin
                val settingsSnapshotJson = operation.settingsSnapshotJson
                val durableApiOperationId = if (target == ExportTarget.API_ENDPOINT) {
                    operation.apiOperationId ?: deterministicRecoveryOperationId(
                        targetDates = requests.map { it.date }.distinct().sorted(),
                        destinationFingerprint = destinationFingerprint,
                        enginePin = enginePin,
                        settingsSnapshotJson = settingsSnapshotJson,
                    )
                } else null
                if (!isDestinationReady(settings, target, destinationFingerprint)) continue
                val restoredOutputSettings = runCatching {
                    if (settingsSnapshotJson == null) {
                        // Explicit old-request compatibility: output settings are read at recovery.
                        settings
                    } else {
                        val snapshot = AndroidExportSettingsSnapshotCodec.decode(settingsSnapshotJson)
                        require(snapshot.enginePin == enginePin)
                        require(snapshot.scheduledExportTarget == target)
                        snapshot.restoreOnto(settings)
                    }
                }.onFailure { error ->
                    Timber.e(error, "Scheduled recovery settings snapshot is invalid")
                }.getOrNull()
                // Inject the exact persisted pin only after restoring the immutable settings.
                val targetSettings = (restoredOutputSettings ?: settings).copy(
                    exportTarget = target,
                    scheduledExportTarget = target,
                    executionEnginePin = enginePin,
                    executionEngineAuthorityIsFrozen = true,
                )
                val recoveryFolderUri = if (target == ExportTarget.DEVICE_FOLDER) {
                    settingsRepository.getExportFolderUri()
                } else {
                    null
                }
                val durableFolderOperationId = if (
                    target == ExportTarget.DEVICE_FOLDER &&
                    enginePin != null &&
                    settingsSnapshotJson != null &&
                    recoveryFolderUri != null &&
                    AndroidDailyAggregateExportPlanner.supportsNonLegacy(targetSettings)
                ) {
                    operation.folderOperationId ?: deterministicFolderRecoveryOperationId(
                        targetDates = targetDates,
                        enginePin = enginePin,
                        settingsSnapshotJson = settingsSnapshotJson,
                        folderUri = recoveryFolderUri,
                        retryGeneration = requests
                            .sortedBy { it.date }
                            .joinToString("|") { request ->
                                "${request.date}:${request.firstFailedAtMillis}:" +
                                    "${request.lastAttemptAtMillis}:${request.attemptCount}"
                            },
                    )
                } else null
                val resumesStoredFolder = durableFolderOperationId != null &&
                    settingsSnapshotJson != null &&
                    exportRepository.hasResumableDurableScheduledFolderOperation(
                        operationId = durableFolderOperationId,
                        dates = targetDates,
                        settings = targetSettings,
                        settingsSnapshotJson = settingsSnapshotJson,
                    )
                if (!resumesStoredAPI && !resumesStoredFolder &&
                    (healthRepository.isBeforeFirstUnlock() || !healthRepository.hasPermissions())
                ) {
                    continue
                }
                val targetResult = if (restoredOutputSettings == null ||
                    (target == ExportTarget.DEVICE_FOLDER &&
                        (enginePin != null || operation.folderOperationId != null) &&
                        durableFolderOperationId == null)
                ) {
                    snapshotFailure(targetDates, target)
                } else try {
                    if (target == ExportTarget.GOOGLE_DRIVE && operation.driveOperationId != null) {
                        when (val resumed = googleDriveDestinationRunner.resume(operation.driveOperationId)) {
                            is GoogleDriveRunResult.Complete -> ExportResult(
                                targetDates.size,
                                targetDates.size,
                                target = ExportTarget.GOOGLE_DRIVE,
                                artifactCount = resumed.artifactCount,
                                exportMode = targetSettings.exportMode,
                            )
                            is GoogleDriveRunResult.Stopped -> ExportResult(
                                0,
                                targetDates.size,
                                targetDates.map { FailedDateDetail(it, resumed.error.toFailureReason()) },
                                target = ExportTarget.GOOGLE_DRIVE,
                                artifactCount = resumed.completedArtifactCount,
                                retryDriveOperationIds = targetDates.associateWith { operation.driveOperationId },
                                exportMode = targetSettings.exportMode,
                            )
                        }
                    } else if (targetSettings.exportMode == ExportMode.RAW_SNAPSHOT) {
                        rawSnapshotService?.exportRange(
                            startDate = targetDates.first(),
                            endDate = targetDates.last(),
                            settings = targetSettings,
                            target = target,
                            expectedDestinationFingerprint = destinationFingerprint,
                        ) ?: ExportResult(
                            successCount = 0,
                            totalCount = 1,
                            failedDateDetails = listOf(
                                FailedDateDetail(targetDates.first(), ExportFailureReason.UNKNOWN),
                            ),
                            target = target,
                            exportMode = ExportMode.RAW_SNAPSHOT,
                        ).also {
                            Timber.w("Raw snapshot service unavailable during scheduled recovery")
                        }
                    } else when (target) {
                        ExportTarget.DEVICE_FOLDER -> {
                            val orchestrator = ExportOrchestrator(healthRepository, exportRepository)
                            if (durableFolderOperationId != null && settingsSnapshotJson != null) {
                                orchestrator.exportDatesDurably(
                                    dates = targetDates,
                                    settings = targetSettings,
                                    durableFolderOperationId = durableFolderOperationId,
                                    durableSettingsSnapshotJson = settingsSnapshotJson,
                                    requireExistingJournal = operation.folderOperationId != null,
                                )
                            } else {
                                orchestrator.exportDates(targetDates, targetSettings)
                            }.copy(target = ExportTarget.DEVICE_FOLDER)
                        }
                        ExportTarget.API_ENDPOINT -> apiEndpointExportRunner?.exportDates(
                            dates = targetDates,
                            settings = targetSettings,
                            expectedDestinationFingerprint = destinationFingerprint,
                            durableOperationId = durableApiOperationId,
                            durableSettingsSnapshotJson = settingsSnapshotJson,
                        ) ?: ExportResult(
                            successCount = 0,
                            totalCount = targetDates.size,
                            failedDateDetails = targetDates.map {
                                FailedDateDetail(it, ExportFailureReason.NETWORK_ERROR)
                            },
                            target = ExportTarget.API_ENDPOINT,
                        ).also {
                            Timber.w("API export service unavailable during scheduled recovery")
                        }
                        ExportTarget.GOOGLE_DRIVE -> googleDriveSelectionStore.get()?.let { destinationId ->
                            googleDriveExportOrchestrator.exportDates(
                                targetDates,
                                targetSettings,
                                destinationId,
                                source = "retry",
                                operationId = deterministicRecoveryOperationId(
                                    targetDates,
                                    destinationFingerprint,
                                    enginePin,
                                    settingsSnapshotJson,
                                ),
                                settingsSnapshotJson = settingsSnapshotJson,
                            )
                        } ?: ExportResult(
                            successCount = 0,
                            totalCount = targetDates.size,
                            failedDateDetails = targetDates.map {
                                FailedDateDetail(it, ExportFailureReason.NO_FOLDER_SELECTED)
                            },
                            target = ExportTarget.GOOGLE_DRIVE,
                        )
                    }
                } catch (error: Exception) {
                    Timber.e(error, "Scheduled export recovery failed")
                    ExportResult(
                        successCount = 0,
                        totalCount = targetDates.size,
                        failedDateDetails = targetDates.map {
                            FailedDateDetail(it, ExportFailureReason.UNKNOWN)
                        },
                        target = target,
                    )
                }

                // Record the attempt before clearing any pending identity. A history failure leaves
                // both the pending request and exact journal available for another reconciliation.
                exportHistoryRepository.insertEntry(
                    historyEntry(
                        settings = targetSettings,
                        dates = targetDates,
                        result = targetResult,
                        target = target,
                        reconciliationKey = scheduledReconciliationKey(
                            target = target,
                            operationId = durableFolderOperationId ?: durableApiOperationId,
                            dates = targetDates,
                        ),
                    )
                )

                // Merge only this attempt's pending-date result into the latest settings so a
                // concurrent endpoint/schedule edit is never overwritten by the recovery snapshot.
                val currentSettings = settingsRepository.getExportSettings()
                val retryDetails = if (targetSettings.exportMode == ExportMode.RAW_SNAPSHOT && !targetResult.isFullSuccess) {
                    val failure = targetResult.failedDateDetails.firstOrNull() ?: FailedDateDetail(
                        targetDates.first(),
                        ExportFailureReason.RAW_PARTIAL,
                    )
                    targetDates.map { failure.copy(date = it) }
                } else {
                    targetResult.failedDateDetails
                }
                latestSettings = ScheduledExportPendingRequests.applyAttemptResult(
                    settings = currentSettings,
                    attemptedDates = targetDates,
                    failedDateDetails = retryDetails,
                    target = target,
                    destinationFingerprint = destinationFingerprint,
                    enginePin = enginePin,
                    settingsSnapshotJson = settingsSnapshotJson,
                    apiOperationIds = targetResult.retryOperationIds,
                    folderOperationIds = targetResult.retryFolderOperationIds,
                    driveOperationIds = targetResult.retryDriveOperationIds,
                    freshCaptureRetryDates = targetResult.freshCaptureRetryDates,
                )
                settingsRepository.updateExportSettings(latestSettings)
                val allFailuresDetachedForFreshCapture =
                    targetResult.failedDateDetails.all { failure ->
                        failure.date in targetResult.freshCaptureRetryDates
                    }
                if (durableApiOperationId != null &&
                    targetResult.retryOperationIds.isEmpty() &&
                    !targetResult.wasCancelled &&
                    allFailuresDetachedForFreshCapture
                ) {
                    apiEndpointExportRunner?.discardCompletedDurableOperation(durableApiOperationId)
                }
                if (durableFolderOperationId != null &&
                    targetResult.retryFolderOperationIds.isEmpty() &&
                    !targetResult.wasCancelled &&
                    allFailuresDetachedForFreshCapture
                ) {
                    exportRepository.discardDurableScheduledFolderOperation(durableFolderOperationId)
                }

                totalSuccessCount += targetResult.successCount
                totalCount += targetResult.totalCount
                allFailures += targetResult.failedDateDetails
            }

            val aggregateResult = ExportResult(
                successCount = totalSuccessCount,
                totalCount = totalCount,
                failedDateDetails = allFailures,
                exportMode = settings.exportMode,
            )
            val remainingDates = ScheduledExportPendingRequests.pendingDates(
                settingsRepository.getExportSettings()
            )
            ScheduledExportRecoveryRunResult(
                status = ScheduledExportRecoveryRunStatus.COMPLETED,
                pendingDates = remainingDates,
                exportResult = aggregateResult,
            )
        } finally {
            ExportAwakeCoordinator.shared.endActivity(awakeActivityId)
            runCoordinator.mutex.unlock()
        }
    }

    private fun deterministicRecoveryOperationId(
        targetDates: List<LocalDate>,
        destinationFingerprint: String?,
        enginePin: ExportEnginePin?,
        settingsSnapshotJson: String?,
    ): String {
        val stable = buildString {
            append("healthmd-api-recovery-v1\n")
            append(destinationFingerprint.orEmpty()).append('\n')
            append(enginePin?.let(com.healthmd.domain.exportengine.ExportEnginePinCodec::encodeCanonical).orEmpty())
                .append('\n')
            append(settingsSnapshotJson.orEmpty()).append('\n')
            targetDates.forEach { append(it).append('\n') }
        }
        return UUID.nameUUIDFromBytes(stable.toByteArray(StandardCharsets.UTF_8)).toString()
    }

    private fun deterministicFolderRecoveryOperationId(
        targetDates: List<LocalDate>,
        enginePin: ExportEnginePin,
        settingsSnapshotJson: String,
        folderUri: String,
        retryGeneration: String,
    ): String {
        val stable = buildString {
            append("healthmd-folder-recovery-v1\n")
            append(com.healthmd.domain.exportengine.ExportEnginePinCodec.encodeCanonical(enginePin))
                .append('\n')
            append(settingsSnapshotJson).append('\n')
            append(folderUri).append('\n')
            append(retryGeneration).append('\n')
            targetDates.forEach { append(it).append('\n') }
        }
        return "folder-${UUID.nameUUIDFromBytes(stable.toByteArray(StandardCharsets.UTF_8))}"
    }

    private fun snapshotFailure(
        dates: List<LocalDate>,
        target: ExportTarget,
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = dates.size,
        failedDateDetails = dates.map { date ->
            FailedDateDetail(
                date = date,
                reason = ExportFailureReason.UNKNOWN,
            )
        },
        target = target,
    )

    private suspend fun inspectPendingRecoveryIgnoringLock(): ScheduledExportRecoveryStatus {
        val settings = settingsRepository.getExportSettings()
        val pendingDates = ScheduledExportPendingRequests.pendingDates(settings)

        if (pendingDates.isEmpty()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = emptyList(),
                blocker = ScheduledExportRecoveryBlocker.NO_PENDING_DATES,
            )
        }
        if (!settingsRepository.isPurchased.first()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.PAYWALL_REQUIRED,
            )
        }
        destinationBlocker(settings)?.let { blocker ->
            return ScheduledExportRecoveryStatus(pendingDates = pendingDates, blocker = blocker)
        }
        val canResumeStoredOperation = hasResumableStoredAPIRequest(settings) ||
            hasResumableStoredFolderRequest(settings)
        if (!canResumeStoredOperation && healthRepository.isBeforeFirstUnlock()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.DEVICE_LOCKED,
            )
        }
        if (!canResumeStoredOperation && !healthRepository.hasPermissions()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.HEALTH_PERMISSIONS_REQUIRED,
            )
        }
        return ScheduledExportRecoveryStatus(pendingDates = pendingDates)
    }

    private suspend fun hasResumableStoredAPIRequest(settings: ExportSettings): Boolean =
        ScheduledExportPendingRequests.pendingRequests(settings).any { request ->
            request.exportTarget == ExportTarget.API_ENDPOINT &&
                request.apiOperationId != null &&
                isDestinationReady(settings, request.exportTarget, request.destinationFingerprint)
        }

    private suspend fun hasResumableStoredFolderRequest(settings: ExportSettings): Boolean {
        val groups = ScheduledExportPendingRequests.pendingRequests(settings)
            .filter { request ->
                request.exportTarget == ExportTarget.DEVICE_FOLDER &&
                    request.folderOperationId != null &&
                    request.settingsSnapshotJson != null
            }
            .groupBy { request ->
                Triple(
                    requireNotNull(request.folderOperationId),
                    request.enginePin,
                    requireNotNull(request.settingsSnapshotJson),
                )
            }
        return groups.any { (identity, requests) ->
            val (operationId, enginePin, snapshotJson) = identity
            val targetSettings = runCatching {
                val snapshot = AndroidExportSettingsSnapshotCodec.decode(snapshotJson)
                require(snapshot.enginePin == enginePin)
                require(snapshot.scheduledExportTarget == ExportTarget.DEVICE_FOLDER)
                snapshot.restoreOnto(settings).copy(
                    exportTarget = ExportTarget.DEVICE_FOLDER,
                    scheduledExportTarget = ExportTarget.DEVICE_FOLDER,
                    executionEnginePin = enginePin,
                    executionEngineAuthorityIsFrozen = true,
                )
            }.getOrNull() ?: return@any false
            exportRepository.hasResumableDurableScheduledFolderOperation(
                operationId = operationId,
                dates = requests.map { it.date }.distinct().sorted(),
                settings = targetSettings,
                settingsSnapshotJson = snapshotJson,
            )
        }
    }

    private suspend fun destinationBlocker(settings: ExportSettings): ScheduledExportRecoveryBlocker? {
        val requests = ScheduledExportPendingRequests.pendingRequests(settings)
        val groups = requests.groupBy { it.exportTarget to it.destinationFingerprint }.keys
        if (groups.any { (target, fingerprint) -> isDestinationReady(settings, target, fingerprint) }) {
            return null
        }

        val hasFolderTarget = groups.any { it.first == ExportTarget.DEVICE_FOLDER }
        if (hasFolderTarget && settingsRepository.getExportFolderUri().isNullOrBlank()) {
            return ScheduledExportRecoveryBlocker.NO_EXPORT_FOLDER
        }

        val driveGroups = groups.filter { it.first == ExportTarget.GOOGLE_DRIVE }
        if (driveGroups.isNotEmpty()) return ScheduledExportRecoveryBlocker.NO_EXPORT_FOLDER

        val apiGroups = groups.filter { it.first == ExportTarget.API_ENDPOINT }
        if (apiGroups.isNotEmpty() && !APIExportEndpoint.isConfigured(settings.apiEndpointUrl)) {
            return ScheduledExportRecoveryBlocker.API_ENDPOINT_NOT_CONFIGURED
        }
        if (apiGroups.isNotEmpty()) return ScheduledExportRecoveryBlocker.API_ENDPOINT_CHANGED
        return null
    }

    private suspend fun isDestinationReady(
        settings: ExportSettings,
        target: ExportTarget,
        destinationFingerprint: String?,
    ): Boolean = when (target) {
        ExportTarget.DEVICE_FOLDER -> !settingsRepository.getExportFolderUri().isNullOrBlank()
        ExportTarget.API_ENDPOINT -> APIExportEndpoint.isConfigured(settings.apiEndpointUrl) &&
            destinationFingerprint == (
                apiCredentialStore?.destinationFingerprint(settings.apiEndpointUrl)
                    ?: APIExportEndpoint.fingerprint(settings.apiEndpointUrl)
                )
        ExportTarget.GOOGLE_DRIVE -> googleDriveSelectionStore.get()
            ?.let { googleDriveDestinationStore.find(it) }
            ?.fingerprint == destinationFingerprint
    }

    private fun historyEntry(
        settings: ExportSettings,
        dates: List<LocalDate>,
        result: ExportResult,
        target: ExportTarget,
        reconciliationKey: String?,
    ): ExportHistoryEntry = ExportHistoryEntry(
        timestamp = System.currentTimeMillis(),
        source = ExportSource.SCHEDULED,
        dateRangeStart = dates.first(),
        dateRangeEnd = dates.last(),
        successCount = result.successCount,
        totalCount = result.totalCount,
        failureReason = result.primaryFailureReason,
        failedDateDetails = result.failedDateDetails,
        target = target,
        targetLabel = targetLabel(settings, target),
        fileCount = if (target == ExportTarget.DEVICE_FOLDER) {
            when {
                settings.exportMode == ExportMode.RAW_SNAPSHOT -> result.artifactCount
                result.usesDurableFolderJournal -> result.artifactCount
                else -> result.successCount * settings.selectedExportFormats.size
            }
        } else 0,
        warningSummary = result.warningSummary(),
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

    private fun targetLabel(settings: ExportSettings, target: ExportTarget): String =
        if (target == ExportTarget.API_ENDPOINT) {
            APIExportEndpoint.redactedDescription(settings.apiEndpointUrl)
        } else buildString {
            val subfolder = settings.subfolder.trim('/').takeIf { it.isNotBlank() }
            append(subfolder ?: EXPORT_FOLDER_ROOT_TARGET_LABEL)
            settings.formatFolderPath(LocalDate.now().minusDays(1))?.takeIf { it.isNotBlank() }?.let {
                append("/").append(it.trim('/'))
            }
        }

    /** History is also returned through the automation broadcast API, so keep this invariant. */
    private fun ExportResult.warningSummary(): String? = when {
        isPartialSuccess -> "Recovery finished with ${failedDateDetails.size} failed date(s) still pending"
        wasCancelled -> "Recovery cancelled; unfinished dates remain pending"
        isFailure -> primaryFailureReason?.name
        else -> "Scheduled recovery completed"
    }
}

private data class PendingRecoveryOperation(
    val target: ExportTarget,
    val destinationFingerprint: String?,
    val enginePin: ExportEnginePin?,
    val settingsSnapshotJson: String?,
    val apiOperationId: String?,
    val folderOperationId: String?,
    val driveOperationId: String?,
)

data class ScheduledExportRecoveryStatus(
    val pendingDates: List<LocalDate>,
    val blocker: ScheduledExportRecoveryBlocker? = null,
) {
    val canRecover: Boolean get() = pendingDates.isNotEmpty() && blocker == null
}

enum class ScheduledExportRecoveryBlocker {
    NO_PENDING_DATES,
    ALREADY_RUNNING,
    PAYWALL_REQUIRED,
    NO_EXPORT_FOLDER,
    API_ENDPOINT_NOT_CONFIGURED,
    API_ENDPOINT_CHANGED,
    DEVICE_LOCKED,
    HEALTH_PERMISSIONS_REQUIRED,
}

data class ScheduledExportRecoveryRunResult(
    val status: ScheduledExportRecoveryRunStatus,
    val pendingDates: List<LocalDate>,
    val blocker: ScheduledExportRecoveryBlocker? = null,
    val exportResult: ExportResult? = null,
)

enum class ScheduledExportRecoveryRunStatus {
    COMPLETED,
    BLOCKED,
    ALREADY_RUNNING,
}
