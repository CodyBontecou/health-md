package com.healthmd.domain.export

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.Duration

class ReviewPromptPolicyTest {
    private val now = 2_000_000_000_000L
    private val version = 52L

    private fun state(
        count: Int = 3,
        days: Int = 2,
        lastAttempt: Long? = null,
        lastAttemptVersion: Long? = null,
        lastFailure: Long? = null,
    ) = ReviewPromptState(
        successfulExportCount = count,
        successDayCount = days,
        lastAttemptEpochMillis = lastAttempt,
        lastAttemptAppVersionCode = lastAttemptVersion,
        lastFailedRequestEpochMillis = lastFailure,
    )

    private fun allowed(state: ReviewPromptState, currentVersion: Long = version) =
        ReviewPromptPolicy.shouldRequestReview(state, currentVersion, now)

    private fun daysAgo(days: Long) = now - Duration.ofDays(days).toMillis()

    @Test
    fun requiresThreeFullSuccesses() {
        assertThat(allowed(state(count = 2))).isFalse()
        assertThat(allowed(state(count = 3))).isTrue()
    }

    @Test
    fun thresholdIsNotAnExactCount() {
        assertThat(allowed(state(count = 40, days = 12))).isTrue()
    }

    @Test
    fun requiresTwoDistinctDays() {
        assertThat(allowed(state(count = 10, days = 1))).isFalse()
    }

    @Test
    fun suppressesRequestsDuringCooldownEvenOnNewVersion() {
        assertThat(allowed(state(lastAttempt = daysAgo(119), lastAttemptVersion = version - 1))).isFalse()
    }

    @Test
    fun afterCooldownRequiresNewVersion() {
        val old = ReviewPromptPolicy.COOLDOWN.toMillis()
        assertThat(allowed(state(lastAttempt = now - old, lastAttemptVersion = version))).isFalse()
        assertThat(allowed(state(lastAttempt = now - old, lastAttemptVersion = version - 1))).isTrue()
    }

    @Test
    fun legacyAttemptWithoutVersionUsesCooldownOnly() {
        assertThat(allowed(state(lastAttempt = daysAgo(121)))).isTrue()
        assertThat(allowed(state(lastAttempt = daysAgo(30)))).isFalse()
    }

    @Test
    fun failedRequestWaitsForShortRetryCooldown() {
        assertThat(allowed(state(lastFailure = daysAgo(6)))).isFalse()
        assertThat(allowed(state(lastFailure = now - ReviewPromptPolicy.FAILED_REQUEST_RETRY.toMillis()))).isTrue()
    }

    @Test
    fun futureOrCorruptTimestampsFailClosed() {
        assertThat(allowed(state(lastAttempt = now + 1))).isFalse()
        assertThat(allowed(state(lastAttempt = -1))).isFalse()
        assertThat(allowed(state(lastFailure = now + 1))).isFalse()
    }
}
