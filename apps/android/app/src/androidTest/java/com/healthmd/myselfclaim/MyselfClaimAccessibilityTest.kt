package com.healthmd.myselfclaim

import androidx.compose.ui.test.*
import com.healthmd.R
import com.healthmd.presentation.accessibility.AccessibilityDisplayCase
import com.healthmd.presentation.accessibility.AccessibilityTestHarness
import com.healthmd.presentation.accessibility.accessibilityDisplays
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class MyselfClaimAccessibilityTest(display: AccessibilityDisplayCase) : AccessibilityTestHarness(display, wakeWithUiAutomation = false) {
    companion object {
        @JvmStatic @Parameterized.Parameters(name = "{0}")
        fun displays() = accessibilityDisplays()
    }

    @Test fun disclosureAndActionsRemainReadableAndReachable() {
        setContent { MyselfClaimContent(MyselfClaimState(failure = MyselfClaimFailure.NO_PURCHASE), {}, {}) }
        compose.onNodeWithTag("myself_claim_close").performScrollTo()
            .assertFullyVisible().assertMinimumTouchTarget()
        for (id in listOf(R.string.myself_claim_intro, R.string.myself_claim_disclosure,
            R.string.myself_claim_account, R.string.myself_claim_no_purchase)) {
            val node = compose.onNodeWithText(text(id)).performScrollTo()
            assertTextFits(node)
        }
        val verify = compose.onNodeWithTag("myself_claim_verify").performScrollTo()
            .assertFullyVisible().assertMinimumTouchTarget()
        assertTextFits(compose.onNodeWithText(text(R.string.myself_claim_verify)))
        capture("myself-claim", verify)
    }
}
