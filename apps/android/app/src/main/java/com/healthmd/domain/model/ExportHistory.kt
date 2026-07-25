package com.healthmd.domain.model

import com.healthmd.rawexport.ExportMode
import kotlinx.serialization.Serializable

@Serializable
enum class ExportSource {
    MANUAL,
    SCHEDULED,
    RETRY,
    SHORTCUT,
    REMOTE,
}

@Serializable
enum class ExportFailureReason {
    NO_FOLDER_SELECTED,
    NO_HEALTH_DATA,
    ACCESS_DENIED,
    FILE_WRITE_ERROR,
    RATE_LIMITED,
    HEALTH_CONNECT_ERROR,
    DEVICE_LOCKED,
    BACKGROUND_PERMISSION_DENIED,
    PAYWALL_REQUIRED,
    INVALID_API_ENDPOINT,
    NETWORK_ERROR,
    API_REJECTED,
    RAW_UNSUPPORTED_PROVIDER,
    RAW_PARTIAL,
    RAW_CANCELLED,
    UNKNOWN,
}

@Serializable
data class FailedDateDetail(
    @Serializable(with = LocalDateSerializer::class)
    val date: java.time.LocalDate,
    val reason: ExportFailureReason,
    val errorDetails: String? = null,
)

data class ExportHistoryEntry(
    val id: Long = 0,
    val timestamp: Long, // epoch millis
    val source: ExportSource,
    val dateRangeStart: java.time.LocalDate,
    val dateRangeEnd: java.time.LocalDate,
    val successCount: Int,
    val totalCount: Int,
    val failureReason: ExportFailureReason? = null,
    val failedDateDetails: List<FailedDateDetail> = emptyList(),
    val target: ExportTarget = ExportTarget.DEVICE_FOLDER,
    val targetLabel: String? = null,
    val fileCount: Int = 0,
    val warningSummary: String? = null,
    val exportMode: ExportMode = ExportMode.COMPATIBILITY,
) {
    val isFullSuccess: Boolean get() = successCount == totalCount && totalCount > 0
    val isPartialSuccess: Boolean get() = successCount in 1 until totalCount
    val isFailure: Boolean get() = successCount == 0 && totalCount > 0
}
