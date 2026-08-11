package com.healthmd.domain.export

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.Duration

class ReviewPromptPolicyTest {
    private val now = 2_000_000_000_000L

    @Test
    fun requiresTwoSuccessfulExports() {
        assertThat(
            ReviewPromptPolicy.shouldRequestReview(
                successfulExportCount = 1,
                lastAttemptEpochMillis = null,
                nowEpochMillis = now,
            )
        ).isFalse()
    }

    @Test
    fun allowsFirstRequestAfterMeaningfulSuccessThreshold() {
        assertThat(
            ReviewPromptPolicy.shouldRequestReview(
                successfulExportCount = 2,
                lastAttemptEpochMillis = null,
                nowEpochMillis = now,
            )
        ).isTrue()
    }

    @Test
    fun suppressesRequestsDuringCooldown() {
        val recentAttempt = now - Duration.ofDays(119).toMillis()

        assertThat(
            ReviewPromptPolicy.shouldRequestReview(
                successfulExportCount = 20,
                lastAttemptEpochMillis = recentAttempt,
                nowEpochMillis = now,
            )
        ).isFalse()
    }

    @Test
    fun allowsRequestWhenCooldownHasElapsed() {
        val oldAttempt = now - ReviewPromptPolicy.COOLDOWN.toMillis()

        assertThat(
            ReviewPromptPolicy.shouldRequestReview(
                successfulExportCount = 20,
                lastAttemptEpochMillis = oldAttempt,
                nowEpochMillis = now,
            )
        ).isTrue()
    }

    @Test
    fun futureOrCorruptAttemptFailsClosed() {
        assertThat(
            ReviewPromptPolicy.shouldRequestReview(
                successfulExportCount = 20,
                lastAttemptEpochMillis = now + 1,
                nowEpochMillis = now,
            )
        ).isFalse()
        assertThat(
            ReviewPromptPolicy.shouldRequestReview(
                successfulExportCount = 20,
                lastAttemptEpochMillis = -1,
                nowEpochMillis = now,
            )
        ).isFalse()
    }
}
