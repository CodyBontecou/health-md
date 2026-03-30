package com.healthmd.domain.model

data class ExportResult(
    val successCount: Int,
    val totalCount: Int,
    val failedDateDetails: List<FailedDateDetail> = emptyList(),
    val wasCancelled: Boolean = false,
) {
    val isFullSuccess: Boolean get() = successCount == totalCount && totalCount > 0 && !wasCancelled
    val isPartialSuccess: Boolean get() = (successCount in 1 until totalCount) || (successCount > 0 && wasCancelled)
    val isFailure: Boolean get() = successCount == 0 && totalCount > 0
    val primaryFailureReason: ExportFailureReason? get() = failedDateDetails.firstOrNull()?.reason
}
