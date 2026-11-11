package com.healthmd.presentation.paywall

import com.healthmd.BuildConfig
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchasePlan

/**
 * Debug-only paywall preview with fixed US prices, for builds Google Play will not
 * sell to (for example the `.e2e` package). Mirrors the Apple `-StaticPurchasePrices`
 * launch argument. Opt in per launch:
 *
 * `adb shell am start -n com.healthmd.android.e2e/com.healthmd.presentation.MainActivity --ez staticPurchasePrices true`
 *
 * Release builds ignore it, and purchases still go through Play billing.
 */
object StaticPurchasePreview {
    const val EXTRA = "staticPurchasePrices"

    @Volatile
    var enabled: Boolean = false
        private set

    fun configure(requested: Boolean) {
        enabled = BuildConfig.DEBUG && requested
    }

    val offers: List<PurchaseOffer> = listOf(
        PurchaseOffer(PurchasePlan.WEEKLY.productId, "$0.99", PurchasePlan.WEEKLY, hasSevenDayTrial = true),
        PurchaseOffer(PurchasePlan.YEARLY.productId, "$29.99", PurchasePlan.YEARLY, hasSevenDayTrial = true),
        PurchaseOffer(PurchasePlan.LIFETIME.productId, "$49.99", PurchasePlan.LIFETIME),
    )
}
