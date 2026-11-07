package com.healthmd.presentation.export

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.tween
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

internal enum class DateRangeOption {
    Today,
    Yesterday,
    /** The last seven complete days, ending yesterday. */
    Last7Days,
    /** The last thirty complete days, ending yesterday. */
    Last30Days,
    AllTime,
    Custom;

    companion object {
        fun fromDates(
            startDate: LocalDate,
            endDate: LocalDate,
            allTimeSelected: Boolean,
        ): DateRangeOption {
            val today = LocalDate.now()
            val yesterday = today.minusDays(1)
            return when {
                allTimeSelected -> AllTime
                startDate == today && endDate == today -> Today
                startDate == yesterday && endDate == yesterday -> Yesterday
                startDate == yesterday.minusDays(6) && endDate == yesterday -> Last7Days
                startDate == yesterday.minusDays(29) && endDate == yesterday -> Last30Days
                else -> Custom
            }
        }
    }
}

internal object ExportDateControlTags {
    const val PRESETS = "export.dateRange.presets"
    const val START_DATE = "export.dateRange.start"
    const val END_DATE = "export.dateRange.end"
    const val SLEEP_GUIDANCE = "export.dateRange.sleepGuidance"
    fun preset(option: DateRangeOption) = "export.dateRange.preset.${option.name}"
}

/**
 * The Dates control, as on iOS: one connected row of Yesterday / 7 days / 30 days / Custom. Custom
 * opens outlined From and To fields and keeps Today and All time (every day with history) one
 * tap away.
 * Stateless: the screen retains date resolution, pickers, and protection guards.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun DateRangeSelectionSection(
    selectedOption: DateRangeOption,
    startDate: LocalDate,
    endDate: LocalDate,
    onOptionSelected: (DateRangeOption) -> Unit,
    onStartDateClick: () -> Unit,
    onEndDateClick: () -> Unit,
    showSleepGuidance: Boolean = false,
    sleepDayAttribution: SleepDayAttribution = SleepDayAttribution.DEFAULT,
) {
    val colors = LocalGeistColors.current
    val segments = listOf(
        DateRangeOption.Yesterday to stringResource(R.string.date_option_yesterday),
        DateRangeOption.Last7Days to stringResource(R.string.date_option_last_7_days),
        DateRangeOption.Last30Days to stringResource(R.string.date_option_last_30_days),
        DateRangeOption.Custom to stringResource(R.string.date_option_custom),
    )
    // Today and All time are custom ranges: one day, or from the first day with history.
    val shownOption = when (selectedOption) {
        DateRangeOption.AllTime, DateRangeOption.Today -> DateRangeOption.Custom
        else -> selectedOption
    }
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            stringResource(R.string.export_dates_heading),
            style = GeistType.heading14,
            color = colors.brandPrimary,
            modifier = Modifier.padding(bottom = Spacing.xs),
        )
        SingleChoiceSegmentedButtonRow(
            Modifier.fillMaxWidth().testTag(ExportDateControlTags.PRESETS),
        ) {
            segments.forEachIndexed { index, (option, label) ->
                SegmentedButton(
                    selected = shownOption == option,
                    onClick = { onOptionSelected(option) },
                    shape = SegmentedButtonDefaults.itemShape(index, segments.size),
                    icon = {},
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = colors.secondaryContainer,
                        activeContentColor = colors.onSecondaryContainer,
                        inactiveContentColor = colors.primary,
                        activeBorderColor = colors.gray.c700,
                        inactiveBorderColor = colors.gray.c700,
                    ),
                    modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget).testTag(ExportDateControlTags.preset(option)),
                ) {
                    Text(label, style = GeistType.button14, textAlign = TextAlign.Center)
                }
            }
        }

        AnimatedVisibility(
            visible = shownOption == DateRangeOption.Custom,
            enter = fadeIn(animationSpec = tween(160)) + expandVertically(animationSpec = tween(180)),
            exit = fadeOut(animationSpec = tween(120)) + shrinkVertically(animationSpec = tween(160)),
        ) {
            Column(Modifier.fillMaxWidth().padding(top = Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                BoxWithConstraints(Modifier.fillMaxWidth()) {
                    val stacked = GeistAdaptiveLayout.stackActions(maxWidth.value, LocalDensity.current.fontScale)
                    val from: @Composable (Modifier) -> Unit = { modifier ->
                        DateField(
                            label = stringResource(R.string.date_from_label),
                            date = startDate,
                            onClick = onStartDateClick,
                            modifier = modifier.testTag(ExportDateControlTags.START_DATE),
                        )
                    }
                    val to: @Composable (Modifier) -> Unit = { modifier ->
                        DateField(
                            label = stringResource(R.string.date_to_label),
                            date = endDate,
                            onClick = onEndDateClick,
                            modifier = modifier.testTag(ExportDateControlTags.END_DATE),
                        )
                    }
                    if (stacked) {
                        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            from(Modifier.fillMaxWidth())
                            to(Modifier.fillMaxWidth())
                        }
                    } else {
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            from(Modifier.weight(1f))
                            to(Modifier.weight(1f))
                        }
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    listOf(
                        DateRangeOption.Today to R.string.date_option_today,
                        DateRangeOption.AllTime to R.string.date_option_all_time,
                    ).forEach { (option, label) ->
                        val chosen = selectedOption == option
                        FilterChip(
                            selected = chosen,
                            onClick = { onOptionSelected(if (chosen) DateRangeOption.Custom else option) },
                            label = { Text(stringResource(label), style = GeistType.button14) },
                            leadingIcon = if (chosen) {
                                { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(18.dp)) }
                            } else {
                                null
                            },
                            shape = RoundedCornerShape(GeistRadii.small),
                            colors = FilterChipDefaults.filterChipColors(
                                selectedContainerColor = colors.secondaryContainer,
                                selectedLabelColor = colors.onSecondaryContainer,
                                selectedLeadingIconColor = colors.onSecondaryContainer,
                                labelColor = colors.secondary,
                            ),
                            modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget).testTag(ExportDateControlTags.preset(option)),
                        )
                    }
                }
            }
        }

        // The chosen dates, then how sleep is counted, as one helper line under the control.
        val range = if (startDate == endDate) {
            formatMediumDate(startDate)
        } else {
            stringResource(R.string.history_date_range, formatMediumDate(startDate), formatMediumDate(endDate))
        }
        val guidance = if (showSleepGuidance) {
            stringResource(
                if (sleepDayAttribution == SleepDayAttribution.MORNING_ENDS) {
                    R.string.export_sleep_date_guidance_morning_ends
                } else {
                    R.string.export_sleep_date_guidance
                },
            )
        } else {
            null
        }
        Text(
            text = listOfNotNull(range, guidance).joinToString(" · "),
            style = GeistType.label12,
            color = colors.secondary,
            modifier = Modifier
                .padding(start = Spacing.xxs, end = Spacing.xxs, top = Spacing.xs)
                .then(if (guidance != null) Modifier.testTag(ExportDateControlTags.SLEEP_GUIDANCE) else Modifier),
        )
    }
}

/** An outlined, read-only date field (`rounded.xs`, 56dp) that opens the date picker. */
@Composable
private fun DateField(
    label: String,
    date: LocalDate,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val value = formatMediumDate(date)
    Box(modifier) {
        OutlinedTextField(
            value = value,
            onValueChange = {},
            readOnly = true,
            label = { Text(label) },
            textStyle = GeistType.label16,
            shape = RoundedCornerShape(GeistRadii.extraSmall),
            colors = OutlinedTextFieldDefaults.colors(
                unfocusedBorderColor = colors.gray.c700,
                focusedBorderColor = colors.brandPrimary,
                unfocusedLabelColor = colors.secondary,
                unfocusedTextColor = colors.primary,
                focusedTextColor = colors.primary,
            ),
            modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
        )
        // The field never takes typing: the whole field is one button that opens the picker.
        Box(
            Modifier
                .matchParentSize()
                .clip(RoundedCornerShape(GeistRadii.extraSmall))
                .clickable(role = Role.Button, onClickLabel = label, onClick = onClick)
                .semantics { contentDescription = "$label, $value" },
        )
    }
}

@Composable
private fun formatMediumDate(date: LocalDate): String = date.format(
    DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)
        .withLocale(LocalConfiguration.current.locales[0]),
)
