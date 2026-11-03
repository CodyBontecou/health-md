package com.healthmd.presentation.paywall

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.healthmd.R
import com.healthmd.domain.billing.BillingError
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchasePlan
import com.healthmd.presentation.theme.HealthMdTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

/** Synthetic offers exercise the UI without launching Billing or touching app/health state. */
class SignalPaywallTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val offers = listOf(
        PurchaseOffer(PurchasePlan.WEEKLY.productId, "$0.99", PurchasePlan.WEEKLY, true),
        PurchaseOffer(PurchasePlan.YEARLY.productId, "$29.99", PurchasePlan.YEARLY, true),
        PurchaseOffer(PurchasePlan.LIFETIME.productId, "$19.99", PurchasePlan.LIFETIME),
    )

    private fun text(id: Int) = compose.activity.getString(id)
    private fun action(id: Int) = compose.onNode(hasText(text(id)) and hasClickAction())
    private fun plansStep() = compose.onNode(
        hasText(text(R.string.paywall_signal_step_plans).uppercase(), substring = true) and hasClickAction(),
    )

    private fun show(
        catalog: List<PurchaseOffer> = offers,
        purchasing: Boolean = false,
        restoring: Boolean = false,
        error: BillingError? = null,
        onPurchase: (PurchasePlan) -> Unit = {},
        onRetry: () -> Unit = {},
        onRestore: () -> Unit = {},
    ) {
        compose.setContent {
            HealthMdTheme {
                PaywallScreen(
                    onPurchase = { kotlin.error("Use the selected plan callback") },
                    onPlanPurchase = onPurchase,
                    onRestore = onRestore,
                    onRetry = onRetry,
                    onDismiss = null,
                    offers = catalog,
                    subtitle = "",
                    isPurchasing = purchasing,
                    isRestoring = restoring,
                    purchaseError = error,
                )
            }
        }
    }

    @Test
    fun planSelectionUsesStorePricesAndPurchasesTheSelectedPlan() {
        val purchased = mutableListOf<PurchasePlan>()
        show(onPurchase = { purchased += it })
        action(R.string.paywall_signal_cta_trial).performClick()
        plansStep().performClick()
        action(R.string.paywall_signal_plan_weekly).performScrollTo().performClick()
        compose.onAllNodesWithText("$0.99", substring = true).onFirst().assertExists()
        action(R.string.paywall_signal_cta_trial).performClick()
        action(R.string.paywall_signal_plan_lifetime).performScrollTo().performClick()
        action(R.string.paywall_signal_cta_lifetime).performClick()
        assertEquals(listOf(PurchasePlan.YEARLY, PurchasePlan.WEEKLY, PurchasePlan.LIFETIME), purchased)
    }

    @Test
    fun ineligibleSubscriptionsNeverShowTheTrialStepOrTrialAction() {
        val purchased = mutableListOf<PurchasePlan>()
        show(catalog = offers.map { it.copy(hasSevenDayTrial = false) }, onPurchase = { purchased += it })
        compose.onNode(hasText(text(R.string.paywall_signal_step_trial).uppercase(), substring = true) and hasClickAction())
            .assertDoesNotExist()
        action(R.string.paywall_signal_cta_trial).assertDoesNotExist()
        action(R.string.paywall_signal_cta_subscribe).performClick()
        assertEquals(listOf(PurchasePlan.YEARLY), purchased)
    }

    @Test
    fun missingProductsRetryAndRestoreWithoutLaunchingAPurchase() {
        var retries = 0
        var restores = 0
        show(catalog = emptyList(), onRetry = { retries++ }, onRestore = { restores++ })
        action(R.string.paywall_retry).assertIsEnabled().performClick()
        action(R.string.paywall_restore).assertIsEnabled().performClick()
        assertEquals(1, retries)
        assertEquals(1, restores)
    }

    @Test
    fun restoreFailureKeepsPlansAvailableAndShowsTheError() {
        show(error = BillingError.RESTORE_FAILED)
        compose.onNodeWithText(text(R.string.billing_error_restore_failed)).assertIsDisplayed()
        action(R.string.paywall_signal_cta_trial).assertIsEnabled()
        action(R.string.paywall_restore).assertIsEnabled()
    }

    @Test
    fun purchaseInProgressDisablesRestoreAndPlanSelection() {
        show(purchasing = true)
        action(R.string.paywall_restore).assertIsNotEnabled()
        plansStep().performClick()
        action(R.string.paywall_signal_plan_weekly).assertIsNotEnabled()
    }

    @Test
    fun restoreInProgressDisablesThePurchaseAction() {
        show(restoring = true)
        action(R.string.paywall_signal_cta_trial).assertIsNotEnabled()
        action(R.string.paywall_restore).assertDoesNotExist()
        compose.onNodeWithText(text(R.string.paywall_restoring)).assertIsDisplayed()
    }
}
