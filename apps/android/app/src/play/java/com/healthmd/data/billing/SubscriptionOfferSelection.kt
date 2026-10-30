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
            (phases.size == 1 || (phases.size == 2 && phases.first().priceAmountMicros == 0L &&
                phases.first().billingPeriod == "P7D" && phases.first().billingCycleCount == 1))
    }.sortedByDescending { it.pricingPhases.pricingPhaseList.size }.firstOrNull()
}
