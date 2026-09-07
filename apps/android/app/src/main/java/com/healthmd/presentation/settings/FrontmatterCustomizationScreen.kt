package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import com.healthmd.R
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

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

    Column(Modifier.fillMaxSize().background(AppColors.bgPrimary).imePadding()) {
        Column(
            modifier = Modifier.weight(1f).fillMaxWidth().testTag(FrontmatterCustomizationTags.BODY)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = Spacing.md, vertical = Spacing.lg),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            // Back has its own target, separate from the wrapping title. It shares the
            // scroll area so navigation does not reserve scarce keyboard/landscape height.
            SecondaryButton(
                text = stringResource(R.string.back), onClick = onBack,
                icon = Icons.AutoMirrored.Filled.ArrowBack,
                modifier = Modifier.testTag(FrontmatterCustomizationTags.BACK),
            )
            Text(
                stringResource(R.string.frontmatter_customization_title),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.fillMaxWidth(),
            )

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.frontmatter_key_style_section))
                FrontmatterCustomizationKeyStyles(normalizedConfiguration.keyStyle) { style ->
                    onConfigurationChanged(normalizedConfiguration.withKeyStyle(style))
                }
            }

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.frontmatter_date_type_section))
                FrontmatterCustomizationToggle(
                    label = stringResource(R.string.frontmatter_include_date), checked = normalizedConfiguration.includeDate,
                    tag = FrontmatterCustomizationTags.DATE_TOGGLE,
                    onCheckedChange = { onConfigurationChanged(normalizedConfiguration.copy(includeDate = it)) },
                )
                if (normalizedConfiguration.includeDate) {
                    FrontmatterCustomizationTextField(
                        label = stringResource(R.string.frontmatter_date_key),
                        value = normalizedConfiguration.customDateKey,
                        onValueChange = { onConfigurationChanged(normalizedConfiguration.copy(customDateKey = it)) },
                        tag = FrontmatterCustomizationTags.DATE_KEY,
                    )
                }
                FrontmatterCustomizationToggle(
                    label = stringResource(R.string.frontmatter_include_type), checked = normalizedConfiguration.includeType,
                    tag = FrontmatterCustomizationTags.TYPE_TOGGLE,
                    onCheckedChange = { onConfigurationChanged(normalizedConfiguration.copy(includeType = it)) },
                )
                if (normalizedConfiguration.includeType) {
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

            GeistCard(padding = Spacing.md) {
                val group = stringResource(R.string.frontmatter_custom_fields_section)
                SectionLabel(group)
                FrontmatterCustomizationInputPair(
                    keyField = { modifier ->
                        FrontmatterCustomizationTextField(
                            label = stringResource(R.string.frontmatter_field_key),
                            value = customFieldKey, onValueChange = { customFieldKey = it },
                            modifier = modifier, context = group, tag = FrontmatterCustomizationTags.CUSTOM_KEY,
                            imeAction = ImeAction.Next,
                        )
                    },
                    valueField = { modifier ->
                        FrontmatterCustomizationTextField(
                            label = stringResource(R.string.frontmatter_field_value),
                            value = customFieldValue, onValueChange = { customFieldValue = it },
                            modifier = modifier, context = group, tag = FrontmatterCustomizationTags.CUSTOM_VALUE,
                        )
                    },
                )
                Spacer(Modifier.height(Spacing.xs))
                SecondaryButton(
                    text = stringResource(R.string.a11y_frontmatter_add_custom_field),
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
                normalizedConfiguration.customFields.toSortedMap().forEach { (key, value) ->
                    FrontmatterCustomizationEntry(
                        title = key, subtitle = value,
                        tag = FrontmatterCustomizationTags.custom(key),
                        deleteDescription = stringResource(R.string.a11y_frontmatter_delete_custom_field, key),
                        onDelete = {
                            onConfigurationChanged(normalizedConfiguration.copy(customFields = normalizedConfiguration.customFields - key))
                        },
                    )
                }
            }

            GeistCard(padding = Spacing.md) {
                val group = stringResource(R.string.frontmatter_placeholder_fields_section)
                SectionLabel(group)
                FrontmatterCustomizationTextField(
                    label = stringResource(R.string.frontmatter_field_key),
                    value = placeholderKey, onValueChange = { placeholderKey = it },
                    context = group, tag = FrontmatterCustomizationTags.PLACEHOLDER_KEY,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(Spacing.xs))
                SecondaryButton(
                    text = stringResource(R.string.a11y_frontmatter_add_placeholder_field),
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
                normalizedConfiguration.placeholderFields.sorted().forEach { key ->
                    FrontmatterCustomizationEntry(
                        title = key, subtitle = stringResource(R.string.frontmatter_placeholder_value),
                        tag = FrontmatterCustomizationTags.placeholder(key),
                        deleteDescription = stringResource(R.string.a11y_frontmatter_delete_placeholder_field, key),
                        onDelete = {
                            onConfigurationChanged(normalizedConfiguration.copy(placeholderFields = normalizedConfiguration.placeholderFields - key))
                        },
                    )
                }
            }

            GeistCard(padding = Spacing.md) {
                SectionLabel(stringResource(R.string.frontmatter_metric_fields_section))
                FrontmatterCustomizationTextField(
                    label = stringResource(R.string.search), value = search, onValueChange = { search = it },
                    context = stringResource(R.string.frontmatter_metric_fields_section),
                    tag = FrontmatterCustomizationTags.SEARCH, identifier = false,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(modifier = Modifier.height(Spacing.sm))
                val filteredFields = normalizedConfiguration.fields.filter { field ->
                    search.isBlank() || field.originalKey.contains(search, ignoreCase = true) || field.customKey.contains(search, ignoreCase = true)
                }
                filteredFields.forEach { field ->
                    key(field.originalKey) {
                        FrontmatterCustomizationMetric(
                            field = field,
                            onEnabledChanged = { enabled ->
                                onConfigurationChanged(normalizedConfiguration.updateField(field.originalKey) { it.copy(isEnabled = enabled) })
                            },
                            onCustomKeyChanged = { key ->
                                onConfigurationChanged(normalizedConfiguration.updateField(field.originalKey) { it.copy(customKey = key) })
                            },
                        )
                        HorizontalDivider(color = AppColors.borderSubtle)
                    }
                }
            }

            Spacer(modifier = Modifier.height(Spacing.xl))
        }
    }
}

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
