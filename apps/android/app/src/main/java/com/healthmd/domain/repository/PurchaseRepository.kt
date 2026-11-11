package com.healthmd.domain.repository

import android.app.Activity
import com.healthmd.domain.billing.BillingError
import com.healthmd.domain.billing.SubscriptionStatus
import com.healthmd.domain.billing.YearlySwitchOffer
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/** Health.md-owned purchase presentation data; no store SDK object crosses this boundary. */
enum class PurchasePlan(val productId: String) {
    WEEKLY("health_md_premium_weekly"),
    YEARLY("health_md_premium_yearly"),
    LIFETIME("health_md_premium_lifetime"),
}

data class PurchaseOffer(
    val productId: String,
    val localizedPriceText: String,
    val plan: PurchasePlan = PurchasePlan.LIFETIME,
    val hasSevenDayTrial: Boolean = false,
)

/** Channel-neutral purchase actions. Unavailable channels expose no simulated buy or restore path. */
interface PurchaseRepository {
    val isAvailable: Boolean
    val isPurchasing: StateFlow<Boolean>
    val isRestoring: StateFlow<Boolean>
    val purchaseError: StateFlow<BillingError?>
    val offer: StateFlow<PurchaseOffer?>
    val offers: StateFlow<List<PurchaseOffer>>

    /** The owned plan from the latest full store snapshot, including a remembered lapse. */
    val subscriptionStatus: StateFlow<SubscriptionStatus> get() = UNKNOWN_STATUS

    /**
     * Play's `switch-yearly-1y` offer (tag `retention-in-app`) when Play returned one with the
     * exact shape the card describes; eligibility is decided by YearlySwitchEligibility.
     */
    val yearlySwitchOffer: StateFlow<YearlySwitchOffer?> get() = NO_SWITCH_OFFER

    fun refresh()

    /** Replaces the active Weekly subscription with the switch offer. False when not possible now. */
    suspend fun launchYearlySwitch(activity: Activity): Boolean = false

    suspend fun launchPurchase(activity: Activity, plan: PurchasePlan = PurchasePlan.LIFETIME): Boolean
    suspend fun restorePurchase(): Boolean
    fun clearError()

    companion object {
        private val UNKNOWN_STATUS = MutableStateFlow<SubscriptionStatus>(SubscriptionStatus.Unknown)
        private val NO_SWITCH_OFFER = MutableStateFlow<YearlySwitchOffer?>(null)
    }
}
