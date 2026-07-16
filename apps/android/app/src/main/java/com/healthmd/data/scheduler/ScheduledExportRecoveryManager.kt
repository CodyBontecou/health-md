package com.healthmd.data.scheduler

import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.domain.model.APIExportEndpoint
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
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ScheduledExportRecoveryManager @Inject constructor(
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
    private val exportHistoryRepository: ExportHistoryRepository,
    private val apiEndpointExportRunner: APIEndpointExportRunner? = null,
    private val rawSnapshotService: RawSnapshotService? = null,
    private val apiCredentialStore: APIExportCredentialStore? = null,
    private val runCoordinator: ScheduledExportRunCoordinator = ScheduledExportRunCoordinator(),
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

        if (healthRepository.isBeforeFirstUnlock()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.DEVICE_LOCKED,
            )
        }

        if (!healthRepository.hasPermissions()) {
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
                .groupBy { it.exportTarget to it.destinationFingerprint }

            var latestSettings = settings
            var totalSuccessCount = 0
            var totalCount = 0
            val allFailures = mutableListOf<FailedDateDetail>()

            for ((destination, requests) in pendingByTarget) {
                val target = destination.first
                val destinationFingerprint = destination.second
                if (!isDestinationReady(settings, target, destinationFingerprint)) continue
                val targetDates = requests.map { it.date }.distinct().sorted()
                val targetSettings = settings.copy(
                    exportTarget = target,
                    scheduledExportTarget = target,
                )
                val targetResult = try {
                    if (targetSettings.exportMode == ExportMode.RAW_SNAPSHOT) {
                        rawSnapshotService?.exportRange(
                            startDate = targetDates.first(),
                            endDate = targetDates.last(),
                            settings = targetSettings,
                            target = target,
                            expectedDestinationFingerprint = destinationFingerprint,
                        ) ?: ExportResult(
                            successCount = 0,
                            totalCount = 1,
                            failedDateDetails = listOf(FailedDateDetail(targetDates.first(), ExportFailureReason.UNKNOWN, "Raw snapshot service unavailable")),
                            target = target,
                            exportMode = ExportMode.RAW_SNAPSHOT,
                        )
                    } else when (target) {
                        ExportTarget.DEVICE_FOLDER -> ExportOrchestrator(healthRepository, exportRepository)
                            .exportDates(targetDates, targetSettings)
                            .copy(target = ExportTarget.DEVICE_FOLDER)
                        ExportTarget.API_ENDPOINT -> apiEndpointExportRunner?.exportDates(
                            dates = targetDates,
                            settings = targetSettings,
                            expectedDestinationFingerprint = destinationFingerprint,
                        )
                            ?: ExportResult(
                                successCount = 0,
                                totalCount = targetDates.size,
                                failedDateDetails = targetDates.map {
                                    FailedDateDetail(it, ExportFailureReason.NETWORK_ERROR, "API export service unavailable")
                                },
                                target = ExportTarget.API_ENDPOINT,
                            )
                    }
                } catch (error: Exception) {
                    ExportResult(
                        successCount = 0,
                        totalCount = targetDates.size,
                        failedDateDetails = targetDates.map {
                            FailedDateDetail(it, ExportFailureReason.UNKNOWN, error.message)
                        },
                        target = target,
                    )
                }

                // Merge only this attempt's pending-date result into the latest settings so a
                // concurrent endpoint/schedule edit is never overwritten by the recovery snapshot.
                val currentSettings = settingsRepository.getExportSettings()
                val retryDetails = if (targetSettings.exportMode == ExportMode.RAW_SNAPSHOT && targetResult.isFailure) {
                    val failure = targetResult.failedDateDetails.first()
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
                )
                settingsRepository.updateExportSettings(latestSettings)
                exportHistoryRepository.insertEntry(
                    historyEntry(
                        settings = targetSettings,
                        dates = targetDates,
                        result = targetResult,
                        target = target,
                    )
                )

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
            runCoordinator.mutex.unlock()
        }
    }

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
        if (healthRepository.isBeforeFirstUnlock()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.DEVICE_LOCKED,
            )
        }
        if (!healthRepository.hasPermissions()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.HEALTH_PERMISSIONS_REQUIRED,
            )
        }
        return ScheduledExportRecoveryStatus(pendingDates = pendingDates)
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
    }

    private fun historyEntry(
        settings: ExportSettings,
        dates: List<LocalDate>,
        result: ExportResult,
        target: ExportTarget,
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
            if (settings.exportMode == ExportMode.RAW_SNAPSHOT) result.successCount else result.successCount * settings.selectedExportFormats.size
        } else 0,
        warningSummary = result.warningSummary(),
        exportMode = settings.exportMode,
    )

    private fun targetLabel(settings: ExportSettings, target: ExportTarget): String =
        if (target == ExportTarget.API_ENDPOINT) {
            APIExportEndpoint.redactedDescription(settings.apiEndpointUrl)
        } else buildString {
            val subfolder = settings.subfolder.trim('/').takeIf { it.isNotBlank() }
            append(subfolder ?: "Export folder")
            settings.formatFolderPath(LocalDate.now().minusDays(1))?.takeIf { it.isNotBlank() }?.let {
                append("/").append(it.trim('/'))
            }
        }

    private fun ExportResult.warningSummary(): String? = when {
        isPartialSuccess -> "Recovery finished with ${failedDateDetails.size} failed date(s) still pending"
        wasCancelled -> "Recovery cancelled; unfinished dates remain pending"
        isFailure -> primaryFailureReason?.name
        else -> "Scheduled recovery completed"
    }
}

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
