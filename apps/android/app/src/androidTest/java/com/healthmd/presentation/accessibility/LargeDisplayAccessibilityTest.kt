package com.healthmd.presentation.accessibility

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Computer
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.healthmd.R
import com.healthmd.presentation.common.*
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.presentation.export.FloatingExportActionBar
import com.healthmd.presentation.navigation.AppNavigationLayout
import com.healthmd.presentation.navigation.NavDestination
import com.healthmd.presentation.onboarding.*
import com.healthmd.presentation.paywall.PaywallScreen
import com.healthmd.presentation.schedule.*
import com.healthmd.presentation.settings.ConfigurationProtectionSettingsCard
import com.healthmd.presentation.settings.SettingsNavigationCard
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistType
import kotlinx.coroutines.launch
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.util.Locale
import java.io.File

/** Real Compose measurements and pointer taps; no health, storage, or billing side effects. */
@RunWith(Parameterized::class)
class LargeDisplayAccessibilityTest(private val display: DisplayCase) {
    @get:Rule
    val compose = createAndroidComposeRule<ComponentActivity>()

    @Before
    fun keepTestActivityAwake() {
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).wakeUp()
        compose.activityRule.scenario.onActivity {
            // Only this synthetic test activity is shown; no device settings are changed.
            it.setShowWhenLocked(true)
            it.setTurnScreenOn(true)
            it.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    data class DisplayCase(
        val width: Int,
        val height: Int,
        val fontScale: Float,
        val language: String = "en",
        val dark: Boolean = false,
    )

    companion object {
        private const val VIEWPORT = "accessibility.viewport"
        private const val LAST_ACTION = "Last action"

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun displays() = listOf(
            DisplayCase(411, 720, 1f),
            DisplayCase(320, 640, 1f), // enlarged display with the default font setting
            DisplayCase(320, 480, 1.3f),
            DisplayCase(320, 480, 2f),
            DisplayCase(320, 640, 2f),
            DisplayCase(568, 280, 2f),
            DisplayCase(640, 280, 2f),
            DisplayCase(320, 480, 2f, language = "de", dark = true),
            DisplayCase(320, 480, 2f, language = "ar", dark = true),
            DisplayCase(320, 640, 2f, language = "ja"), // period-before-hour locale
        ).map { arrayOf(it) }
    }

    private fun configuration(base: Configuration) = Configuration(base).apply {
        screenWidthDp = display.width
        screenHeightDp = display.height
        fontScale = display.fontScale
        setLocale(Locale.forLanguageTag(display.language))
    }

    private fun text(id: Int): String {
        val context = ApplicationProvider.getApplicationContext<Context>()
        return context.createConfigurationContext(configuration(context.resources.configuration)).getString(id)
    }

    @Composable
    private fun TestViewport(content: @Composable () -> Unit) {
        val context = LocalContext.current
        val config = configuration(LocalConfiguration.current)
        val nativeDensity = LocalDensity.current
        // Fit both portrait and landscape dp viewports on the connected Pixel without
        // changing its global display/font settings or touching the installed app's data.
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
                        modifier = Modifier
                            .requiredSize(display.width.dp, display.height.dp)
                            .testTag(VIEWPORT)
                            .clipToBounds(),
                    ) {
                        content()
                    }
                }
            }
        }
    }

    @Test
    fun onboardingActionsRemainReachableThroughTheWholePager() {
        val actions = mutableListOf<String>()
        val pages = listOf(
            OnboardingPage.WELCOME,
            OnboardingPage.HEALTH_ACCESS,
            OnboardingPage.FOLDER_SETUP,
            OnboardingPage.PLAY_ACCESS,
            OnboardingPage.INCLUDED_ACCESS,
            OnboardingPage.READY,
        )
        compose.setContent {
            TestViewport {
                val pager = rememberPagerState(pageCount = { pages.size })
                val scope = rememberCoroutineScope()
                var folderName by remember { mutableStateOf<String?>(null) }
                val canContinue = when (pages[pager.currentPage]) {
                    OnboardingPage.HEALTH_ACCESS -> false
                    OnboardingPage.FOLDER_SETUP -> folderName != null
                    else -> true
                }
                OnboardingLayout(
                    pages = pages,
                    pagerState = pager,
                    canContinue = canContinue,
                    onBack = { scope.launch { pager.animateScrollToPage(pager.currentPage - 1) } },
                    onContinue = { scope.launch { pager.animateScrollToPage(pager.currentPage + 1) } },
                    onSkip = { scope.launch { pager.animateScrollToPage(pager.currentPage + 1) } },
                    onGrantHealthAccess = { actions += "health" },
                    onSelectFolder = {
                        actions += "folder"
                        folderName = "A long selected folder name for accessible exports"
                    },
                    onComplete = { actions += "complete" },
                ) { page ->
                    when (page) {
                        OnboardingPage.WELCOME -> WelcomePage(onUseSharedSetup = { actions += "shared" })
                        OnboardingPage.HEALTH_ACCESS -> HealthAccessPage(
                            hasPermissions = false,
                            actionError = HealthConnectActionError.PERMISSION_DENIED,
                            onDismissError = {},
                        )
                        OnboardingPage.FOLDER_SETUP -> StorageSetupPage(
                            folderName = folderName,
                            onSelectFolder = {
                                actions += "folder"
                                folderName = "A long selected folder name for accessible exports"
                            },
                        )
                        OnboardingPage.PLAY_ACCESS -> PaywallScreen(
                            onPurchase = { actions += "purchase" },
                            onRestore = { actions += "restore" },
                            onDismiss = null,
                            subtitle = text(R.string.schedule_unlock_required_body),
                        )
                        OnboardingPage.INCLUDED_ACCESS -> IncludedAccessPage()
                        OnboardingPage.READY -> ReadyPage()
                    }
                }
            }
        }

        scrollAndTap(R.string.shared_setup_use)
        tap(R.string.onboarding_continue)
        // The useful action is visible immediately, rather than a disabled Continue.
        node(R.string.onboarding_continue).assertDoesNotExist()
        compose.onNodeWithContentDescription(text(R.string.onboarding_back)).assertFullyVisible()
        node(R.string.onboarding_skip).assertFullyVisible()
        tap(R.string.onboarding_health_grant_button)
        compose.onNodeWithContentDescription(text(R.string.onboarding_back)).performTouchInput { click() }
        tap(R.string.onboarding_continue)
        tap(R.string.onboarding_skip)
        capture("folder-intro")
        tap(R.string.onboarding_storage_select_button)
        scrollAndTap(R.string.export_folder_change)
        tap(R.string.onboarding_continue)
        scrollAndTap(R.string.paywall_unlock_button)
        scrollAndTap(R.string.paywall_restore)
        tap(R.string.onboarding_continue)
        // The included-access channel's final feature is also reachable at the largest scales.
        compose.onNodeWithText(text(R.string.fdroid_onboarding_no_play_services))
            .performScrollTo().assertFullyVisible()
        tap(R.string.onboarding_continue)
        capture("ready-intro")
        tap(R.string.onboarding_ready_start_button)

        assertEquals(listOf("shared", "health", "folder", "folder", "purchase", "restore", "complete"), actions)
    }

    @Test
    fun growingNavigationLabelsDoNotClipOrCoverTheLastScreenAction() {
        val actions = mutableListOf<String>()
        compose.setContent {
            TestViewport {
                AppNavigationLayout(
                    destinations = NavDestination.entries,
                    currentRoute = NavDestination.EXPORT.route,
                    onNavigate = { actions += it.route },
                ) { modifier ->
                    Column(modifier = modifier.verticalScroll(rememberScrollState())) {
                        Spacer(Modifier.height(2_000.dp))
                        TextButton(onClick = { actions += LAST_ACTION }) { Text(LAST_ACTION) }
                    }
                }
            }
        }

        val last = compose.onNodeWithText(LAST_ACTION).performScrollTo().assertFullyVisible()
        last.performTouchInput { click() }
        NavDestination.entries.forEach { destination ->
            val tab = node(destination.label)
            if (display.width >= 601) tab.performScrollTo()
            tab.assertFullyVisible()
            assertTextDoesNotOverflow(destination.label)
            if (display.width < 601) {
                assertTrue(
                    "Screen content must end above the measured tab bar",
                    last.getUnclippedBoundsInRoot().bottom <= tab.getUnclippedBoundsInRoot().top,
                )
            }
            tab.performTouchInput { click() }
        }
        assertEquals(listOf(LAST_ACTION) + NavDestination.entries.map { it.route }, actions)
        if (display.width < 601 && GeistAdaptiveLayout.wrapNavigation(display.width - 16f, display.fontScale, 4)) {
            val export = node(R.string.nav_export).getUnclippedBoundsInRoot()
            val schedule = node(R.string.nav_schedule).getUnclippedBoundsInRoot()
            val history = node(R.string.nav_history).getUnclippedBoundsInRoot()
            assertEquals("First row has two wide tabs", export.top, schedule.top)
            assertTrue("Remaining tabs use a second row", history.top >= export.bottom)
        }
    }

    @Test
    fun readingLayoutKeepsFontSizeAndWidensTheExplanation() {
        var continued = 0
        compose.setContent {
            TestViewport {
                val pages = listOf(OnboardingPage.WELCOME, OnboardingPage.HEALTH_ACCESS,
                    OnboardingPage.FOLDER_SETUP, OnboardingPage.PLAY_ACCESS, OnboardingPage.READY)
                val pager = rememberPagerState(initialPage = 1, pageCount = { pages.size })
                var connected by remember { mutableStateOf(false) }
                OnboardingLayout(
                    pages = pages,
                    pagerState = pager,
                    canContinue = connected,
                    onBack = {},
                    onContinue = { continued++ },
                    onSkip = {},
                    onGrantHealthAccess = { connected = true },
                    onSelectFolder = {},
                    onComplete = {},
                ) { page ->
                    if (page == OnboardingPage.HEALTH_ACCESS) HealthAccessPage(connected, null, {})
                }
            }
        }
        capture("health-intro")
        node(R.string.onboarding_health_grant_button).assertFullyVisible().assertIsEnabled()
        val reading = GeistAdaptiveLayout.readingFirst(display.width.toFloat(), display.height.toFloat(), display.fontScale)
        val hero = compose.onNodeWithTag(OnboardingTestTags.HERO)
        if (reading) hero.assertDoesNotExist() else hero.assertExists()

        val subtitle = compose.onNodeWithText(text(R.string.onboarding_health_subtitle))
        subtitle.performScrollTo()
        val results = mutableListOf<TextLayoutResult>()
        subtitle.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        assertEquals(GeistType.copy16.fontSize, results.single().layoutInput.style.fontSize)
        assertEquals(display.fontScale, results.single().layoutInput.density.fontScale)
        if (reading) {
            assertEquals(TextAlign.Start, results.single().layoutInput.style.textAlign)
            val body = compose.onNodeWithTag(OnboardingTestTags.BODY).getUnclippedBoundsInRoot()
            val textBounds = subtitle.getUnclippedBoundsInRoot()
            assertTrue("Explanatory copy uses the reading width, not nested gutters",
                textBounds.right - textBounds.left >= body.right - body.left - 33.dp)
        }
        compose.onNodeWithText(text(R.string.onboarding_health_feature_3)).performScrollTo()
        node(R.string.onboarding_health_grant_button).assertFullyVisible()
        capture("health-details")
        tap(R.string.onboarding_health_grant_button)
        node(R.string.onboarding_health_grant_button).assertDoesNotExist()
        node(R.string.onboarding_skip).assertDoesNotExist()
        tap(R.string.onboarding_continue)
        assertEquals(1, continued)
    }

    @Test
    fun exportActionsUseFullWidthRatherThanNarrowWrappedLabels() {
        val actions = mutableListOf<String>()
        compose.setContent {
            TestViewport {
                AppNavigationLayout(NavDestination.entries, NavDestination.EXPORT.route, {}) { modifier ->
                    Box(modifier) {
                        FloatingExportActionBar(
                            isPurchased = false,
                            freeExportsRemaining = 3,
                            hasSelectedFormat = true,
                            canPreview = true,
                            previewUnavailableReason = null,
                            canExport = true,
                            hitExportLimit = false,
                            isExporting = false,
                            onPreview = { actions += "preview" },
                            onExport = { actions += "export" },
                            modifier = Modifier.align(Alignment.BottomCenter).testTag("export.actions"),
                        )
                    }
                }
            }
        }
        val export = compose.onNode(hasText(text(R.string.export_button)) and hasClickAction() and
            hasAnyAncestor(hasTestTag("export.actions")))
        val preview = node(R.string.export_preview_button)
        capture("export-actions")
        export.assertFullyVisible().performTouchInput { click() }
        preview.assertFullyVisible().performTouchInput { click() }
        val exportBounds = export.getUnclippedBoundsInRoot()
        val previewBounds = preview.getUnclippedBoundsInRoot()
        if (display.fontScale >= 1.3f && display.width <= 411) {
            assertEquals("Stacked actions share their full width", exportBounds.left, previewBounds.left)
            assertTrue("The primary action precedes Preview", exportBounds.bottom <= previewBounds.top)
        }
        assertEquals(listOf("export", "preview"), actions)
    }

    @Test
    fun standalonePaywallClosePurchaseAndRestoreRemainReachable() {
        val actions = mutableListOf<String>()
        compose.setContent {
            TestViewport {
                AppNavigationLayout(emptyList(), null, {}) { modifier ->
                    Box(modifier) {
                        PaywallScreen(
                            onPurchase = { actions += "purchase" },
                            onRestore = { actions += "restore" },
                            onDismiss = { actions += "close" },
                            subtitle = text(R.string.schedule_unlock_required_body),
                        )
                    }
                }
            }
        }
        scrollAndTap(R.string.paywall_unlock_button)
        scrollAndTap(R.string.paywall_restore)
        compose.onNodeWithContentDescription(text(R.string.close))
            .performScrollTo().assertFullyVisible().performTouchInput { click() }
        assertEquals(listOf("purchase", "restore", "close"), actions)
    }

    @Test
    fun scheduleTimeTargetsAreSeparatedInBothHourModes() {
        val hour = mutableStateOf(23)
        val minute = mutableStateOf(59)
        val use24 = mutableStateOf(false)
        val changes = mutableListOf<String>()
        compose.setContent {
            TestViewport {
                Column(Modifier.fillMaxSize().background(AppColors.bgPrimary)
                    .verticalScroll(rememberScrollState()).padding(Spacing.md)) {
                    Text(text(R.string.schedule_time), style = MaterialTheme.typography.titleLarge)
                    Spacer(Modifier.height(Spacing.sm))
                    TimeRow(
                        hour.value, minute.value,
                        onHourDelta = { hour.value = Math.floorMod(hour.value + it, 24); changes += "hour:$it" },
                        onMinuteDelta = { minute.value = Math.floorMod(minute.value + it, 60); changes += "minute:$it" },
                        onTogglePeriod = { hour.value = (hour.value + 12) % 24; changes += "period" },
                        use24HourTime = use24.value,
                    )
                }
            }
        }
        capture("schedule-time")
        listOf(false, true).forEach { mode ->
            compose.runOnIdle { use24.value = mode }
            listOf(ScheduleControlTags.HOUR, ScheduleControlTags.MINUTE).forEach { tag ->
                val number = compose.onNode(hasAnyAncestor(hasTestTag(tag)) and
                    SemanticsMatcher.keyIsDefined(SemanticsActions.GetTextLayoutResult), useUnmergedTree = true)
                number.performScrollTo()
                assertTextFits(number, GeistType.label20Mono.fontSize)
            }
            listOf(
                R.string.schedule_increase_hour, R.string.schedule_decrease_hour,
                R.string.schedule_increase_minute, R.string.schedule_decrease_minute,
            ).forEach { id ->
                compose.onNodeWithContentDescription(text(id)).performScrollTo()
                    .assertFullyVisible().assertMinimumTouchTarget()
                    .performTouchInput { click(Offset(width * 0.1f, height * 0.5f)) }
            }
            val minus = compose.onNodeWithContentDescription(text(R.string.schedule_decrease_minute)).getUnclippedBoundsInRoot()
            val plus = compose.onNodeWithContentDescription(text(R.string.schedule_increase_minute)).getUnclippedBoundsInRoot()
            assertTrue("Opposite actions have an 8 dp gap, including RTL",
                maxOf(minus.left, plus.left) - minOf(minus.right, plus.right) >= 7.dp)
            val period = compose.onNodeWithTag(ScheduleControlTags.PERIOD)
            if (mode) {
                period.assertDoesNotExist()
                compose.runOnIdle { assertEquals(11, hour.value); assertEquals(59, minute.value) }
            } else {
                compose.runOnIdle { assertEquals(23, hour.value); assertEquals(59, minute.value) }
                if (localizedDayPeriodPrecedesHour(Locale.forLanguageTag(display.language))) {
                    assertTrue("Retain the locale's leading period",
                        period.getUnclippedBoundsInRoot().top <= compose.onNodeWithTag(ScheduleControlTags.HOUR).getUnclippedBoundsInRoot().top)
                }
                period.performScrollTo().assertFullyVisible().assertMinimumTouchTarget().performTouchInput { click() }
            }
        }
        assertEquals(listOf("hour:1", "hour:-1", "minute:1", "minute:-1", "period", "hour:1", "hour:-1", "minute:1", "minute:-1"), changes)
    }

    @Test
    fun scheduleFieldsFitLocalizedValuesAndCommitKeyboardEdits() {
        val state = mutableStateOf(ScheduleUiState(cadenceValue = 99999, lookbackDays = 365))
        compose.setContent {
            TestViewport {
                Column(Modifier.fillMaxSize().background(AppColors.bgPrimary).imePadding()
                    .verticalScroll(rememberScrollState()).padding(Spacing.md)) {
                    ScheduleSettingsCard(
                        uiState = state.value,
                        onFrequencyValueChange = { state.value = state.value.copy(cadenceValue = it) },
                        onFrequencyUnitSelected = { state.value = state.value.copy(cadenceUnit = it) },
                        onHourDelta = {}, onMinuteDelta = {}, onTogglePeriod = {},
                        onDateWindowSelected = { state.value = state.value.copy(dateWindow = it) },
                        onLookbackDelta = { state.value = state.value.copy(lookbackDays = state.value.lookbackDays + it) },
                    )
                }
            }
        }
        capture("schedule-fields")
        val field = compose.onNodeWithTag(ScheduleControlTags.FREQUENCY_VALUE)
        field.performScrollTo().assertFullyVisible().assertMinimumTouchTarget()
        assertTextFits(field, GeistType.label20Mono.fontSize)
        val context = ApplicationProvider.getApplicationContext<Context>()
        val resources = context.createConfigurationContext(configuration(context.resources.configuration)).resources
        val locale = Locale.forLanguageTag(display.language)
        compose.onNodeWithTag(ScheduleControlTags.FREQUENCY_UNIT).performScrollTo()
            .assertFullyVisible().assertMinimumTouchTarget().performTouchInput { click() }
        selectMenuItem(resources.getQuantityString(R.plurals.schedule_cadence_unit_minutes, 99999))
        compose.runOnIdle { assertEquals(ScheduleCadenceUnit.MINUTES, state.value.cadenceUnit) }
        compose.onNodeWithTag(ScheduleControlTags.HOUR).assertDoesNotExist()

        field.performScrollTo().performTouchInput { click() }
        field.performTextReplacement(formatInteger(7, locale))
        compose.runOnIdle { assertEquals("Don't persist a below-minimum partial edit", 99999, state.value.cadenceValue) }
        field.performImeAction()
        compose.runOnIdle { assertEquals(15, state.value.cadenceValue) }
        field.assertTextContains(formatInteger(15, locale))

        field.performScrollTo().performTouchInput { click() }
        field.performTextReplacement("")
        field.performImeAction()
        field.assertTextContains(formatInteger(15, locale))
        field.performScrollTo().performTouchInput { click() }
        field.performTextReplacement(formatInteger(123456, locale))
        field.performImeAction()
        compose.runOnIdle { assertEquals("Retain the five-digit limit", 12345, state.value.cadenceValue) }
        field.assertTextContains(formatInteger(12345, locale))
        assertTextFits(field, GeistType.label20Mono.fontSize)

        val dates = compose.onNodeWithTag(ScheduleControlTags.DATE_WINDOW)
        dates.performScrollTo().assertFullyVisible().assertMinimumTouchTarget().performTouchInput { click() }
        selectMenuItem(text(R.string.schedule_date_window_past_complete_days_through_today))
        dates.performScrollTo().assertFullyVisible()
        assertTextFits(compose.onNode(hasText(text(R.string.schedule_date_window_past_complete_days_through_today)), useUnmergedTree = true))
        compose.runOnIdle { assertEquals(ScheduleDateWindow.PAST_COMPLETE_DAYS_THROUGH_TODAY, state.value.dateWindow) }
        listOf(R.string.schedule_increase_lookback_days, R.string.schedule_decrease_lookback_days).forEach { id ->
            compose.onNodeWithContentDescription(text(id)).performScrollTo().assertFullyVisible()
                .assertMinimumTouchTarget().performTouchInput { click() }
        }
        compose.runOnIdle { assertEquals(365, state.value.lookbackDays) }
        dates.performScrollTo().performTouchInput { click() }
        selectMenuItem(text(R.string.schedule_date_window_today))
        compose.onNodeWithTag(ScheduleControlTags.LOOKBACK).assertDoesNotExist()
    }

    @Test
    fun settingsGiveCopyRoomAndKeepOneLabeledProtectionToggle() {
        val enabled = mutableStateOf<Boolean?>(null)
        var blocked = 0
        var changed = 0
        var navigated = 0
        compose.setContent {
            TestViewport {
                Column(Modifier.fillMaxSize().background(AppColors.bgPrimary)
                    .verticalScroll(rememberScrollState()).padding(Spacing.md),
                    verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
                    ConfigurationProtectionSettingsCard(enabled.value, { enabled.value = it })
                    SettingsNavigationCard(
                        title = text(R.string.direct_cli_title), subtitle = text(R.string.settings_direct_cli_subtitle),
                        icon = Icons.Outlined.Computer, onClick = { navigated++ }, modifier = Modifier.testTag("settings.entry"),
                    )
                    CompositionLocalProvider(LocalConfigurationProtection provides ConfigurationProtectionUi(enabled.value == true, { blocked++ })) {
                        ConfigurationProtectedRegion(Modifier.fillMaxWidth()) {
                            TimeRow(6, 0, { changed++ }, { changed++ }, { changed++ }, use24HourTime = false)
                        }
                    }
                }
            }
        }
        val toggle = compose.onNodeWithTag(ConfigurationProtectionTestTags.TOGGLE)
        toggle.performScrollTo().assertIsNotEnabled()
        compose.runOnIdle { enabled.value = false }
        toggle.assertIsOff().assertMinimumTouchTarget()
        // Tapping the label side, not just the switch thumb, activates exactly one toggle.
        toggle.performTouchInput { click(Offset(width * 0.1f, height * 0.5f)) }
        toggle.assertIsOn()
        val explanation = compose.onNodeWithText(text(R.string.configuration_protection_description))
        explanation.performScrollTo()
        assertTextFits(explanation)
        val explanationBounds = explanation.getUnclippedBoundsInRoot()
        val toggleBounds = toggle.getUnclippedBoundsInRoot()
        assertEquals("The explanation is not narrowed by the switch",
            toggleBounds.right - toggleBounds.left, explanationBounds.right - explanationBounds.left)
        capture("settings-lock")

        compose.onNodeWithContentDescription(text(R.string.schedule_increase_hour)).assertDoesNotExist()
        compose.onNodeWithTag(ConfigurationProtectionTestTags.PROTECTED_REGION).performScrollTo()
            .assertFullyVisible().performTouchInput { click() }
        compose.runOnIdle { assertEquals(1, blocked); assertEquals(0, changed) }

        val subtitle = compose.onNodeWithText(text(R.string.settings_direct_cli_subtitle), useUnmergedTree = true)
        subtitle.performScrollTo()
        assertTextFits(subtitle)
        val card = compose.onNodeWithTag("settings.entry")
        card.assertHasClickAction().assertMinimumTouchTarget()
        if (GeistAdaptiveLayout.stackDetailedControls(display.width - 32f, display.fontScale)) {
            val textBounds = subtitle.getUnclippedBoundsInRoot()
            val cardBounds = card.getUnclippedBoundsInRoot()
            assertTrue("Entry descriptions use the full inner card width",
                textBounds.right - textBounds.left >= cardBounds.right - cardBounds.left - 33.dp)
        }
        capture("settings-entry")
        // A tall explanatory card may span the viewport; its visible title remains tappable.
        compose.onNodeWithText(text(R.string.direct_cli_title), useUnmergedTree = true)
            .performScrollTo().assertFullyVisible().performTouchInput { click() }
        compose.runOnIdle { assertEquals(1, navigated) }
        toggle.performScrollTo().performTouchInput { click() }
        toggle.assertIsOff()
        compose.onNodeWithContentDescription(text(R.string.schedule_increase_hour)).performScrollTo()
            .assertFullyVisible().performTouchInput { click() }
        compose.runOnIdle { assertEquals(1, changed); assertEquals(1, blocked) }
    }

    private fun selectMenuItem(label: String) {
        val itemMatcher = hasText(label) and hasClickAction() and hasAnyAncestor(isPopup())
        // The popup is a separate native owner and can attach just after the anchor action's
        // Compose-idle boundary, especially while a numeric IME is finishing its hide request.
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodes(itemMatcher).fetchSemanticsNodes(atLeastOneRootRequired = false).size == 1
        }
        val item = compose.onNode(itemMatcher)
        item.performScrollTo().assertIsDisplayed()
        assertTextFits(compose.onNode(hasText(label) and hasAnyAncestor(isPopup()), useUnmergedTree = true))
        item.performTouchInput { click() }
    }

    private fun assertTextFits(node: SemanticsNodeInteraction, expectedFontSize: TextUnit? = null) {
        val results = mutableListOf<TextLayoutResult>()
        node.performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        assertTrue("Expected measured text", results.isNotEmpty())
        val visibleWidth = node.fetchSemanticsNode().boundsInRoot.width
        results.forEach { result ->
            assertEquals("Respect the chosen font scale", display.fontScale, result.layoutInput.density.fontScale)
            if (expectedFontSize != null) assertEquals(expectedFontSize, result.layoutInput.style.fontSize)
            assertFalse("Text clips vertically", result.didOverflowHeight)
            repeat(result.lineCount) { line ->
                val width = result.getLineRight(line) - result.getLineLeft(line)
                assertTrue("Text clips horizontally: $width in $visibleWidth", width <= visibleWidth + 1f)
                assertFalse("Essential text must not be ellipsized", result.isLineEllipsized(line))
            }
        }
    }

    private fun SemanticsNodeInteraction.assertMinimumTouchTarget(): SemanticsNodeInteraction {
        val bounds = getUnclippedBoundsInRoot()
        assertTrue("Touch target narrower than 48 dp: $bounds", bounds.right - bounds.left >= 47.dp)
        assertTrue("Touch target shorter than 48 dp: $bounds", bounds.bottom - bounds.top >= 47.dp)
        return this
    }

    private fun capture(name: String) {
        if (InstrumentationRegistry.getArguments().getString("healthmd.captureAccessibility") != "true") return
        // A capture immediately after setContent can precede the first attached root,
        // especially when a physical device was asleep at the start of instrumentation.
        compose.waitUntil(timeoutMillis = 10_000) {
            compose.onAllNodesWithTag(VIEWPORT).fetchSemanticsNodes(atLeastOneRootRequired = false).size == 1
        }
        compose.waitForIdle()
        val directory = File(InstrumentationRegistry.getInstrumentation().targetContext.cacheDir, "accessibility-screenshots")
            .apply { mkdirs() }
        val filename = "${display.width}x${display.height}-${display.fontScale}-${display.language}-${display.dark}-$name.png"
        val bitmap = compose.onNodeWithTag(VIEWPORT).captureToImage().asAndroidBitmap()
        File(directory, filename).outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
    }

    private fun node(id: Int) = compose.onNode(hasText(text(id)) and hasClickAction())

    private fun tap(id: Int) {
        node(id).assertIsEnabled().assertFullyVisible().performTouchInput { click() }
    }

    private fun scrollAndTap(id: Int) {
        node(id).performScrollTo().assertIsEnabled().assertFullyVisible()
        assertTextDoesNotOverflow(id)
        node(id).performTouchInput { click() }
    }

    private fun assertTextDoesNotOverflow(id: Int) {
        val results = mutableListOf<TextLayoutResult>()
        compose.onNode(
            hasText(text(id)) and hasAnyAncestor(hasClickAction()),
            useUnmergedTree = true,
        ).performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(results) }
        assertTrue("Expected text layout for ${text(id)}", results.isNotEmpty())
        results.forEach { result ->
            assertFalse("Clipped label height: ${text(id)}", result.didOverflowHeight)
            // Compose 1.7 synthesizes a semantics paragraph using the available width,
            // which can exceed the measured text width even when every glyph fits.
            // Check each line's actual width rather than that paragraph constraint.
            repeat(result.lineCount) { line ->
                val lineWidth = result.getLineRight(line) - result.getLineLeft(line)
                assertTrue("Clipped label width: ${text(id)}", lineWidth <= result.size.width + 1f)
                assertFalse("Ellipsized label: ${text(id)}", result.isLineEllipsized(line))
            }
        }
    }

    private fun SemanticsNodeInteraction.assertFullyVisible(): SemanticsNodeInteraction {
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
}
