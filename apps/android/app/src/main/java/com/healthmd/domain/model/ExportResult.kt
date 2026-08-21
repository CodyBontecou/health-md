package com.healthmd.domain.model

import com.healthmd.rawexport.ExportMode
import java.time.LocalDate

data class ExportResult(
    val successCount: Int,
    val totalCount: Int,
    val failedDateDetails: List<FailedDateDetail> = emptyList(),
    val wasCancelled: Boolean = false,
    val target: ExportTarget = ExportTarget.DEVICE_FOLDER,
    val httpStatusCode: Int? = null,
    val exportMode: ExportMode = ExportMode.COMPATIBILITY,
    /** Number of durable local artifacts produced, including a diagnosable partial raw snapshot. */
    val artifactCount: Int = successCount,
    /** Internal durable retry identity for unresolved API owner dates; never serialized publicly. */
    val retryOperationIds: Map<LocalDate, String> = emptyMap(),
    /** Acknowledged failure-only API/folder dates that must be recaptured as a new operation. */
    val freshCaptureRetryDates: Set<LocalDate> = emptySet(),
    /** Durable exact-plan journal for unresolved scheduled folder owner dates. */
    val retryFolderOperationIds: Map<LocalDate, String> = emptyMap(),
    /** Durable private Drive journal for unresolved owner dates. */
    val retryDriveOperationIds: Map<LocalDate, String> = emptyMap(),
    /** Internal accounting marker; durable folder history uses exact acknowledged artifact count. */
    val usesDurableFolderJournal: Boolean = false,
) {
    val isFullSuccess: Boolean get() = successCount == totalCount && totalCount > 0 && !wasCancelled
    val isPartialSuccess: Boolean get() = (successCount in 1 until totalCount) || (successCount > 0 && wasCancelled)
    val isFailure: Boolean get() = successCount == 0 && totalCount > 0
    val primaryFailureReason: ExportFailureReason?
        get() = failedDateDetails.firstOrNull { it.reason == ExportFailureReason.RATE_LIMITED }?.reason
            ?: failedDateDetails.firstOrNull()?.reason
}
