package com.healthmd.data.billing

import com.android.billingclient.api.ProductDetails
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.repository.PurchasePlan
import io.mockk.every
import io.mockk.mockk
import org.junit.Test

class SubscriptionOfferSelectionTest {
    private fun phase(period: String, price: Long, recurring: Boolean = true, cycles: Int = 1,
                      mode: Int? = null) =
        mockk<ProductDetails.PricingPhase> {
            every { billingPeriod } returns period
            every { priceAmountMicros } returns price
            every { recurrenceMode } returns (mode ?: if (recurring) ProductDetails.RecurrenceMode.INFINITE_RECURRING
                else ProductDetails.RecurrenceMode.FINITE_RECURRING)
            every { billingCycleCount } returns cycles
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

    @Test fun equivalentSevenDayTrialRepresentationsArePreferred() {
        val paid = phase("P1W", 990_000)
        val base = offer(paid)
        for (period in listOf("P7D", "P1W")) {
            for ((mode, cycles) in listOf(
                ProductDetails.RecurrenceMode.FINITE_RECURRING to 1,
                ProductDetails.RecurrenceMode.NON_RECURRING to 0,
            )) {
                val free = phase(period, 0, false, cycles, mode)
                assertThat(free.isSevenDayFreeTrial()).isTrue()
                val trial = offer(free, paid)
                assertThat(selectSubscriptionOffer(details(base, trial), PurchasePlan.WEEKLY))
                    .isSameInstanceAs(trial)
            }
        }
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
            offer(phase("P1W", 0, false, cycles = 2), paid),
            offer(phase("P7D", 0, mode = ProductDetails.RecurrenceMode.INFINITE_RECURRING), paid),
            offer(phase("P7D", 0, false, cycles = 1,
                mode = ProductDetails.RecurrenceMode.NON_RECURRING), paid),
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

    private fun switchPhase(price: Long, mode: Int, cycles: Int, currency: String = "USD", period: String = "P1Y") =
        mockk<ProductDetails.PricingPhase> {
            every { billingPeriod } returns period
            every { priceAmountMicros } returns price
            every { recurrenceMode } returns mode
            every { billingCycleCount } returns cycles
            every { priceCurrencyCode } returns currency
        }

    private fun switchOffer(
        vararg phases: ProductDetails.PricingPhase,
        id: String? = YearlySwitchOfferIds.OFFER_ID,
        basePlan: String = YearlySwitchOfferIds.BASE_PLAN_ID,
        tags: List<String> = listOf(YearlySwitchOfferIds.TAG),
        token: String = "switch-token",
    ) = mockk<ProductDetails.SubscriptionOfferDetails> {
        every { offerId } returns id
        every { basePlanId } returns basePlan
        every { offerTags } returns tags
        every { offerToken } returns token
        every { pricingPhases } returns mockk { every { pricingPhaseList } returns phases.toList() }
    }

    private val intro = switchPhase(19_990_000, ProductDetails.RecurrenceMode.FINITE_RECURRING, 1)
    private val yearly = switchPhase(29_990_000, ProductDetails.RecurrenceMode.INFINITE_RECURRING, 0)

    @Test fun yearlySwitchOfferIsOneDiscountedYearThenTheYearlyPrice() {
        val offer = switchOffer(intro, yearly)
        assertThat(selectYearlySwitchOffer(details(offer))).isSameInstanceAs(offer)
    }

    @Test fun yearlySwitchOfferIsHiddenRatherThanMisdescribed() {
        for (invalid in listOf(
            switchOffer(intro, yearly, id = "trial-7d"),
            switchOffer(intro, yearly, basePlan = "weekly"),
            switchOffer(intro, yearly, tags = emptyList()),
            switchOffer(intro, yearly, token = ""),
            switchOffer(yearly),
            switchOffer(switchPhase(19_990_000, ProductDetails.RecurrenceMode.FINITE_RECURRING, 2), yearly),
            switchOffer(switchPhase(19_990_000, ProductDetails.RecurrenceMode.FINITE_RECURRING, 1, period = "P6M"), yearly),
            switchOffer(switchPhase(19_990_000, ProductDetails.RecurrenceMode.FINITE_RECURRING, 1, currency = "EUR"), yearly),
            switchOffer(switchPhase(0, ProductDetails.RecurrenceMode.FINITE_RECURRING, 1), yearly),
            switchOffer(switchPhase(29_990_000, ProductDetails.RecurrenceMode.FINITE_RECURRING, 1), yearly),
        )) {
            assertThat(selectYearlySwitchOffer(details(invalid))).isNull()
        }
    }

    @Test fun paywallNeverAdvertisesTheSwitchOffer() {
        val base = offer(phase("P1Y", 29_990_000))
        val switch = switchOffer(intro, yearly)
        assertThat(selectSubscriptionOffer(details(switch, base), PurchasePlan.YEARLY)).isSameInstanceAs(base)
    }
}
