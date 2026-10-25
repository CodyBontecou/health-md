package com.healthmd.presentation.export

import android.graphics.Bitmap
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.unit.Density
import androidx.test.platform.app.InstrumentationRegistry
import com.healthmd.R
import com.healthmd.presentation.theme.HealthMdTheme
import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized

@RunWith(Parameterized::class)
class PostExportGuidanceTest(private val dark: Boolean, private val fontScale: Float) {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    private fun show(milestone: Int, onSchedule: () -> Unit = {}, onUpgrade: () -> Unit = {}, onDismiss: () -> Unit = {}) {
        compose.runOnUiThread {
            compose.activity.setShowWhenLocked(true)
            compose.activity.setTurnScreenOn(true)
            compose.activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
        compose.setContent {
            HealthMdTheme(darkTheme = dark) {
                val density = LocalDensity.current
                CompositionLocalProvider(LocalDensity provides Density(density.density, fontScale)) {
                    PostExportGuidanceDialog(milestone, 5 - milestone, onSchedule, onUpgrade, onDismiss)
                }
            }
        }
        compose.waitForIdle()
    }

    private fun capture(name: String) {
        // Dialog window fades run outside Compose's test clock.
        android.os.SystemClock.sleep(500)
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val outputDir = InstrumentationRegistry.getArguments().getString("additionalTestOutputDir")
            ?.let(::File) ?: instrumentation.targetContext.getExternalFilesDir(null)
        checkNotNull(outputDir).mkdirs()
        val file = File(outputDir, "pricing-flow-$name-$dark-$fontScale.png")
        file.outputStream().use { output -> instrumentation.uiAutomation.takeScreenshot().compress(Bitmap.CompressFormat.PNG, 100, output) }
    }

    @Test fun firstExportOpensScheduleWithoutPurchasing() {
        var schedules = 0
        var upgrades = 0
        show(1, onSchedule = { schedules++ }, onUpgrade = { upgrades++ })
        val context = compose.activity
        compose.onNodeWithText(context.resources.getQuantityString(R.plurals.free_exports_remaining, 4, 4)).assertIsDisplayed()
        val action = compose.onNodeWithText(context.getString(R.string.post_export_schedule_action))
        action.assertIsDisplayed()
        capture("first")
        action.performClick()
        assertEquals(1, schedules)
        assertEquals(0, upgrades)
    }

    @Test fun thirdExportCanContinueFreeWithTwoRemaining() {
        var dismissals = 0
        var upgrades = 0
        show(3, onUpgrade = { upgrades++ }, onDismiss = { dismissals++ })
        val context = compose.activity
        compose.onNodeWithText(context.resources.getQuantityString(R.plurals.free_exports_remaining, 2, 2)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.post_export_upgrade_action)).assertIsDisplayed()
        capture("third")
        compose.onNodeWithText(context.getString(R.string.post_export_continue_free)).performClick()
        assertEquals(1, dismissals)
        assertEquals(0, upgrades)
    }

    @Test fun thirdExportOpensLifetimeReview() {
        var schedules = 0
        var upgrades = 0
        show(3, onSchedule = { schedules++ }, onUpgrade = { upgrades++ })
        compose.onNodeWithText(compose.activity.getString(R.string.post_export_upgrade_action)).performClick()
        assertEquals(0, schedules)
        assertEquals(1, upgrades)
    }

    companion object {
        @JvmStatic @Parameterized.Parameters(name = "dark={0}, fontScale={1}")
        fun cases() = listOf(arrayOf<Any>(false, 1f), arrayOf<Any>(true, 1f), arrayOf<Any>(false, 1.5f), arrayOf<Any>(true, 1.5f))
    }
}
