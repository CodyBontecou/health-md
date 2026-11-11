package com.healthmd.domain.billing

import com.healthmd.domain.repository.PurchasePlan

/** The plan a fresh store snapshot reports as owned. Lifetime never auto-renews. */
data class ActivePurchase(
    val plan: PurchasePlan,
    val isAutoRenewing: Boolean,
)

/**
 * What Settings › Subscription shows. Derived from a full store snapshot plus the one
 * subscription plan remembered from earlier snapshots, so a lapse can be told apart from a
 * user who never subscribed. The Play client exposes no renewal or end date; one is shown only
 * after myself.md has read it from Google Play for this purchase token (see [SubscriptionDates]).
 */
sealed interface SubscriptionStatus {
    /** The store has not answered yet (or could not be reached before any answer). */
    data object Unknown : SubscriptionStatus

    /** No paid access now and no subscription remembered. */
    data object Free : SubscriptionStatus

    /**
     * A weekly or yearly subscription is owned. [isAutoRenewing] is false after cancelling.
     * [periodEndMillis] is the server-verified end of the paid period (the next billing date
     * while renewing, the last day of access once canceled); null until verified.
     */
    data class Subscribed(
        val plan: PurchasePlan,
        val isAutoRenewing: Boolean,
        val periodEndMillis: Long? = null,
    ) : SubscriptionStatus

    /** The one-time Lifetime product is owned: nothing renews and nothing can be cancelled. */
    data object Lifetime : SubscriptionStatus

    /** Permanent access that is not a store purchase (grandfathered early installs). */
    data object IncludedAccess : SubscriptionStatus

    /** A subscription was owned before and is not owned now. */
    data class Ended(val previousPlan: PurchasePlan) : SubscriptionStatus
}

/** Pure lapse detection, kept free of store SDK and storage types so it is unit-testable. */
object SubscriptionLapse {
    /**
     * The subscription plan to remember after a full snapshot. An owned subscription replaces
     * the memory; Lifetime clears it (there is nothing left to lapse); no ownership keeps it,
     * which is exactly the "had one before, has none now" signal.
     */
    fun rememberedPlan(previous: PurchasePlan?, active: ActivePurchase?): PurchasePlan? = when {
        active == null -> previous?.takeUnless { it == PurchasePlan.LIFETIME }
        active.plan == PurchasePlan.LIFETIME -> null
        else -> active.plan
    }

    /**
     * Status after a full snapshot. Store ownership wins over grandfathered access so a
     * subscriber still sees their plan and its cancel path; grandfathered access wins over a
     * remembered lapse because nothing actually stopped.
     */
    fun status(
        active: ActivePurchase?,
        rememberedPlan: PurchasePlan?,
        hasIncludedAccess: Boolean,
    ): SubscriptionStatus = when {
        active?.plan == PurchasePlan.LIFETIME -> SubscriptionStatus.Lifetime
        active != null -> SubscriptionStatus.Subscribed(active.plan, active.isAutoRenewing)
        hasIncludedAccess -> SubscriptionStatus.IncludedAccess
        rememberedPlan != null && rememberedPlan != PurchasePlan.LIFETIME ->
            SubscriptionStatus.Ended(rememberedPlan)
        else -> SubscriptionStatus.Free
    }

    /**
     * Picks the plan to present when several completed purchases are owned. Lifetime first
     * (it needs no management), then the longer subscription, then weekly.
     */
    fun primary(owned: List<ActivePurchase>): ActivePurchase? =
        owned.minByOrNull { PRIORITY.indexOf(it.plan) }

    private val PRIORITY = listOf(PurchasePlan.LIFETIME, PurchasePlan.YEARLY, PurchasePlan.WEEKLY)
}

/** Google Play's answer for one purchase token, as relayed by myself.md. No token is held. */
data class VerifiedPlaySubscription(
    val productId: String,
    /** active, grace, on_hold, paused, canceled, expired or pending. */
    val state: String,
    val expiresAtMillis: Long?,
    val autoRenewing: Boolean,
)

/** Reads one subscription's period from the server. Null on any failure; never throws. */
fun interface PlaySubscriptionVerifier {
    suspend fun verify(purchaseToken: String): VerifiedPlaySubscription?
}

/** Pure date admission, so a stale or mismatched answer is never shown as a date. */
object SubscriptionDates {
    private val DATED_STATES = setOf("active", "grace", "canceled")

    /**
     * The period end to show for [status], or null. The server answer must name the same
     * product, be in a state that still has paid access, and end in the future.
     */
    fun periodEnd(status: SubscriptionStatus.Subscribed, verified: VerifiedPlaySubscription?, nowMillis: Long): Long? {
        verified ?: return null
        val expires = verified.expiresAtMillis ?: return null
        if (verified.productId != status.plan.productId || verified.state !in DATED_STATES) return null
        return expires.takeIf { it > nowMillis }
    }
}

/** The in-app Weekly -> Yearly switch, priced only from Play's ProductDetails. No token is held here. */
data class YearlySwitchOffer(
    /** First-year price of the offer phase. */
    val introductoryFormattedPrice: String,
    /** Yearly base price that applies after the first year. */
    val recurringFormattedPrice: String,
)

/** Who may see the switch offer: an active, renewing Weekly subscriber only. */
object YearlySwitchEligibility {
    fun eligible(status: SubscriptionStatus, offer: YearlySwitchOffer?): YearlySwitchOffer? = offer?.takeIf {
        status is SubscriptionStatus.Subscribed && status.plan == PurchasePlan.WEEKLY && status.isAutoRenewing
    }
}

/** Google Play's subscription-center links. */
object PlaySubscriptionLinks {
    const val SUBSCRIPTION_CENTER = "https://play.google.com/store/account/subscriptions"

    /**
     * Opens Play's page for one subscription so Cancel is one tap away. Lifetime and an
     * unknown plan fall back to the subscription list; Play documents `sku` and `package`
     * only as a pair.
     */
    fun manage(plan: PurchasePlan?, packageName: String): String {
        if (plan == null || plan == PurchasePlan.LIFETIME || packageName.isBlank()) return SUBSCRIPTION_CENTER
        return "$SUBSCRIPTION_CENTER?sku=${encode(plan.productId)}&package=${encode(packageName)}"
    }

    /** The managed subscription for [status] (owned or just ended), else the subscription list. */
    fun forStatus(status: SubscriptionStatus, packageName: String): String = manage(
        when (status) {
            is SubscriptionStatus.Subscribed -> status.plan
            is SubscriptionStatus.Ended -> status.previousPlan
            else -> null
        },
        packageName,
    )

    private fun encode(value: String): String = java.net.URLEncoder.encode(value, Charsets.UTF_8.name())
}
