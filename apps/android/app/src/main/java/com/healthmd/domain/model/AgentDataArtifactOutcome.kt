package com.healthmd.domain.model

import java.time.LocalDate

/**
 * Health-free outcome of one Agent Data gateway artifact upload, surfaced in the export
 * result so UI and history can report per-artifact acceptance, a stable rejection code,
 * or an upload failure without ever disclosing health values.
 */
data class AgentDataArtifactOutcome(
    /** Owner date of the uploaded artifact partition (exported day; capture day for raw kinds). */
    val ownerDate: LocalDate,
    /** Destination-relative artifact path (a filename, never health content). */
    val relativePath: String,
    val state: State,
    /** Stable protocol rejection code when [state] is [State.REJECTED]. */
    val rejectionCode: String? = null,
) {
    enum class State { ACCEPTED, REJECTED, UPLOAD_FAILED }
}

/** The four stable, health-free Agent Data ingestion v1 rejection codes. */
object AgentDataRejectionCodes {
    const val TRUNCATED = "truncated"
    const val CHECKSUM_INVALID = "checksum_invalid"
    const val MANIFEST_INCOMPLETE = "manifest_incomplete"
    const val TRANSIENT = "transient"

    val ALL: Set<String> = setOf(TRUNCATED, CHECKSUM_INVALID, MANIFEST_INCOMPLETE, TRANSIENT)

    /** Fix-and-re-upload outcomes are never retried by the phone. */
    fun isFixAndReupload(code: String): Boolean =
        code == TRUNCATED || code == CHECKSUM_INVALID || code == MANIFEST_INCOMPLETE
}
