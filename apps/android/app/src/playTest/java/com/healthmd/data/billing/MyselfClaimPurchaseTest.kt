package com.healthmd.data.billing

import com.android.billingclient.api.Purchase
import io.mockk.every
import io.mockk.mockk
import org.junit.Assert.*
import org.junit.Test

class MyselfClaimPurchaseTest {
    private fun purchase(product: String = "health_md_premium_lifetime",
        state: Int = Purchase.PurchaseState.PURCHASED, token: String = "play-token"): Purchase = mockk {
        every { products } returns listOf(product)
        every { purchaseState } returns state
        every { purchaseToken } returns token
    }

    @Test fun onlyACompletedMatchingPurchaseCanSupplyEvidence() {
        assertNull(myselfClaimPurchaseToken(emptyList()))
        assertNull(myselfClaimPurchaseToken(listOf(purchase(state = Purchase.PurchaseState.PENDING))))
        assertNull(myselfClaimPurchaseToken(listOf(purchase(state = Purchase.PurchaseState.UNSPECIFIED_STATE))))
        assertNull(myselfClaimPurchaseToken(listOf(purchase(product = "other"))))
        assertNull(myselfClaimPurchaseToken(listOf(purchase(token = ""))))
        assertEquals("play-token", myselfClaimPurchaseToken(listOf(
            purchase(product = "other"), purchase(state = Purchase.PurchaseState.PENDING), purchase())))
    }
}
