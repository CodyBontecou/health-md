package com.healthmd.domain.export

import com.healthmd.domain.model.ExportResult

object ExportAccountingPolicy {
    fun shouldConsumeFreeExport(result: ExportResult, isPurchased: Boolean): Boolean =
        !isPurchased && result.isFullSuccess

    fun shouldCountForReviewPrompt(result: ExportResult): Boolean =
        result.isFullSuccess
}
