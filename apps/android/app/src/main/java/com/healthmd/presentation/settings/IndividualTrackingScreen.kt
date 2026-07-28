package com.healthmd.presentation.settings

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.IndeterminateCheckBox
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.presentation.common.*
import com.healthmd.presentation.i18n.displayNameRes
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun IndividualTrackingScreen(
    settings: IndividualTrackingSettings,
    onSettingsChanged: (IndividualTrackingSettings) -> Unit,
    onBack: () -> Unit,
) {
    var searchQuery by remember { mutableStateOf("") }
    var expandedCategories by remember { mutableStateOf(HealthMetrics.categories.toSet()) }
    val context = LocalContext.current

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary),
        contentPadding = PaddingValues(horizontal = Spacing.md, vertical = Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        item(key = "header") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = onBack) {
                    Icon(Icons.Filled.ArrowBack, stringResource(R.string.back), tint = AppColors.textPrimary)
                }
                Text(
                    stringResource(R.string.individual_tracking_title),
                    style = MaterialTheme.typography.titleLarge,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    "${settings.trackedMetricCount}/${HealthMetrics.totalCount}",
                    style = MaterialTheme.typography.labelLarge,
                    color = AppColors.accent,
                )
            }
        }

        item(key = "description") {
            GeistCard {
                Text(
                    stringResource(R.string.individual_tracking_description),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
        }

        item(key = "master_toggle") {
            GeistCard {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(stringResource(R.string.individual_tracking_enable_title), color = AppColors.textPrimary, style = MaterialTheme.typography.titleMedium)
                        Text(
                            stringResource(R.string.individual_tracking_metrics_count, settings.trackedMetricCount),
                            color = AppColors.textSecondary,
                            style = MaterialTheme.typography.bodySmall,
                        )
                    }
                    Switch(
                        checked = settings.globalEnabled,
                        onCheckedChange = { onSettingsChanged(settings.copy(globalEnabled = it)) },
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = AppColors.onAccent,
                            checkedTrackColor = AppColors.accent,
                            uncheckedThumbColor = AppColors.textMuted,
                            uncheckedTrackColor = AppColors.bgSecondary,
                            uncheckedBorderColor = AppColors.borderDefault,
                        ),
                    )
                }
            }
        }

        if (settings.globalEnabled) {
            item(key = "quick_actions") {
                GeistCard {
                    SectionLabel(stringResource(R.string.section_quick_actions))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                    ) {
                        SecondaryButton(
                            text = stringResource(R.string.action_suggested),
                            onClick = { onSettingsChanged(settings.enableSuggested()) },
                            modifier = Modifier.weight(1f),
                        )
                        SecondaryButton(
                            text = stringResource(R.string.action_all),
                            onClick = { onSettingsChanged(settings.enableAll()) },
                            modifier = Modifier.weight(1f),
                        )
                        SecondaryButton(
                            text = stringResource(R.string.action_none),
                            onClick = { onSettingsChanged(settings.disableAll()) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }
            }

            item(key = "search") {
                OutlinedTextField(
                    value = searchQuery,
                    onValueChange = { searchQuery = it },
                    modifier = Modifier.fillMaxWidth(),
                    placeholder = { Text(stringResource(R.string.search_metrics_hint), color = AppColors.textMuted) },
                    leadingIcon = { Icon(Icons.Filled.Search, null, tint = AppColors.textMuted) },
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedBorderColor = AppColors.accent,
                        unfocusedBorderColor = AppColors.borderDefault,
                        focusedTextColor = AppColors.textPrimary,
                        unfocusedTextColor = AppColors.textPrimary,
                        cursorColor = AppColors.accent,
                    ),
                    shape = RoundedCornerShape(Radii.card),
                    singleLine = true,
                )
            }

            item(key = "folder_config") {
                GeistCard {
                    SectionLabel(stringResource(R.string.section_entries_folder))
                    OutlinedTextField(
                        value = settings.entriesFolder,
                        onValueChange = { onSettingsChanged(settings.copy(entriesFolder = it)) },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text(stringResource(R.string.entries_folder_hint), color = AppColors.textMuted) },
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = AppColors.accent,
                            unfocusedBorderColor = AppColors.borderDefault,
                            focusedTextColor = AppColors.textPrimary,
                            unfocusedTextColor = AppColors.textPrimary,
                            cursorColor = AppColors.accent,
                        ),
                        shape = RoundedCornerShape(Radii.card),
                        singleLine = true,
                    )
                    Spacer(modifier = Modifier.height(Spacing.sm))
                    SectionLabel(stringResource(R.string.section_filename_template))
                    OutlinedTextField(
                        value = settings.filenameTemplate,
                        onValueChange = { onSettingsChanged(settings.copy(filenameTemplate = it)) },
                        modifier = Modifier.fillMaxWidth(),
                        placeholder = { Text(stringResource(R.string.individual_tracking_filename_hint), color = AppColors.textMuted) },
                        supportingText = { Text(stringResource(R.string.individual_tracking_filename_tokens), color = AppColors.textMuted) },
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = AppColors.accent,
                            unfocusedBorderColor = AppColors.borderDefault,
                            focusedTextColor = AppColors.textPrimary,
                            unfocusedTextColor = AppColors.textPrimary,
                            cursorColor = AppColors.accent,
                        ),
                        shape = RoundedCornerShape(Radii.card),
                        singleLine = true,
                    )
                }
            }

            item(key = "organize_by_category") {
                GeistCard {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(modifier = Modifier.weight(1f)) {
                            Text(stringResource(R.string.organize_by_category_title), color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                            Text(
                                stringResource(R.string.organize_by_category_subtitle),
                                color = AppColors.textSecondary,
                                style = MaterialTheme.typography.bodySmall,
                            )
                        }
                        Switch(
                            checked = settings.organizeByCategory,
                            onCheckedChange = { onSettingsChanged(settings.copy(organizeByCategory = it)) },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = AppColors.onAccent,
                                checkedTrackColor = AppColors.accent,
                                uncheckedThumbColor = AppColors.textMuted,
                                uncheckedTrackColor = AppColors.bgSecondary,
                                uncheckedBorderColor = AppColors.borderDefault,
                            ),
                        )
                    }
                }
            }


            HealthMetrics.categories.forEach { category ->
                val metrics = HealthMetrics.metricsForCategory(category)
                val filteredMetrics = if (searchQuery.isBlank()) metrics else metrics.filter {
                    context.getString(it.displayNameRes()).contains(searchQuery, ignoreCase = true) ||
                        it.id.contains(searchQuery, ignoreCase = true)
                }
                if (filteredMetrics.isEmpty() && searchQuery.isNotBlank()) return@forEach

                val isExpanded = searchQuery.isNotBlank() || category in expandedCategories
                val enabledCount = settings.enabledCountForCategory(category)
                val totalCount = settings.totalMetricCount(category)

                item(key = "category_${category.name}") {
                    GeistCard {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    expandedCategories = if (category in expandedCategories) {
                                        expandedCategories - category
                                    } else {
                                        expandedCategories + category
                                    }
                                },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            IconButton(
                                onClick = { onSettingsChanged(settings.toggleCategory(category)) },
                                modifier = Modifier.size(40.dp),
                            ) {
                                Icon(
                                    when {
                                        settings.isCategoryFullyEnabled(category) -> Icons.Filled.CheckBox
                                        settings.isCategoryPartiallyEnabled(category) -> Icons.Filled.IndeterminateCheckBox
                                        else -> Icons.Filled.CheckBoxOutlineBlank
                                    },
                                    contentDescription = null,
                                    tint = if (settings.isCategoryFullyEnabled(category) || settings.isCategoryPartiallyEnabled(category)) AppColors.accent else AppColors.textMuted,
                                )
                            }
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    category.localizedDisplayName(),
                                    style = MaterialTheme.typography.titleMedium,
                                    color = AppColors.textPrimary,
                                    fontWeight = FontWeight.SemiBold,
                                )
                                Text(
                                    stringResource(R.string.metrics_enabled_category, enabledCount, totalCount),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = AppColors.textMuted,
                                )
                            }
                            Icon(
                                if (isExpanded) Icons.Filled.ExpandLess else Icons.Filled.ExpandMore,
                                contentDescription = null,
                                tint = AppColors.textMuted,
                            )
                        }

                        AnimatedVisibility(visible = isExpanded) {
                            Column {
                                HorizontalDivider(
                                    color = AppColors.borderDefault,
                                    modifier = Modifier.padding(vertical = Spacing.xs),
                                )
                                filteredMetrics.forEach { metric ->
                                    val suggested = IndividualTrackingSettings.isSuggested(metric.id)
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable { onSettingsChanged(settings.toggleMetric(metric.id)) }
                                            .padding(vertical = Spacing.xxs, horizontal = Spacing.xxs),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Checkbox(
                                            checked = settings.isMetricEnabled(metric.id),
                                            onCheckedChange = { onSettingsChanged(settings.toggleMetric(metric.id)) },
                                            colors = CheckboxDefaults.colors(
                                                checkedColor = AppColors.accent,
                                                uncheckedColor = AppColors.textMuted,
                                                checkmarkColor = AppColors.onAccent,
                                            ),
                                        )
                                        Column(modifier = Modifier.weight(1f)) {
                                            Row(verticalAlignment = Alignment.CenterVertically) {
                                                Text(
                                                    metric.localizedDisplayName(),
                                                    style = MaterialTheme.typography.bodyLarge,
                                                    color = AppColors.textPrimary,
                                                )
                                                if (suggested) {
                                                    Spacer(modifier = Modifier.width(Spacing.xs))
                                                    Text(
                                                        stringResource(R.string.individual_tracking_suggested_badge),
                                                        style = MaterialTheme.typography.labelSmall,
                                                        color = AppColors.accent,
                                                    )
                                                }
                                            }
                                            Text(
                                                if (metric.unit.isNotEmpty()) metric.unit else metric.id,
                                                style = MaterialTheme.typography.bodySmall,
                                                color = AppColors.textMuted,
                                            )
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        item { Spacer(modifier = Modifier.height(Spacing.xl)) }
    }
}
