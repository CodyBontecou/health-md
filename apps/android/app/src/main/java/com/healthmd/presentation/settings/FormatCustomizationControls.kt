package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import com.healthmd.presentation.theme.*

internal object FormatCustomizationTags {
    const val SCROLL = "format.scroll"
    const val BACK = "format.back"
    const val FRONTMATTER = "format.frontmatter"
    const val DATE = "format.date"
    const val TIME = "format.time"
    const val UNIT = "format.unit"
    const val TEMPLATE = "format.template"
    const val BULLET = "format.bullet"
    const val HEADER = "format.header"
    const val EMOJI = "format.emoji"
    const val SUMMARY = "format.summary"
    const val NATIVE_FIELDS = "format.nativeFields"
    const val LEGACY_ALIASES = "format.legacyAliases"
    const val TEMPLATE_FIELD = "format.template.field"
    const val TEMPLATE_RESET = "format.template.reset"
    const val TEMPLATE_PREVIEW = "format.template.preview"

    fun choice(group: String, value: Any) = "$group.$value"
    fun label(tag: String) = "$tag.label"
    fun indicator(tag: String) = "$tag.indicator"
    fun description(tag: String) = "$tag.description"
}

/** The row owns selection; the radio artwork never becomes a second TalkBack action. */
@Composable
internal fun FormatCustomizationChoice(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    tag: String,
    modifier: Modifier = Modifier,
    description: String? = null,
    labelStyle: TextStyle = MaterialTheme.typography.bodyLarge,
    bordered: Boolean = false,
) {
    val shape = RoundedCornerShape(Radii.card)
    Column(
        modifier = modifier.fillMaxWidth().testTag(tag)
            .heightIn(min = GeistSizes.minimumTouchTarget).clip(shape)
            .background(if (selected) AppColors.accentSubtle else AppColors.bgPrimary)
            .then(if (bordered) Modifier.border(
                1.dp, if (selected) AppColors.accentBorder else AppColors.borderDefault, shape,
            ) else Modifier)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .padding(Spacing.xs),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
        ) {
            RadioButton(
                selected = selected,
                onClick = null,
                modifier = Modifier.testTag(FormatCustomizationTags.indicator(tag)),
                colors = RadioButtonDefaults.colors(
                    selectedColor = AppColors.accent,
                    unselectedColor = AppColors.textSecondary,
                ),
            )
            Text(
                label,
                color = if (selected) AppColors.textPrimary else AppColors.textSecondary,
                style = labelStyle,
                modifier = Modifier.weight(1f).testTag(FormatCustomizationTags.label(tag)),
            )
        }
        if (description != null) {
            // Descriptions use the whole inner width, not the column beside the indicator.
            Text(
                description,
                color = AppColors.textSecondary,
                style = MaterialTheme.typography.bodySmall,
                modifier = Modifier.fillMaxWidth().testTag(FormatCustomizationTags.description(tag)),
            )
        }
    }
}

/** Weighted choices only share a row when there is enough reading width at the user's scale. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun <T> FormatCustomizationChoices(
    options: List<T>,
    selected: T,
    onSelected: (T) -> Unit,
    group: String,
    label: @Composable (T) -> String,
    description: (@Composable (T) -> String)? = null,
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        FlowRow(
            modifier = Modifier.fillMaxWidth().selectableGroup().testTag(group),
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs),
            maxItemsInEachRow = if (stacked) 1 else options.size,
        ) {
            options.forEach { option ->
                // Choice contains no subcomposing layout: FlowRow can measure its intrinsic size.
                FormatCustomizationChoice(
                    label = label(option), selected = selected == option,
                    onClick = { onSelected(option) },
                    tag = FormatCustomizationTags.choice(group, option),
                    modifier = if (stacked) Modifier.fillMaxWidth() else Modifier.weight(1f),
                    description = description?.invoke(option),
                    labelStyle = MaterialTheme.typography.labelLarge,
                    bordered = true,
                )
            }
        }
    }
}

/** One labeled switch target; long labels get full width instead of wrapping beside a thumb. */
@Composable
internal fun FormatCustomizationToggle(
    label: String,
    checked: Boolean,
    tag: String,
    onCheckedChange: (Boolean) -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        val text: @Composable (Modifier) -> Unit = { modifier ->
            Text(
                label, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge,
                modifier = modifier.testTag(FormatCustomizationTags.label(tag)),
            )
        }
        val indicator: @Composable () -> Unit = {
            Switch(
                checked = checked, onCheckedChange = null,
                modifier = Modifier.testTag(FormatCustomizationTags.indicator(tag)),
                colors = SwitchDefaults.colors(
                    checkedThumbColor = AppColors.onAccent,
                    checkedTrackColor = AppColors.accent,
                    uncheckedThumbColor = AppColors.textMuted,
                    uncheckedTrackColor = AppColors.bgSecondary,
                    uncheckedBorderColor = AppColors.borderDefault,
                ),
            )
        }
        val target = Modifier.fillMaxWidth().testTag(tag)
            .heightIn(min = GeistSizes.minimumTouchTarget).clip(RoundedCornerShape(Radii.card))
            .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)
            .padding(vertical = Spacing.xs)
        if (stacked) {
            Column(target, verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                text(Modifier.fillMaxWidth())
                Box(Modifier.align(Alignment.End)) { indicator() }
            }
        } else {
            Row(
                target, verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                text(Modifier.weight(1f))
                indicator()
            }
        }
    }
}
