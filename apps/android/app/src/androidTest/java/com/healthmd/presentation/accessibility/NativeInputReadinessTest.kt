package com.healthmd.presentation.accessibility

import android.app.Dialog
import android.widget.TextView
import androidx.compose.ui.test.ComposeTimeoutException
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class NativeInputReadinessTest : AccessibilityTestHarness(AccessibilityDisplayCase(411, 720, 1f)) {
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
        } finally {
            compose.runOnUiThread { dialog.dismiss() }
        }

        awaitNativeInputReady()
        assertTrue("Admit the restored native owner", compose.runOnUiThread {
            compose.activity.window.decorView.hasWindowFocus()
        })
    }
}
