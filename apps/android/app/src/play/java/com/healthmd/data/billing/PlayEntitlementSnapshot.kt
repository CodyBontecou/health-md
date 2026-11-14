package com.healthmd.data.billing

import com.android.billingclient.api.Purchase
import com.healthmd.domain.billing.ActivePurchase
import com.healthmd.domain.billing.SubscriptionLapse
import com.healthmd.domain.repository.PurchasePlan

/** A fresh Play snapshot, not a durable boolean grant for subscription owners. */
internal data class PlayEntitlementSnapshot(
    val hasAccess: Boolean,
    val hasLifetime: Boolean,
    val unacknowledgedTokens: List<String>,
    /** The owned plan to present in Settings › Subscription; null when nothing is owned. */
    val activePurchase: ActivePurchase? = null,
    /**
     * Purchase token of [activePurchase] when it is a subscription: the old token for a plan
     * switch and the proof for the server date read. Held in memory only, never logged.
     */
    val activeSubscriptionToken: String? = null,
) {
    override fun toString(): String =
        "PlayEntitlementSnapshot(hasAccess=$hasAccess, hasLifetime=$hasLifetime, activePurchase=$activePurchase)"
}

internal fun playEntitlementSnapshot(purchases: List<Purchase>): PlayEntitlementSnapshot {
    val completed = purchases.filter { purchase ->
        purchase.purchaseState == Purchase.PurchaseState.PURCHASED &&
            purchase.products.any { id -> PurchasePlan.entries.any { it.productId == id } }
    }
    val owned = completed.flatMap { purchase ->
        PurchasePlan.entries
            .filter { it.productId in purchase.products }
            .map { plan ->
                ActivePurchase(plan, isAutoRenewing = plan != PurchasePlan.LIFETIME && purchase.isAutoRenewing)
            }
    }
    val active = SubscriptionLapse.primary(owned)
    val activeToken = active?.plan?.takeIf { it != PurchasePlan.LIFETIME }?.let { plan ->
        completed.firstOrNull { plan.productId in it.products }?.purchaseToken?.takeIf { it.isNotBlank() }
    }
    return PlayEntitlementSnapshot(
        hasAccess = completed.isNotEmpty(),
        hasLifetime = completed.any { PurchasePlan.LIFETIME.productId in it.products },
        unacknowledgedTokens = completed.filterNot { it.isAcknowledged }.map { it.purchaseToken }.distinct(),
        activePurchase = active,
        activeSubscriptionToken = activeToken,
    )
}
