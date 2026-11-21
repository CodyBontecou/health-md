package com.healthmd.data.scheduler

import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.export.ExportAccountingPolicy
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.util.runCatchingCancellable
import java.time.LocalDate
import timber.log.Timber

/**
 * Counts a scheduled full success toward the review threshold. Background work never
 * prompts; the next foreground success decides. Counting can never fail the export.
 */
internal suspend fun SettingsRepository.countScheduledReviewSuccess(
    result: ExportResult,
    distributionPolicy: DistributionPolicy,
    today: LocalDate = LocalDate.now(),
) {
    if (!distributionPolicy.reviewPromptAvailable) return
    if (!ExportAccountingPolicy.shouldCountForReviewPrompt(result)) return
    runCatchingCancellable { recordReviewEligibleSuccess(today.toEpochDay()) }
        .onFailure { Timber.w(it, "Could not count scheduled export toward review prompt") }
}
