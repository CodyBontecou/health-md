package com.healthmd.presentation.accessibility

import android.app.KeyguardManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.os.Build
import android.os.Looper
import android.os.PowerManager
import android.view.WindowManager
import android.view.inspector.WindowInspector
import android.view.inputmethod.InputMethodManager
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
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
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpRect
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
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

    private val fixtureContent = mutableStateOf<(@Composable () -> Unit)?>(null)

    @Before
    fun keepTestActivityAwake() {
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).wakeUp()
        withNativeInputDiagnostics("Native test activity could not prepare for input") {
            compose.runOnUiThread {
                val activity = compose.activity
                activity.setShowWhenLocked(true)
                activity.setTurnScreenOn(true)
                activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                val keyguard = activity.getSystemService(KeyguardManager::class.java)
                if (keyguard.isKeyguardLocked) {
                    assertFalse(
                        "Accessibility input requires an unlocked device; secure keyguard remains locked",
                        keyguard.isKeyguardSecure,
                    )
                    keyguard.requestDismissKeyguard(activity, null)
                }
            }
        }
        // Admit the rendered native host before a fixture can request input or open a modal.
        // The Compose rule permits one setContent call, so fixtures publish into this host.
        compose.setContent { TestViewport { fixtureContent.value?.invoke() } }
        waitForViewport()
        awaitNativeInputReady()
    }

    /** Compose semantics can receive input before Android admits input to the native window. */
    protected fun awaitNativeInputReady() {
        withNativeInputDiagnostics("Native test activity did not become ready for input") {
            compose.waitUntil(timeoutMillis = 10_000) {
                compose.runOnUiThread {
                    val activity = compose.activity
                    val decor = activity.window.decorView
                    !activity.getSystemService(KeyguardManager::class.java).isKeyguardLocked &&
                        decor.isAttachedToWindow && decor.hasWindowFocus()
                }
            }
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
        compose.runOnUiThread {
            check(fixtureContent.value == null) { "Cannot call setContent twice per test!" }
            fixtureContent.value = {
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

    /** Failure-only facts from this test process's native owners; never read editor contents. */
    protected fun withNativeInputDiagnostics(stage: String, assertion: () -> Unit) {
        try {
            assertion()
        } catch (failure: AssertionError) {
            throw AssertionError("$stage; ${nativeInputDiagnostics()}", failure)
        } catch (failure: ComposeTimeoutException) {
            throw AssertionError("$stage; ${nativeInputDiagnostics()}", failure)
        }
    }

    private fun nativeInputDiagnostics(): String = runCatching {
        // This also runs before setContent, when there is no Compose root to await.
        val ownerFacts = compose.runOnUiThread {
            val keyguard = compose.activity.getSystemService(KeyguardManager::class.java)
            val power = compose.activity.getSystemService(PowerManager::class.java)
            val state = "keyguard(locked=${keyguard.isKeyguardLocked}, secure=${keyguard.isKeyguardSecure}); " +
                "display(interactive=${power.isInteractive}, state=${compose.activity.window.decorView.display?.state}); "
            val inputMethod = compose.activity.getSystemService(InputMethodManager::class.java)
            val owners = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                WindowInspector.getGlobalWindowViews()
            } else {
                listOf(compose.activity.window.decorView)
            }
            owners.take(8).mapIndexed { index, owner ->
                val focused = owner.findFocus()
                val insets = ViewCompat.getRootWindowInsets(owner)
                val params = owner.layoutParams as? WindowManager.LayoutParams
                "owner[$index](class=${owner.javaClass.simpleName}, " +
                    "attached=${owner.isAttachedToWindow}, windowFocus=${owner.hasWindowFocus()}, " +
                    "visibility=${owner.visibility}, windowVisibility=${owner.windowVisibility}, " +
                    "shown=${owner.isShown}, flags=${params?.flags}, " +
                    "focusedView=${focused?.javaClass?.simpleName}, " +
                    "inputActive=${focused?.let { inputMethod?.isActive(it) }}, " +
                    "imeVisible=${insets?.isVisible(WindowInsetsCompat.Type.ime())}, " +
                    "imeBottom=${insets?.getInsets(WindowInsetsCompat.Type.ime())?.bottom}, " +
                    "size=${owner.width}x${owner.height}, softInputMode=${params?.softInputMode})"
            }.joinToString(prefix = state + "nativeInput=", separator = "; ")
        }
        ownerFacts + "; " + nativeWindowPolicyDiagnostics(compose.activity.packageName)
    }.getOrElse { "nativeInput unavailable: ${it.javaClass.simpleName}" }

    /** Raw dumps stay in memory; diagnostics expose only categories, IDs, and booleans. */
    private fun nativeWindowPolicyDiagnostics(packageName: String): String = runCatching {
        check(Looper.myLooper() != Looper.getMainLooper())
        val device = UiDevice.getInstance(InstrumentationRegistry.getInstrumentation())
        val windows = device.executeShellCommand("dumpsys -t 2 window")
        val input = device.executeShellCommand("dumpsys -t 2 input")
        val currentFocus = Regex("^\\s*mCurrentFocus=(.*)$", RegexOption.MULTILINE)
            .find(windows)?.groupValues?.get(1)
        val focusedApp = Regex("^\\s*mFocusedApp=(.*)$", RegexOption.MULTILINE)
            .find(windows)?.groupValues?.get(1)
        val token = Regex("Window\\{([0-9a-fA-F]+)\\b").find(currentFocus.orEmpty())?.groupValues?.get(1)
        val selectedStart = token?.let {
            Regex("^\\s*Window #\\d+ Window\\{${Regex.escape(it)}\\b.*$", RegexOption.MULTILINE).find(windows)
        }
        val selectedWindow = selectedStart?.let {
            val rest = windows.substring(it.range.last + 1)
            val next = Regex("^\\s*Window #\\d+ ", RegexOption.MULTILINE).find(rest)
            if (next == null) rest else rest.substring(0, next.range.first)
        }
        val surface = Regex("mHasSurface=(true|false)").find(selectedWindow.orEmpty())
            ?.groupValues?.get(1) ?: "unavailable"
        val display = Regex("^\\s*FocusedDisplayId:\\s*(-?\\d+)", RegexOption.MULTILINE)
            .find(input)?.groupValues?.get(1)
        val lines = input.lineSequence().toList()
        val header = lines.indexOfFirst { it.trim() == "FocusedWindows:" }
        val focusedWindow = if (header < 0 || display == null) {
            "unavailable"
        } else {
            val record = lines.drop(header + 1).takeWhile { it.trimStart().startsWith("displayId=") }
                .firstOrNull { Regex("displayId=$display(?:,|\\s)").containsMatchIn(it) }
            if (record == null) "none" else focusOwnerCategory(record, packageName)
        }
        "nativePolicy=window(currentFocus=${focusOwnerCategory(currentFocus, packageName)}, " +
            "focusedApp=${focusOwnerCategory(focusedApp, packageName)}, focusedSurface=$surface); " +
            "input(focusedDisplay=${display ?: "unavailable"}, focusedWindow=$focusedWindow)"
    }.getOrElse { "nativePolicy unavailable: ${it.javaClass.simpleName}" }

    private fun focusOwnerCategory(record: String?, packageName: String): String = when {
        record == null -> "unavailable"
        record.trim() == "null" -> "none"
        Regex("(?<![\\w.])${Regex.escape(packageName)}(?![\\w.])").containsMatchIn(record) -> "own"
        else -> "other"
    }

    protected fun assertTextFits(node: SemanticsNodeInteraction, expectedFontSize: TextUnit? = null) {
        val results = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        assertTrue("Expected measured text", results.isNotEmpty())
        val visibleWidth = node.readLayoutOnIdle { it.boundsInRoot.width }
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
        val bounds = unclippedBoundsOnIdle()
        assertTrue("Touch target narrower than 48 dp: $bounds", bounds.right - bounds.left >= 47.dp)
        assertTrue("Touch target shorter than 48 dp: $bounds", bounds.bottom - bounds.top >= 47.dp)
        return this
    }

    /** For content in the embedded viewport, not separate native dialog/popup windows. */
    protected fun SemanticsNodeInteraction.assertFullyVisible(): SemanticsNodeInteraction {
        val bounds = unclippedBoundsOnIdle()
        val viewport = compose.onNodeWithTag(VIEWPORT).unclippedBoundsOnIdle()
        val tolerance = 1.dp
        assertTrue("Control has no width: $bounds", bounds.right > bounds.left)
        assertTrue("Control has no height: $bounds", bounds.bottom > bounds.top)
        assertTrue("Control is clipped horizontally: $bounds in $viewport",
            bounds.left >= viewport.left - tolerance && bounds.right <= viewport.right + tolerance)
        assertTrue("Control is clipped vertically: $bounds in $viewport",
            bounds.top >= viewport.top - tolerance && bounds.bottom <= viewport.bottom + tolerance)
        return this
    }

    /** Read live layout coordinates on the owner thread after Compose reaches idle. */
    protected fun <T> SemanticsNodeInteraction.readLayoutOnIdle(
        block: (SemanticsNode) -> T,
    ): T {
        val semanticsNode = fetchSemanticsNode("Failed to read layout for the node.")
        return compose.runOnIdle { block(semanticsNode) }
    }

    protected fun SemanticsNodeInteraction.unclippedBoundsOnIdle(): DpRect = readLayoutOnIdle { node ->
        if (!node.layoutInfo.isPlaced) {
            DpRect(Dp.Unspecified, Dp.Unspecified, Dp.Unspecified, Dp.Unspecified)
        } else {
            with(node.layoutInfo.density) {
                val position = node.positionInRoot
                val size = node.size
                DpRect(
                    position.x.toDp(),
                    position.y.toDp(),
                    (position.x + size.width).toDp(),
                    (position.y + size.height).toDp(),
                )
            }
        }
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
