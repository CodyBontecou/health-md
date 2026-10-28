package com.healthmd.myselfclaim

import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import com.healthmd.BuildConfig
import com.healthmd.presentation.MainActivity
import org.junit.Rule
import org.junit.Test

class MyselfClaimNavigationTest {
    @get:Rule val compose = createEmptyComposeRule()

    @Test fun coldAndWarmExactDeepLinksRespectDistributionWithoutVerification() {
        fun link() = Intent(ApplicationProvider.getApplicationContext(), MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW).setData(Uri.parse(MyselfClaimLinks.URL))
        fun awaitDisclosure() {
            compose.waitUntil(timeoutMillis = 10_000) {
                compose.onAllNodesWithTag("myself_claim_screen")
                    .fetchSemanticsNodes(atLeastOneRootRequired = false).size == 1
            }
        }
        ActivityScenario.launch<MainActivity>(link()).use { scenario ->
            if (!BuildConfig.MYSELF_CLAIM_ENABLED || BuildConfig.FLAVOR != "play") {
                compose.waitForIdle()
                compose.onNodeWithTag("myself_claim_screen").assertDoesNotExist()
                scenario.onActivity { it.startActivity(link().addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)) }
                compose.waitForIdle()
                compose.onNodeWithTag("myself_claim_screen").assertDoesNotExist()
                return@use
            }
            awaitDisclosure()
            compose.onNodeWithTag("myself_claim_screen").assertIsDisplayed()
            compose.onNodeWithTag("myself_claim_verify").performScrollTo().assertIsEnabled()
            compose.onNodeWithTag("myself_claim_close").performScrollTo().performClick()
            compose.onNodeWithTag("myself_claim_screen").assertDoesNotExist()
            // A cancelled link must not be replayed by Activity recreation.
            scenario.recreate()
            compose.waitForIdle()
            compose.onNodeWithTag("myself_claim_screen").assertDoesNotExist()
            scenario.onActivity { it.startActivity(link().addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)) }
            awaitDisclosure()
            compose.onNodeWithTag("myself_claim_screen").assertIsDisplayed()
            compose.onNodeWithTag("myself_claim_verify").performScrollTo().assertIsEnabled()
        }
    }
}
