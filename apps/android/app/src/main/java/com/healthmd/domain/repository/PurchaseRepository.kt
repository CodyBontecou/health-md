package com.healthmd.domain.repository

import android.app.Activity
import com.healthmd.domain.billing.BillingError
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

    fun refresh()
    suspend fun launchPurchase(activity: Activity, plan: PurchasePlan = PurchasePlan.LIFETIME): Boolean
    suspend fun restorePurchase(): Boolean
    fun clearError()
}
