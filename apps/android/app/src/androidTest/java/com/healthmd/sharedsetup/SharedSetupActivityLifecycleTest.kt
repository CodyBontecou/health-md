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
import com.healthmd.BuildConfig
import com.healthmd.R
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.MainActivity
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import java.time.ZoneId

@LargeTest
@RunWith(AndroidJUnit4::class)
class SharedSetupActivityLifecycleTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    /** Production v2 share bytes from the real writer owners, seeding a profile if needed. */
    private fun productionV2ShareBytes(context: Context, entryPoint: SharedSetupInstrumentationEntryPoint): ByteArray {
        val profileRepository = entryPoint.exportProfileRepository()
        if (runBlocking { profileRepository.getProfiles() }.isEmpty()) {
            val snapshot = AndroidExportSettingsSnapshot.capture(
                ExportSettings.newInstallDefaults(),
                pin = null,
                zone = ZoneId.systemDefault(),
            )
            runBlocking {
                profileRepository.migrateDefaultIfNeeded(
                    settingsSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot),
                    target = ExportTarget.DEVICE_FOLDER,
                )
            }
        }
        val production = entryPoint.sharedSetupV2ProductionTransaction()
        val source = RepositorySharedSetupV2ExportSource(
            profileRepository = profileRepository,
            scheduledProfileEntryStore = entryPoint.scheduledProfileEntryStore(),
            appVersion = BuildConfig.VERSION_NAME,
            preservedAppleExtensions = { production.preservedAppleExtensionsByProfileId() },
        )
        return runBlocking { entryPoint.sharedSetupService().exportV2Bytes(source) }
    }

    @Test
    fun externalApplyAndUndoSurviveRecreationWithoutIntentReplay() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val entryPoint = EntryPointAccessors.fromApplication(
            context,
            SharedSetupInstrumentationEntryPoint::class.java,
        )
        val store = entryPoint.sharedSetupDocumentStore()
        val share = store.shareIntent(productionV2ShareBytes(context, entryPoint))
        val uri = IntentCompat.getParcelableExtra(share.intent, Intent.EXTRA_STREAM, Uri::class.java)
        assertNotNull(uri)
        val profileName = runBlocking { entryPoint.exportProfileRepository().getProfiles().first().name }

        val scenario = ActivityScenario.launch<MainActivity>(
            Intent(Intent.ACTION_VIEW, requireNotNull(uri), context, MainActivity::class.java)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
        )
        try {
            val review = context.getString(R.string.shared_setup_v2_review)
            val apply = context.getString(R.string.shared_setup_apply)
            val applied = context.getString(R.string.shared_setup_v2_applied)
            val undo = context.getString(R.string.shared_setup_undo)
            val undone = context.getString(R.string.shared_setup_v2_undone)
            val done = context.getString(R.string.shared_setup_done)
            val use = context.getString(R.string.shared_setup_use)

            waitForText(review)
            // Select the first profile row, then apply in the default Add mode.
            compose.onNodeWithText(profileName).performScrollTo().performClick()
            compose.onNodeWithText(apply).performScrollTo().performClick()
            waitForText(applied)

            scenario.recreate()
            waitForText(applied)
            compose.onAllNodesWithText(review).assertCountEquals(0)

            compose.onNodeWithText(undo).performScrollTo().performClick()
            waitForText(undone)
            compose.onNodeWithText(done).performScrollTo().performClick()
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

        val share = store.shareIntent(productionV2ShareBytes(context, entryPoint))
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
                assertNotNull(activity.distributionRuntime)
                activity.startActivity(
                    Intent(Intent.ACTION_VIEW, uri, context, MainActivity::class.java)
                        .addFlags(
                            Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                Intent.FLAG_ACTIVITY_SINGLE_TOP,
                        ),
                )
            }

            val review = context.getString(R.string.shared_setup_v2_review)
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
