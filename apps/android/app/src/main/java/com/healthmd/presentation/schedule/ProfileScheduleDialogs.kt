package com.healthmd.presentation.schedule

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.*
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.theme.*
import java.time.DayOfWeek
import java.time.format.TextStyle

@Composable
internal fun ProfileCadenceEditorDialog(
    profileId: String,
    profileName: String,
    entry: ScheduledProfileEntry?,
    onSave: (ScheduledProfileEntry) -> Unit,
    onDismiss: () -> Unit,
) {
    var draft by remember(entry, profileId) {
        mutableStateOf(
            entry ?: ScheduledProfileEntry(
                profileId = profileId,
                isEnabled = true,
                anchorEpochDay = java.time.LocalDate.now().toEpochDay(),
                zoneId = java.time.ZoneId.systemDefault().id,
            ),
        )
    }
    ProfileScheduleDialog(onDismiss) {
        ProfileScheduleDialogContent(
            title = profileName,
            confirmLabel = stringResource(R.string.a11y_profiles_save),
            onConfirm = { onSave(draft) }, onDismiss = onDismiss,
            confirmEnabled = draft.profileId.isNotBlank(),
            tag = ProfileScheduleTags.DIALOG,
        ) {
            ProfileScheduleEditorFields(draft = draft, onDraftChange = { draft = it })
        }
    }
}

/** Stateless real editor fields; clamps stay identical to the original profile UI. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ProfileScheduleEditorFields(
    draft: ScheduledProfileEntry,
    onDraftChange: (ScheduledProfileEntry) -> Unit,
) {
    ProfileScheduleToggle(
        stringResource(R.string.enabled), draft.isEnabled,
        { onDraftChange(draft.copy(isEnabled = it)) }, Modifier.testTag(ProfileScheduleTags.ENABLED),
    )
    ProfileScheduleDropdown(
        draft.cadenceUnit,
        listOf(
            ScheduledProfileCadenceUnit.DAY to stringResource(R.string.a11y_profiles_days),
            ScheduledProfileCadenceUnit.WEEK to stringResource(R.string.a11y_profiles_weeks),
            ScheduledProfileCadenceUnit.MONTH to stringResource(R.string.a11y_profiles_months),
        ),
        stringResource(R.string.a11y_profiles_cadence_unit),
        { onDraftChange(draft.copy(cadenceUnit = it)) }, ProfileScheduleTags.CADENCE_UNIT,
    )
    if (draft.cadenceUnit == ScheduledProfileCadenceUnit.WEEK) {
        val locale = LocalConfiguration.current.locales[0]
        ProfileScheduleDropdown(
            draft.weekdayIso,
            (1..7).map { it to DayOfWeek.of(it).getDisplayName(TextStyle.FULL, locale) },
            stringResource(R.string.a11y_profiles_weekday),
            { onDraftChange(draft.copy(weekdayIso = it)) }, ProfileScheduleTags.WEEKDAY,
        )
    }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = GeistAdaptiveLayout.stackActions(maxWidth.value, LocalDensity.current.fontScale)
        // Reflow without moving the fields to another composition (keep draft text and focus).
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
            maxItemsInEachRow = if (stacked) 1 else 2,
        ) {
            ProfileScheduleNumberField(
                stringResource(R.string.a11y_profiles_hour), draft.hour,
                { onDraftChange(draft.copy(hour = it.coerceIn(0, 23))) }, ProfileScheduleTags.HOUR,
                if (stacked) Modifier.fillMaxWidth() else Modifier.weight(1f),
            )
            ProfileScheduleNumberField(
                stringResource(R.string.a11y_profiles_minute), draft.minute,
                { onDraftChange(draft.copy(minute = it.coerceIn(0, 59))) }, ProfileScheduleTags.MINUTE,
                if (stacked) Modifier.fillMaxWidth() else Modifier.weight(1f),
            )
        }
    }
    ProfileScheduleNumberField(
        stringResource(R.string.a11y_profiles_lookback), draft.lookbackDays,
        { onDraftChange(draft.copy(lookbackDays = it.coerceIn(1, 30))) }, ProfileScheduleTags.LOOKBACK,
    )
    ProfileScheduleNumberField(
        stringResource(when (draft.cadenceUnit) {
            ScheduledProfileCadenceUnit.DAY -> R.string.a11y_profiles_every_days
            ScheduledProfileCadenceUnit.WEEK -> R.string.a11y_profiles_every_weeks
            ScheduledProfileCadenceUnit.MONTH -> R.string.a11y_profiles_every_months
        }),
        draft.cadenceValue,
        { onDraftChange(draft.copy(cadenceValue = it.coerceAtLeast(1))) }, ProfileScheduleTags.EVERY,
    )
    ProfileScheduleToggle(
        stringResource(R.string.profile_schedule_today_refresh), draft.todayRefreshEnabled,
        { onDraftChange(draft.copy(todayRefreshEnabled = it)) }, Modifier.testTag(ProfileScheduleTags.REFRESH),
    )
    if (draft.todayRefreshEnabled) {
        ProfileScheduleDropdown(
            draft.todayRefreshIntervalHours,
            ScheduledProfileEntry.TODAY_REFRESH_INTERVAL_OPTIONS.map { hours ->
                hours to stringResource(R.string.profile_schedule_refresh_interval_hours, hours)
            },
            stringResource(R.string.profile_schedule_refresh_interval),
            { onDraftChange(draft.copy(todayRefreshIntervalHours = it)) }, ProfileScheduleTags.REFRESH_INTERVAL,
        )
    }
}

@Composable
internal fun ProfileScheduleDeleteDialog(
    profileName: String,
    onDelete: () -> Unit,
    onDismiss: () -> Unit,
) {
    ProfileScheduleDialog(onDismiss) {
        ProfileScheduleDialogContent(
            title = stringResource(R.string.a11y_profiles_delete_title, profileName),
            confirmLabel = stringResource(R.string.a11y_profiles_delete),
            onConfirm = onDelete, onDismiss = onDismiss, tag = ProfileScheduleTags.DELETE_DIALOG,
            destructive = true,
        ) {
            Text(stringResource(R.string.a11y_profiles_delete_body),
                style = MaterialTheme.typography.bodyMedium, color = AppColors.textPrimary,
                modifier = Modifier.fillMaxWidth())
        }
    }
}

/** Separate native window with unchanged anchor locals; no display/font setting overrides. */
@Composable
private fun ProfileScheduleDialog(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val configuration = LocalConfiguration.current
    val context = LocalContext.current
    Dialog(onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        CompositionLocalProvider(
            LocalDensity provides density, LocalLayoutDirection provides direction,
            LocalConfiguration provides configuration, LocalContext provides context,
        ) {
            BoxWithConstraints(
                Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).imePadding(),
                contentAlignment = Alignment.Center,
            ) {
                // Respect both this native owner's available area (including IME) and the
                // anchor configuration. Synthetic embedded viewports are not native windows.
                val availableHeight = minOf(maxHeight, configuration.screenHeightDp.dp)
                val availableWidth = minOf(maxWidth, configuration.screenWidthDp.dp)
                Box(
                    Modifier.widthIn(max = availableWidth).fillMaxWidth()
                        .padding(horizontal = GeistSpacing.space4),
                    contentAlignment = Alignment.Center,
                ) {
                    Surface(
                        modifier = Modifier.widthIn(max = GeistBreakpoints.medium.dp).fillMaxWidth()
                            .heightIn(max = minOf(
                                availableHeight * GeistSizes.dialogMaxHeightFraction,
                                (availableHeight - GeistSpacing.space10 * 2).coerceAtLeast(GeistSizes.minimumTouchTarget),
                            )),
                        shape = RoundedCornerShape(GeistRadii.medium), color = AppColors.bgPrimary,
                        border = BorderStroke(1.dp, AppColors.borderDefault), tonalElevation = 0.dp,
                    ) { content() }
                }
            }
        }
    }
}

/**
 * Fixed header/footer and scrolling form when there is reading room. Short/IME windows or an
 * unusually long title scroll the same composition as a whole instead of clipping title/actions
 * or leaving a zero-height form. Changing only modifiers retains field state and keyboard focus.
 */
@Composable
internal fun ProfileScheduleDialogContent(
    title: String,
    confirmLabel: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
    tag: String,
    confirmEnabled: Boolean = true,
    destructive: Boolean = false,
    body: @Composable ColumnScope.() -> Unit,
) {
    val density = LocalDensity.current
    val measurer = rememberTextMeasurer()
    val titleStyle = MaterialTheme.typography.headlineSmall
    val wholeScroll = rememberScrollState()
    val bodyScroll = rememberScrollState()
    BoxWithConstraints(Modifier.fillMaxWidth().testTag(tag)) {
        val titleHeight = with(density) {
            measurer.measure(title, titleStyle, constraints = Constraints(
                maxWidth = (maxWidth - Spacing.md * 2).roundToPx().coerceAtLeast(1),
            )).size.height.toDp()
        }
        val scrollTogether = maxHeight.value / density.fontScale < GeistBreakpoints.small ||
            titleHeight + Spacing.md * 2 > maxHeight / 3
        Column(Modifier.fillMaxWidth().then(if (scrollTogether) Modifier.verticalScroll(wholeScroll) else Modifier)) {
            Text(title, style = titleStyle, color = AppColors.textPrimary,
                modifier = Modifier.fillMaxWidth().padding(Spacing.md).testTag(ProfileScheduleTags.TITLE)
                    .semantics { heading() })
            HorizontalDivider(color = AppColors.borderDefault)
            Column(
                modifier = Modifier.fillMaxWidth()
                    .then(if (scrollTogether) Modifier else Modifier.weight(1f, fill = false).verticalScroll(bodyScroll))
                    .testTag(ProfileScheduleTags.BODY).padding(Spacing.md),
                verticalArrangement = Arrangement.spacedBy(Spacing.md),
                content = body,
            )
            HorizontalDivider(color = AppColors.borderDefault)
            AdaptiveActionPair(
                modifier = Modifier.padding(Spacing.md),
                primaryAction = { actionModifier ->
                    TextButton(onClick = onConfirm, enabled = confirmEnabled,
                        modifier = actionModifier.heightIn(min = GeistSizes.minimumTouchTarget).testTag(ProfileScheduleTags.SAVE)) {
                        Text(confirmLabel, color = if (!confirmEnabled) AppColors.textMuted
                            else if (destructive) AppColors.error else AppColors.accent)
                    }
                },
                secondaryAction = { actionModifier ->
                    TextButton(onClick = onDismiss,
                        modifier = actionModifier.heightIn(min = GeistSizes.minimumTouchTarget).testTag(ProfileScheduleTags.CANCEL)) {
                        Text(stringResource(R.string.cancel))
                    }
                },
            )
        }
    }
}
