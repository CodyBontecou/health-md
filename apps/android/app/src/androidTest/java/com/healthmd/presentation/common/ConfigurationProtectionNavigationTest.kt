package com.healthmd.presentation.common

import android.content.Context
import android.content.Intent
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onFirst
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.export.ExportProfilesTestTags
import com.healthmd.presentation.navigation.SubRoutes
import com.healthmd.sharedsetup.SharedSetupInstrumentationEntryPoint
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Real NavController/dialog-window coverage for the configuration-protection shortcut. */
@LargeTest
@RunWith(AndroidJUnit4::class)
class ConfigurationProtectionNavigationTest {
    @get:Rule
    val compose = createEmptyComposeRule()

    @Test
    fun protectedProfileChangeOpensProtectionSettingWithoutRestoringNestedRoute() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val repository = EntryPointAccessors.fromApplication(
            context,
            SharedSetupInstrumentationEntryPoint::class.java,
        ).settingsRepository()
        val originalOnboarding = runBlocking { repository.hasCompletedOnboarding.first() }
        val originalProtection = runBlocking { repository.preventAccidentalChanges.first() }
        runBlocking {
            repository.setOnboardingCompleted(true)
            repository.setPreventAccidentalChanges(true)
        }

        val scenario = ActivityScenario.launch<MainActivity>(
            Intent(context, MainActivity::class.java)
                .putExtra(MainActivity.EXTRA_START_ROUTE, SubRoutes.EXPORT_PROFILES),
        )
        try {
            compose.waitUntil(timeoutMillis = 15_000) {
                compose.onAllNodesWithText("New").fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithText("New").performClick()

            compose.onNodeWithTag(ConfigurationProtectionTestTags.TOAST)
                .assertIsDisplayed()
            compose.onNodeWithTag(ConfigurationProtectionTestTags.TOAST).performClick()

            compose.waitUntil(timeoutMillis = 10_000) {
                compose.onAllNodesWithTag(ConfigurationProtectionTestTags.SECTION)
                    .fetchSemanticsNodes().isNotEmpty()
            }
            compose.onNodeWithTag(ConfigurationProtectionTestTags.SECTION)
                .assertIsDisplayed()
        } finally {
            scenario.close()
            runBlocking {
                repository.setPreventAccidentalChanges(originalProtection)
                repository.setOnboardingCompleted(originalOnboarding)
            }
        }
    }

    @Test
    fun protectedDetailActionDismissesDialogBeforeShowingActionableNotice() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val entryPoint = EntryPointAccessors.fromApplication(
            context,
            SharedSetupInstrumentationEntryPoint::class.java,
        )
        val repository = entryPoint.settingsRepository()
        val profileRepository = entryPoint.exportProfileRepository()
        val profileCoordinator = entryPoint.exportProfileCoordinator()
        val originalOnboarding = runBlocking { repository.hasCompletedOnboarding.first() }
        val originalProtection = runBlocking { repository.preventAccidentalChanges.first() }
        profileCoordinator.ensureStarted()
        runBlocking {
            kotlinx.coroutines.withTimeout(10_000) {
                profileRepository.profiles.first { it.isNotEmpty() }
            }
            repository.setOnboardingCompleted(true)
            repository.setPreventAccidentalChanges(true)
        }

        val scenario = ActivityScenario.launch<MainActivity>(
            Intent(context, MainActivity::class.java)
                .putExtra(MainActivity.EXTRA_START_ROUTE, SubRoutes.EXPORT_PROFILES),
        )
        try {
            compose.waitUntil(timeoutMillis = 15_000) {
                compose.onAllNodesWithTag(ExportProfilesTestTags.ROW)
                    .fetchSemanticsNodes().isNotEmpty()
            }
            compose.onAllNodesWithTag(ExportProfilesTestTags.ROW).onFirst().performClick()
            compose.onNodeWithText("Edit").performClick()

            compose.onNodeWithTag(ConfigurationProtectionTestTags.TOAST)
                .assertIsDisplayed()
            compose.onAllNodesWithText("Edit").assertCountEquals(0)
            compose.onNodeWithTag(ConfigurationProtectionTestTags.TOAST).performClick()
            compose.waitUntil(timeoutMillis = 10_000) {
                compose.onAllNodesWithTag(ConfigurationProtectionTestTags.SECTION)
                    .fetchSemanticsNodes().isNotEmpty()
            }
        } finally {
            scenario.close()
            runBlocking {
                repository.setPreventAccidentalChanges(originalProtection)
                repository.setOnboardingCompleted(originalOnboarding)
            }
        }
    }

    private fun waitForText(text: String) {
        compose.waitUntil(timeoutMillis = 15_000) {
            compose.onAllNodesWithText(text).fetchSemanticsNodes().isNotEmpty()
        }
    }
}
