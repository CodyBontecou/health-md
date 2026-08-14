package com.healthmd.presentation.common

import androidx.compose.foundation.layout.fillMaxWidth
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
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import com.healthmd.presentation.theme.HealthMdTheme
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class ConfigurationProtectionTest {
    @get:Rule
    val compose = createComposeRule()

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

        compose.onNodeWithTag("configuration_action").performTouchInput { click() }
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
