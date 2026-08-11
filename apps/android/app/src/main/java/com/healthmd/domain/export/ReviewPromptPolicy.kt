package com.healthmd.domain.export

import java.time.Duration

object ReviewPromptPolicy {
    const val MINIMUM_SUCCESSFUL_EXPORTS = 2
    val COOLDOWN: Duration = Duration.ofDays(120)

    fun shouldRequestReview(
        successfulExportCount: Int,
        lastAttemptEpochMillis: Long?,
        nowEpochMillis: Long,
    ): Boolean {
        require(nowEpochMillis >= 0)
        if (successfulExportCount < MINIMUM_SUCCESSFUL_EXPORTS) return false
        if (lastAttemptEpochMillis == null) return true
        if (lastAttemptEpochMillis < 0 || lastAttemptEpochMillis > nowEpochMillis) return false
        return nowEpochMillis - lastAttemptEpochMillis >= COOLDOWN.toMillis()
    }
}
