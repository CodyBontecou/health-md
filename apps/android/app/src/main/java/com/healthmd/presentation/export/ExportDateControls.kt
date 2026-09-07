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
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
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
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

internal enum class DateRangeOption {
    Today,
    Yesterday,
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
                else -> Custom
            }
        }
    }
}

internal object ExportDateControlTags {
    const val PRESETS = "export.dateRange.presets"
    const val START_DATE = "export.dateRange.start"
    const val END_DATE = "export.dateRange.end"
    fun preset(option: DateRangeOption) = "export.dateRange.preset.${option.name}"
}

/** Stateless presentation: the screen retains date resolution, pickers, and protection guards. */
@Composable
internal fun DateRangeSelectionSection(
    selectedOption: DateRangeOption,
    startDate: LocalDate,
    endDate: LocalDate,
    onOptionSelected: (DateRangeOption) -> Unit,
    onStartDateClick: () -> Unit,
    onEndDateClick: () -> Unit,
) {
    val options = listOf(
        DateRangeOption.Today to stringResource(R.string.date_option_today),
        DateRangeOption.Yesterday to stringResource(R.string.date_option_yesterday),
        DateRangeOption.AllTime to stringResource(R.string.date_option_all_time),
        DateRangeOption.Custom to stringResource(R.string.date_option_custom),
    )
    Column(modifier = Modifier.fillMaxWidth()) {
        SectionLabel(stringResource(R.string.section_date_range))
        GeistCard(padding = Spacing.md) {
            BoxWithConstraints(Modifier.fillMaxWidth().testTag(ExportDateControlTags.PRESETS).selectableGroup()) {
                val columns = if (GeistAdaptiveLayout.stackActions(maxWidth.value, LocalDensity.current.fontScale)) 1 else 2
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    options.chunked(columns).forEach { row ->
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                            row.forEach { (option, label) ->
                                DateRangeOptionButton(
                                    text = label,
                                    selected = selectedOption == option,
                                    onClick = { onOptionSelected(option) },
                                    modifier = Modifier.weight(1f).testTag(ExportDateControlTags.preset(option)),
                                )
                            }
                        }
                    }
                }
            }

            AnimatedVisibility(
                visible = selectedOption == DateRangeOption.Custom,
                enter = fadeIn(animationSpec = tween(160)) + expandVertically(animationSpec = tween(180)),
                exit = fadeOut(animationSpec = tween(120)) + shrinkVertically(animationSpec = tween(160)),
            ) {
                Column(modifier = Modifier.fillMaxWidth()) {
                    Spacer(modifier = Modifier.height(Spacing.md))
                    HorizontalDivider(color = AppColors.borderDefault)
                    DateRangeDateRow(
                        label = stringResource(R.string.date_start_label),
                        date = startDate,
                        onClick = onStartDateClick,
                        modifier = Modifier.testTag(ExportDateControlTags.START_DATE),
                    )
                    HorizontalDivider(color = AppColors.borderDefault)
                    DateRangeDateRow(
                        label = stringResource(R.string.date_end_label),
                        date = endDate,
                        onClick = onEndDateClick,
                        modifier = Modifier.testTag(ExportDateControlTags.END_DATE),
                    )
                }
            }
        }
    }
}

@Composable
private fun DateRangeOptionButton(
    text: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(Radii.button)
    Column(
        modifier = modifier
            .heightIn(min = GeistSizes.minimumTouchTarget)
            .clip(shape)
            .background(if (selected) AppColors.accentSubtle else Color.Transparent)
            .then(if (selected) Modifier.border(1.dp, AppColors.accentBorder, shape) else Modifier)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .padding(horizontal = Spacing.sm, vertical = Spacing.xs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.xs, Alignment.CenterVertically),
    ) {
        // Selection remains visible without taking any width away from the essential label.
        if (selected) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(Spacing.lg),
            )
        }
        Text(
            text = text,
            color = if (selected) AppColors.accent else AppColors.textSecondary,
            style = MaterialTheme.typography.titleMedium,
            textAlign = TextAlign.Center,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** One labeled date action; neither the label nor the formatted value competes for row width. */
@Composable
private fun DateRangeDateRow(
    label: String,
    date: LocalDate,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier = modifier.fillMaxWidth()
            .heightIn(min = GeistSizes.minimumTouchTarget)
            .clip(RoundedCornerShape(Radii.card))
            .clickable(role = Role.Button, onClick = onClick)
            .padding(vertical = Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.titleLarge,
            color = AppColors.textPrimary,
            modifier = Modifier.fillMaxWidth(),
        )
        Box(
            modifier = Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(Radii.card))
                .background(AppColors.bgSecondary)
                .padding(horizontal = Spacing.md, vertical = Spacing.xs),
        ) {
            Text(
                text = formatCompactDate(date),
                style = GeistType.label20Mono,
                color = AppColors.textPrimary,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun formatCompactDate(date: LocalDate): String = date.format(
    DateTimeFormatter.ofLocalizedDate(FormatStyle.SHORT)
        .withLocale(LocalConfiguration.current.locales[0]),
)
