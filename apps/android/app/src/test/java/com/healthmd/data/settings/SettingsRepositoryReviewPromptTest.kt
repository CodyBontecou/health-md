package com.healthmd.data.settings

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SettingsRepositoryReviewPromptTest {
    private val migrationEpochMillis = 2_000_000_000_000L

    @Test
    fun currentTimestampTakesPrecedenceOverLegacyFlag() {
        assertThat(
            resolveReviewAttemptEpochMillis(
                currentAttemptEpochMillis = 1234L,
                legacyRequested = true,
                migrationEpochMillis = migrationEpochMillis,
            )
        ).isEqualTo(1234L)
    }

    @Test
    fun legacyOneShotMigratesToCurrentTimestamp() {
        assertThat(
            resolveReviewAttemptEpochMillis(
                currentAttemptEpochMillis = null,
                legacyRequested = true,
                migrationEpochMillis = migrationEpochMillis,
            )
        ).isEqualTo(migrationEpochMillis)
    }

    @Test
    fun freshInstallHasNoPreviousAttempt() {
        assertThat(
            resolveReviewAttemptEpochMillis(
                currentAttemptEpochMillis = null,
                legacyRequested = false,
                migrationEpochMillis = migrationEpochMillis,
            )
        ).isNull()
    }

    @Test
    fun corruptNegativeTimestampDoesNotSuppressFuturePrompts() {
        assertThat(
            resolveReviewAttemptEpochMillis(
                currentAttemptEpochMillis = -1L,
                legacyRequested = false,
                migrationEpochMillis = migrationEpochMillis,
            )
        ).isNull()
    }

    @Test
    fun firstTrackedDayStartsAtOne() {
        assertThat(nextReviewSuccessDayCount(currentDayCount = null, hasTrackedDay = false, previousSuccessCount = 0))
            .isEqualTo(1)
    }

    @Test
    fun countsFromBeforeDayTrackingAreOneEarlierDay() {
        assertThat(nextReviewSuccessDayCount(currentDayCount = null, hasTrackedDay = false, previousSuccessCount = 7))
            .isEqualTo(2)
    }

    @Test
    fun newDayAddsOne() {
        assertThat(nextReviewSuccessDayCount(currentDayCount = 2, hasTrackedDay = true, previousSuccessCount = 7))
            .isEqualTo(3)
    }
}
