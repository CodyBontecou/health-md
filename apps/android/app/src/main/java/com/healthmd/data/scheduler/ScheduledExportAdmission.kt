package com.healthmd.data.scheduler

import androidx.work.Data
import java.nio.charset.StandardCharsets
import java.util.UUID

/** Durable single-flight admission for one scheduled export occurrence. */
internal data class ScheduledExportAdmission(
    val occurrence: ScheduledExportOccurrence,
    val catchUpThroughMillis: Long,
    val expedited: Boolean,
    val operationId: String,
    val workRequestId: UUID,
    val phase: ScheduledExportAdmissionPhase = ScheduledExportAdmissionPhase.ACTIVE,
) {
    init {
        requireNotNull(occurrence.generation) {
            "A scheduled export admission requires a generation."
        }
        require(catchUpThroughMillis >= occurrence.triggerAtMillis) {
            "Scheduled export catch-up cannot precede its occurrence."
        }
        require(operationId.matches(OPERATION_ID_PATTERN)) {
            "Scheduled export operation ID is invalid."
        }
    }

    val inputData: Data
        get() = occurrence.toWorkData(
            catchUpThroughMillis = catchUpThroughMillis,
            admissionOperationId = operationId,
        )

    companion object {
        const val KEY_OPERATION_ID = "scheduled_export_admission_operation_id"

        fun create(
            occurrence: ScheduledExportOccurrence,
            catchUpThroughMillis: Long,
            expedited: Boolean,
        ): ScheduledExportAdmission {
            val generation = requireNotNull(occurrence.generation)
            val identity = buildString {
                append("healthmd-scheduled-operation-v1\n")
                append(generation).append('\n')
                append(occurrence.configuration.signature).append('\n')
                append(occurrence.triggerAtMillis).append('\n')
                append(occurrence.intendedLocalDate)
            }
            val identityBytes = identity.toByteArray(StandardCharsets.UTF_8)
            val operationUuid = UUID.nameUUIDFromBytes(identityBytes)
            val workUuid = UUID.nameUUIDFromBytes(
                "healthmd-scheduled-work-v1\n$identity".toByteArray(StandardCharsets.UTF_8),
            )
            return ScheduledExportAdmission(
                occurrence = occurrence,
                catchUpThroughMillis = catchUpThroughMillis.coerceAtLeast(
                    occurrence.triggerAtMillis,
                ),
                expedited = expedited,
                operationId = "scheduled-$operationUuid",
                workRequestId = workUuid,
            ).also { admission ->
                // Build the exact transport envelope before any durable scheduler state changes.
                admission.inputData
            }
        }

        fun operationIdFrom(data: Data): String? = data.getString(KEY_OPERATION_ID)
            ?.takeIf { it.matches(OPERATION_ID_PATTERN) }

        private val OPERATION_ID_PATTERN = Regex("[A-Za-z0-9._-]{1,128}")
    }
}

internal enum class ScheduledExportAdmissionPhase {
    ACTIVE,
    EXECUTION_COMPLETED,
}

internal enum class ScheduledExportDeliveryResult {
    ADMITTED,
    STALE,
    BUSY,
}
