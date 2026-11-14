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
        /** Permanent access remains independent of this owned subscription. */
        val hasIncludedAccess: Boolean = false,
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
    /** Purchase callbacks are deltas; only a full snapshot may displace known Lifetime. */
    fun shouldApplyPurchaseUpdate(current: SubscriptionStatus, active: ActivePurchase?, fullSnapshot: Boolean): Boolean =
        fullSnapshot || (active != null &&
            (current != SubscriptionStatus.Lifetime || active.plan == PurchasePlan.LIFETIME))

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
        active != null -> SubscriptionStatus.Subscribed(active.plan, active.isAutoRenewing, hasIncludedAccess = hasIncludedAccess)
        hasIncludedAccess -> SubscriptionStatus.IncludedAccess
        rememberedPlan != null && rememberedPlan != PurchasePlan.LIFETIME ->
            SubscriptionStatus.Ended(rememberedPlan)
        else -> SubscriptionStatus.Free
    }

    /**
     * Picks the plan to present when several completed purchases are owned. A subscription that
     * still renews comes first even beside Lifetime: it keeps billing, so its Manage path must stay
     * reachable (the caller marks it as having included access). Then Lifetime, which needs no
     * management, then a canceled subscription. Yearly ranks before Weekly within each group.
     */
    fun primary(owned: List<ActivePurchase>): ActivePurchase? =
        owned.minByOrNull { rank(it) }

    private fun rank(purchase: ActivePurchase): Int = when {
        purchase.plan == PurchasePlan.LIFETIME -> 2
        purchase.isAutoRenewing -> if (purchase.plan == PurchasePlan.YEARLY) 0 else 1
        else -> if (purchase.plan == PurchasePlan.YEARLY) 3 else 4
    }
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

    /**
     * [status] with the admitted server date. When the server, asked for this token and local
     * renewal state, reports the plan no longer renews, that wins over the local Play cache, so a
     * plan canceled elsewhere never shows a "Next billing date" or the retention sheet. Only ever
     * downgrades: a stale server "renewing" never overrides a fresh local cancel.
     */
    fun apply(status: SubscriptionStatus.Subscribed, verified: VerifiedPlaySubscription?, nowMillis: Long): SubscriptionStatus.Subscribed {
        val end = periodEnd(status, verified, nowMillis) ?: return status.copy(periodEndMillis = null)
        val canceledOnServer = verified != null && (!verified.autoRenewing || verified.state == "canceled")
        return status.copy(
            periodEndMillis = end,
            isAutoRenewing = status.isAutoRenewing && !canceledOnServer,
        )
    }
}

/** The in-app Weekly -> Yearly switch, priced only from Play's ProductDetails. No token is held here. */
data class YearlySwitchOffer(
    /** First-year price of the offer phase. */
    val introductoryFormattedPrice: String,
    /** Yearly base price that applies after the first year. */
    val recurringFormattedPrice: String,
)

/**
 * Who may see the switch offer: an active, renewing Weekly subscriber without permanent access.
 * Someone who also owns Lifetime or grandfathered access gains nothing from a paid upgrade.
 */
object YearlySwitchEligibility {
    fun eligible(status: SubscriptionStatus, offer: YearlySwitchOffer?): YearlySwitchOffer? = offer?.takeIf {
        status is SubscriptionStatus.Subscribed && status.plan == PurchasePlan.WEEKLY && status.isAutoRenewing &&
            !status.hasIncludedAccess
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
