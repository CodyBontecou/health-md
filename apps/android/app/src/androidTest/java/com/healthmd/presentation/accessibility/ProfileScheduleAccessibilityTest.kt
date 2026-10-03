package com.healthmd.presentation.accessibility

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.UiDevice
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfilePendingExport
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.ConfigurationProtectionUi
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.schedule.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.Spacing
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.Parameterized
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId
import java.time.format.TextStyle
import java.util.Locale

/** Synthetic production UI only. No ViewModel, repository, scheduler, folder, or health access. */
@RunWith(Parameterized::class)
class ProfileScheduleAccessibilityTest(display: AccessibilityDisplayCase) : AccessibilityTestHarness(display) {
    companion object {
        private const val ID = "synthetic-profile"
        private const val LONG_NAME = "Synthetic weekly archive for a family with a long descriptive profile name"

        @JvmStatic
        @Parameterized.Parameters(name = "{0}")
        fun displays() = accessibilityDisplays()
    }

    @Test
    fun longRowSeparatesReadingEditDeleteAndOneLabeledToggle() {
        val entry = mutableStateOf(sampleEntry().copy(cadenceValue = Int.MAX_VALUE, todayRefreshEnabled = true))
        val actions = mutableListOf<String>()
        setContent {
            Column(Modifier.fillMaxSize().background(AppColors.bgPrimary)
                .verticalScroll(rememberScrollState()).padding(Spacing.md)) {
                ProfileScheduleRowContent(
                    ProfileScheduleRow(sampleProfile(), entry.value),
                    onToggle = { actions += "toggle:$it"; entry.value = entry.value.copy(isEnabled = it) },
                    onOpenEditor = { actions += "edit" }, onDelete = { actions += "delete" },
                )
            }
        }
        val row = compose.onNodeWithTag(ProfileScheduleTags.ROW)
        row.assert(SemanticsMatcher.keyNotDefined(SemanticsActions.OnClick))
        listOf(ProfileScheduleTags.NAME to GeistType.copy16.fontSize,
            ProfileScheduleTags.SUMMARY to GeistType.copy13.fontSize).forEach { (tag, size) ->
            val copy = compose.onNodeWithTag(tag, useUnmergedTree = true).performScrollTo()
            assertTextFits(copy, size)
            assertEquals("Text gets the full row width, not the space left by three actions",
                width(row), width(copy))
        }
        val summary = cadenceSummary(entry.value, text(R.string.profile_schedule_refresh_summary, 3))
        compose.onNodeWithTag(ProfileScheduleTags.SUMMARY).assertTextEquals(summary)
        compose.onNodeWithTag(ProfileScheduleTags.NAME).performScrollTo()
        capture("profiles-rows")

        val edit = compose.onNodeWithTag(ProfileScheduleTags.EDIT).performScrollTo()
        edit.assertMinimumTouchTarget().assertFullyVisible().assertRole(Role.Button)
        assertActionTextFits(ProfileScheduleTags.EDIT, text(R.string.a11y_profiles_edit))
        edit.performTouchInput { click() }
        val toggle = compose.onNodeWithTag(ProfileScheduleTags.TOGGLE).performScrollTo()
        toggle.assertRole(Role.Switch).assertIsOn().assertTextContains(text(R.string.enabled))
            .assertContentDescriptionEquals(text(R.string.a11y_profiles_schedule_named, LONG_NAME))
            .assertMinimumTouchTarget().assertFullyVisible()
        compose.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch)).assertCountEquals(1)
        assertActionTextFits(ProfileScheduleTags.TOGGLE, text(R.string.enabled), GeistType.copy14.fontSize)
        // Label edge and switch edge both hit the same single target, in LTR and RTL.
        toggle.performTouchInput { click(Offset(width * 0.1f, height * 0.2f)) }
        toggle.assertIsOff()
        toggle.performScrollTo().performTouchInput { click(Offset(width * 0.9f, height * 0.8f)) }
        toggle.assertIsOn()
        val delete = compose.onNodeWithTag(ProfileScheduleTags.DELETE).performScrollTo()
        delete.assertMinimumTouchTarget().assertFullyVisible().assertRole(Role.Button)
        assertActionTextFits(ProfileScheduleTags.DELETE, text(R.string.a11y_profiles_delete))
        delete.performTouchInput { click() }
        assertEquals(listOf("edit", "toggle:false", "toggle:true", "delete"), actions)
        val editBounds = edit.getUnclippedBoundsInRoot()
        val deleteBounds = delete.getUnclippedBoundsInRoot()
        assertTrue("Edit and Delete do not overlap", editBounds.bottom <= deleteBounds.top ||
            deleteBounds.bottom <= editBounds.top || editBounds.right <= deleteBounds.left || deleteBounds.right <= editBounds.left)
    }

    @Test
    fun boundedProductionDialogBodyKeepsTitleLabelsAndActionsScrollable() {
        val draft = mutableStateOf(sampleEntry().copy(todayRefreshEnabled = true))
        val changes = mutableListOf<ScheduledProfileEntry>()
        var saves = 0
        var cancels = 0
        setContent {
            ProfileScheduleDialogContent(
                title = LONG_NAME, confirmLabel = text(R.string.a11y_profiles_save),
                onConfirm = { saves++ }, onDismiss = { cancels++ }, tag = ProfileScheduleTags.DIALOG,
            ) {
                ProfileScheduleEditorFields(draft.value, { changes += it; draft.value = it })
            }
        }
        val title = compose.onNodeWithTag(ProfileScheduleTags.TITLE, useUnmergedTree = true).scrollIfPossible()
        assertTextFits(title, GeistType.heading20.fontSize)
        compose.onAllNodes(SemanticsMatcher.expectValue(SemanticsProperties.Role, Role.Switch)).assertCountEquals(2)
        listOf(ProfileScheduleTags.ENABLED, ProfileScheduleTags.REFRESH).forEach { tag ->
            val toggle = compose.onNodeWithTag(tag).scrollIfPossible()
            toggle.assertRole(Role.Switch).assertIsOn().assertMinimumTouchTarget().assertFullyVisible()
            toggle.performTouchInput { click(Offset(width * 0.1f, height * 0.2f)) }
            toggle.assertIsOff()
            toggle.performTouchInput { click() }
            toggle.assertIsOn()
        }
        assertEquals("Each tap makes exactly one draft change", 4, changes.size)
        assertEquals(listOf(false, true), changes.take(2).map { it.isEnabled })
        assertEquals(listOf(false, true), changes.takeLast(2).map { it.todayRefreshEnabled })

        listOf(
            R.string.a11y_profiles_cadence_unit, R.string.a11y_profiles_weekday,
            R.string.a11y_profiles_hour, R.string.a11y_profiles_minute, R.string.a11y_profiles_lookback,
            R.string.a11y_profiles_every_weeks, R.string.profile_schedule_refresh_interval,
        ).forEach { id ->
            val label = compose.onNode(hasText(text(id)) and hasAnyAncestor(hasTestTag(ProfileScheduleTags.BODY)),
                useUnmergedTree = true).scrollIfPossible()
            assertTextFits(label, GeistType.copy16.fontSize)
        }
        listOf(ProfileScheduleTags.HOUR, ProfileScheduleTags.MINUTE, ProfileScheduleTags.LOOKBACK,
            ProfileScheduleTags.EVERY).forEach { tag ->
            val field = compose.onNodeWithTag(tag).scrollIfPossible()
            field.assertFullyVisible().assertMinimumTouchTarget()
            assertTextFits(field, GeistType.label20Mono.fontSize)
        }
        listOf(ProfileScheduleTags.SAVE to R.string.a11y_profiles_save, ProfileScheduleTags.CANCEL to R.string.cancel)
            .forEach { (tag, label) ->
                val action = compose.onNodeWithTag(tag).scrollIfPossible()
                action.assertFullyVisible().assertMinimumTouchTarget().assertRole(Role.Button)
                assertActionTextFits(tag, text(label))
                action.performTouchInput { click() }
            }
        assertEquals(1, saves)
        assertEquals(1, cancels)
        assertEquals(sampleEntry().copy(todayRefreshEnabled = true), draft.value)
    }

    @Test
    fun nativeCadenceWeekdayAndTodayRefreshMenusRetainFullScaleAndExactChoices() {
        val initial = sampleEntry().copy(cadenceUnit = ScheduledProfileCadenceUnit.DAY, todayRefreshEnabled = false)
        val saved = mutableListOf<ScheduledProfileEntry>()
        setContent {
            ProfileCadenceEditorDialog(ID, LONG_NAME, initial, { saved += it }, {})
        }
        val title = compose.onNodeWithTag(ProfileScheduleTags.TITLE, useUnmergedTree = true).scrollIfPossible()
        assertTextFits(title, GeistType.heading20.fontSize)
        assertAnchorLocals(title)
        captureContent("profiles-editor-title", ProfileScheduleTags.DIALOG)
        listOf(R.string.a11y_profiles_months, R.string.a11y_profiles_days, R.string.a11y_profiles_weeks).forEach {
            selectNativeOption(ProfileScheduleTags.CADENCE_UNIT, text(it))
        }
        val locale = Locale.forLanguageTag(display.language)
        (1..7).forEach { iso ->
            selectNativeOption(ProfileScheduleTags.WEEKDAY, DayOfWeek.of(iso).getDisplayName(TextStyle.FULL, locale),
                captureName = if (iso == 7) "profiles-weekday-menu" else null)
        }
        val refresh = compose.onNodeWithTag(ProfileScheduleTags.REFRESH).scrollIfPossible()
        refresh.assertRole(Role.Switch).assertIsOff().assertMinimumTouchTarget().assertInNativeOwner()
            .performTouchInput { click(Offset(width * 0.1f, height * 0.2f)) }
        refresh.assertIsOn()
        ScheduledProfileEntry.TODAY_REFRESH_INTERVAL_OPTIONS.forEach { hours ->
            selectNativeOption(ProfileScheduleTags.REFRESH_INTERVAL,
                text(R.string.profile_schedule_refresh_interval_hours, hours),
                captureName = if (hours == 12) "profiles-refresh-menu" else null)
        }
        captureContent("profiles-editor-refresh", ProfileScheduleTags.DIALOG)
        tapNativeAction(ProfileScheduleTags.SAVE, text(R.string.a11y_profiles_save))
        assertEquals(listOf(initial.copy(cadenceUnit = ScheduledProfileCadenceUnit.WEEK, weekdayIso = 7,
            todayRefreshEnabled = true, todayRefreshIntervalHours = 12)), saved)
    }

    @Test
    fun profileNumbersKeepTheirOwnBoundsFullIntRangeAndPriorValidDraftOnInvalidInput() {
        val initial = sampleEntry()
        val draft = mutableStateOf(initial)
        val saved = mutableListOf<ScheduledProfileEntry>()
        setContent {
            ProfileScheduleDialogContent(
                title = LONG_NAME, confirmLabel = text(R.string.a11y_profiles_save),
                onConfirm = { saved += draft.value }, onDismiss = {}, tag = ProfileScheduleTags.DIALOG,
            ) { ProfileScheduleEditorFields(draft.value, { draft.value = it }) }
        }
        replace(ProfileScheduleTags.HOUR, "99")
        compose.runOnIdle { assertEquals(23, draft.value.hour) }
        replace(ProfileScheduleTags.HOUR, "-7")
        compose.runOnIdle { assertEquals(0, draft.value.hour) }
        replace(ProfileScheduleTags.HOUR, "19")
        replace(ProfileScheduleTags.MINUTE, "99")
        compose.runOnIdle { assertEquals(59, draft.value.minute) }
        replace(ProfileScheduleTags.MINUTE, "-8")
        compose.runOnIdle { assertEquals(0, draft.value.minute) }
        replace(ProfileScheduleTags.MINUTE, "37")
        replace(ProfileScheduleTags.LOOKBACK, "99")
        compose.runOnIdle { assertEquals(30, draft.value.lookbackDays) }
        replace(ProfileScheduleTags.LOOKBACK, "-2")
        compose.runOnIdle { assertEquals(1, draft.value.lookbackDays) }
        replace(ProfileScheduleTags.LOOKBACK, "17")
        replace(ProfileScheduleTags.EVERY, "0")
        compose.runOnIdle { assertEquals(1, draft.value.cadenceValue) }
        replace(ProfileScheduleTags.EVERY, "-2147483648")
        compose.runOnIdle { assertEquals(1, draft.value.cadenceValue) }
        replace(ProfileScheduleTags.EVERY, "123456")
        compose.runOnIdle { assertEquals("The profile does NOT inherit the legacy five-digit cap", 123456, draft.value.cadenceValue) }
        replace(ProfileScheduleTags.EVERY, Int.MAX_VALUE.toString())
        compose.runOnIdle { assertEquals(Int.MAX_VALUE, draft.value.cadenceValue) }
        assertTextFits(compose.onNodeWithTag(ProfileScheduleTags.EVERY), GeistType.label20Mono.fontSize)
        val expected = initial.copy(hour = 19, minute = 37, lookbackDays = 17, cadenceValue = Int.MAX_VALUE)
        listOf(ProfileScheduleTags.HOUR, ProfileScheduleTags.MINUTE, ProfileScheduleTags.LOOKBACK,
            ProfileScheduleTags.EVERY).forEach { tag ->
            listOf("2147483648", "not a number", "").forEach { raw ->
                replace(tag, raw)
                compose.onNodeWithTag(tag).performImeAction()
                compose.runOnIdle { assertEquals("Invalid/empty input and Done keep the prior valid entry", expected, draft.value) }
            }
        }
        assertTrue("Draft changes do not save automatically", saved.isEmpty())
        compose.onNodeWithTag(ProfileScheduleTags.SAVE).scrollIfPossible().assertFullyVisible()
            .performTouchInput { click() }
        assertEquals(listOf(expected), saved)
    }

    @Test
    fun nativeSaveReachesTheLastFocusedNumberAndPreservesEveryOtherEntryField() {
        val initial = sampleEntry().copy(todayRefreshEnabled = false)
        val saved = mutableListOf<ScheduledProfileEntry>()
        val open = mutableStateOf(true)
        var dismisses = 0
        setContent {
            if (open.value) ProfileCadenceEditorDialog(ID, LONG_NAME, initial,
                onSave = { saved += it; open.value = false }, onDismiss = { dismisses++; open.value = false })
        }
        val last = compose.onNodeWithTag(ProfileScheduleTags.EVERY).scrollIfPossible()
        last.assertMinimumTouchTarget().assertInNativeOwner().performTouchInput { click() }
        last.assertIsFocused().performTextReplacement(Int.MAX_VALUE.toString())
        last.scrollIfPossible().assertInNativeOwner()
        assertAnchorLocals(last)
        assertTextFits(last, GeistType.label20Mono.fontSize)
        // No Done/focus-clear prerequisite: Save remains scroll-reachable with the field focused.
        tapNativeAction(ProfileScheduleTags.SAVE, text(R.string.a11y_profiles_save))
        compose.onNodeWithTag(ProfileScheduleTags.DIALOG).assertDoesNotExist()
        assertEquals(listOf(initial.copy(cadenceValue = Int.MAX_VALUE)), saved)
        assertEquals(0, dismisses)
    }

    @Test
    fun nativeCancelAndBackDismissWithoutSavingDraftEdits() {
        val initial = sampleEntry()
        val open = mutableStateOf(true)
        val saved = mutableListOf<ScheduledProfileEntry>()
        var dismisses = 0
        setContent {
            if (open.value) ProfileCadenceEditorDialog(ID, LONG_NAME, initial,
                onSave = { saved += it }, onDismiss = { dismisses++; open.value = false })
        }
        replace(ProfileScheduleTags.EVERY, "123456")
        compose.onNodeWithTag(ProfileScheduleTags.EVERY).performImeAction()
        compose.onNodeWithTag(ProfileScheduleTags.EVERY).assertIsNotFocused()
        tapNativeAction(ProfileScheduleTags.CANCEL, text(R.string.cancel))
        compose.onNodeWithTag(ProfileScheduleTags.DIALOG).assertDoesNotExist()
        assertEquals(1, dismisses)
        compose.runOnIdle { open.value = true }
        val restored = compose.onNodeWithTag(ProfileScheduleTags.EVERY).scrollIfPossible()
        restored.assertTextEquals(initial.cadenceValue.toString())
        replace(ProfileScheduleTags.EVERY, "")
        compose.onNodeWithTag(ProfileScheduleTags.EVERY).performImeAction()
        compose.onNodeWithTag(ProfileScheduleTags.EVERY).assertIsNotFocused()
        captureContent("profiles-editor-cancel", ProfileScheduleTags.DIALOG)
        // Espresso selects the activity root even while this separate native dialog owns focus.
        // Inject the real system Back key without requiring the obscured activity window to focus.
        UiDevice.getInstance(InstrumentationRegistry.getInstrumentation()).pressBack()
        compose.waitForIdle()
        compose.onNodeWithTag(ProfileScheduleTags.DIALOG).assertDoesNotExist()
        assertEquals(2, dismisses)
        assertTrue(saved.isEmpty())
    }

    @Test
    fun openEditorAndDeleteConfirmationStillUseLiveProtectionWrappers() {
        val state = mutableStateOf(ProfileSchedulesUiState(listOf(ProfileScheduleRow(sampleProfile(), sampleEntry()))))
        val protectionEnabled = mutableStateOf(false)
        val actions = mutableListOf<String>()
        setContent { TestSection(state, protectionEnabled, actions) }
        tapRow(ProfileScheduleTags.EDIT)
        compose.runOnIdle { protectionEnabled.value = true }
        tapNativeAction(ProfileScheduleTags.SAVE, text(R.string.a11y_profiles_save))
        compose.onNodeWithTag(ProfileScheduleTags.DIALOG).assertDoesNotExist()
        assertEquals(listOf("editor:$ID", "editor:null", "blocked"), actions)

        compose.runOnIdle { protectionEnabled.value = false }
        tapRow(ProfileScheduleTags.DELETE)
        val title = compose.onNodeWithTag(ProfileScheduleTags.TITLE, useUnmergedTree = true).scrollIfPossible()
        assertTextFits(title, GeistType.heading20.fontSize)
        val message = compose.onNodeWithText(text(R.string.a11y_profiles_delete_body), useUnmergedTree = true).scrollIfPossible()
        assertTextFits(message, GeistType.copy14.fontSize)
        captureContent("profiles-delete-confirmation", ProfileScheduleTags.DELETE_DIALOG)
        compose.runOnIdle { protectionEnabled.value = true }
        tapNativeAction(ProfileScheduleTags.SAVE, text(R.string.a11y_profiles_delete))
        compose.onNodeWithTag(ProfileScheduleTags.DELETE_DIALOG).assertDoesNotExist()
        assertEquals(listOf("editor:$ID", "editor:null", "blocked", "blocked"), actions)

        compose.runOnIdle { protectionEnabled.value = false }
        tapRow(ProfileScheduleTags.EDIT)
        compose.runOnIdle { protectionEnabled.value = true }
        tapNativeAction(ProfileScheduleTags.CANCEL, text(R.string.cancel))
        assertEquals(listOf("editor:$ID", "editor:null", "blocked", "blocked", "editor:$ID", "editor:null"), actions)
        assertEquals("No rejected draft/toggle/delete altered the synthetic entry", sampleEntry(), state.value.rows.single().entry)
        compose.runOnIdle { protectionEnabled.value = false }
        tapRow(ProfileScheduleTags.DELETE)
        compose.runOnIdle { protectionEnabled.value = true }
        tapNativeAction(ProfileScheduleTags.CANCEL, text(R.string.cancel))
        compose.onNodeWithTag(ProfileScheduleTags.DELETE_DIALOG).assertDoesNotExist()
        assertEquals("Cancel is still allowed while protected", 6, actions.size)
    }

    @Test
    fun protectedRowsBlockPointerTargetsAndAllowedActionsStillDispatchOnce() {
        val state = mutableStateOf(ProfileSchedulesUiState(listOf(ProfileScheduleRow(sampleProfile(), sampleEntry()))))
        val protectionEnabled = mutableStateOf(true)
        val actions = mutableListOf<String>()
        setContent { TestSection(state, protectionEnabled, actions) }
        listOf(ProfileScheduleTags.EDIT, ProfileScheduleTags.TOGGLE, ProfileScheduleTags.DELETE,
            ProfileScheduleTags.ADD).forEach { tag ->
            // Unmerged geometry reaches the real child coordinates under the production overlay.
            compose.onNodeWithTag(tag, useUnmergedTree = true).scrollIfPossible().assertFullyVisible()
                .performTouchInput { click() }
        }
        assertEquals(List(4) { "blocked" }, actions)
        compose.onNodeWithTag(ProfileScheduleTags.DIALOG).assertDoesNotExist()
        compose.onNodeWithTag(ProfileScheduleTags.DELETE_DIALOG).assertDoesNotExist()
        compose.runOnIdle { protectionEnabled.value = false }
        tapRow(ProfileScheduleTags.TOGGLE)
        tapRow(ProfileScheduleTags.ADD)
        tapRow(ProfileScheduleTags.DELETE)
        tapNativeAction(ProfileScheduleTags.CANCEL, text(R.string.cancel))
        assertEquals(List(4) { "blocked" } + listOf("toggle:false", "add"), actions)
        tapRow(ProfileScheduleTags.DELETE)
        tapNativeAction(ProfileScheduleTags.SAVE, text(R.string.a11y_profiles_delete))
        assertEquals(List(4) { "blocked" } + listOf("toggle:false", "add", "delete:$ID"), actions)
        assertEquals(sampleEntry().copy(isEnabled = false), state.value.rows.single().entry)
        tapRow(ProfileScheduleTags.EDIT)
        tapNativeAction(ProfileScheduleTags.SAVE, text(R.string.a11y_profiles_save))
        assertEquals(List(4) { "blocked" } + listOf("toggle:false", "add", "delete:$ID", "editor:$ID", "save"), actions)
        // The last-profile refusal remains the ViewModel/coordinator's responsibility, not a UI rule.
    }

    @Test
    fun newDraftDefaultsAndBlankProfileSaveGuardRemainUnchanged() {
        val id = mutableStateOf("")
        val saved = mutableListOf<ScheduledProfileEntry>()
        val startDay = LocalDate.now().toEpochDay()
        setContent { ProfileCadenceEditorDialog(id.value, LONG_NAME, null, { saved += it }, {}) }
        compose.onNodeWithTag(ProfileScheduleTags.SAVE).scrollIfPossible().assertIsNotEnabled()
        compose.runOnIdle { id.value = ID }
        tapNativeAction(ProfileScheduleTags.SAVE, text(R.string.a11y_profiles_save))
        val result = saved.single()
        assertTrue(result.anchorEpochDay in startDay..LocalDate.now().toEpochDay())
        assertEquals(ScheduledProfileEntry(ID, isEnabled = true, anchorEpochDay = result.anchorEpochDay,
            zoneId = ZoneId.systemDefault().id), result)
    }

    @Composable
    private fun TestSection(
        state: MutableState<ProfileSchedulesUiState>,
        protectionEnabled: MutableState<Boolean>,
        actions: MutableList<String>,
    ) {
        CompositionLocalProvider(LocalConfigurationProtection provides ConfigurationProtectionUi(
            protectionEnabled.value, { actions += "blocked" },
        )) {
            Column(Modifier.fillMaxSize().background(AppColors.bgPrimary)
                .verticalScroll(rememberScrollState()).padding(Spacing.md)) {
                ProfileSchedulesContent(
                    uiState = state.value,
                    onToggle = { _, enabled ->
                        actions += "toggle:$enabled"
                        state.value = state.value.copy(rows = state.value.rows.map {
                            it.copy(entry = it.entry!!.copy(isEnabled = enabled))
                        })
                    },
                    onOpenEditor = { actions += "editor:$it"; state.value = state.value.copy(editingProfileId = it) },
                    onDeleteProfile = { actions += "delete:$it" }, onAddProfile = { actions += "add" },
                    onSaveEntry = { actions += "save"; state.value = state.value.copy(editingProfileId = null) },
                )
            }
        }
    }

    private fun sampleProfile() = ExportProfile(
        id = ID, name = LONG_NAME, settingsSnapshotJson = "{}", target = ExportTarget.DEVICE_FOLDER,
        createdAtEpochMillis = 1, updatedAtEpochMillis = 2,
    )

    private fun sampleEntry() = ScheduledProfileEntry(
        profileId = ID, isEnabled = true, anchorEpochDay = 20_000, weekdayIso = 3, hour = 8, minute = 12,
        cadenceValue = 2, cadenceUnit = ScheduledProfileCadenceUnit.WEEK, lookbackDays = 7,
        zoneId = "UTC", lastSuccessEpochMillis = 11, lastRefreshSuccessEpochMillis = 12,
        pendingExports = listOf(ScheduledProfilePendingExport(
            id = "synthetic-pending", ownerEpochDays = listOf(19_999), fireAtMillis = 10,
            settingsSnapshotJson = "{}", target = ExportTarget.DEVICE_FOLDER, profileName = LONG_NAME,
        )),
    )

    private fun replace(tag: String, raw: String) {
        compose.onNodeWithTag(tag).scrollIfPossible().performTouchInput { click() }
        compose.onNodeWithTag(tag).performTextReplacement(raw)
    }

    private fun tapRow(tag: String) {
        compose.onNodeWithTag(tag).scrollIfPossible().assertFullyVisible().assertMinimumTouchTarget()
            .performTouchInput { click() }
    }

    private fun tapNativeAction(tag: String, label: String) {
        val action = compose.onNodeWithTag(tag).scrollIfPossible()
        action.assertMinimumTouchTarget().assertInNativeOwner().assertRole(Role.Button)
        assertActionTextFits(tag, label)
        action.performTouchInput { click() }
    }

    private fun selectNativeOption(tag: String, label: String, captureName: String? = null) {
        compose.onNodeWithTag(tag).scrollIfPossible().assertMinimumTouchTarget().assertInNativeOwner()
            .performTouchInput { click() }
        val item = compose.onNode(hasText(label) and hasClickAction() and hasAnyAncestor(isPopup()))
            .scrollIfPossible().assertMinimumTouchTarget().assertInNativeOwner()
        val copy = compose.onNode(hasText(label) and hasAnyAncestor(isPopup()), useUnmergedTree = true)
        assertTextFits(copy, GeistType.button14.fontSize)
        assertAnchorLocals(copy)
        if (captureName != null) captureContent(captureName, tag + ProfileScheduleTags.MENU)
        item.performTouchInput { click() }
        compose.onNodeWithTag(tag + ProfileScheduleTags.MENU).assertDoesNotExist()
        val selected = compose.onNode(hasText(label) and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true)
            .scrollIfPossible()
        assertTextFits(selected, GeistType.copy16.fontSize)
    }

    private fun captureContent(name: String, tag: String) {
        compose.mainClock.advanceTimeBy(400)
        compose.waitForIdle()
        capture(name, compose.onNodeWithTag(tag))
    }

    private fun assertActionTextFits(tag: String, label: String,
        fontSize: androidx.compose.ui.unit.TextUnit = GeistType.button14.fontSize) {
        val copy = compose.onNode(hasText(label) and hasAnyAncestor(hasTestTag(tag)), useUnmergedTree = true)
        assertTextFits(copy, fontSize)
    }

    private fun SemanticsNodeInteraction.assertRole(role: Role) =
        assert(SemanticsMatcher.expectValue(SemanticsProperties.Role, role))

    private fun SemanticsNodeInteraction.scrollIfPossible(): SemanticsNodeInteraction {
        if (generateSequence(fetchSemanticsNode().parent) { it.parent }
                .any { it.config.contains(SemanticsActions.ScrollBy) }) performScrollTo()
        return this
    }

    private fun width(node: SemanticsNodeInteraction) = node.getUnclippedBoundsInRoot().let { it.right - it.left }

    private fun assertAnchorLocals(node: SemanticsNodeInteraction) {
        val anchor = compose.onNodeWithTag(VIEWPORT).fetchSemanticsNode().layoutInfo
        val layout = node.fetchSemanticsNode().layoutInfo
        assertEquals(anchor.density.density, layout.density.density)
        assertEquals(display.fontScale, layout.density.fontScale)
        assertEquals(if (display.language == "ar") LayoutDirection.Rtl else LayoutDirection.Ltr, layout.layoutDirection)
    }

    /** Compare physical pixels within THIS native owner, never against the embedded VIEWPORT. */
    private fun SemanticsNodeInteraction.assertInNativeOwner(): SemanticsNodeInteraction {
        assertIsDisplayed()
        val node = fetchSemanticsNode()
        val owner = generateSequence(node) { it.parent }.last().boundsInRoot
        val density = node.layoutInfo.density.density
        val bounds = getUnclippedBoundsInRoot().let {
            Rect(it.left.value * density, it.top.value * density, it.right.value * density, it.bottom.value * density)
        }
        assertTrue("Native control has size: $bounds", bounds.width > 0 && bounds.height > 0)
        assertTrue("Native control is clipped: $bounds in $owner",
            bounds.left >= owner.left - 1 && bounds.right <= owner.right + 1 &&
                bounds.top >= owner.top - 1 && bounds.bottom <= owner.bottom + 1)
        return this
    }
}
