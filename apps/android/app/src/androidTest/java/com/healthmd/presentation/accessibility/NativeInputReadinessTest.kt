package com.healthmd.presentation.accessibility

import android.app.Dialog
import android.view.View
import android.widget.TextView
import androidx.compose.material3.Text
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.window.Dialog as ComposeDialog
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeInputReadinessTest : AccessibilityTestHarness(AccessibilityDisplayCase(411, 720, 1f)) {
    @Test
    fun admittedHostCanPublishAnInitialModalThatOwnsFocusAndDismissesWithOneBack() {
        // Setup must render/admit a neutral host before this first fixture is published.
        compose.onNodeWithTag(VIEWPORT).assertExists()
        assertTrue("Admit the rendered native host before fixture publication", compose.runOnUiThread {
            val decor = compose.activity.window.decorView
            decor.isAttachedToWindow && decor.hasWindowFocus()
        })

        val visible = mutableStateOf(true)
        var modalOwner: View? = null
        setContent {
            if (visible.value) {
                ComposeDialog(onDismissRequest = { visible.value = false }) {
                    val view = LocalView.current
                    DisposableEffect(view) {
                        modalOwner = view.rootView
                        onDispose { modalOwner = null }
                    }
                    Text("Synthetic initial modal", Modifier.testTag(INITIAL_MODAL))
                }
            }
        }
        compose.onNodeWithTag(INITIAL_MODAL).assertIsDisplayed()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.runOnUiThread {
                modalOwner?.hasWindowFocus() == true &&
                    !compose.activity.window.decorView.hasWindowFocus()
            }
        }
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.runOnUiThread { !visible.value }
        }
        compose.onNodeWithTag(INITIAL_MODAL).assertDoesNotExist()
        assertFalse("One native Back dismisses the initial modal", visible.value)
        awaitNativeInputReady()
    }

    @Test
    fun fixturePublicationPreservesTheSingleContentContract() {
        setContent { Text("First synthetic fixture") }
        assertThrows(IllegalStateException::class.java) {
            setContent { Text("Second synthetic fixture") }
        }
        compose.onNodeWithText("First synthetic fixture").assertExists()
        compose.onNodeWithText("Second synthetic fixture").assertDoesNotExist()
    }

    @Test
    fun anotherNativeWindowBlocksInputUntilActivityFocusReturns() {
        val dialog = compose.runOnUiThread {
            Dialog(compose.activity).apply {
                setContentView(TextView(context).apply { text = "Synthetic focus owner" })
                show()
            }
        }
        try {
            compose.waitUntil(timeoutMillis = 10_000) {
                compose.runOnUiThread {
                    dialog.window!!.decorView.hasWindowFocus() &&
                        !compose.activity.window.decorView.hasWindowFocus()
                }
            }
            val failure = assertThrows(AssertionError::class.java) { awaitNativeInputReady() }
            assertTrue("Preserve the native readiness timeout", failure.cause is ComposeTimeoutException)
            assertTrue("Report the missing native focus", failure.message.orEmpty().contains("windowFocus=false"))
            assertTrue("Report actual keyguard state", failure.message.orEmpty().contains("keyguard(locked="))
            assertTrue("Report actual display state", failure.message.orEmpty().contains("display(interactive="))
            assertTrue("Classify the actual native policy owner", failure.message.orEmpty().contains(
                "nativePolicy=window(currentFocus=own, focusedApp=own, focusedSurface=true)",
            ))
            val displayId = compose.runOnUiThread { compose.activity.window.decorView.display.displayId }
            assertTrue("Classify the input dispatcher owner", failure.message.orEmpty().contains(
                "input(focusedDisplay=$displayId, focusedWindow=own)",
            ))
            assertFalse("Diagnostics omit fixture text", failure.message.orEmpty().contains("Synthetic focus owner"))
        } finally {
            compose.runOnUiThread { dialog.dismiss() }
        }

        awaitNativeInputReady()
        assertTrue("Admit the restored native owner", compose.runOnUiThread {
            compose.activity.window.decorView.hasWindowFocus()
        })
    }

    companion object {
        private const val INITIAL_MODAL = "native-input.initial-modal"
    }
}
