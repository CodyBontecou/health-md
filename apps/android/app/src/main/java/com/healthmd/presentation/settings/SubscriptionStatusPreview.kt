package com.healthmd.presentation.settings

import com.healthmd.BuildConfig
import com.healthmd.domain.billing.SubscriptionStatus
import com.healthmd.domain.billing.YearlySwitchOffer
import com.healthmd.domain.repository.PurchasePlan

/**
 * Debug-only Settings › Subscription preview, for emulators without a Play test account.
 * It changes what the Subscription screen shows, never access, purchases or stored state.
 * Opt in per launch, like [com.healthmd.presentation.paywall.StaticPurchasePreview]:
 *
 * `adb shell am start -n com.healthmd.android/com.healthmd.presentation.MainActivity --es previewSubscriptionStatus yearly`
 *
 * Values: free, weekly, yearly, weekly_canceled, yearly_canceled, lifetime, included,
 * ended_weekly, ended_yearly. Add `_dated` to a weekly or yearly value to show a sample verified
 * date (5 days out for Weekly, 300 for Yearly). `weekly_offer` shows the Weekly -> Yearly card
 * with sample prices. Release builds ignore it.
 */
object SubscriptionStatusPreview {
    const val EXTRA = "previewSubscriptionStatus"

    @Volatile
    var status: SubscriptionStatus? = null
        private set

    @Volatile
    var switchOffer: YearlySwitchOffer? = null
        private set

    fun configure(requested: String?) {
        status = if (BuildConfig.DEBUG) parse(requested) else null
        switchOffer = if (BuildConfig.DEBUG && requested?.trim()?.lowercase()?.startsWith("weekly_offer") == true) {
            YearlySwitchOffer(introductoryFormattedPrice = "$19.99", recurringFormattedPrice = "$29.99")
        } else {
            null
        }
    }

    internal fun parse(value: String?, nowMillis: Long = System.currentTimeMillis()): SubscriptionStatus? {
        val normalized = value?.trim()?.lowercase() ?: return null
        if (normalized.startsWith("weekly_offer")) return parse(normalized.replace("weekly_offer", "weekly"), nowMillis)
        if (normalized.endsWith("_dated")) {
            val base = parse(normalized.removeSuffix("_dated"), nowMillis) as? SubscriptionStatus.Subscribed ?: return null
            val days = if (base.plan == PurchasePlan.WEEKLY) 5L else 300L
            return base.copy(periodEndMillis = nowMillis + days * 24 * 60 * 60 * 1000)
        }
        return parseBase(normalized)
    }

    private fun parseBase(value: String): SubscriptionStatus? = when (value) {
        "free" -> SubscriptionStatus.Free
        "weekly" -> SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = true)
        "yearly" -> SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = true)
        "weekly_canceled" -> SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = false)
        "yearly_canceled" -> SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = false)
        "lifetime" -> SubscriptionStatus.Lifetime
        "included" -> SubscriptionStatus.IncludedAccess
        "ended_weekly" -> SubscriptionStatus.Ended(PurchasePlan.WEEKLY)
        "ended_yearly" -> SubscriptionStatus.Ended(PurchasePlan.YEARLY)
        else -> null
    }
}
