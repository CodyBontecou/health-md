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

/** Synthetic offers exercise the carousel without launching Billing or touching app/health state. */
class PaywallCarouselUiTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    private val offers = listOf(
        PurchaseOffer(PurchasePlan.WEEKLY.productId, "$0.99", PurchasePlan.WEEKLY, true),
        PurchaseOffer(PurchasePlan.YEARLY.productId, "$29.99", PurchasePlan.YEARLY, true),
        PurchaseOffer(PurchasePlan.LIFETIME.productId, "$19.99", PurchasePlan.LIFETIME),
    )

    private fun text(id: Int) = compose.activity.getString(id)
    private fun action(id: Int) = compose.onNode(hasText(text(id)) and hasClickAction())
    private fun plan(id: Int) = action(id).performScrollTo()
    private fun showPlans() = action(R.string.paywall_see_all_plans).performClick().also { compose.waitForIdle() }

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
        action(R.string.paywall_cta_trial).performClick()
        showPlans()
        plan(R.string.paywall_plan_weekly).performClick()
        compose.onAllNodesWithText("$0.99", substring = true).onFirst().assertExists()
        action(R.string.paywall_cta_trial).performClick()
        plan(R.string.paywall_plan_lifetime).performClick()
        action(R.string.paywall_cta_lifetime).performClick()
        assertEquals(listOf(PurchasePlan.YEARLY, PurchasePlan.WEEKLY, PurchasePlan.LIFETIME), purchased)
    }

    @Test
    fun ineligibleSubscriptionsNeverShowTheTrialSlideOrTrialAction() {
        val purchased = mutableListOf<PurchasePlan>()
        show(catalog = offers.map { it.copy(hasSevenDayTrial = false) }, onPurchase = { purchased += it })
        compose.onNodeWithContentDescription(compose.activity.getString(R.string.paywall_slide, 2, 2)).assertExists()
        compose.onNodeWithContentDescription(compose.activity.getString(R.string.paywall_slide, 3, 3)).assertDoesNotExist()
        action(R.string.paywall_cta_trial).assertDoesNotExist()
        action(R.string.paywall_cta_subscribe).performClick()
        assertEquals(listOf(PurchasePlan.YEARLY), purchased)
    }

    @Test
    fun missingProductsRetryAndRestoreWithoutLaunchingAPurchase() {
        var retries = 0
        var restores = 0
        show(catalog = emptyList(), onRetry = { retries++ }, onRestore = { restores++ })
        showPlans()
        action(R.string.paywall_retry).assertIsEnabled().performClick()
        action(R.string.paywall_restore).assertIsEnabled().performClick()
        action(R.string.paywall_cta_subscribe).assertIsNotEnabled()
        assertEquals(1, retries)
        assertEquals(1, restores)
    }

    @Test
    fun restoreFailureKeepsPlansAvailableAndShowsTheError() {
        show(error = BillingError.RESTORE_FAILED)
        compose.onNodeWithText(text(R.string.billing_error_restore_failed)).assertIsDisplayed()
        action(R.string.paywall_cta_trial).assertIsEnabled()
        action(R.string.paywall_restore).assertIsEnabled()
    }

    @Test
    fun purchaseInProgressDisablesRestoreAndPlanSelection() {
        show(purchasing = true)
        action(R.string.paywall_restore).assertIsNotEnabled()
        showPlans()
        plan(R.string.paywall_plan_weekly).assertIsNotEnabled()
    }

    @Test
    fun restoreInProgressDisablesThePurchaseAction() {
        show(restoring = true)
        action(R.string.paywall_cta_trial).assertIsNotEnabled()
        action(R.string.paywall_restore).assertDoesNotExist()
        compose.onNodeWithText(text(R.string.paywall_restoring)).assertIsDisplayed()
    }
}
