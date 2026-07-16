package com.healthmd.presentation.export

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.FailedDateDetail
import java.time.LocalDate
import kotlin.math.max

private const val DEFAULT_DATE_SAMPLE_LIMIT = 6

enum class ExportDiagnosticGuidance {
    RATE_LIMIT,
    HISTORICAL_PERMISSION,
    FILE_WRITE,
    NO_DATA,
    BACKGROUND_PERMISSION,
    DEVICE_LOCKED,
    NO_FOLDER,
    PAYWALL,
    HEALTH_CONNECT,
    API_CONFIGURATION,
    NETWORK,
    API_REJECTED,
    UNKNOWN,
}

data class ExportFailureDiagnosticGroup(
    val reason: ExportFailureReason,
    val count: Int,
    val sampleDates: List<LocalDate>,
    val remainingDateCount: Int,
    val guidance: ExportDiagnosticGuidance,
)

data class ExportDiagnosticsSummary(
    val successCount: Int,
    val totalCount: Int,
    val failedDayCount: Int,
    val wasCancelled: Boolean,
    val failureGroups: List<ExportFailureDiagnosticGroup>,
    val failedRangeStart: LocalDate?,
    val failedRangeEnd: LocalDate?,
) {
    val isFullSuccess: Boolean = successCount == totalCount && totalCount > 0 && !wasCancelled
    val isPartial: Boolean = (successCount in 1 until totalCount) || (successCount > 0 && wasCancelled)
    val isFailure: Boolean = successCount == 0 && totalCount > 0
    val shouldAutoDismiss: Boolean = isFullSuccess
    val hasDetailedFailures: Boolean = failureGroups.isNotEmpty()
}

fun ExportResult.toDiagnosticsSummary(
    dateSampleLimit: Int = DEFAULT_DATE_SAMPLE_LIMIT,
): ExportDiagnosticsSummary =
    buildDiagnosticsSummary(
        successCount = successCount,
        totalCount = totalCount,
        failedDateDetails = failedDateDetails,
        wasCancelled = wasCancelled,
        dateSampleLimit = dateSampleLimit,
    )

fun ExportHistoryEntry.toDiagnosticsSummary(
    dateSampleLimit: Int = DEFAULT_DATE_SAMPLE_LIMIT,
): ExportDiagnosticsSummary =
    buildDiagnosticsSummary(
        successCount = successCount,
        totalCount = totalCount,
        failedDateDetails = failedDateDetails,
        wasCancelled = false,
        dateSampleLimit = dateSampleLimit,
    )

private fun buildDiagnosticsSummary(
    successCount: Int,
    totalCount: Int,
    failedDateDetails: List<FailedDateDetail>,
    wasCancelled: Boolean,
    dateSampleLimit: Int,
): ExportDiagnosticsSummary {
    val safeSampleLimit = max(1, dateSampleLimit)
    val failedDayCount = max(totalCount - successCount, failedDateDetails.size)
    val failedDates = failedDateDetails.map { it.date }
    val groups = failedDateDetails
        .groupBy { it.reason }
        .map { (reason, details) ->
            val dates = details.map { it.date }.sorted()
            ExportFailureDiagnosticGroup(
                reason = reason,
                count = details.size,
                sampleDates = dates.take(safeSampleLimit),
                remainingDateCount = (dates.size - safeSampleLimit).coerceAtLeast(0),
                guidance = reason.toDiagnosticGuidance(),
            )
        }
        .sortedWith(
            compareByDescending<ExportFailureDiagnosticGroup> { it.count }
                .thenBy { it.reason.ordinal }
        )

    return ExportDiagnosticsSummary(
        successCount = successCount,
        totalCount = totalCount,
        failedDayCount = failedDayCount,
        wasCancelled = wasCancelled,
        failureGroups = groups,
        failedRangeStart = failedDates.minOrNull(),
        failedRangeEnd = failedDates.maxOrNull(),
    )
}

private fun ExportFailureReason.toDiagnosticGuidance(): ExportDiagnosticGuidance =
    when (this) {
        ExportFailureReason.RATE_LIMITED -> ExportDiagnosticGuidance.RATE_LIMIT
        ExportFailureReason.ACCESS_DENIED -> ExportDiagnosticGuidance.HISTORICAL_PERMISSION
        ExportFailureReason.FILE_WRITE_ERROR -> ExportDiagnosticGuidance.FILE_WRITE
        ExportFailureReason.NO_HEALTH_DATA -> ExportDiagnosticGuidance.NO_DATA
        ExportFailureReason.BACKGROUND_PERMISSION_DENIED -> ExportDiagnosticGuidance.BACKGROUND_PERMISSION
        ExportFailureReason.DEVICE_LOCKED -> ExportDiagnosticGuidance.DEVICE_LOCKED
        ExportFailureReason.NO_FOLDER_SELECTED -> ExportDiagnosticGuidance.NO_FOLDER
        ExportFailureReason.PAYWALL_REQUIRED -> ExportDiagnosticGuidance.PAYWALL
        ExportFailureReason.HEALTH_CONNECT_ERROR -> ExportDiagnosticGuidance.HEALTH_CONNECT
        ExportFailureReason.INVALID_API_ENDPOINT -> ExportDiagnosticGuidance.API_CONFIGURATION
        ExportFailureReason.NETWORK_ERROR -> ExportDiagnosticGuidance.NETWORK
        ExportFailureReason.API_REJECTED -> ExportDiagnosticGuidance.API_REJECTED
        ExportFailureReason.RAW_UNSUPPORTED_PROVIDER -> ExportDiagnosticGuidance.HEALTH_CONNECT
        ExportFailureReason.RAW_PARTIAL -> ExportDiagnosticGuidance.HEALTH_CONNECT
        ExportFailureReason.RAW_CANCELLED -> ExportDiagnosticGuidance.UNKNOWN
        ExportFailureReason.UNKNOWN -> ExportDiagnosticGuidance.UNKNOWN
    }
