package com.healthmd.domain.model

import com.healthmd.rawexport.ExportMode

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
) {
    val isFullSuccess: Boolean get() = successCount == totalCount && totalCount > 0 && !wasCancelled
    val isPartialSuccess: Boolean get() = (successCount in 1 until totalCount) || (successCount > 0 && wasCancelled)
    val isFailure: Boolean get() = successCount == 0 && totalCount > 0
    val primaryFailureReason: ExportFailureReason?
        get() = failedDateDetails.firstOrNull { it.reason == ExportFailureReason.RATE_LIMITED }?.reason
            ?: failedDateDetails.firstOrNull()?.reason
}
