package com.healthmd.myselfclaim

import androidx.activity.ComponentActivity
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.healthmd.presentation.theme.HealthMdTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class MyselfClaimUiTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @org.junit.Before fun prepareNativeWindow() {
        compose.activityRule.scenario.onActivity {
            it.setShowWhenLocked(true)
            it.setTurnScreenOn(true)
        }
    }

    @Test fun disclosureDoesNotVerifyUntilTappedAndFailureCanBeRetriedOrCancelled() {
        var submissions = 0
        var cancellations = 0
        val state = mutableStateOf(MyselfClaimState())
        compose.setContent { HealthMdTheme { MyselfClaimContent(state.value,
            onVerify = { submissions++; state.value = MyselfClaimState(failure = MyselfClaimFailure.NO_PURCHASE) },
            onBack = { cancellations++ }) } }
        compose.onNodeWithTag("myself_claim_screen").assertIsDisplayed()
        assertEquals(0, submissions)
        compose.onNodeWithTag("myself_claim_verify").performScrollTo().performClick()
        compose.onNodeWithTag("myself_claim_error").performScrollTo().assertIsDisplayed()
        assertEquals(1, submissions)
        compose.onNodeWithTag("myself_claim_verify").performScrollTo().performClick()
        assertEquals(2, submissions)
        compose.onNodeWithTag("myself_claim_close").performScrollTo().performClick()
        assertEquals(1, cancellations)
    }

    @Test fun busyDisablesResubmissionAndHandoffStillRequiresAccountConfirmation() {
        val state = mutableStateOf(MyselfClaimState(busy = true))
        compose.setContent { HealthMdTheme { MyselfClaimContent(state.value, {}, {}) } }
        compose.onNodeWithTag("myself_claim_verify").performScrollTo().assertIsNotEnabled()
        compose.runOnIdle { state.value = MyselfClaimState(awaitingUser = true) }
        compose.onNodeWithTag("myself_claim_awaiting_user").performScrollTo().assertIsDisplayed()
        compose.onNodeWithTag("myself_claim_verify").performScrollTo().assertIsEnabled()
    }
}
