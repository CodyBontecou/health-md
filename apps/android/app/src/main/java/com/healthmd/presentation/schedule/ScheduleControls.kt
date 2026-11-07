package com.healthmd.presentation.schedule

import android.text.format.DateFormat
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.SwapVert
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.*
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.*
import java.text.DateFormatSymbols
import java.text.NumberFormat

internal object ScheduleControlTags {
    const val FREQUENCY_VALUE = "schedule.frequency.value"
    const val FREQUENCY_UNIT = "schedule.frequency.unit"
    const val DATE_WINDOW = "schedule.dateWindow"
    const val HOUR = "schedule.time.hour"
    const val MINUTE = "schedule.time.minute"
    const val PERIOD = "schedule.time.period"
    const val LOOKBACK = "schedule.lookback"
}


/** The Material 3 `input` outline: 4 dp corners, gray-700 at rest, a 2 dp brand outline on focus. */
internal val ScheduleFieldShape = RoundedCornerShape(GeistRadii.extraSmall)

/** DESIGN.md `input` height. */
internal val ScheduleFieldMinHeight = 56.dp

internal fun Modifier.scheduleFieldOutline(colors: GeistColors, focused: Boolean = false): Modifier =
    clip(ScheduleFieldShape).border(
        width = if (focused) 2.dp else 1.dp,
        color = if (focused) colors.brandPrimary else colors.gray.c700,
        shape = ScheduleFieldShape,
    )

/** Stateless UI: callers retain scheduling, bounds, persistence, and protection policy. */
@Composable
internal fun ScheduleSettingsCard(
    uiState: ScheduleUiState,
    onFrequencyValueChange: (Int) -> Unit,
    onFrequencyUnitSelected: (ScheduleCadenceUnit) -> Unit,
    onHourDelta: (Int) -> Unit,
    onMinuteDelta: (Int) -> Unit,
    onTogglePeriod: () -> Unit,
    onDateWindowSelected: (ScheduleDateWindow) -> Unit,
    onLookbackDelta: (Int) -> Unit,
) {
    // A list group of labelled rows (DESIGN.md `list-group`). The frequency and date rows keep
    // fixed positions so an in-progress frequency edit survives the conditional rows below.
    val showTime = uiState.cadenceUnit == ScheduleCadenceUnit.DAYS || uiState.cadenceUnit == ScheduleCadenceUnit.WEEKS
    val showLookback = uiState.dateWindow != ScheduleDateWindow.TODAY
    val count = 2 + (if (showTime) 1 else 0) + (if (showLookback) 1 else 0)
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        ScheduleGroupRow(groupRowShape(0, count)) {
            FrequencyRow(uiState.cadenceValue, uiState.cadenceUnit, onFrequencyValueChange, onFrequencyUnitSelected)
        }
        ScheduleGroupRow(groupRowShape(1, count)) {
            ControlLabel(stringResource(R.string.schedule_date_window))
            ScheduleDropdown(
                selected = uiState.dateWindow,
                options = listOf(
                    ScheduleDateWindow.PAST_COMPLETE_DAYS to stringResource(R.string.schedule_date_window_past_complete_days),
                    ScheduleDateWindow.PAST_COMPLETE_DAYS_THROUGH_TODAY to stringResource(R.string.schedule_date_window_past_complete_days_through_today),
                    ScheduleDateWindow.TODAY to stringResource(R.string.schedule_date_window_today),
                ),
                description = stringResource(R.string.schedule_date_window),
                onSelected = onDateWindowSelected,
                tag = ScheduleControlTags.DATE_WINDOW,
            )
        }
        if (showTime) {
            ScheduleGroupRow(groupRowShape(2, count)) {
                ControlLabel(stringResource(R.string.schedule_time))
                TimeRow(uiState.hour, uiState.minute, onHourDelta, onMinuteDelta, onTogglePeriod)
            }
        }
        if (showLookback) {
            ScheduleGroupRow(groupRowShape(count - 1, count)) {
                ControlLabel(stringResource(R.string.schedule_export_past_days))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    val value = formatInteger(uiState.lookbackDays, LocalConfiguration.current.locales[0])
                    Text(
                        value, style = GeistType.label20Mono, color = LocalGeistColors.current.primary,
                        modifier = Modifier.weight(1f).testTag(ScheduleControlTags.LOOKBACK),
                    )
                    StepperActions(
                        value = value,
                        onDecrease = { onLookbackDelta(-1) }, onIncrease = { onLookbackDelta(1) },
                        decreaseDescription = stringResource(R.string.schedule_decrease_lookback_days),
                        increaseDescription = stringResource(R.string.schedule_increase_lookback_days),
                    )
                }
            }
        }
    }
}

/** One list-group row on `background-200`: the label above its control, 16 dp padding. */
@Composable
private fun ScheduleGroupRow(shape: Shape, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(LocalGeistColors.current.background200)
            .padding(GeistSpacing.space4),
        content = content,
    )
}

@Composable
private fun ControlLabel(text: String) {
    Text(text, style = GeistType.label16, color = LocalGeistColors.current.primary)
    Spacer(Modifier.height(GeistSpacing.space2))
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun FrequencyRow(
    value: Int,
    unit: ScheduleCadenceUnit,
    onValueChange: (Int) -> Unit,
    onUnitSelected: (ScheduleCadenceUnit) -> Unit,
) {
    ControlLabel(stringResource(R.string.schedule_frequency))
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = GeistAdaptiveLayout.stackActions(maxWidth.value, LocalDensity.current.fontScale)
        // Keep the same composition when fields reflow so an in-progress edit retains focus.
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            maxItemsInEachRow = if (stacked) 1 else 2,
        ) {
            FrequencyValueField(value, unit, onValueChange, if (stacked) Modifier.fillMaxWidth() else Modifier)
            ScheduleDropdown(
                selected = unit,
                options = listOf(
                    ScheduleCadenceUnit.MINUTES to pluralStringResource(R.plurals.schedule_cadence_unit_minutes, value),
                    ScheduleCadenceUnit.HOURS to pluralStringResource(R.plurals.schedule_cadence_unit_hours, value),
                    ScheduleCadenceUnit.DAYS to pluralStringResource(R.plurals.schedule_cadence_unit_days, value),
                    ScheduleCadenceUnit.WEEKS to pluralStringResource(R.plurals.schedule_cadence_unit_weeks, value),
                ),
                description = stringResource(R.string.schedule_frequency),
                onSelected = onUnitSelected,
                modifier = Modifier.weight(1f),
                tag = ScheduleControlTags.FREQUENCY_UNIT,
            )
        }
    }
    if (unit == ScheduleCadenceUnit.MINUTES) {
        Spacer(Modifier.height(GeistSpacing.space2))
        Text(
            stringResource(R.string.cadence_minutes_minimum),
            style = GeistType.copy13, color = LocalGeistColors.current.secondary,
        )
    }
}

@Composable
private fun FrequencyValueField(
    value: Int,
    unit: ScheduleCadenceUnit,
    onValueChange: (Int) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val locale = LocalConfiguration.current.locales[0]
    var text by rememberSaveable(locale) { mutableStateOf(formatInteger(value, locale)) }
    var isFocused by remember { mutableStateOf(false) }
    val minimumValue = if (unit == ScheduleCadenceUnit.MINUTES) 15 else 1
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val description = stringResource(R.string.schedule_frequency)
    val style = GeistType.label20Mono.copy(color = colors.primary, textAlign = TextAlign.Center)
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val digitWidth = remember(measurer, locale, style, density) {
        (0..9).maxOf { measurer.measure(formatInteger(it, locale).repeat(MAX_FREQUENCY_DIGITS), style).size.width }
    }
    val inputWidth = with(density) {
        maxOf(digitWidth, measurer.measure(text, style).size.width).toDp() + GeistSpacing.space4 * 2
    }

    LaunchedEffect(value, unit, isFocused) {
        if (!isFocused) text = formatInteger(value, locale)
    }

    fun commitValue() {
        val committed = parseLocalizedInteger(text, locale)?.coerceAtLeast(minimumValue) ?: minimumValue
        text = formatInteger(committed, locale)
        onValueChange(committed)
    }

    BasicTextField(
        value = text,
        onValueChange = { raw ->
            val digits = raw.filter { it.isDigit() }.take(MAX_FREQUENCY_DIGITS)
            text = digits
            parseLocalizedInteger(digits, locale)?.takeIf { it >= minimumValue }?.let(onValueChange)
        },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number, imeAction = ImeAction.Done),
        keyboardActions = KeyboardActions(onDone = { focusManager.clearFocus(); keyboard?.hide() }),
        textStyle = style,
        cursorBrush = SolidColor(colors.brandPrimary),
        decorationBox = { innerField ->
            // Decoration belongs inside the field's focus/semantics target, not outside it.
            Box(
                Modifier.padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
                contentAlignment = Alignment.Center,
            ) { innerField() }
        },
        modifier = modifier
            .testTag(ScheduleControlTags.FREQUENCY_VALUE)
            .semantics { contentDescription = description }
            .width(inputWidth).heightIn(min = ScheduleFieldMinHeight)
            .scheduleFieldOutline(colors, focused = isFocused)
            .onFocusChanged { state ->
                val wasFocused = isFocused
                isFocused = state.isFocused
                if (wasFocused && !state.isFocused) commitValue()
            },
    )
}

/** An M3 exposed dropdown: an outlined `input` anchor whose full selected label wraps. */
@Composable
private fun <T> ScheduleDropdown(
    selected: T,
    options: List<Pair<T, String>>,
    description: String,
    onSelected: (T) -> Unit,
    tag: String,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    var expanded by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    val density = LocalDensity.current
    val direction = LocalLayoutDirection.current
    var anchorWidth by remember { mutableIntStateOf(0) }
    // A regular Box supports FlowRow's intrinsic sizing; BoxWithConstraints does not.
    Box(modifier) {
        Row(
            modifier = Modifier.fillMaxWidth().testTag(tag).heightIn(min = ScheduleFieldMinHeight)
                .onSizeChanged { anchorWidth = it.width }
                .scheduleFieldOutline(colors, focused = expanded)
                .clickable(role = Role.Button) {
                    focusManager.clearFocus()
                    keyboard?.hide()
                    expanded = true
                }
                .semantics { contentDescription = description }
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space3, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            Text(
                options.firstOrNull { it.first == selected }?.second.orEmpty(),
                style = GeistType.label16, color = colors.primary,
                modifier = Modifier.weight(1f),
            )
            Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null,
                tint = colors.secondary, modifier = Modifier.size(GeistSpacing.space6))
        }
        DropdownMenu(
            expanded, onDismissRequest = { expanded = false },
            modifier = Modifier.widthIn(max = with(density) { anchorWidth.toDp() }),
            shape = RoundedCornerShape(GeistRadii.extraSmall),
            containerColor = colors.gray.c200,
        ) {
            // A popup creates another Compose owner. Preserve the anchor's scale and
            // direction rather than reverting scoped accessibility layouts to its defaults.
            CompositionLocalProvider(LocalDensity provides density, LocalLayoutDirection provides direction) {
                options.forEach { (value, label) ->
                    DropdownMenuItem(
                        text = { Text(label, style = GeistType.label16, color = colors.primary) },
                        onClick = { expanded = false; onSelected(value) },
                    )
                }
            }
        }
    }
}

@Composable
internal fun TimeRow(
    hour: Int,
    minute: Int,
    onHourDelta: (Int) -> Unit,
    onMinuteDelta: (Int) -> Unit,
    onTogglePeriod: () -> Unit,
    use24HourTime: Boolean = DateFormat.is24HourFormat(LocalContext.current),
) {
    val colors = LocalGeistColors.current
    val locale = LocalConfiguration.current.locales[0]
    val displayHour = localizedDisplayHour(hour, localizedHourCycle(locale, use24HourTime))
    val period = DateFormatSymbols.getInstance(locale).amPmStrings[if (hour < 12) 0 else 1]
    val periodFirst = !use24HourTime && localizedDayPeriodPrecedesHour(locale)
    val hourFormat = remember(locale, use24HourTime) {
        NumberFormat.getIntegerInstance(locale).apply {
            isGroupingUsed = false
            minimumIntegerDigits = localizedHourMinimumDigits(locale, use24HourTime)
        }
    }
    val minuteFormat = remember(locale) {
        NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = false; minimumIntegerDigits = 2 }
    }
    val hourValue = hourFormat.format(displayHour)
    val minuteValue = minuteFormat.format(minute)
    val separator = localizedTimeSeparator(locale, use24HourTime)
    val measurer = rememberTextMeasurer()
    val separatorWidth = with(LocalDensity.current) {
        measurer.measure(separator, GeistType.label20Mono).size.width.toDp()
    }
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val separatePeriod = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale) ||
            maxWidth < GeistSizes.minimumTouchTarget * 6 + GeistSpacing.space2 * 6 + separatorWidth
        val separateNumbers = maxWidth < GeistSizes.minimumTouchTarget * 4 + GeistSpacing.space2 * 4 + separatorWidth
        val periodAction: @Composable (Modifier) -> Unit = { modifier ->
            val description = stringResource(R.string.schedule_toggle_time_period)
            // One tonal AM/PM action (DESIGN.md): the period and its swap affordance.
            Box(
                modifier = modifier.testTag(ScheduleControlTags.PERIOD)
                    .heightIn(min = GeistSizes.minimumTouchTarget)
                    .clip(RoundedCornerShape(GeistRadii.full))
                    .background(colors.secondaryContainer)
                    .clickable(role = Role.Button, onClick = onTogglePeriod)
                    .semantics { contentDescription = description; stateDescription = period }
                    .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
                contentAlignment = Alignment.Center,
            ) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                    Text(period, style = GeistType.label20Mono, color = colors.onSecondaryContainer, modifier = Modifier.weight(1f, fill = false))
                    Icon(Icons.Filled.SwapVert, contentDescription = null, tint = colors.onSecondaryContainer,
                        modifier = Modifier.size(GeistSpacing.space6))
                }
            }
        }
        val hourPicker: @Composable (Modifier) -> Unit = { modifier ->
            PickerPill(hourValue, { onHourDelta(1) }, { onHourDelta(-1) },
                stringResource(R.string.schedule_increase_hour), stringResource(R.string.schedule_decrease_hour),
                modifier.testTag(ScheduleControlTags.HOUR))
        }
        val minutePicker: @Composable (Modifier) -> Unit = { modifier ->
            PickerPill(minuteValue, { onMinuteDelta(1) }, { onMinuteDelta(-1) },
                stringResource(R.string.schedule_increase_minute), stringResource(R.string.schedule_decrease_minute),
                modifier.testTag(ScheduleControlTags.MINUTE))
        }
        Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4)) {
            if (periodFirst && separatePeriod) periodAction(Modifier.fillMaxWidth())
            if (separateNumbers) {
                // Very narrow windows still keep both targets intact and identify each field.
                Column {
                    ControlLabel(pluralStringResource(R.plurals.schedule_cadence_unit_hours, 1))
                    hourPicker(Modifier.fillMaxWidth())
                }
                Column {
                    ControlLabel(pluralStringResource(R.plurals.schedule_cadence_unit_minutes, 1))
                    minutePicker(Modifier.fillMaxWidth())
                }
            } else {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                    verticalAlignment = Alignment.Top,
                ) {
                    if (periodFirst && !separatePeriod) periodAction(Modifier.weight(1f))
                    hourPicker(Modifier.weight(1f))
                    Text(separator, style = GeistType.label20Mono, color = colors.secondary,
                        modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget).padding(vertical = GeistSpacing.space2))
                    minutePicker(Modifier.weight(1f))
                    if (!use24HourTime && !periodFirst && !separatePeriod) periodAction(Modifier.weight(1f))
                }
            }
            if (!use24HourTime && !periodFirst && separatePeriod) periodAction(Modifier.fillMaxWidth())
        }
    }
}

@Composable
private fun PickerPill(
    label: String,
    onIncrement: () -> Unit,
    onDecrement: () -> Unit,
    incrementDescription: String,
    decrementDescription: String,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier,
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        Text(label, style = GeistType.label20Mono, color = LocalGeistColors.current.primary,
            modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget).padding(vertical = GeistSpacing.space2))
        StepperActions(label, onDecrement, onIncrement, decrementDescription, incrementDescription)
    }
}

@Composable
private fun StepperActions(
    value: String,
    onDecrease: () -> Unit,
    onIncrease: () -> Unit,
    decreaseDescription: String,
    increaseDescription: String,
) {
    // Separated 48 dp minus/plus targets with an 8 dp gap (DESIGN.md time editors).
    Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
        StepperIcon(Icons.Filled.Remove, value, decreaseDescription, onDecrease)
        StepperIcon(Icons.Filled.Add, value, increaseDescription, onIncrease)
    }
}

/** A filled tonal icon button on `secondary-container`. */
@Composable
private fun StepperIcon(icon: ImageVector, value: String, description: String, onClick: () -> Unit) {
    val colors = LocalGeistColors.current
    Box(
        modifier = Modifier.size(GeistSizes.minimumTouchTarget).clip(CircleShape)
            .background(colors.secondaryContainer)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description; stateDescription = value },
        contentAlignment = Alignment.Center,
    ) {
        Icon(icon, contentDescription = null, tint = colors.onSecondaryContainer, modifier = Modifier.size(GeistSpacing.space6))
    }
}

private const val MAX_FREQUENCY_DIGITS = 5
