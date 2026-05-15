package com.healthmd.domain.model

import kotlinx.serialization.Serializable

@Serializable
enum class ExportSource {
    MANUAL,
    SCHEDULED,
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
) {
    val isFullSuccess: Boolean get() = successCount == totalCount && totalCount > 0
    val isPartialSuccess: Boolean get() = successCount in 1 until totalCount
    val isFailure: Boolean get() = successCount == 0 && totalCount > 0
}
