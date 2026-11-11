package com.healthmd.presentation.settings

import androidx.annotation.StringRes
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.R
import com.healthmd.domain.billing.BillingError
import com.healthmd.domain.billing.PlaySubscriptionLinks
import com.healthmd.domain.billing.SubscriptionStatus
import com.healthmd.domain.billing.YearlySwitchEligibility
import com.healthmd.domain.billing.YearlySwitchOffer
import android.app.Activity
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchasePlan
import com.healthmd.domain.repository.PurchaseRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

/** Settings › Subscription: the owned plan, its Play management path, and restore. */
@HiltViewModel
class SubscriptionViewModel @Inject constructor(
    private val purchaseRepository: PurchaseRepository,
    private val entitlementRepository: EntitlementRepository,
    distributionPolicy: DistributionPolicy,
) : ViewModel() {
    val purchasesAvailable: Boolean = distributionPolicy.purchasesAvailable && purchaseRepository.isAvailable

    val status: StateFlow<SubscriptionStatus> =
        SubscriptionStatusPreview.status?.let { MutableStateFlow(it).asStateFlow() }
            ?: purchaseRepository.subscriptionStatus

    /** The Weekly -> Yearly card, only for an active renewing Weekly subscriber. */
    val switchOffer: StateFlow<YearlySwitchOffer?> =
        SubscriptionStatusPreview.switchOffer?.let { MutableStateFlow<YearlySwitchOffer?>(it).asStateFlow() }
            ?: combine(status, purchaseRepository.yearlySwitchOffer) { current, offer ->
                YearlySwitchEligibility.eligible(current, offer)
            }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), null)

    val isPurchasing: StateFlow<Boolean> = purchaseRepository.isPurchasing
    val isRestoring: StateFlow<Boolean> = purchaseRepository.isRestoring
    val purchaseError: StateFlow<BillingError?> = purchaseRepository.purchaseError

    init {
        purchaseRepository.clearError()
        refresh()
    }

    fun refresh() {
        if (!purchasesAvailable) return
        entitlementRepository.refresh()
        purchaseRepository.refresh()
    }

    fun restore() {
        if (!purchasesAvailable) return
        viewModelScope.launch { purchaseRepository.restorePurchase() }
    }

    fun switchToYearly(activity: Activity) {
        if (!purchasesAvailable || SubscriptionStatusPreview.status != null) return
        viewModelScope.launch { purchaseRepository.launchYearlySwitch(activity) }
    }

    fun clearError() = purchaseRepository.clearError()
}

/** The screen's primary action for a status. */
internal enum class SubscriptionAction {
    /** Opens "Before you go", whose Continue to cancel opens Play. */
    MANAGE_OR_CANCEL,

    /** Already canceled: Play directly, no retention step. */
    MANAGE_IN_PLAY,

    /** The existing paywall. */
    SEE_PLANS,
}

/** Everything the Subscription screen shows for one status; pure so it is unit-tested. */
internal data class SubscriptionUi(
    @StringRes val title: Int,
    @StringRes val status: Int,
    /** The brand-tinted card for owned access; neutral otherwise. */
    val owned: Boolean,
    @StringRes val planValue: Int?,
    /** Renewing: the next billing date row (the date, or "Shown in Google Play"). */
    val showsBillingDate: Boolean,
    val showsBilledBy: Boolean,
    val showsIncludes: Boolean,
    val action: SubscriptionAction?,
    @StringRes val actionNote: Int?,
    /** The subscription Play's deep link names; null opens Play's subscription list. */
    val managedPlan: PurchasePlan?,
    /** Subscription ended: the screen shows what still works and what is paused. */
    val ended: Boolean = false,
    /** Server-verified end of the paid period; null shows Google Play as the source instead. */
    val periodEndMillis: Long? = null,
    /** Canceled subscription without independent permanent access: date or Play fallback. */
    val showsAccessUntil: Boolean = false,
)

internal fun subscriptionUi(status: SubscriptionStatus): SubscriptionUi = when (status) {
    SubscriptionStatus.Unknown -> SubscriptionUi(
        title = R.string.m3_subscription_title,
        status = R.string.m3_subscription_status_checking,
        owned = false, planValue = null, showsBillingDate = false, showsBilledBy = false,
        // Play may never answer (billing unavailable, signed out): a subscriber must still be
        // able to reach Play's subscription list to cancel, so this is never a dead end.
        showsIncludes = false, action = SubscriptionAction.MANAGE_IN_PLAY, actionNote = null, managedPlan = null,
    )
    SubscriptionStatus.Free -> SubscriptionUi(
        title = R.string.m3_subscription_plan_free,
        status = R.string.m3_subscription_status_free,
        owned = false, planValue = null, showsBillingDate = false, showsBilledBy = false,
        showsIncludes = false, action = SubscriptionAction.SEE_PLANS, actionNote = null, managedPlan = null,
    )
    is SubscriptionStatus.Subscribed -> SubscriptionUi(
        title = planTitle(status.plan),
        status = when {
            status.isAutoRenewing -> R.string.m3_subscription_status_renews
            status.hasIncludedAccess -> R.string.m3_subscription_status_included
            else -> R.string.m3_subscription_status_cancelled
        },
        owned = true,
        planValue = if (status.plan == PurchasePlan.WEEKLY) R.string.m3_subscription_value_weekly else R.string.m3_subscription_value_yearly,
        showsBillingDate = status.isAutoRenewing,
        showsBilledBy = true,
        showsIncludes = true,
        // Included access survives cancellation; skip the sheet claiming features will stop.
        action = if (status.isAutoRenewing && !status.hasIncludedAccess) SubscriptionAction.MANAGE_OR_CANCEL else SubscriptionAction.MANAGE_IN_PLAY,
        actionNote = when {
            status.hasIncludedAccess -> null
            status.isAutoRenewing -> R.string.m3_subscription_cancel_note
            else -> R.string.m3_subscription_cancelled_note
        },
        managedPlan = status.plan,
        periodEndMillis = status.periodEndMillis,
        showsAccessUntil = !status.isAutoRenewing && !status.hasIncludedAccess,
    )
    // One-time purchase: nothing renews, so there is no cancel path at all.
    SubscriptionStatus.Lifetime -> SubscriptionUi(
        title = R.string.m3_subscription_plan_lifetime,
        status = R.string.m3_subscription_status_lifetime,
        owned = true, planValue = R.string.m3_subscription_value_lifetime, showsBillingDate = false,
        showsBilledBy = true, showsIncludes = true, action = null, actionNote = null, managedPlan = null,
    )
    SubscriptionStatus.IncludedAccess -> SubscriptionUi(
        title = R.string.m3_subscription_plan_full_access,
        status = R.string.m3_subscription_status_included,
        owned = true, planValue = null, showsBillingDate = false, showsBilledBy = false,
        showsIncludes = true, action = null, actionNote = null, managedPlan = null,
    )
    is SubscriptionStatus.Ended -> SubscriptionUi(
        title = R.string.m3_subscription_ended_title,
        status = R.string.m3_subscription_ended_subtitle,
        owned = false, planValue = null, showsBillingDate = false, showsBilledBy = false,
        showsIncludes = false, action = SubscriptionAction.SEE_PLANS, actionNote = null,
        managedPlan = status.previousPlan, ended = true,
    )
}

@StringRes
internal fun planTitle(plan: PurchasePlan): Int = when (plan) {
    PurchasePlan.WEEKLY -> R.string.m3_subscription_plan_weekly
    PurchasePlan.YEARLY -> R.string.m3_subscription_plan_yearly
    PurchasePlan.LIFETIME -> R.string.m3_subscription_plan_lifetime
}

/** A verified date in the reader's locale and time zone, e.g. "December 1, 2026". */
internal fun formatPeriodEnd(millis: Long, locale: java.util.Locale, zone: java.time.ZoneId = java.time.ZoneId.systemDefault()): String =
    java.time.format.DateTimeFormatter.ofLocalizedDate(java.time.format.FormatStyle.LONG)
        .withLocale(locale)
        .format(java.time.Instant.ofEpochMilli(millis).atZone(zone))

/** Play's page for the managed subscription, or its subscription list. */
internal fun subscriptionManageUrl(ui: SubscriptionUi, packageName: String): String =
    PlaySubscriptionLinks.manage(ui.managedPlan, packageName)
