package com.healthmd.data.billing

import com.android.billingclient.api.Purchase
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.repository.PurchasePlan
import io.mockk.every
import io.mockk.mockk
import org.junit.Test

class PlayEntitlementSnapshotTest {
    private fun purchase(plan: PurchasePlan, state: Int = Purchase.PurchaseState.PURCHASED, acknowledged: Boolean = false) =
        mockk<Purchase> {
            every { products } returns listOf(plan.productId)
            every { purchaseState } returns state
            every { isAcknowledged } returns acknowledged
            every { purchaseToken } returns "test-token-${plan.name}"
        }

    @Test fun trialsAndSubscriptionsNeverGrantPermanentAccess() {
        for (plan in listOf(PurchasePlan.WEEKLY, PurchasePlan.YEARLY)) {
            val snapshot = playEntitlementSnapshot(listOf(purchase(plan)))
            assertThat(snapshot.hasAccess).isTrue()
            assertThat(snapshot.hasLifetime).isFalse()
            assertThat(snapshot.unacknowledgedTokens).hasSize(1)
        }
    }

    @Test fun existingLifetimeRemainsPermanentAlongsideASubscription() {
        val snapshot = playEntitlementSnapshot(listOf(purchase(PurchasePlan.YEARLY), purchase(PurchasePlan.LIFETIME)))
        assertThat(snapshot.hasAccess).isTrue()
        assertThat(snapshot.hasLifetime).isTrue()
    }

    @Test fun emptyExpiredSnapshotHasNoSubscriptionGrant() {
        assertThat(playEntitlementSnapshot(emptyList()).hasAccess).isFalse()
        assertThat(playEntitlementSnapshot(emptyList()).hasLifetime).isFalse()
    }

    @Test fun pendingAndUnknownPurchasesDoNotUnlockOrAcknowledge() {
        val pending = purchase(PurchasePlan.YEARLY, Purchase.PurchaseState.PENDING)
        val unknown = purchase(PurchasePlan.LIFETIME, Purchase.PurchaseState.UNSPECIFIED_STATE)
        val unrelated = mockk<Purchase> {
            every { purchaseState } returns Purchase.PurchaseState.PURCHASED
            every { products } returns listOf("not-a-healthmd-product")
        }
        val snapshot = playEntitlementSnapshot(listOf(pending, unknown, unrelated))
        assertThat(snapshot.hasAccess).isFalse()
        assertThat(snapshot.hasLifetime).isFalse()
        assertThat(snapshot.unacknowledgedTokens).isEmpty()
    }

    @Test fun completedAcknowledgedPurchaseIsNotAcknowledgedAgain() {
        val snapshot = playEntitlementSnapshot(listOf(purchase(PurchasePlan.WEEKLY, acknowledged = true)))
        assertThat(snapshot.hasAccess).isTrue()
        assertThat(snapshot.unacknowledgedTokens).isEmpty()
    }
}
