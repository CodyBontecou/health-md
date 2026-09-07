package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.FrontmatterKeyStyle
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.theme.*

internal object FrontmatterCustomizationTags {
    const val BACK = "frontmatter.back"
    const val BODY = "frontmatter.body"
    const val DATE_TOGGLE = "frontmatter.date.toggle"
    const val DATE_KEY = "frontmatter.date.key"
    const val TYPE_TOGGLE = "frontmatter.type.toggle"
    const val TYPE_KEY = "frontmatter.type.key"
    const val TYPE_VALUE = "frontmatter.type.value"
    const val CUSTOM_KEY = "frontmatter.custom.key"
    const val CUSTOM_VALUE = "frontmatter.custom.value"
    const val CUSTOM_ADD = "frontmatter.custom.add"
    const val PLACEHOLDER_KEY = "frontmatter.placeholder.key"
    const val PLACEHOLDER_ADD = "frontmatter.placeholder.add"
    const val SEARCH = "frontmatter.search"
    fun style(style: FrontmatterKeyStyle) = "frontmatter.style.${style.name}"
    fun metric(key: String) = "frontmatter.metric.$key"
    fun outputKey(key: String) = "frontmatter.output.$key"
    fun custom(key: String) = "frontmatter.custom.entry.$key"
    fun placeholder(key: String) = "frontmatter.placeholder.entry.$key"
    fun delete(entry: String) = "$entry.delete"
    fun label(field: String) = "$field.label"
    fun currentValue(field: String) = "$field.currentValue"
}

/** UI-only controls; the screen owns the existing configuration transforms and draft values. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FrontmatterCustomizationKeyStyles(
    selected: FrontmatterKeyStyle,
    onSelected: (FrontmatterKeyStyle) -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = GeistAdaptiveLayout.stackActions(maxWidth.value, LocalDensity.current.fontScale)
        FlowRow(
            modifier = Modifier.fillMaxWidth().selectableGroup(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs),
            maxItemsInEachRow = if (stacked) 1 else 2,
        ) {
            FrontmatterKeyStyle.entries.forEach { style ->
                val isSelected = selected == style
                val shape = RoundedCornerShape(Radii.card)
                Row(
                    modifier = Modifier.weight(1f).heightIn(min = GeistSizes.minimumTouchTarget)
                        .testTag(FrontmatterCustomizationTags.style(style)).clip(shape)
                        .background(if (isSelected) AppColors.accentSubtle else AppColors.bgSecondary)
                        .border(1.dp, if (isSelected) AppColors.accentBorder else AppColors.borderDefault, shape)
                        .selectable(selected = isSelected, role = Role.RadioButton, onClick = { onSelected(style) })
                        .padding(Spacing.xs),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                ) {
                    // These are the existing machine-readable style examples, not translated prose.
                    Text(
                        when (style) {
                            FrontmatterKeyStyle.SNAKE_CASE -> "snake_case"
                            FrontmatterKeyStyle.CAMEL_CASE -> "camelCase"
                        },
                        style = GeistType.copy16.copy(fontFamily = GeistMono),
                        color = if (isSelected) AppColors.accent else AppColors.textSecondary,
                        modifier = Modifier.weight(1f),
                    )
                    RadioButton(
                        selected = isSelected, onClick = null,
                        colors = RadioButtonDefaults.colors(selectedColor = AppColors.accent, unselectedColor = AppColors.textSecondary),
                        modifier = Modifier.clearAndSetSemantics {},
                    )
                }
            }
        }
    }
}

/** Labels use the full width in reading layouts; there is only one labeled switch target. */
@Composable
internal fun FrontmatterCustomizationToggle(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    tag: String,
    textStyle: TextStyle = GeistType.copy16,
    fullWidthLabel: Boolean = false,
) {
    val state = stringResource(if (checked) R.string.enabled else R.string.disabled)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = fullWidthLabel ||
            GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        val control: @Composable () -> Unit = {
            Switch(
                checked = checked, onCheckedChange = null,
                modifier = Modifier.clearAndSetSemantics {},
                colors = SwitchDefaults.colors(
                    checkedThumbColor = AppColors.onAccent,
                    checkedTrackColor = AppColors.accent,
                    uncheckedThumbColor = AppColors.textMuted,
                    uncheckedTrackColor = AppColors.bgSecondary,
                    uncheckedBorderColor = AppColors.borderDefault,
                ),
            )
        }
        Column(
            Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget).testTag(tag)
                .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)
                .semantics { stateDescription = state }
                .padding(vertical = Spacing.xs),
        ) {
            if (stacked) {
                Text(label, style = textStyle, color = AppColors.textPrimary,
                    modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.label(tag)))
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(state, style = GeistType.copy13, color = AppColors.textSecondary,
                        modifier = Modifier.weight(1f).clearAndSetSemantics {})
                    control()
                }
            } else {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(label, style = textStyle, color = AppColors.textPrimary,
                        modifier = Modifier.weight(1f).testTag(FrontmatterCustomizationTags.label(tag)))
                    control()
                }
            }
        }
    }
}

/** A stable composition preserves keyboard focus as the key/value pair reflows. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FrontmatterCustomizationInputPair(
    keyField: @Composable (Modifier) -> Unit,
    valueField: @Composable (Modifier) -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = GeistAdaptiveLayout.stackActions(maxWidth.value, LocalDensity.current.fontScale)
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs),
            maxItemsInEachRow = if (stacked) 1 else 2,
        ) {
            keyField(Modifier.weight(1f))
            valueField(Modifier.weight(1f))
        }
    }
}

/** No floating label or font reduction. Identifiers scroll during editing without rewriting them. */
@Composable
internal fun FrontmatterCustomizationTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    tag: String,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    context: String? = null,
    identifier: Boolean = true,
    imeAction: ImeAction = ImeAction.Done,
) {
    val description = listOfNotNull(context, label).joinToString(", ")
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    var focused by remember { mutableStateOf(false) }
    var fieldWidth by remember { mutableIntStateOf(0) }
    val style = if (identifier) GeistType.copy16.copy(fontFamily = GeistMono) else GeistType.copy16
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val horizontalPadding = with(density) { Spacing.sm.roundToPx() * 2 }
    val valueOverflows = remember(value, style, measurer, density, fieldWidth, horizontalPadding) {
        // Only determine whether a second reading surface is needed. Keep measurement
        // bounded instead of creating an arbitrarily wide paragraph for a saved value.
        fieldWidth > 0 && measurer.measure(
            text = value,
            style = style,
            maxLines = 1,
            constraints = Constraints(maxWidth = (fieldWidth - horizontalPadding).coerceAtLeast(1)),
        ).hasVisualOverflow
    }
    val shape = RoundedCornerShape(Radii.card)
    Column(modifier.padding(vertical = Spacing.xxs), verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Text(label, style = GeistType.copy16, color = AppColors.textPrimary,
            modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.label(tag)))
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            enabled = enabled,
            singleLine = true,
            textStyle = style.copy(color = if (enabled) AppColors.textPrimary else AppColors.textMuted),
            cursorBrush = SolidColor(AppColors.accent),
            keyboardOptions = KeyboardOptions(imeAction = imeAction),
            keyboardActions = KeyboardActions(
                onNext = { focusManager.moveFocus(FocusDirection.Next) },
                onDone = { focusManager.clearFocus(); keyboard?.hide() },
            ),
            decorationBox = { innerField ->
                Box(Modifier.padding(Spacing.sm), contentAlignment = Alignment.CenterStart) { innerField() }
            },
            modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
                .testTag(tag).semantics { contentDescription = description }
                .onSizeChanged { fieldWidth = it.width }
                .onFocusChanged { focused = it.isFocused }
                .clip(shape).background(AppColors.bgPrimary)
                .border(1.dp, if (focused) AppColors.accent else AppColors.borderDefault, shape),
        )
        if (fieldWidth > 0 && (valueOverflows || value.contains('\n'))) {
            // A separate wrapping reading surface also exposes long disabled values. It does
            // not make the single-line editing/touch target taller than a short viewport.
            Text(value, style = style, color = AppColors.textSecondary,
                modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.currentValue(tag)))
        }
    }
}

@Composable
internal fun FrontmatterCustomizationMetric(
    field: CustomFrontmatterField,
    onEnabledChanged: (Boolean) -> Unit,
    onCustomKeyChanged: (String) -> Unit,
) {
    Column(Modifier.fillMaxWidth().padding(vertical = Spacing.xs)) {
        FrontmatterCustomizationToggle(
            label = field.originalKey, checked = field.isEnabled, onCheckedChange = onEnabledChanged,
            tag = FrontmatterCustomizationTags.metric(field.originalKey),
            textStyle = GeistType.copy14Mono, fullWidthLabel = true,
        )
        FrontmatterCustomizationTextField(
            label = stringResource(R.string.frontmatter_output_key), value = field.customKey,
            onValueChange = onCustomKeyChanged, enabled = field.isEnabled,
            context = field.originalKey, tag = FrontmatterCustomizationTags.outputKey(field.originalKey),
        )
    }
}

@Composable
internal fun FrontmatterCustomizationEntry(
    title: String,
    subtitle: String,
    deleteDescription: String,
    tag: String,
    onDelete: () -> Unit,
) {
    Column(Modifier.fillMaxWidth().testTag(tag).padding(vertical = Spacing.xs),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        Text(title, style = GeistType.copy14Mono, color = AppColors.textPrimary,
            modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.label(tag)))
        Text(subtitle, style = GeistType.copy13, color = AppColors.textSecondary,
            modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.currentValue(tag)))
        // Keep the action compact even for arbitrarily long saved keys/values. Its spoken
        // label includes the visible key and group; its current value remains available too.
        SecondaryButton(
            text = stringResource(R.string.action_delete_field), onClick = onDelete,
            modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.delete(tag))
                .semantics { contentDescription = deleteDescription; stateDescription = subtitle },
        )
    }
}
