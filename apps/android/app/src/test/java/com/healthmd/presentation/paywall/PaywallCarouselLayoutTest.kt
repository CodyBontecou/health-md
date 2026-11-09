package com.healthmd.presentation.paywall

import android.app.Application
import android.content.Context
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertDoesNotExist
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.assertIsSelected
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import com.healthmd.R
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchasePlan
import com.healthmd.presentation.theme.HealthMdTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Host layout/semantics checks; these do not establish device or visual readiness. */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w800dp-h1000dp", application = Application::class)
class PaywallCarouselLayoutTest {
    @get:Rule val compose = createComposeRule()
    private val context = ApplicationProvider.getApplicationContext<Context>()
    private val offers = listOf(
        PurchaseOffer("yearly", "$29.99", PurchasePlan.YEARLY, hasSevenDayTrial = true),
        PurchaseOffer("lifetime", "$49.99", PurchasePlan.LIFETIME),
    )

    private var catalog by mutableStateOf(offers)
    private var purchasing by mutableStateOf(false)
    private var restoring by mutableStateOf(false)

    private fun text(id: Int) = context.getString(id)
    private fun action(id: Int) = compose.onNode(hasText(text(id)) and hasClickAction())

    private fun readingPlan(id: Int) = action(id).also { target ->
        // The nearest scroll ancestor is the horizontal pager. Scroll the outer vertical
        // viewport explicitly before injecting a pointer click into its plan card.
        val viewport = compose.onNode(
            hasScrollAction() and SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange),
        )
        val offset = target.fetchSemanticsNode().positionInRoot.y - viewport.fetchSemanticsNode().boundsInRoot.top
        viewport.performSemanticsAction(SemanticsActions.ScrollBy) { it(0f, offset) }
    }

    private fun show(
        width: Int,
        height: Int,
        scale: Float,
        darkTheme: Boolean = false,
        onRestore: () -> Unit = {},
        onRetry: () -> Unit = {},
        onPurchase: (PurchasePlan) -> Unit = {},
    ) {
        compose.setContent {
            CompositionLocalProvider(LocalDensity provides Density(1f, scale)) {
                HealthMdTheme(darkTheme = darkTheme) {
                    Box(Modifier.requiredSize(width.dp, height.dp)) {
                        PaywallCarousel(
                            offers = catalog,
                            onPlanPurchase = onPurchase,
                            onRestore = onRestore,
                            onRetry = onRetry,
                            onDismiss = {},
                            isPurchasing = purchasing,
                            isRestoring = restoring,
                            errorMessage = text(R.string.billing_error_restore_failed),
                            debugControls = null,
                        )
                    }
                }
            }
        }
    }

    private fun assertReadingActionsReachable(width: Int, height: Int, scale: Float, darkTheme: Boolean = false) {
        val purchased = mutableListOf<PurchasePlan>()
        show(width, height, scale, darkTheme, onPurchase = { purchased += it })
        compose.onNodeWithText(text(R.string.paywall_benefit_title)).performScrollTo().assertIsDisplayed()
        action(R.string.paywall_cta_trial).performScrollTo().assertIsDisplayed().performClick()
        action(R.string.paywall_restore).performScrollTo().assertIsDisplayed()
        action(R.string.paywall_terms).performScrollTo().assertIsDisplayed()
        action(R.string.paywall_privacy).performScrollTo().assertIsDisplayed()
        action(R.string.paywall_see_all_plans).performScrollTo().performClick()
        compose.waitForIdle()
        compose.onNodeWithText(text(R.string.paywall_plans_title)).assertIsDisplayed()
        readingPlan(R.string.paywall_plan_lifetime).assertIsDisplayed().performClick()
        compose.waitForIdle()
        action(R.string.paywall_plan_lifetime).assertIsSelected()
        action(R.string.paywall_cta_lifetime).performScrollTo().assertIsDisplayed().performClick()
        assertEquals(listOf(PurchasePlan.YEARLY, PurchasePlan.LIFETIME), purchased)
    }

    @Test fun largeTextKeepsSlidesPurchaseRestoreAndLegalActionsReachable() {
        assertReadingActionsReachable(411, 720, 2f)
    }

    @Test fun darkLargeTextKeepsSlidesPurchaseRestoreAndLegalActionsReachable() {
        assertReadingActionsReachable(411, 720, 2f, darkTheme = true)
    }

    @Test fun shortLandscapeKeepsSlidesPurchaseRestoreAndLegalActionsReachable() {
        assertReadingActionsReachable(640, 280, 1f)
    }

    @Test fun narrowViewportKeepsSlidesPurchaseRestoreAndLegalActionsReachable() {
        assertReadingActionsReachable(320, 640, 1f)
    }

    @Test fun ordinaryLayoutKeepsPurchaseAndLegalActionsVisibleWithoutScrolling() {
        show(411, 720, 1f)
        action(R.string.paywall_cta_trial).assertIsDisplayed()
        action(R.string.paywall_terms).assertIsDisplayed()
        action(R.string.paywall_privacy).assertIsDisplayed()
    }

    @Test fun purchaseBusyKeepsItsLabelAndDisablesPurchaseRestoreDismissAndPlanChanges() {
        purchasing = true
        show(320, 640, 1f)
        action(R.string.paywall_cta_trial).performScrollTo().assertIsNotEnabled()
        action(R.string.paywall_restore).assertIsNotEnabled()
        compose.onNodeWithContentDescription(text(R.string.close)).assertIsNotEnabled()
        action(R.string.paywall_see_all_plans).performScrollTo().performClick()
        compose.waitForIdle()
        readingPlan(R.string.paywall_plan_lifetime).assertIsNotEnabled()
        compose.runOnIdle { purchasing = false }
        action(R.string.paywall_cta_trial).performScrollTo().assertIsEnabled()
        action(R.string.paywall_restore).assertIsEnabled()
        compose.onNodeWithContentDescription(text(R.string.close)).assertIsEnabled()
    }

    @Test fun restoringDisablesPurchaseAndRestoreThenAllowsAnotherRestore() {
        var restores = 0
        restoring = true
        show(320, 640, 1f, onRestore = { restores++ })
        action(R.string.paywall_cta_trial).performScrollTo().assertIsNotEnabled()
        action(R.string.paywall_restoring).performScrollTo().assertIsNotEnabled()
        compose.onNodeWithContentDescription(text(R.string.close)).assertIsNotEnabled()
        compose.runOnIdle { restoring = false }
        action(R.string.paywall_restore).performScrollTo().assertIsEnabled().performClick()
        action(R.string.paywall_cta_trial).assertIsEnabled()
        assertEquals(1, restores)
    }

    @Test fun unavailableOffersAllowRestoreAndRetryThenUseTheRefreshedPlan() {
        var restores = 0
        var retries = 0
        val purchases = mutableListOf<PurchasePlan>()
        catalog = emptyList()
        show(320, 640, 1f, onRestore = { restores++ }, onRetry = { retries++ }, onPurchase = { purchases += it })
        action(R.string.paywall_cta_subscribe).performScrollTo().assertIsNotEnabled()
        action(R.string.paywall_restore).performScrollTo().performClick()
        action(R.string.paywall_see_all_plans).performScrollTo().performClick()
        compose.waitForIdle()
        readingPlan(R.string.paywall_retry).assertIsEnabled().performClick()
        compose.runOnIdle { catalog = offers.filter { it.plan == PurchasePlan.LIFETIME } }
        action(R.string.paywall_cta_trial).assertDoesNotExist()
        action(R.string.paywall_cta_lifetime).performScrollTo().assertIsEnabled().performClick()
        assertEquals(1, restores)
        assertEquals(1, retries)
        assertEquals(listOf(PurchasePlan.LIFETIME), purchases)
    }

    @Test fun addingTrialEligibilityKeepsThePlansSlideSelected() {
        catalog = offers.map { it.copy(hasSevenDayTrial = false) }
        show(320, 640, 1f)
        action(R.string.paywall_see_all_plans).performScrollTo().performClick()
        compose.waitForIdle()
        compose.runOnIdle { catalog = offers }
        compose.onNodeWithText(text(R.string.paywall_plans_title)).assertIsDisplayed()
        action(R.string.paywall_see_all_plans).assertDoesNotExist()
    }

    @Test fun trialNavigationResetsTheReadingViewportWithoutChangingTheSelectedPlan() {
        val purchases = mutableListOf<PurchasePlan>()
        show(320, 640, 1f, onPurchase = { purchases += it })
        action(R.string.paywall_see_all_plans).performScrollTo().performClick()
        compose.waitForIdle()
        readingPlan(R.string.paywall_plan_lifetime).performClick()
        val trialTab = compose.onNodeWithContentDescription(context.getString(R.string.paywall_slide, 2, 3))
        trialTab.performScrollTo().performClick()
        compose.waitForIdle()
        compose.onNodeWithText(text(R.string.paywall_trial_title)).assertIsDisplayed()
        action(R.string.paywall_cta_lifetime).performScrollTo().performClick()
        assertEquals(listOf(PurchasePlan.LIFETIME), purchases)
    }

}
