package com.healthmd.domain.export

import com.healthmd.domain.model.ExportResult

object ExportAccountingPolicy {
    /**
     * Mirrors iOS trigger policy: one successful user-triggered export action
     * consumes one free use, regardless of how many days/files were written.
     * Background scheduled exports remain premium-only and do not call this.
     */
    fun shouldConsumeFreeExport(result: ExportResult, isPurchased: Boolean): Boolean =
        !isPurchased && result.successCount > 0

    fun shouldCountForReviewPrompt(result: ExportResult): Boolean =
        result.isFullSuccess
}
