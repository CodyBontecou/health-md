package com.healthmd.presentation.common

import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.click
import androidx.compose.ui.test.assert
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.healthmd.presentation.theme.HealthMdTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test

class ConfigurationProtectionTest {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    @Before
    fun showSyntheticTestWindow() {
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).wakeUp()
        compose.activityRule.scenario.onActivity {
            it.setShowWhenLocked(true)
            it.setTurnScreenOn(true)
            it.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    @Test
    fun protectedRegionMatchesContentInsideAnUnboundedScrollColumn() {
        val actionCount = AtomicInteger(0)
        val blockedCount = AtomicInteger(0)
        compose.setContent {
            HealthMdTheme {
                CompositionLocalProvider(LocalConfigurationProtection provides ConfigurationProtectionUi(
                    enabled = true, onBlockedChange = { blockedCount.incrementAndGet() },
                )) {
                    Column(Modifier.verticalScroll(rememberScrollState())) {
                        Spacer(Modifier.height(1_000.dp))
                        ConfigurationProtectedRegion(Modifier.fillMaxWidth()) {
                            Button(onClick = { actionCount.incrementAndGet() }, modifier = Modifier.testTag("scrolled_action")) {
                                Text("Change configuration")
                            }
                        }
                    }
                }
            }
        }
        // Tap the real child coordinates, not a synthetic click on the overlay's semantics.
        compose.onNodeWithTag("scrolled_action", useUnmergedTree = true)
            .performScrollTo().performTouchInput { click() }
        assertEquals(0, actionCount.get())
        assertEquals(1, blockedCount.get())
    }

    @Test
    fun protectedRegionBlocksChildActionAndPresentsToast() {
        val actionCount = AtomicInteger(0)
        val blockedCount = AtomicInteger(0)
        val toastVisible = mutableStateOf(false)
        val openSettingsCount = AtomicInteger(0)

        compose.setContent {
            HealthMdTheme {
                CompositionLocalProvider(
                    LocalConfigurationProtection provides ConfigurationProtectionUi(
                        enabled = true,
                        onBlockedChange = {
                            blockedCount.incrementAndGet()
                            toastVisible.value = true
                        },
                    ),
                ) {
                    ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
                        Button(
                            onClick = { actionCount.incrementAndGet() },
                            modifier = Modifier.testTag("configuration_action"),
                        ) {
                            Text("Change configuration")
                        }
                    }
                    ConfigurationProtectionToast(
                        visible = toastVisible.value,
                        onOpenSettings = { openSettingsCount.incrementAndGet() },
                    )
                }
            }
        }

        compose.onNodeWithTag("configuration_action", useUnmergedTree = true)
            .performTouchInput { click() }
        compose.onNodeWithTag(ConfigurationProtectionTestTags.TOAST)
            .assert(
                SemanticsMatcher.expectValue(
                    SemanticsProperties.LiveRegion,
                    LiveRegionMode.Polite,
                ),
            )
            .performClick()

        assertEquals(0, actionCount.get())
        assertEquals(1, blockedCount.get())
        assertEquals(1, openSettingsCount.get())
    }
}
