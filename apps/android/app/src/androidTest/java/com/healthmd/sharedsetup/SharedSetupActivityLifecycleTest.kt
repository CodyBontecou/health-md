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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
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

    @Test
    fun warmActionViewRoutesExistingActivityDirectlyToReview() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val entryPoint = EntryPointAccessors.fromApplication(
            context,
            SharedSetupInstrumentationEntryPoint::class.java,
        )
        val settingsRepository = entryPoint.settingsRepository()
        val coordinator = entryPoint.sharedSetupCoordinator()
        val store = entryPoint.sharedSetupDocumentStore()
        val originalOnboarding = runBlocking { settingsRepository.hasCompletedOnboarding.first() }
        runBlocking { settingsRepository.setOnboardingCompleted(true) }
        coordinator.finishExternalImport()

        val share = store.shareIntent(runBlocking { entryPoint.sharedSetupService().exportBytes() })
        val uri = requireNotNull(
            IntentCompat.getParcelableExtra(share.intent, Intent.EXTRA_STREAM, Uri::class.java),
        )
        val scenario = ActivityScenario.launch<MainActivity>(
            Intent(context, MainActivity::class.java),
        )
        var activityIdentity = 0
        var originalActivityIntent: Intent? = null
        try {
            scenario.onActivity { activity ->
                activityIdentity = System.identityHashCode(activity)
                originalActivityIntent = Intent(activity.intent)
                assertNotNull(activity.wearPhoneSyncScheduler)
                activity.startActivity(
                    Intent(Intent.ACTION_VIEW, uri, context, MainActivity::class.java)
                        .addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP,
                        ),
                )
            }

            val review = context.getString(R.string.shared_setup_review)
            waitForText(review)
            compose.onAllNodesWithText(context.getString(R.string.shared_setup_use))
                .assertCountEquals(0)
            scenario.onActivity { activity ->
                assertEquals(activityIdentity, System.identityHashCode(activity))
                // ActivityScenario identifies the launched instance by its current Intent. Restore
                // the original after verifying onNewIntent so close() can observe DESTROYED.
                activity.intent = requireNotNull(originalActivityIntent)
            }
        } finally {
            originalActivityIntent?.let { original ->
                runCatching { scenario.onActivity { activity -> activity.intent = original } }
            }
            coordinator.finishExternalImport()
            scenario.close()
            runBlocking {
                store.discardShareArtifact(share.artifactID)
                settingsRepository.setOnboardingCompleted(originalOnboarding)
            }
        }
    }

    private fun waitForText(text: String) {
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }
}
