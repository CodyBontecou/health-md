package com.healthmd.domain.billing

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.repository.PurchasePlan
import org.junit.Test

class SubscriptionLapseTest {
    private val weekly = ActivePurchase(PurchasePlan.WEEKLY, isAutoRenewing = true)
    private val yearlyCanceled = ActivePurchase(PurchasePlan.YEARLY, isAutoRenewing = false)
    private val lifetime = ActivePurchase(PurchasePlan.LIFETIME, isAutoRenewing = false)

    @Test fun anOwnedSubscriptionIsRememberedAndReplacesAnOlderOne() {
        assertThat(SubscriptionLapse.rememberedPlan(null, weekly)).isEqualTo(PurchasePlan.WEEKLY)
        assertThat(SubscriptionLapse.rememberedPlan(PurchasePlan.WEEKLY, yearlyCanceled)).isEqualTo(PurchasePlan.YEARLY)
    }

    @Test fun anEmptySnapshotKeepsTheRememberedSubscription() {
        assertThat(SubscriptionLapse.rememberedPlan(PurchasePlan.YEARLY, null)).isEqualTo(PurchasePlan.YEARLY)
        assertThat(SubscriptionLapse.rememberedPlan(null, null)).isNull()
    }

    @Test fun lifetimeClearsTheMemoryBecauseNothingCanLapse() {
        assertThat(SubscriptionLapse.rememberedPlan(PurchasePlan.WEEKLY, lifetime)).isNull()
        assertThat(SubscriptionLapse.rememberedPlan(PurchasePlan.LIFETIME, null)).isNull()
    }

    @Test fun hadASubscriptionBeforeAndNoneNowIsALapse() {
        val remembered = SubscriptionLapse.rememberedPlan(PurchasePlan.YEARLY, null)
        assertThat(SubscriptionLapse.status(null, remembered, hasIncludedAccess = false))
            .isEqualTo(SubscriptionStatus.Ended(PurchasePlan.YEARLY))
    }

    @Test fun neverSubscribedIsFreeNotEnded() {
        assertThat(SubscriptionLapse.status(null, null, hasIncludedAccess = false)).isEqualTo(SubscriptionStatus.Free)
    }

    @Test fun ownershipMapsToItsPlanAndRenewalState() {
        assertThat(SubscriptionLapse.status(weekly, PurchasePlan.WEEKLY, hasIncludedAccess = false))
            .isEqualTo(SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = true))
        assertThat(SubscriptionLapse.status(yearlyCanceled, PurchasePlan.YEARLY, hasIncludedAccess = false))
            .isEqualTo(SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = false))
        assertThat(SubscriptionLapse.status(lifetime, null, hasIncludedAccess = false)).isEqualTo(SubscriptionStatus.Lifetime)
    }

    @Test fun grandfatheredAccessIsNeverReportedAsALapse() {
        assertThat(SubscriptionLapse.status(null, PurchasePlan.WEEKLY, hasIncludedAccess = true))
            .isEqualTo(SubscriptionStatus.IncludedAccess)
        // A store subscription still wins so its cancel path stays reachable.
        assertThat(SubscriptionLapse.status(weekly, PurchasePlan.WEEKLY, hasIncludedAccess = true))
            .isEqualTo(SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = true, hasIncludedAccess = true))
    }

    @Test fun primaryPrefersLifetimeThenYearlyThenWeekly() {
        assertThat(SubscriptionLapse.primary(listOf(weekly, lifetime, yearlyCanceled))).isEqualTo(lifetime)
        assertThat(SubscriptionLapse.primary(listOf(weekly, yearlyCanceled))).isEqualTo(yearlyCanceled)
        assertThat(SubscriptionLapse.primary(emptyList())).isNull()
    }

    @Test fun manageLinkNamesTheActiveSubscriptionAndPackage() {
        assertThat(PlaySubscriptionLinks.manage(PurchasePlan.YEARLY, "com.healthmd.android")).isEqualTo(
            "https://play.google.com/store/account/subscriptions?sku=health_md_premium_yearly&package=com.healthmd.android",
        )
        assertThat(PlaySubscriptionLinks.manage(PurchasePlan.WEEKLY, "com.healthmd.android.e2e")).isEqualTo(
            "https://play.google.com/store/account/subscriptions?sku=health_md_premium_weekly&package=com.healthmd.android.e2e",
        )
    }

    @Test fun manageLinkFallsBackToTheSubscriptionListWithoutASubscription() {
        val list = "https://play.google.com/store/account/subscriptions"
        assertThat(PlaySubscriptionLinks.manage(null, "com.healthmd.android")).isEqualTo(list)
        assertThat(PlaySubscriptionLinks.manage(PurchasePlan.LIFETIME, "com.healthmd.android")).isEqualTo(list)
        assertThat(PlaySubscriptionLinks.manage(PurchasePlan.YEARLY, "")).isEqualTo(list)
    }
}
