package com.healthmd.presentation.review

import android.app.Activity
import com.healthmd.BuildConfig
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.export.ReviewPromptPolicy
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.domain.review.ReviewPromptResult
import com.healthmd.domain.review.ReviewPrompter
import com.healthmd.util.runCatchingCancellable
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.sync.Mutex
import timber.log.Timber

/**
 * The review moment for people who rely on scheduled exports (Android's counterpart of the
 * Apple "dismissed scheduled-export result" moment).
 *
 * Scheduled full successes count toward [ReviewPromptPolicy] in the background and leave one
 * pending moment ([SettingsRepository.recordScheduledReviewSuccess]). The next time the Archive
 * (which shows those exported days) is resumed, focused and has settled, this may ask Google
 * Play for the in-app review card. It asks only for Play installs, only with paid access
 * (scheduled exports are premium; the free-export flow stays excluded), and only when the same
 * policy as the Export screen allows it (3 full successes on 2 days, 120 days and a new version
 * after an attempt, 7 days after a failed request). A pending moment is kept while the screen
 * isn't ready (a dialog or sheet holds focus) and consumed once it is evaluated.
 */
@Singleton
class ScheduledReviewMoment internal constructor(
    private val settingsRepository: SettingsRepository,
    private val entitlementRepository: EntitlementRepository,
    private val reviewPrompter: ReviewPrompter,
    private val distributionPolicy: DistributionPolicy,
    private val appVersionCode: Long,
    private val nowEpochMillis: () -> Long,
) {
    @Inject constructor(
        settingsRepository: SettingsRepository,
        entitlementRepository: EntitlementRepository,
        reviewPrompter: ReviewPrompter,
        distributionPolicy: DistributionPolicy,
    ) : this(
        settingsRepository,
        entitlementRepository,
        reviewPrompter,
        distributionPolicy,
        BuildConfig.VERSION_CODE.toLong(),
        System::currentTimeMillis,
    )

    enum class Outcome { UNAVAILABLE, BUSY, NOT_READY, NO_MOMENT, NOT_PAID, NOT_ELIGIBLE, PROMPTED, FAILED }

    private val running = Mutex()

    /** [isReady]: the Archive is resumed and focused, with nothing else on screen. */
    suspend fun maybePrompt(activity: Activity, isReady: () -> Boolean): Outcome {
        if (!distributionPolicy.reviewPromptAvailable || !reviewPrompter.isAvailable) return Outcome.UNAVAILABLE
        if (!running.tryLock()) return Outcome.BUSY
        try {
            if (!isReady()) return Outcome.NOT_READY
            val pending = runCatchingCancellable { settingsRepository.takeScheduledReviewMoment() }
                .getOrElse { Timber.w(it, "Could not read the scheduled review moment"); false }
            if (!pending) return Outcome.NO_MOMENT
            if (!entitlementRepository.isUnlocked.value) return Outcome.NOT_PAID
            val now = nowEpochMillis()
            val eligible = runCatchingCancellable {
                ReviewPromptPolicy.shouldRequestReview(
                    state = settingsRepository.getReviewPromptState(now),
                    currentAppVersionCode = appVersionCode,
                    nowEpochMillis = now,
                )
            }.getOrDefault(false)
            if (!eligible) return Outcome.NOT_ELIGIBLE
            if (!isReady()) return Outcome.NOT_READY
            val completed = reviewPrompter.prompt(activity) == ReviewPromptResult.Completed
            runCatchingCancellable {
                if (completed) settingsRepository.recordReviewAttempt(now, appVersionCode)
                else settingsRepository.recordReviewRequestFailure(now)
            }.onFailure { Timber.e(it, "Failed to persist the scheduled review request") }
            return if (completed) Outcome.PROMPTED else Outcome.FAILED
        } finally {
            running.unlock()
        }
    }
}
