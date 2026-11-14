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
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Shape
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
import androidx.compose.ui.semantics.error
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
import com.healthmd.domain.model.FrontmatterConflictSource
import com.healthmd.domain.model.FrontmatterConflictSection
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.presentation.common.AppSwitch
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
    // Route only canonical field IDs or fixed group tags, never user-defined names.
    fun conflictTarget(source: FrontmatterConflictSource): String = when (source.section) {
        FrontmatterConflictSection.METRIC -> if (source.originalKey in HealthDataFields.allKeys) outputKey(source.originalKey) else SEARCH
        FrontmatterConflictSection.DATE -> DATE_KEY
        FrontmatterConflictSection.TYPE -> TYPE_KEY
        FrontmatterConflictSection.CUSTOM -> CUSTOM_KEY
        FrontmatterConflictSection.PLACEHOLDER -> PLACEHOLDER_KEY
    }
}

/** UI-only controls; the screen owns the existing configuration transforms and draft values. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun FrontmatterCustomizationKeyStyles(
    selected: FrontmatterKeyStyle,
    onSelected: (FrontmatterKeyStyle) -> Unit,
) {
    val colors = LocalGeistColors.current
    val styles = FrontmatterKeyStyle.entries
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = GeistAdaptiveLayout.stackActions(maxWidth.value, LocalDensity.current.fontScale)
        FlowRow(
            modifier = Modifier.fillMaxWidth().selectableGroup(),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalArrangement = Arrangement.spacedBy(2.dp),
            maxItemsInEachRow = if (stacked) 1 else styles.size,
        ) {
            styles.forEachIndexed { index, style ->
                val isSelected = selected == style
                val shape = if (stacked) groupRowShape(index, styles.size) else groupCellShape(index, styles.size)
                Row(
                    modifier = Modifier.weight(1f).heightIn(min = GroupRowMinHeight)
                        .testTag(FrontmatterCustomizationTags.style(style)).clip(shape)
                        .background(if (isSelected) colors.secondaryContainer else colors.background200)
                        .selectable(selected = isSelected, role = Role.RadioButton, onClick = { onSelected(style) })
                        .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                ) {
                    RadioButton(
                        selected = isSelected, onClick = null,
                        colors = RadioButtonDefaults.colors(selectedColor = colors.brandPrimary, unselectedColor = colors.secondary),
                        modifier = Modifier.clearAndSetSemantics {},
                    )
                    // These are the existing machine-readable style examples, not translated prose.
                    Text(
                        when (style) {
                            FrontmatterKeyStyle.SNAKE_CASE -> "snake_case"
                            FrontmatterKeyStyle.CAMEL_CASE -> "camelCase"
                        },
                        style = GeistType.copy16.copy(fontFamily = GeistMono),
                        color = if (isSelected) colors.onSecondaryContainer else colors.primary,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }
    }
}

/**
 * One whole-row labeled switch target (the switch is indicator artwork). Labels use the full
 * width in reading layouts; insets sit inside the label node so it reports that width.
 */
@Composable
internal fun FrontmatterCustomizationToggle(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
    tag: String,
    textStyle: TextStyle = GeistType.copy16,
    fullWidthLabel: Boolean = false,
) {
    val colors = LocalGeistColors.current
    val state = stringResource(if (checked) R.string.enabled else R.string.disabled)
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val stacked = fullWidthLabel ||
            GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        val control: @Composable () -> Unit = {
            AppSwitch(checked = checked, onCheckedChange = null, modifier = Modifier.clearAndSetSemantics {})
        }
        Column(
            Modifier.fillMaxWidth().heightIn(min = GroupRowMinHeight).testTag(tag)
                .toggleable(value = checked, role = Role.Switch, onValueChange = onCheckedChange)
                .semantics { stateDescription = state }
                .padding(vertical = GeistSpacing.space2),
            verticalArrangement = Arrangement.Center,
        ) {
            if (stacked) {
                Text(label, style = textStyle, color = colors.primary,
                    modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.label(tag))
                        .padding(horizontal = GeistSpacing.space4))
                Row(
                    modifier = Modifier.fillMaxWidth().padding(horizontal = GeistSpacing.space4),
                    horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(state, style = GeistType.copy13, color = colors.secondary,
                        modifier = Modifier.weight(1f).clearAndSetSemantics {})
                    control()
                }
            } else {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(end = GeistSpacing.space4),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(label, style = textStyle, color = colors.primary,
                        modifier = Modifier.weight(1f).testTag(FrontmatterCustomizationTags.label(tag))
                            .padding(start = GeistSpacing.space4, end = GeistSpacing.space3))
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
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            maxItemsInEachRow = if (stacked) 1 else 2,
        ) {
            keyField(Modifier.weight(1f))
            valueField(Modifier.weight(1f))
        }
    }
}

/**
 * An outlined input with its label outside the field: no floating label or font reduction.
 * Identifiers scroll during editing without rewriting them; long values get a wrapping reading
 * surface below.
 */
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
    errorText: String? = null,
) {
    val colors = LocalGeistColors.current
    val description = listOfNotNull(context, label).joinToString(", ")
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    var focused by remember { mutableStateOf(false) }
    var fieldWidth by remember { mutableIntStateOf(0) }
    val style = if (identifier) GeistType.copy16.copy(fontFamily = GeistMono) else GeistType.copy16
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val horizontalPadding = with(density) { GeistSpacing.space4.roundToPx() * 2 }
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
    val shape = RoundedCornerShape(GeistRadii.extraSmall)
    val outline = when {
        errorText != null -> colors.red.c900
        focused -> colors.brandPrimary
        enabled -> colors.gray.c700
        else -> colors.gray.c500
    }
    Column(modifier, verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
        Text(label, style = GeistType.copy16, color = if (enabled) colors.primary else colors.secondary,
            modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.label(tag)))
        BasicTextField(
            value = value,
            onValueChange = onValueChange,
            enabled = enabled,
            singleLine = true,
            textStyle = style.copy(color = if (enabled) colors.primary else colors.disabled),
            cursorBrush = SolidColor(colors.brandPrimary),
            keyboardOptions = KeyboardOptions(imeAction = imeAction),
            keyboardActions = KeyboardActions(
                onNext = { focusManager.moveFocus(FocusDirection.Next) },
                onDone = { focusManager.clearFocus(); keyboard?.hide() },
            ),
            decorationBox = { innerField ->
                Box(
                    Modifier.padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
                    contentAlignment = Alignment.CenterStart,
                ) { innerField() }
            },
            modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
                .testTag(tag).semantics {
                    contentDescription = description
                    errorText?.let { error(it) }
                }
                .onSizeChanged { fieldWidth = it.width }
                .onFocusChanged { focused = it.isFocused }
                .clip(shape)
                .border(if (focused) 2.dp else 1.dp, outline, shape),
        )
        errorText?.let { message ->
            Text(message, style = GeistType.copy13, color = colors.red.c900,
                modifier = Modifier.fillMaxWidth().testTag("$tag.error"))
        }
        if (fieldWidth > 0 && (valueOverflows || value.contains('\n'))) {
            // A separate wrapping reading surface also exposes long disabled values. It does
            // not make the single-line editing/touch target taller than a short viewport.
            Text(value, style = style, color = colors.secondary,
                modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.currentValue(tag)))
        }
    }
}

/** A metric's tonal list-group row: its whole-row switch, then its output-key input. */
@Composable
internal fun FrontmatterCustomizationMetric(
    field: CustomFrontmatterField,
    shape: Shape,
    onEnabledChanged: (Boolean) -> Unit,
    onCustomKeyChanged: (String) -> Unit,
    hasKeyConflict: Boolean = false,
    modifier: Modifier = Modifier,
) {
    FrontmatterCustomizationGroupRow(shape, modifier = modifier, contentPadding = false) {
        FrontmatterCustomizationToggle(
            label = field.originalKey, checked = field.isEnabled, onCheckedChange = onEnabledChanged,
            tag = FrontmatterCustomizationTags.metric(field.originalKey),
            textStyle = GeistType.copy14Mono, fullWidthLabel = true,
        )
        FrontmatterCustomizationTextField(
            label = stringResource(R.string.frontmatter_output_key), value = field.customKey,
            onValueChange = onCustomKeyChanged, enabled = field.isEnabled,
            context = field.originalKey, tag = FrontmatterCustomizationTags.outputKey(field.originalKey),
            errorText = if (hasKeyConflict) stringResource(R.string.frontmatter_key_conflict_inline) else null,
            modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space4),
        )
    }
}

/**
 * A tonal list-group row container. With [contentPadding] its content sits inside the 16dp row
 * inset; without it, whole-row targets (switch rows) span the row and inset their own content.
 */
@Composable
internal fun FrontmatterCustomizationGroupRow(
    shape: Shape,
    modifier: Modifier = Modifier,
    contentPadding: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    Column(
        modifier.fillMaxWidth().clip(shape).background(colors.background200)
            .then(if (contentPadding) Modifier.padding(GeistSpacing.space4) else Modifier),
        verticalArrangement = Arrangement.spacedBy(if (contentPadding) GeistSpacing.space3 else GeistSpacing.space1),
        content = content,
    )
}

/** A saved key as its own tonal row: the key, its value, and a separate contextual Delete. */
@Composable
internal fun FrontmatterCustomizationEntry(
    title: String,
    subtitle: String,
    deleteDescription: String,
    tag: String,
    shape: Shape,
    onDelete: () -> Unit,
) {
    val colors = LocalGeistColors.current
    FrontmatterCustomizationGroupRow(shape, modifier = Modifier.testTag(tag)) {
        Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
            Text(title, style = GeistType.copy14Mono, color = colors.primary,
                modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.label(tag)))
            Text(subtitle, style = GeistType.copy13, color = colors.secondary,
                modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.currentValue(tag)))
        }
        // Keep the action compact even for arbitrarily long saved keys/values. Its spoken
        // label includes the visible key and group; its current value remains available too.
        SecondaryButton(
            text = stringResource(R.string.action_delete_field), onClick = onDelete,
            modifier = Modifier.align(Alignment.End).testTag(FrontmatterCustomizationTags.delete(tag))
                .semantics { contentDescription = deleteDescription; stateDescription = subtitle },
        )
    }
}
