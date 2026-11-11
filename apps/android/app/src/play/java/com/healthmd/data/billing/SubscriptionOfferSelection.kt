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
