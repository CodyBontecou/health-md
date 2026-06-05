package com.healthmd.data.scheduler

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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import java.time.LocalDate
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ScheduledExportRecoveryManager @Inject constructor(
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
    private val exportHistoryRepository: ExportHistoryRepository,
) {
    private val recoveryMutex = Mutex()

    suspend fun inspectPendingRecovery(): ScheduledExportRecoveryStatus {
        val settings = settingsRepository.getExportSettings()
        val pendingDates = ScheduledExportPendingRequests.pendingDates(settings)

        if (pendingDates.isEmpty()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = emptyList(),
                blocker = ScheduledExportRecoveryBlocker.NO_PENDING_DATES,
            )
        }

        if (recoveryMutex.isLocked) {
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

        if (settingsRepository.getExportFolderUri().isNullOrBlank()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.NO_EXPORT_FOLDER,
            )
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
        if (!recoveryMutex.tryLock()) {
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
            val pendingDates = ScheduledExportPendingRequests.pendingDates(settings)
            val result = try {
                ExportOrchestrator(healthRepository, exportRepository)
                    .exportDates(pendingDates, settings)
            } catch (e: Exception) {
                ExportResult(
                    successCount = 0,
                    totalCount = pendingDates.size,
                    failedDateDetails = pendingDates.map {
                        FailedDateDetail(it, ExportFailureReason.UNKNOWN, e.message)
                    },
                )
            }

            val latestSettings = settingsRepository.getExportSettings()
            val updatedSettings = ScheduledExportPendingRequests.applyAttemptResult(
                settings = latestSettings,
                attemptedDates = pendingDates,
                failedDateDetails = result.failedDateDetails,
            )
            settingsRepository.updateExportSettings(updatedSettings)

            exportHistoryRepository.insertEntry(
                historyEntry(
                    settings = settings,
                    dates = pendingDates,
                    result = result,
                )
            )

            val remainingDates = ScheduledExportPendingRequests.pendingDates(updatedSettings)
            ScheduledExportRecoveryRunResult(
                status = ScheduledExportRecoveryRunStatus.COMPLETED,
                pendingDates = remainingDates,
                exportResult = result,
            )
        } finally {
            recoveryMutex.unlock()
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
        if (settingsRepository.getExportFolderUri().isNullOrBlank()) {
            return ScheduledExportRecoveryStatus(
                pendingDates = pendingDates,
                blocker = ScheduledExportRecoveryBlocker.NO_EXPORT_FOLDER,
            )
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

    private fun historyEntry(
        settings: ExportSettings,
        dates: List<LocalDate>,
        result: ExportResult,
    ): ExportHistoryEntry = ExportHistoryEntry(
        timestamp = System.currentTimeMillis(),
        source = ExportSource.SCHEDULED,
        dateRangeStart = dates.first(),
        dateRangeEnd = dates.last(),
        successCount = result.successCount,
        totalCount = result.totalCount,
        failureReason = result.primaryFailureReason,
        failedDateDetails = result.failedDateDetails,
        targetLabel = targetLabel(settings),
        fileCount = result.successCount * settings.selectedExportFormats.size,
        warningSummary = result.warningSummary(),
    )

    private fun targetLabel(settings: ExportSettings): String = buildString {
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
