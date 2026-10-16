package com.healthmd.domain.repository

import android.app.Activity
import com.healthmd.domain.billing.BillingError
import kotlinx.coroutines.flow.StateFlow

/** Health.md-owned purchase presentation data; no store SDK object crosses this boundary. */
data class PurchaseOffer(
    val productId: String,
    val localizedPriceText: String,
)

/** Channel-neutral purchase actions. Unavailable channels expose no simulated buy or restore path. */
interface PurchaseRepository {
    val isAvailable: Boolean
    val isPurchasing: StateFlow<Boolean>
    val isRestoring: StateFlow<Boolean>
    val purchaseError: StateFlow<BillingError?>
    val offer: StateFlow<PurchaseOffer?>

    fun refresh()
    suspend fun launchPurchase(activity: Activity): Boolean
    suspend fun restorePurchase(): Boolean
    /** Store purchase evidence for an explicit, user-initiated myself.md claim. */
    suspend fun migrationPurchaseToken(): String? = null
    fun clearError()
}
