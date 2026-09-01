package com.healthmd.distribution

import android.content.Context
import com.healthmd.data.attribution.CampaignAttributionInitializer
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsInitializer
import com.healthmd.wear.WearPhoneSync
import com.healthmd.wear.WearPhoneSyncResult
import com.healthmd.wear.WearPhoneSyncScheduler
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

class PlayDistributionRuntime @Inject constructor(
    @ApplicationContext private val context: Context,
    private val campaignAttributionInitializer: CampaignAttributionInitializer,
    private val onboardingAnalyticsInitializer: OnboardingAnalyticsInitializer,
    private val wearPhoneSync: WearPhoneSync,
    private val wearPhoneSyncScheduler: WearPhoneSyncScheduler,
) : DistributionRuntime {
    private val initialized = AtomicBoolean(false)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    override fun initialize() {
        if (!initialized.compareAndSet(false, true)) return
        campaignAttributionInitializer.start()
        onboardingAnalyticsInitializer.start()
        scope.launch {
            if (wearPhoneSync.resumePendingClear() == WearPhoneSyncResult.RETRY) {
                WearPhoneSyncScheduler.enqueueClearRecovery(context)
            }
            wearPhoneSyncScheduler.reconcile()
        }
    }

    override suspend fun reconcileForeground() {
        wearPhoneSyncScheduler.reconcile()
    }
}
