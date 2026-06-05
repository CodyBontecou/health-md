package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.outlined.Add
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.FrontmatterKeyStyle
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.presentation.common.GlassCard
import com.healthmd.presentation.common.GlassIconButton
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.res.stringResource

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

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(Icons.Filled.ArrowBack, stringResource(R.string.back), tint = AppColors.textPrimary)
            }
            Text(
                stringResource(R.string.frontmatter_customization_title),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Bold,
            )
        }

        GlassCard {
            SectionLabel(stringResource(R.string.frontmatter_key_style_section))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), modifier = Modifier.fillMaxWidth()) {
                FrontmatterKeyStyle.entries.forEach { style ->
                    val selected = normalizedConfiguration.keyStyle == style
                    val label = when (style) {
                        FrontmatterKeyStyle.SNAKE_CASE -> "snake_case"
                        FrontmatterKeyStyle.CAMEL_CASE -> "camelCase"
                    }
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(RoundedCornerShape(100.dp))
                            .background(if (selected) AppColors.accent.copy(alpha = 0.15f) else AppColors.bgSecondary)
                            .border(1.dp, if (selected) AppColors.accent.copy(alpha = 0.5f) else AppColors.glassBorder, RoundedCornerShape(100.dp))
                            .clickable { onConfigurationChanged(normalizedConfiguration.withKeyStyle(style)) }
                            .padding(vertical = 12.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(label, color = if (selected) AppColors.accent else AppColors.textSecondary)
                    }
                }
            }
        }

        GlassCard {
            SectionLabel(stringResource(R.string.frontmatter_date_type_section))
            FrontmatterToggleRow(stringResource(R.string.frontmatter_include_date), normalizedConfiguration.includeDate) {
                onConfigurationChanged(normalizedConfiguration.copy(includeDate = it))
            }
            if (normalizedConfiguration.includeDate) {
                FrontmatterTextField(
                    label = stringResource(R.string.frontmatter_date_key),
                    value = normalizedConfiguration.customDateKey,
                    onValueChange = { onConfigurationChanged(normalizedConfiguration.copy(customDateKey = it)) },
                )
            }
            FrontmatterToggleRow(stringResource(R.string.frontmatter_include_type), normalizedConfiguration.includeType) {
                onConfigurationChanged(normalizedConfiguration.copy(includeType = it))
            }
            if (normalizedConfiguration.includeType) {
                FrontmatterTextField(
                    label = stringResource(R.string.frontmatter_type_key),
                    value = normalizedConfiguration.customTypeKey,
                    onValueChange = { onConfigurationChanged(normalizedConfiguration.copy(customTypeKey = it)) },
                )
                FrontmatterTextField(
                    label = stringResource(R.string.frontmatter_type_value),
                    value = normalizedConfiguration.customTypeValue,
                    onValueChange = { onConfigurationChanged(normalizedConfiguration.copy(customTypeValue = it)) },
                )
            }
        }

        GlassCard {
            SectionLabel(stringResource(R.string.frontmatter_custom_fields_section))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs), modifier = Modifier.fillMaxWidth()) {
                FrontmatterTextField(
                    label = stringResource(R.string.frontmatter_field_key),
                    value = customFieldKey,
                    onValueChange = { customFieldKey = it },
                    modifier = Modifier.weight(1f),
                )
                FrontmatterTextField(
                    label = stringResource(R.string.frontmatter_field_value),
                    value = customFieldValue,
                    onValueChange = { customFieldValue = it },
                    modifier = Modifier.weight(1f),
                )
                GlassIconButton(
                    icon = Icons.Outlined.Add,
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
            normalizedConfiguration.customFields.toSortedMap().forEach { (key, value) ->
                EditableChipRow(
                    title = key,
                    subtitle = value,
                    onDelete = {
                        onConfigurationChanged(normalizedConfiguration.copy(customFields = normalizedConfiguration.customFields - key))
                    },
                )
            }
        }

        GlassCard {
            SectionLabel(stringResource(R.string.frontmatter_placeholder_fields_section))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs), modifier = Modifier.fillMaxWidth()) {
                FrontmatterTextField(
                    label = stringResource(R.string.frontmatter_field_key),
                    value = placeholderKey,
                    onValueChange = { placeholderKey = it },
                    modifier = Modifier.weight(1f),
                )
                GlassIconButton(
                    icon = Icons.Outlined.Add,
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
            normalizedConfiguration.placeholderFields.sorted().forEach { key ->
                EditableChipRow(
                    title = key,
                    subtitle = stringResource(R.string.frontmatter_placeholder_value),
                    onDelete = {
                        onConfigurationChanged(normalizedConfiguration.copy(placeholderFields = normalizedConfiguration.placeholderFields - key))
                    },
                )
            }
        }

        GlassCard {
            SectionLabel(stringResource(R.string.frontmatter_metric_fields_section))
            FrontmatterTextField(
                label = stringResource(R.string.search),
                value = search,
                onValueChange = { search = it },
                modifier = Modifier.fillMaxWidth(),
            )
            Spacer(modifier = Modifier.height(Spacing.sm))
            val filteredFields = normalizedConfiguration.fields.filter { field ->
                search.isBlank() || field.originalKey.contains(search, ignoreCase = true) || field.customKey.contains(search, ignoreCase = true)
            }
            filteredFields.forEach { field ->
                MetricFieldRow(
                    field = field,
                    onEnabledChanged = { enabled ->
                        onConfigurationChanged(normalizedConfiguration.updateField(field.originalKey) { it.copy(isEnabled = enabled) })
                    },
                    onCustomKeyChanged = { key ->
                        onConfigurationChanged(normalizedConfiguration.updateField(field.originalKey) { it.copy(customKey = key) })
                    },
                )
                HorizontalDivider(color = AppColors.glassBorder.copy(alpha = 0.5f))
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

@Composable
private fun MetricFieldRow(
    field: CustomFrontmatterField,
    onEnabledChanged: (Boolean) -> Unit,
    onCustomKeyChanged: (String) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.xs)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(field.originalKey, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyMedium)
                Text(if (field.isEnabled) stringResource(R.string.enabled) else stringResource(R.string.disabled), color = AppColors.textMuted, style = MaterialTheme.typography.bodySmall)
            }
            Switch(
                checked = field.isEnabled,
                onCheckedChange = onEnabledChanged,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = Color.White,
                    checkedTrackColor = AppColors.accent,
                    uncheckedThumbColor = AppColors.textMuted,
                    uncheckedTrackColor = AppColors.bgSecondary,
                ),
            )
        }
        FrontmatterTextField(
            label = stringResource(R.string.frontmatter_output_key),
            value = field.customKey,
            onValueChange = onCustomKeyChanged,
            modifier = Modifier.fillMaxWidth(),
            enabled = field.isEnabled,
        )
    }
}

@Composable
private fun FrontmatterToggleRow(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.xs),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = AppColors.accent,
                uncheckedThumbColor = AppColors.textMuted,
                uncheckedTrackColor = AppColors.bgSecondary,
            ),
        )
    }
}

@Composable
private fun FrontmatterTextField(
    label: String,
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.padding(vertical = 4.dp),
        label = { Text(label) },
        enabled = enabled,
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = AppColors.accent,
            unfocusedBorderColor = AppColors.borderDefault,
            focusedTextColor = AppColors.textPrimary,
            unfocusedTextColor = AppColors.textPrimary,
            disabledTextColor = AppColors.textMuted,
            cursorColor = AppColors.accent,
        ),
        shape = RoundedCornerShape(12.dp),
        singleLine = true,
    )
}

@Composable
private fun EditableChipRow(title: String, subtitle: String, onDelete: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = Spacing.xs),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyMedium)
            Text(subtitle, color = AppColors.textMuted, style = MaterialTheme.typography.bodySmall)
        }
        IconButton(onClick = onDelete) {
            Icon(Icons.Outlined.Delete, contentDescription = stringResource(R.string.delete), tint = AppColors.textMuted)
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
