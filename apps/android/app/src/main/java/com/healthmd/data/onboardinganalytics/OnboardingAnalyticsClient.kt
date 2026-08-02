package com.healthmd.data.onboardinganalytics

import com.healthmd.domain.billing.FreemiumPolicy
import com.healthmd.domain.repository.SettingsRepository
import kotlinx.coroutines.CancellationException
import javax.inject.Inject
import javax.inject.Singleton

/** Typed, closed entry point for the eight supported onboarding events. */
@Singleton
class OnboardingAnalyticsClient @Inject constructor(
    private val eventFactory: OnboardingAnalyticsEventFactory,
    private val store: OnboardingAnalyticsStore,
    private val scheduler: OnboardingAnalyticsWorkScheduler,
    private val settingsRepository: SettingsRepository,
) {
    suspend fun onboardingStarted() = record(
        PricingOnboardingEventName.STARTED,
        OnboardingAnalyticsStep.WELCOME,
    )

    suspend fun stepViewed(step: OnboardingAnalyticsStep) = record(
        PricingOnboardingEventName.STEP_VIEWED,
        step,
    )

    suspend fun healthSkipped() = record(
        PricingOnboardingEventName.HEALTH_SKIPPED,
        OnboardingAnalyticsStep.HEALTH_ACCESS,
    )

    suspend fun folderSelected() = record(
        PricingOnboardingEventName.FOLDER_SELECTED,
        OnboardingAnalyticsStep.FOLDER_SETUP,
    )

    suspend fun folderSkipped() = record(
        PricingOnboardingEventName.FOLDER_SKIPPED,
        OnboardingAnalyticsStep.FOLDER_SETUP,
    )

    suspend fun continueFreeTapped() = record(
        PricingOnboardingEventName.CONTINUE_FREE_TAPPED,
        OnboardingAnalyticsStep.UNLOCK,
    )

    suspend fun purchaseTapped() = record(
        PricingOnboardingEventName.PURCHASE_TAPPED,
        OnboardingAnalyticsStep.UNLOCK,
        OnboardingAnalyticsProductId.PREMIUM_LIFETIME,
    )

    suspend fun onboardingCompleted() = record(
        PricingOnboardingEventName.COMPLETED,
        OnboardingAnalyticsStep.READY,
    )

    private suspend fun record(
        eventName: PricingOnboardingEventName,
        step: OnboardingAnalyticsStep,
        productId: OnboardingAnalyticsProductId? = null,
    ) {
        val usage = loadFreeExportUsage()
        val event = eventFactory.create(
            eventName = eventName,
            step = step,
            productId = productId,
            freeExportsUsed = usage?.first,
            freeExportsRemaining = usage?.second,
        )
        val inserted = store.enqueue(
            event = event,
            milestoneKey = DurableOnboardingAnalyticsStore.milestoneKey(eventName, step),
        )
        if (inserted) scheduler.enqueueUpload()
    }

    private suspend fun loadFreeExportUsage(): Pair<Int, Int>? = try {
        val used = settingsRepository.getFreeExportsUsed()
        val remaining = settingsRepository.getFreeExportsRemaining()
        if (used in 0..FreemiumPolicy.FREE_EXPORT_LIMIT &&
            remaining in 0..FreemiumPolicy.FREE_EXPORT_LIMIT &&
            used + remaining == FreemiumPolicy.FREE_EXPORT_LIMIT
        ) {
            used to remaining
        } else {
            null
        }
    } catch (error: CancellationException) {
        throw error
    } catch (_: Exception) {
        // Usage is optional. Never attach or log the underlying settings error.
        null
    }
}
