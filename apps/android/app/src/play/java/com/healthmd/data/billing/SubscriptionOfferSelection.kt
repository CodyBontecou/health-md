package com.healthmd.data.billing

import com.android.billingclient.api.ProductDetails
import com.healthmd.domain.repository.PurchasePlan

/** Only show store-returned base plans or the requested seven-day free trial. */
internal fun selectSubscriptionOffer(
    details: ProductDetails,
    plan: PurchasePlan,
): ProductDetails.SubscriptionOfferDetails? {
    if (plan == PurchasePlan.LIFETIME) return null
    val period = if (plan == PurchasePlan.WEEKLY) "P1W" else "P1Y"
    return details.subscriptionOfferDetails.orEmpty().filter { offer ->
        val phases = offer.pricingPhases.pricingPhaseList
        val recurring = phases.lastOrNull()
        recurring?.billingPeriod == period && recurring.priceAmountMicros > 0 &&
            recurring.recurrenceMode == ProductDetails.RecurrenceMode.INFINITE_RECURRING &&
            (phases.size == 1 || (phases.size == 2 && phases.first().isSevenDayFreeTrial()))
    }.sortedByDescending { it.pricingPhases.pricingPhaseList.size }.firstOrNull()
}

/** Play may express one week as P1W or P7D; a non-recurring phase has zero cycles. */
internal fun ProductDetails.PricingPhase.isSevenDayFreeTrial(): Boolean =
    priceAmountMicros == 0L && billingPeriod in setOf("P7D", "P1W") &&
        when (recurrenceMode) {
            ProductDetails.RecurrenceMode.FINITE_RECURRING -> billingCycleCount == 1
            ProductDetails.RecurrenceMode.NON_RECURRING -> billingCycleCount == 0
            else -> false
        }

/** Play Console IDs for the in-app Weekly -> Yearly switch offer (see docs/retention-messages.md). */
internal object YearlySwitchOfferIds {
    const val BASE_PLAN_ID = "yearly"
    const val OFFER_ID = "switch-yearly-1y"
    const val TAG = "retention-in-app"
}

/**
 * The `switch-yearly-1y` offer on the Yearly base plan, tagged `retention-in-app`. The card says
 * "for your first year, then the Yearly price", so the offer must be exactly one discounted P1Y
 * cycle followed by the recurring P1Y price in the same currency; anything else hides the card
 * rather than misdescribing it. The paywall never shows this offer ([selectSubscriptionOffer]
 * admits only a base plan or a free trial).
 */
internal fun selectYearlySwitchOffer(details: ProductDetails): ProductDetails.SubscriptionOfferDetails? {
    val offer = details.subscriptionOfferDetails.orEmpty().firstOrNull {
        it.basePlanId == YearlySwitchOfferIds.BASE_PLAN_ID &&
            it.offerId == YearlySwitchOfferIds.OFFER_ID &&
            YearlySwitchOfferIds.TAG in it.offerTags &&
            it.offerToken.isNotBlank()
    } ?: return null
    val phases = offer.pricingPhases.pricingPhaseList
    if (phases.size != 2) return null
    val (intro, recurring) = phases
    if (intro.billingPeriod != "P1Y" || intro.billingCycleCount != 1 ||
        intro.recurrenceMode != ProductDetails.RecurrenceMode.FINITE_RECURRING) return null
    if (recurring.billingPeriod != "P1Y" ||
        recurring.recurrenceMode != ProductDetails.RecurrenceMode.INFINITE_RECURRING) return null
    if (intro.priceCurrencyCode != recurring.priceCurrencyCode) return null
    if (intro.priceAmountMicros <= 0 || intro.priceAmountMicros >= recurring.priceAmountMicros) return null
    return offer
}
