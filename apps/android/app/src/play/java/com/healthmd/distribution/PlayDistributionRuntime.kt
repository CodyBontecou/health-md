package com.healthmd.distribution

import com.healthmd.data.attribution.CampaignAttributionInitializer
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsInitializer
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject

/** Google Play integrations that are active in the phone-only release. */
class PlayDistributionRuntime @Inject constructor(
    private val campaignAttributionInitializer: CampaignAttributionInitializer,
    private val onboardingAnalyticsInitializer: OnboardingAnalyticsInitializer,
) : DistributionRuntime {
    private val initialized = AtomicBoolean(false)

    override fun initialize() {
        if (!initialized.compareAndSet(false, true)) return
        campaignAttributionInitializer.start()
        onboardingAnalyticsInitializer.start()
    }

    override suspend fun reconcileForeground() = Unit
}
