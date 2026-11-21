package com.healthmd.domain.export

import java.time.Duration

/** Persisted review-request inputs. Never contains health data. */
data class ReviewPromptState(
    val successfulExportCount: Int,
    val successDayCount: Int,
    val lastAttemptEpochMillis: Long?,
    val lastAttemptAppVersionCode: Long?,
    val lastFailedRequestEpochMillis: Long?,
)

/**
 * When Health.md may ask Google Play for an in-app review. Mirrors the Apple
 * `ReviewManager` policy:
 * - every full success counts (manual or scheduled); partial and failed exports never do;
 * - eligible at [MINIMUM_SUCCESSFUL_EXPORTS] full successes on [MINIMUM_SUCCESS_DAYS]
 *   distinct days;
 * - after a completed Play flow, wait [COOLDOWN] and a new app version;
 * - after a failed Play request, wait [FAILED_REQUEST_RETRY] so it stops retrying
 *   after every export.
 * Only the foreground export UI asks; background work only counts.
 */
object ReviewPromptPolicy {
    const val MINIMUM_SUCCESSFUL_EXPORTS = 3
    const val MINIMUM_SUCCESS_DAYS = 2
    val COOLDOWN: Duration = Duration.ofDays(120)
    val FAILED_REQUEST_RETRY: Duration = Duration.ofDays(7)

    fun shouldRequestReview(
        state: ReviewPromptState,
        currentAppVersionCode: Long,
        nowEpochMillis: Long,
    ): Boolean {
        require(nowEpochMillis >= 0)
        if (state.successfulExportCount < MINIMUM_SUCCESSFUL_EXPORTS) return false
        if (state.successDayCount < MINIMUM_SUCCESS_DAYS) return false
        if (!hasElapsed(state.lastFailedRequestEpochMillis, FAILED_REQUEST_RETRY, nowEpochMillis)) return false
        val lastAttempt = state.lastAttemptEpochMillis ?: return true
        if (!hasElapsed(lastAttempt, COOLDOWN, nowEpochMillis)) return false
        return state.lastAttemptAppVersionCode != currentAppVersionCode
    }

    /** Null means "never"; a corrupt or future timestamp fails closed. */
    private fun hasElapsed(epochMillis: Long?, duration: Duration, nowEpochMillis: Long): Boolean {
        if (epochMillis == null) return true
        if (epochMillis < 0 || epochMillis > nowEpochMillis) return false
        return nowEpochMillis - epochMillis >= duration.toMillis()
    }
}
