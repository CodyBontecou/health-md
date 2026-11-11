package com.healthmd.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Add
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.input.ImeAction
import com.healthmd.R
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SubScreenTopBar
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing

@Composable
fun FrontmatterCustomizationScreen(
    configuration: FrontmatterConfiguration,
    onConfigurationChanged: (FrontmatterConfiguration) -> Unit,
    onBack: () -> Unit,
) {
    var search by remember { mutableStateOf("") }
    var customFieldKey by remember { mutableStateOf("") }
    var customFieldValue by remember { mutableStateOf("") }
    var placeholderKey by remember { mutableStateOf("") }

    val normalizedConfiguration = remember(configuration) { configuration.withDefaultFields() }

    Box(Modifier.fillMaxSize().imePadding(), contentAlignment = Alignment.TopCenter) {
        Column(
            modifier = Modifier.widthIn(max = GeistSizes.readableContentMaxWidth).fillMaxSize()
                .testTag(FrontmatterCustomizationTags.BODY)
                .verticalScroll(rememberScrollState()),
        ) {
            // Back shares the scroll area so navigation does not reserve scarce
            // keyboard/landscape height.
            SubScreenTopBar(title = stringResource(R.string.frontmatter_customization_title), onBack = onBack, backButtonModifier = Modifier.testTag(FrontmatterCustomizationTags.BACK))
            Column(
                Modifier.fillMaxWidth().padding(
                    start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space8,
                ),
            ) {
                SettingsGroup(
                    title = stringResource(R.string.frontmatter_key_style_section),
                    rows = listOf { _ ->
                        FrontmatterCustomizationKeyStyles(normalizedConfiguration.keyStyle) { style ->
                            onConfigurationChanged(normalizedConfiguration.withKeyStyle(style))
                        }
                    },
                )

                SettingsGroup(
                    title = stringResource(R.string.frontmatter_date_type_section),
                    rows = listOf(
                        { shape ->
                            FrontmatterCustomizationGroupRow(shape, contentPadding = false) {
                                FrontmatterCustomizationToggle(
                                    label = stringResource(R.string.frontmatter_include_date),
                                    checked = normalizedConfiguration.includeDate,
                                    tag = FrontmatterCustomizationTags.DATE_TOGGLE,
                                    onCheckedChange = { onConfigurationChanged(normalizedConfiguration.copy(includeDate = it)) },
                                )
                                if (normalizedConfiguration.includeDate) {
                                    FrontmatterCustomizationTextField(
                                        label = stringResource(R.string.frontmatter_date_key),
                                        value = normalizedConfiguration.customDateKey,
                                        onValueChange = { onConfigurationChanged(normalizedConfiguration.copy(customDateKey = it)) },
                                        tag = FrontmatterCustomizationTags.DATE_KEY,
                                        modifier = Modifier.rowFieldInset(),
                                    )
                                }
                            }
                        },
                        { shape ->
                            FrontmatterCustomizationGroupRow(shape, contentPadding = false) {
                                FrontmatterCustomizationToggle(
                                    label = stringResource(R.string.frontmatter_include_type),
                                    checked = normalizedConfiguration.includeType,
                                    tag = FrontmatterCustomizationTags.TYPE_TOGGLE,
                                    onCheckedChange = { onConfigurationChanged(normalizedConfiguration.copy(includeType = it)) },
                                )
                                if (normalizedConfiguration.includeType) {
                                    Column(Modifier.rowFieldInset(), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                                        FrontmatterCustomizationTextField(
                                            label = stringResource(R.string.frontmatter_type_key),
                                            value = normalizedConfiguration.customTypeKey,
                                            onValueChange = { onConfigurationChanged(normalizedConfiguration.copy(customTypeKey = it)) },
                                            tag = FrontmatterCustomizationTags.TYPE_KEY, imeAction = ImeAction.Next,
                                        )
                                        FrontmatterCustomizationTextField(
                                            label = stringResource(R.string.frontmatter_type_value),
                                            value = normalizedConfiguration.customTypeValue,
                                            onValueChange = { onConfigurationChanged(normalizedConfiguration.copy(customTypeValue = it)) },
                                            tag = FrontmatterCustomizationTags.TYPE_VALUE,
                                        )
                                    }
                                }
                            }
                        },
                    ),
                )

                val customGroup = stringResource(R.string.frontmatter_custom_fields_section)
                val customEntries = normalizedConfiguration.customFields.toSortedMap().toList()
                SettingsGroup(
                    title = customGroup,
                    rows = listOf<@Composable (Shape) -> Unit> { shape ->
                        FrontmatterCustomizationGroupRow(shape) {
                            FrontmatterCustomizationInputPair(
                                keyField = { modifier ->
                                    FrontmatterCustomizationTextField(
                                        label = stringResource(R.string.frontmatter_field_key),
                                        value = customFieldKey, onValueChange = { customFieldKey = it },
                                        modifier = modifier, context = customGroup, tag = FrontmatterCustomizationTags.CUSTOM_KEY,
                                        imeAction = ImeAction.Next,
                                    )
                                },
                                valueField = { modifier ->
                                    FrontmatterCustomizationTextField(
                                        label = stringResource(R.string.frontmatter_field_value),
                                        value = customFieldValue, onValueChange = { customFieldValue = it },
                                        modifier = modifier, context = customGroup, tag = FrontmatterCustomizationTags.CUSTOM_VALUE,
                                    )
                                },
                            )
                            SecondaryButton(
                                text = stringResource(R.string.a11y_frontmatter_add_custom_field),
                                icon = Icons.Outlined.Add,
                                modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.CUSTOM_ADD),
                                onClick = {
                                    val key = customFieldKey.trim()
                                    if (key.isNotEmpty()) {
                                        onConfigurationChanged(
                                            normalizedConfiguration.copy(
                                                customFields = normalizedConfiguration.customFields + (key to customFieldValue.trim()),
                                            )
                                        )
                                        customFieldKey = ""
                                        customFieldValue = ""
                                    }
                                },
                            )
                        }
                    } + customEntries.map { (key, value) ->
                        { shape ->
                            FrontmatterCustomizationEntry(
                                title = key, subtitle = value,
                                tag = FrontmatterCustomizationTags.custom(key),
                                shape = shape,
                                deleteDescription = stringResource(R.string.a11y_frontmatter_delete_custom_field, key),
                                onDelete = {
                                    onConfigurationChanged(normalizedConfiguration.copy(customFields = normalizedConfiguration.customFields - key))
                                },
                            )
                        }
                    },
                )

                val placeholderGroup = stringResource(R.string.frontmatter_placeholder_fields_section)
                val placeholders = normalizedConfiguration.placeholderFields.sorted()
                SettingsGroup(
                    title = placeholderGroup,
                    rows = listOf<@Composable (Shape) -> Unit> { shape ->
                        FrontmatterCustomizationGroupRow(shape) {
                            FrontmatterCustomizationTextField(
                                label = stringResource(R.string.frontmatter_field_key),
                                value = placeholderKey, onValueChange = { placeholderKey = it },
                                context = placeholderGroup, tag = FrontmatterCustomizationTags.PLACEHOLDER_KEY,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            SecondaryButton(
                                text = stringResource(R.string.a11y_frontmatter_add_placeholder_field),
                                icon = Icons.Outlined.Add,
                                modifier = Modifier.fillMaxWidth().testTag(FrontmatterCustomizationTags.PLACEHOLDER_ADD),
                                onClick = {
                                    val key = placeholderKey.trim()
                                    if (key.isNotEmpty() && key !in normalizedConfiguration.placeholderFields) {
                                        onConfigurationChanged(
                                            normalizedConfiguration.copy(
                                                placeholderFields = (normalizedConfiguration.placeholderFields + key).sorted(),
                                            )
                                        )
                                        placeholderKey = ""
                                    }
                                },
                            )
                        }
                    } + placeholders.map { key ->
                        { shape ->
                            FrontmatterCustomizationEntry(
                                title = key, subtitle = stringResource(R.string.frontmatter_placeholder_value),
                                tag = FrontmatterCustomizationTags.placeholder(key),
                                shape = shape,
                                deleteDescription = stringResource(R.string.a11y_frontmatter_delete_placeholder_field, key),
                                onDelete = {
                                    onConfigurationChanged(normalizedConfiguration.copy(placeholderFields = normalizedConfiguration.placeholderFields - key))
                                },
                            )
                        }
                    },
                )

                val metricGroup = stringResource(R.string.frontmatter_metric_fields_section)
                val filteredFields = normalizedConfiguration.fields.filter { field ->
                    search.isBlank() || field.originalKey.contains(search, ignoreCase = true) || field.customKey.contains(search, ignoreCase = true)
                }
                SettingsGroup(
                    title = metricGroup,
                    rows = listOf<@Composable (Shape) -> Unit> { shape ->
                        FrontmatterCustomizationGroupRow(shape) {
                            FrontmatterCustomizationTextField(
                                label = stringResource(R.string.search), value = search, onValueChange = { search = it },
                                context = metricGroup,
                                tag = FrontmatterCustomizationTags.SEARCH, identifier = false,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    } + filteredFields.map { field ->
                        { shape ->
                            key(field.originalKey) {
                                FrontmatterCustomizationMetric(
                                    field = field,
                                    shape = shape,
                                    onEnabledChanged = { enabled ->
                                        onConfigurationChanged(normalizedConfiguration.updateField(field.originalKey) { it.copy(isEnabled = enabled) })
                                    },
                                    onCustomKeyChanged = { key ->
                                        onConfigurationChanged(normalizedConfiguration.updateField(field.originalKey) { it.copy(customKey = key) })
                                    },
                                )
                            }
                        }
                    },
                )
            }
        }
    }
}

/** Inputs under a whole-row switch take the row's 16dp inset. */
private fun Modifier.rowFieldInset(): Modifier =
    fillMaxWidth().padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space4)

private fun FrontmatterConfiguration.withDefaultFields(): FrontmatterConfiguration {
    val existingByKey = fields.associateBy { it.originalKey }
    val normalized = HealthDataFields.allKeys.map { key -> existingByKey[key] ?: CustomFrontmatterField(key, keyStyle.apply(key)) }
    return copy(fields = normalized)
}

private fun FrontmatterConfiguration.updateField(
    originalKey: String,
    transform: (CustomFrontmatterField) -> CustomFrontmatterField,
): FrontmatterConfiguration = withDefaultFields().copy(
    fields = withDefaultFields().fields.map { field ->
        if (field.originalKey == originalKey) transform(field) else field
    },
)
