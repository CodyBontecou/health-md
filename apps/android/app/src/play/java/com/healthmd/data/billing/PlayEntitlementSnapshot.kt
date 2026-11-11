package com.healthmd.data.billing

import com.android.billingclient.api.Purchase
import com.healthmd.domain.repository.PurchasePlan

/** A fresh Play snapshot, not a durable boolean grant for subscription owners. */
internal data class PlayEntitlementSnapshot(
    val hasAccess: Boolean,
    val hasLifetime: Boolean,
    val unacknowledgedTokens: List<String>,
)

internal fun playEntitlementSnapshot(purchases: List<Purchase>): PlayEntitlementSnapshot {
    val completed = purchases.filter { purchase ->
        purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
            purchase.products.any { id -> PurchasePlan.entries.any { it.productId == id } }
    }
    return PlayEntitlementSnapshot(
        hasAccess = completed.isNotEmpty(),
        hasLifetime = completed.any { PurchasePlan.LIFETIME.productId in it.products },
        unacknowledgedTokens = completed.filterNot { it.isAcknowledged }.map { it.purchaseToken }.distinct(),
    )
}
