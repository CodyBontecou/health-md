package com.healthmd.domain.model

import java.time.LocalDate

/** Dry-run representation of what an export action would write. */
data class ExportPreview(
    val requestedDateCount: Int,
    val previewedDateCount: Int,
    val isTruncated: Boolean,
    val days: List<ExportPreviewDay>,
    /** True when the files represent one immutable artifact for the complete selected range. */
    val isRangeArtifact: Boolean = false,
) {
    val totalFileCount: Int get() = days.sumOf { it.files.size + it.sideEffects.count { effect -> effect.wouldWrite } }
    val totalByteCount: Int get() = days.sumOf { day ->
        day.files.sumOf { it.byteCount } + day.sideEffects.filter { it.wouldWrite }.sumOf { it.byteCount }
    }
}

data class ExportPreviewDay(
    val date: LocalDate,
    val files: List<ExportPreviewFile> = emptyList(),
    val sideEffects: List<ExportPreviewSideEffect> = emptyList(),
    val failureReason: ExportFailureReason? = null,
    val warning: String? = null,
    /** Exact owner-date scope represented by this preview item. API bodies may span several days. */
    val requestedDates: List<LocalDate> = listOf(date),
) {
    val hasOutput: Boolean get() = files.isNotEmpty() || sideEffects.any { it.wouldWrite }
}

data class ExportPreviewFile(
    val format: ExportFormat,
    val relativePath: String,
    val byteCount: Int,
    val content: String,
    /** Optional product-specific label, such as NDJSON for a raw snapshot artifact. */
    val formatLabel: String? = null,
    /** Bytes omitted when content was bounded before entering the UI model. */
    val previewOmittedByteCount: Int = 0,
)

enum class ExportPreviewSideEffectType {
    DAILY_NOTE,
    INDIVIDUAL_ENTRY,
}

data class ExportPreviewSideEffect(
    val type: ExportPreviewSideEffectType,
    val relativePath: String,
    val action: String,
    val byteCount: Int = 0,
    val content: String? = null,
    val wouldWrite: Boolean = true,
)
