package com.healthmd.sharedsetup

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.core.content.IntentCompat
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import com.healthmd.R
import com.healthmd.presentation.MainActivity
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@LargeTest
@RunWith(AndroidJUnit4::class)
class SharedSetupActivityLifecycleTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    @Test
    fun externalApplyAndUndoSurviveRecreationWithoutIntentReplay() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val entryPoint = EntryPointAccessors.fromApplication(
            context,
            SharedSetupInstrumentationEntryPoint::class.java,
        )
        val store = entryPoint.sharedSetupDocumentStore()
        val share = store.shareIntent(runBlocking { entryPoint.sharedSetupService().exportBytes() })
        val uri = IntentCompat.getParcelableExtra(share.intent, Intent.EXTRA_STREAM, Uri::class.java)
        assertNotNull(uri)

        val scenario = ActivityScenario.launch<MainActivity>(
            Intent(Intent.ACTION_VIEW, requireNotNull(uri), context, MainActivity::class.java)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        try {
            val review = context.getString(R.string.shared_setup_review)
            val apply = context.getString(R.string.shared_setup_apply)
            val applied = context.getString(R.string.shared_setup_applied)
            val undo = context.getString(R.string.shared_setup_undo)
            val use = context.getString(R.string.shared_setup_use)

            waitForText(review)
            compose.onNodeWithText(apply).performScrollTo().performClick()
            waitForText(applied)

            scenario.recreate()
            waitForText(applied)
            compose.onAllNodesWithText(review).assertCountEquals(0)

            compose.onNodeWithText(undo).performScrollTo().performClick()
            waitForText(use)

            scenario.recreate()
            waitForText(use)
            compose.onAllNodesWithText(review).assertCountEquals(0)
            compose.onAllNodesWithText(applied).assertCountEquals(0)
        } finally {
            scenario.close()
            runBlocking { store.discardShareArtifact(share.artifactID) }
        }
    }

    private fun waitForText(text: String) {
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }
}
