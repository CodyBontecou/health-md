package com.healthmd.data.billing

import com.android.billingclient.api.Purchase
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.billing.ActivePurchase
import com.healthmd.domain.repository.PurchasePlan
import io.mockk.every
import io.mockk.mockk
import org.junit.Test

class PlayEntitlementSnapshotTest {
    private fun purchase(
        plan: PurchasePlan,
        state: Int = Purchase.PurchaseState.PURCHASED,
        acknowledged: Boolean = false,
        autoRenewing: Boolean = true,
    ) =
        mockk<Purchase> {
            every { products } returns listOf(plan.productId)
            every { purchaseState } returns state
            every { isAcknowledged } returns acknowledged
            every { isAutoRenewing } returns autoRenewing
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

    @Test fun ownedSubscriptionReportsItsPlanAndRenewalState() {
        val renewing = playEntitlementSnapshot(listOf(purchase(PurchasePlan.WEEKLY)))
        assertThat(renewing.activePurchase).isEqualTo(ActivePurchase(PurchasePlan.WEEKLY, isAutoRenewing = true))

        val cancelled = playEntitlementSnapshot(listOf(purchase(PurchasePlan.YEARLY, autoRenewing = false)))
        assertThat(cancelled.activePurchase).isEqualTo(ActivePurchase(PurchasePlan.YEARLY, isAutoRenewing = false))
    }

    @Test fun lifetimeIsPresentedOverASubscriptionAndNeverRenews() {
        val snapshot = playEntitlementSnapshot(listOf(purchase(PurchasePlan.WEEKLY), purchase(PurchasePlan.LIFETIME)))
        assertThat(snapshot.activePurchase).isEqualTo(ActivePurchase(PurchasePlan.LIFETIME, isAutoRenewing = false))
    }

    @Test fun pendingPurchaseIsNotPresentedAsOwned() {
        val snapshot = playEntitlementSnapshot(listOf(purchase(PurchasePlan.YEARLY, Purchase.PurchaseState.PENDING)))
        assertThat(snapshot.activePurchase).isNull()
    }

    @Test fun activeSubscriptionTokenIsKeptOnlyForTheOwnedSubscription() {
        assertThat(playEntitlementSnapshot(listOf(purchase(PurchasePlan.WEEKLY))).activeSubscriptionToken)
            .isEqualTo("test-token-WEEKLY")
        // Lifetime wins the presentation, so no subscription token is offered for switching.
        assertThat(playEntitlementSnapshot(listOf(purchase(PurchasePlan.WEEKLY), purchase(PurchasePlan.LIFETIME)))
            .activeSubscriptionToken).isNull()
        assertThat(playEntitlementSnapshot(emptyList()).activeSubscriptionToken).isNull()
    }

    @Test fun snapshotTextNeverContainsPurchaseTokens() {
        val text = playEntitlementSnapshot(listOf(purchase(PurchasePlan.YEARLY))).toString()
        assertThat(text).doesNotContain("test-token")
    }
}
