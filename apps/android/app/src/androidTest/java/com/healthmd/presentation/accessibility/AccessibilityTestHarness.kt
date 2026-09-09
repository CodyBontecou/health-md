package com.healthmd.presentation.accessibility

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.InterceptPlatformTextInput
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.healthmd.presentation.theme.HealthMdTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import kotlinx.coroutines.awaitCancellation
import org.junit.Before
import org.junit.Rule
import java.io.File
import java.util.Locale

/** Shared geometry only: fixture callbacks must never read or mutate real health/settings state. */
data class AccessibilityDisplayCase(
    val width: Int,
    val height: Int,
    val fontScale: Float,
    val language: String = "en",
    val dark: Boolean = false,
)

fun accessibilityDisplays(): List<Array<AccessibilityDisplayCase>> = listOf(
    AccessibilityDisplayCase(411, 720, 1f),
    AccessibilityDisplayCase(320, 640, 1f),
    AccessibilityDisplayCase(320, 480, 1.3f),
    AccessibilityDisplayCase(320, 480, 2f),
    AccessibilityDisplayCase(320, 640, 2f),
    AccessibilityDisplayCase(568, 280, 2f),
    AccessibilityDisplayCase(640, 280, 2f),
    AccessibilityDisplayCase(320, 480, 2f, language = "de", dark = true),
    AccessibilityDisplayCase(320, 480, 2f, language = "ar", dark = true),
    AccessibilityDisplayCase(320, 640, 2f, language = "ja"),
).map { arrayOf(it) }

/**
 * Reuses the established LargeDisplayAccessibilityTest viewport recipe for additional surfaces.
 * No device-wide font/display/locale settings, app storage, or permissions are changed.
 * Native popup/dialog windows are separate owners: check their own bounds and density explicitly.
 */
abstract class AccessibilityTestHarness(protected val display: AccessibilityDisplayCase) {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    @Before
    fun keepTestActivityAwake() {
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).wakeUp()
        compose.activityRule.scenario.onActivity {
            it.setShowWhenLocked(true)
            it.setTurnScreenOn(true)
            it.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    protected fun configuration(base: Configuration) = Configuration(base).apply {
        screenWidthDp = display.width
        screenHeightDp = display.height
        fontScale = display.fontScale
        setLocale(Locale.forLanguageTag(display.language))
    }

    protected fun text(id: Int, vararg arguments: Any): String {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val resources = context.createConfigurationContext(configuration(context.resources.configuration)).resources
        return if (arguments.isEmpty()) resources.getString(id) else resources.getString(id, *arguments)
    }

    @OptIn(ExperimentalComposeUiApi::class)
    protected fun setContent(
        suppressSoftwareKeyboard: Boolean = false,
        content: @Composable () -> Unit,
    ) {
        compose.setContent {
            TestViewport {
                if (suppressSoftwareKeyboard) {
                    // The fitted dp matrix is intentionally independent of the physical
                    // emulator window. A real IME belongs to that outer owner and otherwise
                    // double-shrinks synthetic landscape viewports to zero height.
                    InterceptPlatformTextInput(
                        interceptor = { _, _ -> awaitCancellation() },
                        content = content,
                    )
                } else {
                    content()
                }
            }
        }
        waitForViewport()
    }

    @Composable
    protected fun TestViewport(content: @Composable () -> Unit) {
        val context = LocalContext.current
        val config = configuration(LocalConfiguration.current)
        val nativeDensity = LocalDensity.current
        BoxWithConstraints {
            val fit = minOf(maxWidth.value / display.width, maxHeight.value / display.height)
            CompositionLocalProvider(
                LocalContext provides context.createConfigurationContext(config),
                LocalConfiguration provides config,
                LocalDensity provides Density(nativeDensity.density * fit, display.fontScale),
                LocalLayoutDirection provides if (display.language == "ar") LayoutDirection.Rtl else LayoutDirection.Ltr,
            ) {
                HealthMdTheme(darkTheme = display.dark) {
                    Box(
                        modifier = Modifier.requiredSize(display.width.dp, display.height.dp)
                            .testTag(VIEWPORT).clipToBounds(),
                    ) { content() }
                }
            }
        }
    }

    protected fun waitForViewport() {
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithTag(VIEWPORT)
                .fetchSemanticsNodes(atLeastOneRootRequired = false).size == 1
        }
        compose.waitForIdle()
    }

    protected fun assertTextFits(node: SemanticsNodeInteraction, expectedFontSize: TextUnit? = null) {
        val results = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        assertTrue("Expected measured text", results.isNotEmpty())
        val visibleWidth = node.fetchSemanticsNode().boundsInRoot.width
        results.forEach { result ->
            assertEquals("Respect the chosen font scale", display.fontScale, result.layoutInput.density.fontScale)
            if (expectedFontSize != null) assertEquals(expectedFontSize, result.layoutInput.style.fontSize)
            assertFalse("Text clips vertically", result.didOverflowHeight)
            // Compose 1.7 semantics paragraphs may be wider than the measured text node.
            // Check actual line widths instead of treating hasVisualOverflow as a fit check.
            repeat(result.lineCount) { line ->
                val width = result.getLineRight(line) - result.getLineLeft(line)
                assertTrue("Text clips horizontally: $width in $visibleWidth", width <= visibleWidth + 1f)
                assertFalse("Essential text must not be ellipsized", result.isLineEllipsized(line))
            }
        }
    }

    protected fun SemanticsNodeInteraction.assertMinimumTouchTarget(): SemanticsNodeInteraction {
        val bounds = getUnclippedBoundsInRoot()
        assertTrue("Touch target narrower than 48 dp: $bounds", bounds.right - bounds.left >= 47.dp)
        assertTrue("Touch target shorter than 48 dp: $bounds", bounds.bottom - bounds.top >= 47.dp)
        return this
    }

    /** For content in the embedded viewport, not separate native dialog/popup windows. */
    protected fun SemanticsNodeInteraction.assertFullyVisible(): SemanticsNodeInteraction {
        assertIsDisplayed()
        val bounds = getUnclippedBoundsInRoot()
        val viewport = compose.onNodeWithTag(VIEWPORT).getUnclippedBoundsInRoot()
        val tolerance = 1.dp
        assertTrue("Control has no width: $bounds", bounds.right > bounds.left)
        assertTrue("Control has no height: $bounds", bounds.bottom > bounds.top)
        assertTrue("Control is clipped horizontally: $bounds in $viewport",
            bounds.left >= viewport.left - tolerance && bounds.right <= viewport.right + tolerance)
        assertTrue("Control is clipped vertically: $bounds in $viewport",
            bounds.top >= viewport.top - tolerance && bounds.bottom <= viewport.bottom + tolerance)
        return this
    }

    /**
     * Opt-in synthetic captures only. Use a lane-specific name; pass a content node for dialogs.
     * Never capture the whole device display (notifications or keyboard suggestions may be private).
     */
    protected fun capture(name: String, node: SemanticsNodeInteraction? = null) {
        if (InstrumentationRegistry.getArguments().getString("healthmd.captureAccessibility") != "true") return
        waitForViewport()
        val directory = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "accessibility-screenshots")
            .apply { mkdirs() }
        val filename = "${display.width}x${display.height}-${display.fontScale}-${display.language}-${display.dark}-$name.png"
        val bitmap = (node ?: compose.onNodeWithTag(VIEWPORT)).captureToImage().asAndroidBitmap()
        File(directory, filename).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    companion object {
        const val VIEWPORT = "accessibility.viewport"
    }
}
