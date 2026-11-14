package com.healthmd.domain.billing

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.repository.PurchasePlan
import org.junit.Test

class SubscriptionDatesTest {
    private val now = 1_800_000_000_000L
    private val later = now + 86_400_000L
    private val yearly = SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = true)

    private fun answer(product: String = PurchasePlan.YEARLY.productId, state: String = "active", expires: Long? = later) =
        VerifiedPlaySubscription(product, state, expires, autoRenewing = true)

    @Test fun matchingActiveGraceOrCanceledAnswerGivesTheDate() {
        for (state in listOf("active", "grace", "canceled")) {
            assertThat(SubscriptionDates.periodEnd(yearly, answer(state = state), now)).isEqualTo(later)
        }
    }

    @Test fun anythingElseIsUndated() {
        assertThat(SubscriptionDates.periodEnd(yearly, null, now)).isNull()
        assertThat(SubscriptionDates.periodEnd(yearly, answer(product = PurchasePlan.WEEKLY.productId), now)).isNull()
        for (state in listOf("on_hold", "paused", "expired", "pending", "")) {
            assertThat(SubscriptionDates.periodEnd(yearly, answer(state = state), now)).isNull()
        }
        assertThat(SubscriptionDates.periodEnd(yearly, answer(expires = null), now)).isNull()
        assertThat(SubscriptionDates.periodEnd(yearly, answer(expires = now), now)).isNull()
    }

    @Test fun switchOfferIsOnlyForARenewingWeeklySubscriber() {
        val offer = YearlySwitchOffer("$19.99", "$29.99")
        val weekly = SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = true)
        assertThat(YearlySwitchEligibility.eligible(weekly, offer)).isEqualTo(offer)
        assertThat(YearlySwitchEligibility.eligible(weekly, null)).isNull()
        for (status in listOf(
            weekly.copy(isAutoRenewing = false),
            // Lifetime or grandfathered access beside Weekly: a paid upgrade gains nothing.
            weekly.copy(hasIncludedAccess = true),
            yearly,
            SubscriptionStatus.Lifetime,
            SubscriptionStatus.IncludedAccess,
            SubscriptionStatus.Ended(PurchasePlan.WEEKLY),
            SubscriptionStatus.Free,
            SubscriptionStatus.Unknown,
        )) {
            assertThat(YearlySwitchEligibility.eligible(status, offer)).isNull()
        }
    }

    @Test fun manageLinkFollowsTheOwnedOrJustEndedPlan() {
        val pkg = "com.healthmd.android"
        assertThat(PlaySubscriptionLinks.forStatus(yearly, pkg))
            .isEqualTo("https://play.google.com/store/account/subscriptions?sku=health_md_premium_yearly&package=com.healthmd.android")
        assertThat(PlaySubscriptionLinks.forStatus(SubscriptionStatus.Ended(PurchasePlan.WEEKLY), pkg))
            .isEqualTo("https://play.google.com/store/account/subscriptions?sku=health_md_premium_weekly&package=com.healthmd.android")
        for (status in listOf(SubscriptionStatus.Lifetime, SubscriptionStatus.Free, SubscriptionStatus.Unknown, SubscriptionStatus.IncludedAccess)) {
            assertThat(PlaySubscriptionLinks.forStatus(status, pkg)).isEqualTo(PlaySubscriptionLinks.SUBSCRIPTION_CENTER)
        }
    }

    @Test fun serverCancelDowngradesALocallyRenewingStatusAndKeepsTheDate() {
        for (canceled in listOf(
            answer(state = "canceled").copy(autoRenewing = false),
            answer(state = "active").copy(autoRenewing = false),
            answer(state = "canceled"),
        )) {
            assertThat(SubscriptionDates.apply(yearly, canceled, now))
                .isEqualTo(yearly.copy(isAutoRenewing = false, periodEndMillis = later))
        }
    }

    @Test fun serverRenewingNeverOverridesALocalCancelAndUnusableAnswersAddNothing() {
        val localCancel = yearly.copy(isAutoRenewing = false)
        assertThat(SubscriptionDates.apply(localCancel, answer(), now))
            .isEqualTo(localCancel.copy(periodEndMillis = later))
        assertThat(SubscriptionDates.apply(yearly, answer(), now)).isEqualTo(yearly.copy(periodEndMillis = later))
        // A mismatched or stale answer neither dates nor downgrades.
        for (unusable in listOf(
            null,
            answer(product = PurchasePlan.WEEKLY.productId).copy(autoRenewing = false),
            answer(state = "expired").copy(autoRenewing = false),
            answer(expires = now).copy(autoRenewing = false),
        )) {
            assertThat(SubscriptionDates.apply(yearly, unusable, now)).isEqualTo(yearly)
        }
    }
}
