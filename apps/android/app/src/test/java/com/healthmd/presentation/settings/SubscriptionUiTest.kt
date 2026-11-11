package com.healthmd.presentation.settings

import com.google.common.truth.Truth.assertThat
import com.healthmd.R
import com.healthmd.domain.billing.ActivePurchase
import com.healthmd.domain.billing.SubscriptionLapse
import com.healthmd.domain.billing.SubscriptionStatus
import com.healthmd.domain.repository.PurchasePlan
import org.junit.Test

class SubscriptionUiTest {
    @Test fun renewingSubscriptionOffersManageOrCancelThroughBeforeYouGo() {
        val ui = subscriptionUi(SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = true))
        assertThat(ui.title).isEqualTo(R.string.m3_subscription_plan_yearly)
        assertThat(ui.status).isEqualTo(R.string.m3_subscription_status_renews)
        assertThat(ui.action).isEqualTo(SubscriptionAction.MANAGE_OR_CANCEL)
        assertThat(ui.managedPlan).isEqualTo(PurchasePlan.YEARLY)
        assertThat(ui.showsBillingDate).isTrue()
        assertThat(subscriptionManageUrl(ui, "com.healthmd.android")).isEqualTo(
            "https://play.google.com/store/account/subscriptions?sku=health_md_premium_yearly&package=com.healthmd.android",
        )
    }

    @Test fun canceledSubscriptionGoesStraightToPlayWithoutARetentionStep() {
        val ui = subscriptionUi(SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = false))
        assertThat(ui.status).isEqualTo(R.string.m3_subscription_status_cancelled)
        assertThat(ui.action).isEqualTo(SubscriptionAction.MANAGE_IN_PLAY)
        assertThat(ui.showsBillingDate).isFalse()
        assertThat(ui.showsAccessUntil).isTrue()
        assertThat(ui.periodEndMillis).isNull()
        assertThat(ui.managedPlan).isEqualTo(PurchasePlan.WEEKLY)
    }

    @Test fun grandfatheredSubscribersCanCancelWithoutClaimsOfLosingAccess() {
        for (renewing in listOf(true, false)) {
            val status = SubscriptionLapse.status(
                ActivePurchase(PurchasePlan.WEEKLY, isAutoRenewing = renewing),
                PurchasePlan.WEEKLY,
                hasIncludedAccess = true,
            )
            val ui = subscriptionUi((status as SubscriptionStatus.Subscribed).copy(periodEndMillis = 1_800_000_000_000L))
            assertThat(ui.action).isEqualTo(SubscriptionAction.MANAGE_IN_PLAY)
            assertThat(ui.actionNote).isNull()
            assertThat(ui.showsAccessUntil).isFalse()
            assertThat(ui.owned).isTrue()
            assertThat(ui.showsIncludes).isTrue()
            assertThat(subscriptionManageUrl(ui, "com.healthmd.android")).contains("sku=health_md_premium_weekly")
            assertThat(subscriptionUi(SubscriptionLapse.status(null, PurchasePlan.WEEKLY, true)).ended).isFalse()
        }
    }

    @Test fun lifetimeAndIncludedAccessHaveNoCancelPath() {
        listOf(SubscriptionStatus.Lifetime, SubscriptionStatus.IncludedAccess).forEach { status ->
            val ui = subscriptionUi(status)
            assertThat(ui.action).isNull()
            assertThat(ui.managedPlan).isNull()
            assertThat(ui.showsBillingDate).isFalse()
        }
        assertThat(subscriptionUi(SubscriptionStatus.Lifetime).status).isEqualTo(R.string.m3_subscription_status_lifetime)
    }

    @Test fun endedShowsTheLapsedLayoutAndLinksBackToThePreviousSubscription() {
        val ui = subscriptionUi(SubscriptionStatus.Ended(PurchasePlan.YEARLY))
        assertThat(ui.ended).isTrue()
        assertThat(ui.owned).isFalse()
        assertThat(ui.title).isEqualTo(R.string.m3_subscription_ended_title)
        assertThat(ui.action).isEqualTo(SubscriptionAction.SEE_PLANS)
        assertThat(ui.managedPlan).isEqualTo(PurchasePlan.YEARLY)
    }

    @Test fun freeAndUnknownNeverClaimOwnership() {
        assertThat(subscriptionUi(SubscriptionStatus.Free).action).isEqualTo(SubscriptionAction.SEE_PLANS)
        assertThat(subscriptionUi(SubscriptionStatus.Free).owned).isFalse()
        val unknown = subscriptionUi(SubscriptionStatus.Unknown)
        // Never a dead end: Play's subscription list stays reachable while Play hasn't answered.
        assertThat(unknown.action).isEqualTo(SubscriptionAction.MANAGE_IN_PLAY)
        assertThat(unknown.managedPlan).isNull()
        assertThat(unknown.owned).isFalse()
        assertThat(unknown.status).isEqualTo(R.string.m3_subscription_status_checking)
    }

    @Test fun previewValuesParseAndUnknownValuesAreIgnored() {
        assertThat(SubscriptionStatusPreview.parse("yearly"))
            .isEqualTo(SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = true))
        assertThat(SubscriptionStatusPreview.parse("ended_weekly")).isEqualTo(SubscriptionStatus.Ended(PurchasePlan.WEEKLY))
        assertThat(SubscriptionStatusPreview.parse("lifetime")).isEqualTo(SubscriptionStatus.Lifetime)
        assertThat(SubscriptionStatusPreview.parse("bogus")).isNull()
        assertThat(SubscriptionStatusPreview.parse(null)).isNull()
    }

    @Test fun verifiedDateIsCarriedAndCanceledShowsAccessUntil() {
        val end = 1_800_000_000_000L
        val renewing = subscriptionUi(SubscriptionStatus.Subscribed(PurchasePlan.YEARLY, isAutoRenewing = true, periodEndMillis = end))
        assertThat(renewing.periodEndMillis).isEqualTo(end)
        assertThat(renewing.showsBillingDate).isTrue()
        assertThat(renewing.showsAccessUntil).isFalse()

        val canceled = subscriptionUi(SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = false, periodEndMillis = end))
        assertThat(canceled.showsAccessUntil).isTrue()
        assertThat(subscriptionUi(SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = false)).showsAccessUntil).isTrue()
        assertThat(subscriptionUi(SubscriptionStatus.Ended(PurchasePlan.WEEKLY)).showsAccessUntil).isFalse()
    }

    @Test fun periodEndIsFormattedInTheReadersLocaleAndZone() {
        val utc = java.time.ZoneId.of("UTC")
        val millis = java.time.Instant.parse("2026-12-01T10:00:00Z").toEpochMilli()
        assertThat(formatPeriodEnd(millis, java.util.Locale.US, utc)).isEqualTo("December 1, 2026")
        assertThat(formatPeriodEnd(millis, java.util.Locale.GERMANY, utc)).isEqualTo("1. Dezember 2026")
    }

    @Test fun previewDatesAndOfferAreDebugSamplesOnly() {
        val now = 1_800_000_000_000L
        val dated = SubscriptionStatusPreview.parse("yearly_canceled_dated", now) as SubscriptionStatus.Subscribed
        assertThat(dated.isAutoRenewing).isFalse()
        assertThat(dated.periodEndMillis).isEqualTo(now + 300L * 86_400_000L)
        assertThat(SubscriptionStatusPreview.parse("weekly_offer", now))
            .isEqualTo(SubscriptionStatus.Subscribed(PurchasePlan.WEEKLY, isAutoRenewing = true))
        assertThat(SubscriptionStatusPreview.parse("lifetime_dated", now)).isNull()
    }
}
