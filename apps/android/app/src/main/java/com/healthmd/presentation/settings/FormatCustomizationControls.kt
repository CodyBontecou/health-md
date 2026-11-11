package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.unit.dp
import com.healthmd.presentation.common.AppSwitch
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

/** List-group rows are 56dp tall at minimum (DESIGN.md `list-group`). */
internal val GroupRowMinHeight = 56.dp

/**
 * Cells that share one line of a list group: the line's outer ends take the 20dp list-group
 * corners and the joins between cells the 4dp inner corners.
 */
internal fun groupCellShape(index: Int, count: Int): Shape {
    val outer = GeistRadii.listGroup
    val inner = GeistRadii.extraSmall
    val start = if (index == 0) outer else inner
    val end = if (index == count - 1) outer else inner
    return RoundedCornerShape(topStart = start, bottomStart = start, topEnd = end, bottomEnd = end)
}

/**
 * One list-group radio row. The row owns selection; the radio artwork never becomes a second
 * TalkBack action. Text end insets sit inside the text nodes, so the label and the description
 * below it keep the row's whole reading width.
 */
@Composable
internal fun FormatCustomizationChoice(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    tag: String,
    shape: Shape,
    modifier: Modifier = Modifier,
    description: String? = null,
    labelStyle: TextStyle = GeistType.copy16,
) {
    val colors = LocalGeistColors.current
    Column(
        modifier = modifier.fillMaxWidth().testTag(tag)
            .clip(shape)
            .background(if (selected) colors.secondaryContainer else colors.background200)
            .selectable(selected = selected, role = Role.RadioButton, onClick = onClick)
            .heightIn(min = GroupRowMinHeight)
            .padding(start = GeistSpacing.space4, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1, Alignment.CenterVertically),
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            RadioButton(
                selected = selected,
                onClick = null,
                modifier = Modifier.testTag(FormatCustomizationTags.indicator(tag)),
                colors = RadioButtonDefaults.colors(
                    selectedColor = colors.brandPrimary,
                    unselectedColor = colors.secondary,
                ),
            )
            Text(
                label,
                color = if (selected) colors.onSecondaryContainer else colors.primary,
                style = labelStyle,
                modifier = Modifier.weight(1f).testTag(FormatCustomizationTags.label(tag))
                    .padding(end = GeistSpacing.space4),
            )
        }
        if (description != null) {
            // Descriptions use the whole row width, not the column beside the indicator.
            Text(
                description,
                color = if (selected) colors.onSecondaryContainer else colors.secondary,
                style = GeistType.copy13,
                modifier = Modifier.fillMaxWidth().testTag(FormatCustomizationTags.description(tag))
                    .padding(end = GeistSpacing.space4),
            )
        }
    }
}

/** A vertical list group of radio rows; [extra] rows (such as an editor) follow the choices. */
@Composable
internal fun <T : Any> FormatCustomizationChoiceGroup(
    title: String,
    options: List<T>,
    selected: T,
    onSelected: (T) -> Unit,
    group: String,
    label: @Composable (T) -> String,
    extra: List<@Composable (Shape) -> Unit> = emptyList(),
) {
    val choices: List<@Composable (Shape) -> Unit> = options.map { option ->
        { shape ->
            FormatCustomizationChoice(
                label = label(option), selected = selected == option,
                onClick = { onSelected(option) },
                tag = FormatCustomizationTags.choice(group, option),
                shape = shape,
            )
        }
    }
    SettingsGroup(
        title = title,
        rows = choices + extra,
        modifier = Modifier.selectableGroup().testTag(group),
    )
}

/** Weighted choices only share a line when there is enough reading width at the user's scale. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun <T : Any> FormatCustomizationChoices(
    title: String,
    options: List<T>,
    selected: T,
    onSelected: (T) -> Unit,
    group: String,
    label: @Composable (T) -> String,
    description: (@Composable (T) -> String)? = null,
) {
    SettingsGroup(
        title = title,
        rows = listOf { _ ->
            BoxWithConstraints(Modifier.fillMaxWidth()) {
                val stacked = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
                FlowRow(
                    modifier = Modifier.fillMaxWidth().selectableGroup().testTag(group),
                    horizontalArrangement = Arrangement.spacedBy(2.dp),
                    verticalArrangement = Arrangement.spacedBy(2.dp),
                    maxItemsInEachRow = if (stacked) 1 else options.size,
                ) {
                    options.forEachIndexed { index, option ->
                        // Choice contains no subcomposing layout: FlowRow can measure its intrinsic size.
                        FormatCustomizationChoice(
                            label = label(option), selected = selected == option,
                            onClick = { onSelected(option) },
                            tag = FormatCustomizationTags.choice(group, option),
                            shape = if (stacked) groupRowShape(index, options.size) else groupCellShape(index, options.size),
                            modifier = if (stacked) Modifier.fillMaxWidth() else Modifier.weight(1f).fillMaxRowHeight(),
                            description = description?.invoke(option),
                            labelStyle = GeistType.button14,
                        )
                    }
                }
            }
        },
    )
}

/**
 * One whole-row switch target on a list-group row; long labels get the full width instead of
 * wrapping beside the thumb. The switch is indicator artwork only.
 */
@Composable
internal fun FormatCustomizationToggle(
    label: String,
    checked: Boolean,
    tag: String,
    shape: Shape,
    onCheckedChange: (Boolean) -> Unit,
) {
    val colors = LocalGeistColors.current
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        // The label node spans its insets, so a stacked label reports the row's full width.
        val text: @Composable (Modifier, Modifier) -> Unit = { outer, inset ->
            Text(
                label, color = colors.primary, style = GeistType.copy16,
                modifier = outer.testTag(FormatCustomizationTags.label(tag)).then(inset),
            )
        }
        val indicator: @Composable (Modifier) -> Unit = { modifier ->
            AppSwitch(
                checked = checked, onCheckedChange = null,
                modifier = modifier.testTag(FormatCustomizationTags.indicator(tag)),
            )
        }
        val target = Modifier.fillMaxWidth().testTag(tag)
            .clip(shape).background(colors.background200)
            .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)
            .heightIn(min = GroupRowMinHeight)
            .padding(vertical = GeistSpacing.space2)
        if (stacked) {
            Column(target, verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1, Alignment.CenterVertically)) {
                text(Modifier.fillMaxWidth(), Modifier.padding(horizontal = GeistSpacing.space4))
                indicator(Modifier.align(Alignment.End).padding(end = GeistSpacing.space4))
            }
        } else {
            Row(target, verticalAlignment = Alignment.CenterVertically) {
                text(Modifier.weight(1f), Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space3))
                indicator(Modifier.padding(end = GeistSpacing.space4))
            }
        }
    }
}
