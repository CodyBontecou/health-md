package com.healthmd.data.billing

import com.android.billingclient.api.Purchase

/** This is evidence selection, never a client-side grant. The server rechecks with Google. */
internal fun myselfClaimPurchaseToken(purchases: List<Purchase>): String? = purchases.firstOrNull {
    "health_md_premium_lifetime" in it.products &&
        it.purchaseState == Purchase.PurchaseState.PURCHASED && it.purchaseToken.isNotBlank()
}?.purchaseToken
