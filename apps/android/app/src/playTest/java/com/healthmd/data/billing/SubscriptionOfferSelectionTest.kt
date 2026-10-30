package com.healthmd.data.billing

import com.android.billingclient.api.ProductDetails
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.repository.PurchasePlan
import io.mockk.every
import io.mockk.mockk
import org.junit.Test

class SubscriptionOfferSelectionTest {
    private fun phase(period: String, price: Long, recurring: Boolean = true) =
        mockk<ProductDetails.PricingPhase> {
            every { billingPeriod } returns period
            every { priceAmountMicros } returns price
            every { recurrenceMode } returns if (recurring) ProductDetails.RecurrenceMode.INFINITE_RECURRING
                else ProductDetails.RecurrenceMode.FINITE_RECURRING
            every { billingCycleCount } returns 1
        }

    private fun offer(vararg phases: ProductDetails.PricingPhase) =
        mockk<ProductDetails.SubscriptionOfferDetails> {
            every { pricingPhases } returns mockk {
                every { pricingPhaseList } returns phases.toList()
            }
        }

    private fun details(vararg offers: ProductDetails.SubscriptionOfferDetails) = mockk<ProductDetails> {
        every { subscriptionOfferDetails } returns offers.toList()
    }

    @Test fun eligibleSevenDayTrialIsPreferredToPaidBasePlan() {
        val paid = phase("P1W", 990_000)
        val base = offer(paid)
        val trial = offer(phase("P7D", 0, false), paid)
        assertThat(selectSubscriptionOffer(details(base, trial), PurchasePlan.WEEKLY)).isSameInstanceAs(trial)
    }

    @Test fun ineligibleAccountGetsOnlyItsPaidTerms() {
        val base = offer(phase("P1Y", 29_990_000))
        assertThat(selectSubscriptionOffer(details(base), PurchasePlan.YEARLY)).isSameInstanceAs(base)
    }

    @Test fun wrongCadenceTrialLengthAndFinitePaidPlansAreNotAdvertised() {
        val paid = phase("P1W", 990_000)
        for (invalid in listOf(
            offer(phase("P1M", 4_990_000)),
            offer(phase("P3D", 0, false), paid),
            offer(phase("P7D", 100_000, false), paid),
            offer(phase("P1W", 990_000, false)),
            offer(),
        )) {
            assertThat(selectSubscriptionOffer(details(invalid), PurchasePlan.WEEKLY)).isNull()
        }
    }

    @Test fun lifetimeNeverSelectsASubscriptionOffer() {
        assertThat(selectSubscriptionOffer(details(offer(phase("P1Y", 29_990_000))), PurchasePlan.LIFETIME)).isNull()
        assertThat(PurchasePlan.entries.map { it.productId }).containsExactly(
            "health_md_premium_weekly", "health_md_premium_yearly", "health_md_premium_lifetime",
        )
    }
}
