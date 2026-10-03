package com.healthmd.presentation.schedule

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.*
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.theme.*

internal object ProfileScheduleTags {
    const val ROW = "profileSchedule.row"
    const val NAME = "profileSchedule.name"
    const val SUMMARY = "profileSchedule.summary"
    const val EDIT = "profileSchedule.edit"
    const val DELETE = "profileSchedule.delete"
    const val TOGGLE = "profileSchedule.toggle"
    const val ADD = "profileSchedule.add"
    const val DIALOG = "profileSchedule.dialog.content"
    const val DELETE_DIALOG = "profileSchedule.deleteDialog.content"
    const val TITLE = "profileSchedule.dialog.title"
    const val BODY = "profileSchedule.dialog.body"
    const val SAVE = "profileSchedule.dialog.save"
    const val CANCEL = "profileSchedule.dialog.cancel"
    const val ENABLED = "profileSchedule.dialog.enabled"
    const val CADENCE_UNIT = "profileSchedule.dialog.cadenceUnit"
    const val WEEKDAY = "profileSchedule.dialog.weekday"
    const val HOUR = "profileSchedule.dialog.hour"
    const val MINUTE = "profileSchedule.dialog.minute"
    const val LOOKBACK = "profileSchedule.dialog.lookback"
    const val EVERY = "profileSchedule.dialog.every"
    const val REFRESH = "profileSchedule.dialog.refresh"
    const val REFRESH_INTERVAL = "profileSchedule.dialog.refreshInterval"
    const val MENU = ".menu"
}

/** No surrounding editor click: reading text and three independent actions have their own space. */
@Composable
internal fun ProfileScheduleRowContent(
    row: ProfileScheduleRow,
    onToggle: (Boolean) -> Unit,
    onOpenEditor: () -> Unit,
    onDelete: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth().testTag(ProfileScheduleTags.ROW),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(row.profile.name, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary,
            modifier = Modifier.fillMaxWidth().testTag(ProfileScheduleTags.NAME))
        Text(
            cadenceSummary(row.entry, stringResource(R.string.profile_schedule_refresh_summary,
                row.entry?.todayRefreshIntervalHours ?: ScheduledProfileEntry.DEFAULT_TODAY_REFRESH_INTERVAL_HOURS)),
            style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary,
            modifier = Modifier.fillMaxWidth().testTag(ProfileScheduleTags.SUMMARY),
        )
        AdaptiveActionPair(
            primaryAction = { actionModifier ->
                val description = stringResource(R.string.a11y_profiles_edit_named, row.profile.name)
                OutlinedButton(onClick = onOpenEditor,
                    modifier = actionModifier.heightIn(min = GeistSizes.minimumTouchTarget)
                        .testTag(ProfileScheduleTags.EDIT).semantics { contentDescription = description }) {
                    Text(stringResource(R.string.a11y_profiles_edit))
                }
            },
            secondaryAction = { actionModifier ->
                val description = stringResource(R.string.a11y_profiles_delete_named, row.profile.name)
                TextButton(onClick = onDelete,
                    modifier = actionModifier.heightIn(min = GeistSizes.minimumTouchTarget)
                        .testTag(ProfileScheduleTags.DELETE).semantics { contentDescription = description }) {
                    Text(stringResource(R.string.a11y_profiles_delete), color = AppColors.error)
                }
            },
        )
        ProfileScheduleToggle(
            label = stringResource(R.string.enabled), checked = row.entry?.isEnabled == true,
            onCheckedChange = onToggle, modifier = Modifier.testTag(ProfileScheduleTags.TOGGLE),
            description = stringResource(R.string.a11y_profiles_schedule_named, row.profile.name),
        )
    }
}

/** One whole labeled switch target; the visual switch never adds a second action. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ProfileScheduleToggle(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
    description: String? = null,
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        FlowRow(
            modifier = modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
                .toggleable(checked, role = Role.Switch, onValueChange = onCheckedChange)
                .semantics { if (description != null) contentDescription = description }
                .padding(vertical = Spacing.xxs),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.xxs),
            maxItemsInEachRow = if (stacked) 1 else 2,
        ) {
            Text(label, style = MaterialTheme.typography.bodyMedium, color = AppColors.textPrimary,
                modifier = if (stacked) Modifier.fillMaxWidth() else Modifier.weight(1f).align(Alignment.CenterVertically))
            Switch(checked = checked, onCheckedChange = null)
        }
    }
}

@Composable
internal fun <T> ProfileScheduleDropdown(
    selected: T,
    options: List<Pair<T, String>>,
    label: String,
    onSelected: (T) -> Unit,
    tag: String,
) {
    var expanded by remember { mutableStateOf(false) }
    var anchorWidth by remember { mutableIntStateOf(0) }
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val shape = RoundedCornerShape(Radii.card)
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary,
            modifier = Modifier.fillMaxWidth())
        Box {
            Row(
                modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
                    .testTag(tag).onSizeChanged { anchorWidth = it.width }
                    .clip(shape).background(AppColors.bgPrimary).border(1.dp, AppColors.borderDefault, shape)
                    .clickable(role = Role.Button) {
                        focusManager.clearFocus(); keyboard?.hide(); expanded = true
                    }
                    .semantics { contentDescription = label }.padding(Spacing.xs),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                Text(options.firstOrNull { it.first == selected }?.second.orEmpty(),
                    style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary,
                    modifier = Modifier.weight(1f))
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null,
                    tint = AppColors.textSecondary, modifier = Modifier.size(Spacing.lg))
            }
            DropdownMenu(
                expanded = expanded, onDismissRequest = { expanded = false },
                modifier = Modifier.widthIn(max = with(density) { anchorWidth.toDp() }).testTag(tag + ProfileScheduleTags.MENU),
            ) {
                // Native popup owners must retain the anchor's exact user scale and direction.
                CompositionLocalProvider(LocalDensity provides density, LocalLayoutDirection provides direction) {
                    options.forEach { (value, text) ->
                        DropdownMenuItem(
                            text = { Text(text, style = MaterialTheme.typography.labelLarge) },
                            onClick = { expanded = false; onSelected(value) },
                            modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
                        )
                    }
                }
            }
        }
    }
}

@Composable
internal fun ProfileScheduleNumberField(
    label: String,
    value: Int,
    onValue: (Int) -> Unit,
    tag: String,
    modifier: Modifier = Modifier,
) {
    // Preserve the profile editor's existing parsing/clamping behavior, NOT the legacy
    // schedule's five-digit cap or empty-input commit. Invalid input keeps the valid draft.
    var text by rememberSaveable(label, value) { mutableStateOf(value.toString()) }
    var lastCommitted by rememberSaveable(label) { mutableStateOf(value) }
    if (value != lastCommitted && text.toIntOrNull() != value) {
        text = value.toString()
        lastCommitted = value
    }
    var focused by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val shape = RoundedCornerShape(Radii.card)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Text(label, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary,
            modifier = Modifier.fillMaxWidth())
        BasicTextField(
            value = text,
            onValueChange = { raw ->
                text = raw
                raw.toIntOrNull()?.let { typed ->
                    val clamped = typed.coerceAtLeast(0)
                    if (clamped != lastCommitted) {
                        lastCommitted = clamped
                        onValue(clamped)
                    }
                }
            },
            textStyle = GeistType.label20Mono.copy(color = AppColors.textPrimary),
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
            keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus(); keyboard?.hide() }),
            cursorBrush = SolidColor(AppColors.accent),
            decorationBox = { inner -> Box(Modifier.padding(Spacing.xs)) { inner() } },
            modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
                .testTag(tag).semantics { contentDescription = label }.onFocusChanged { focused = it.isFocused }
                .clip(shape).background(AppColors.bgPrimary)
                .border(1.dp, if (focused) AppColors.accent else AppColors.borderDefault, shape),
        )
    }
}
