package com.healthmd.presentation.review

import android.app.Activity
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.scheduler.countScheduledReviewSuccess
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.review.ReviewPromptResult
import com.healthmd.domain.review.ReviewPrompter
import com.healthmd.export.FakeBillingRepository
import com.healthmd.export.FakeSettingsRepository
import com.healthmd.presentation.review.ScheduledReviewMoment.Outcome
import io.mockk.mockk
import java.time.Duration
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Test

class ScheduledReviewMomentTest {
    private val now = 2_000_000_000_000L
    private val version = 53L
    private val activity = mockk<Activity>(relaxed = true)
    private val day = LocalDate.of(2026, 11, 20)
    private val fullSuccess = ExportResult(successCount = 1, totalCount = 1)

    private class CountingPrompter(
        override val isAvailable: Boolean = true,
        var result: ReviewPromptResult = ReviewPromptResult.Completed,
    ) : ReviewPrompter {
        var prompts = 0
        override suspend fun prompt(activity: Activity): ReviewPromptResult {
            prompts++
            return result
        }
    }

    private val settings = FakeSettingsRepository()
    private val billing = FakeBillingRepository(initialUnlocked = true)
    private val prompter = CountingPrompter()

    private fun moment(policy: DistributionPolicy = DistributionPolicy.play(), reviewPrompter: ReviewPrompter = prompter) =
        ScheduledReviewMoment(settings, billing, reviewPrompter, policy, version) { now }

    /** Three scheduled full successes on two days: eligible, with a pending moment. */
    private suspend fun threeScheduledSuccesses(policy: DistributionPolicy = DistributionPolicy.play()) {
        settings.countScheduledReviewSuccess(fullSuccess, policy, day)
        settings.countScheduledReviewSuccess(fullSuccess, policy, day)
        settings.countScheduledReviewSuccess(fullSuccess, policy, day.plusDays(1))
    }

    @Test
    fun scheduledSuccessesAloneLeadToOnePromptOnTheNextCalmVisit() = runTest {
        threeScheduledSuccesses()

        assertThat(moment().maybePrompt(activity) { true }).isEqualTo(Outcome.PROMPTED)
        assertThat(prompter.prompts).isEqualTo(1)
        val state = settings.getReviewPromptState(now)
        assertThat(state.lastAttemptEpochMillis).isEqualTo(now)
        assertThat(state.lastAttemptAppVersionCode).isEqualTo(version)

        // The moment is consumed: returning to the Archive doesn't ask again.
        assertThat(moment().maybePrompt(activity) { true }).isEqualTo(Outcome.NO_MOMENT)
        assertThat(prompter.prompts).isEqualTo(1)
    }

    @Test
    fun aScreenThatIsNotReadyKeepsTheMomentForLater() = runTest {
        threeScheduledSuccesses()

        assertThat(moment().maybePrompt(activity) { false }).isEqualTo(Outcome.NOT_READY)
        assertThat(prompter.prompts).isEqualTo(0)
        assertThat(moment().maybePrompt(activity) { true }).isEqualTo(Outcome.PROMPTED)
    }

    @Test
    fun belowTheThresholdNothingIsAsked() = runTest {
        settings.countScheduledReviewSuccess(fullSuccess, DistributionPolicy.play(), day)
        settings.countScheduledReviewSuccess(fullSuccess, DistributionPolicy.play(), day)

        assertThat(moment().maybePrompt(activity) { true }).isEqualTo(Outcome.NOT_ELIGIBLE)
        assertThat(prompter.prompts).isEqualTo(0)
    }

    @Test
    fun partialScheduledExportsLeaveNoMoment() = runTest {
        repeat(3) { i ->
            settings.countScheduledReviewSuccess(
                ExportResult(successCount = 1, totalCount = 2), DistributionPolicy.play(), day.plusDays(i.toLong()),
            )
        }

        assertThat(moment().maybePrompt(activity) { true }).isEqualTo(Outcome.NO_MOMENT)
    }

    @Test
    fun withoutPaidAccessNothingIsAsked() = runTest {
        threeScheduledSuccesses()
        billing.isUnlocked.value = false

        assertThat(moment().maybePrompt(activity) { true }).isEqualTo(Outcome.NOT_PAID)
        assertThat(prompter.prompts).isEqualTo(0)
    }

    @Test
    fun fdroidAndNonPlayInstallsNeverAsk() = runTest {
        threeScheduledSuccesses()

        assertThat(moment(policy = DistributionPolicy.fdroid()).maybePrompt(activity) { true })
            .isEqualTo(Outcome.UNAVAILABLE)
        assertThat(moment(reviewPrompter = CountingPrompter(isAvailable = false)).maybePrompt(activity) { true })
            .isEqualTo(Outcome.UNAVAILABLE)
        assertThat(prompter.prompts).isEqualTo(0)
    }

    @Test
    fun fdroidScheduledExportsAreNotCounted() = runTest {
        threeScheduledSuccesses(policy = DistributionPolicy.fdroid())

        assertThat(settings.getReviewPromptState(now).successfulExportCount).isEqualTo(0)
        assertThat(settings.takeScheduledReviewMoment()).isFalse()
    }

    @Test
    fun aFailedPlayRequestStartsOnlyTheShortRetryCooldown() = runTest {
        threeScheduledSuccesses()
        prompter.result = ReviewPromptResult.Failed

        assertThat(moment().maybePrompt(activity) { true }).isEqualTo(Outcome.FAILED)
        val state = settings.getReviewPromptState(now)
        assertThat(state.lastFailedRequestEpochMillis).isEqualTo(now)
        assertThat(state.lastAttemptEpochMillis).isNull()
    }

    @Test
    fun theCooldownAfterAnEarlierAttemptStillApplies() = runTest {
        threeScheduledSuccesses()
        settings.recordReviewAttempt(now - Duration.ofDays(30).toMillis(), version - 1)

        assertThat(moment().maybePrompt(activity) { true }).isEqualTo(Outcome.NOT_ELIGIBLE)
        assertThat(prompter.prompts).isEqualTo(0)
    }
}
