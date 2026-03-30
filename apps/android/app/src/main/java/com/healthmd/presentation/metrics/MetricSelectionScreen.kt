package com.healthmd.presentation.metrics

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowBack
import androidx.compose.material.icons.filled.CheckBox
import androidx.compose.material.icons.filled.CheckBoxOutlineBlank
import androidx.compose.material.icons.filled.IndeterminateCheckBox
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.healthmd.domain.model.*
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.presentation.i18n.displayNameRes
import com.healthmd.presentation.i18n.localizedDisplayName

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MetricSelectionScreen(
    metricSelection: MetricSelectionState,
    onSelectionChanged: (MetricSelectionState) -> Unit,
    onBack: () -> Unit,
) {
    var searchQuery by remember { mutableStateOf("") }
    var expandedCategories by remember {
        mutableStateOf(HealthMetricCategory.entries.toSet())
    }
    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary),
    ) {
        // Top bar
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.md, vertical = Spacing.sm),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.Filled.ArrowBack, stringResource(R.string.back), tint = AppColors.textPrimary)
            }
            Text(
                stringResource(R.string.metric_selection_title),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.Bold,
                modifier = Modifier.weight(1f),
            )
            Text(
                "${metricSelection.enabledCount}/${HealthMetrics.totalCount}",
                style = MaterialTheme.typography.labelLarge,
                color = AppColors.accent,
            )
        }

        // Search bar
        OutlinedTextField(
            value = searchQuery,
            onValueChange = { searchQuery = it },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.md),
            placeholder = { Text(stringResource(R.string.search_metrics_hint), color = AppColors.textMuted) },
            leadingIcon = { Icon(Icons.Filled.Search, null, tint = AppColors.textMuted) },
            colors = OutlinedTextFieldDefaults.colors(
                focusedBorderColor = AppColors.accent,
                unfocusedBorderColor = AppColors.borderDefault,
                focusedTextColor = AppColors.textPrimary,
                unfocusedTextColor = AppColors.textPrimary,
                cursorColor = AppColors.accent,
            ),
            shape = RoundedCornerShape(12.dp),
            singleLine = true,
        )

        Spacer(modifier = Modifier.height(Spacing.xs))

        // Bulk actions
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.md),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            SecondaryButton(
                text = stringResource(R.string.select_all),
                onClick = { onSelectionChanged(metricSelection.enableAll()) },
                modifier = Modifier.weight(1f),
            )
            SecondaryButton(
                text = stringResource(R.string.deselect_all),
                onClick = { onSelectionChanged(metricSelection.disableAll()) },
                modifier = Modifier.weight(1f),
            )
        }

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Progress bar
        LinearProgressIndicator(
            progress = { metricSelection.enabledCount.toFloat() / HealthMetrics.totalCount },
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Spacing.md)
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp)),
            color = AppColors.accent,
            trackColor = AppColors.bgSecondary,
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Categories list
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(horizontal = Spacing.md, vertical = Spacing.xs),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs),
        ) {
            HealthMetrics.categories.forEach { category ->
                val metrics = HealthMetrics.metricsForCategory(category)
                val filteredMetrics = if (searchQuery.isBlank()) metrics
                else metrics.filter {
                    context.getString(it.displayNameRes()).contains(searchQuery, ignoreCase = true)
                }

                if (filteredMetrics.isEmpty() && searchQuery.isNotBlank()) return@forEach

                val isExpanded = category in expandedCategories
                val enabledCount = metricSelection.enabledCountForCategory(category)
                val totalCategoryCount = metrics.size

                // Category header
                item(key = "category_${category.name}") {
                    GlassCard {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .clickable {
                                    expandedCategories = if (isExpanded) {
                                        expandedCategories - category
                                    } else {
                                        expandedCategories + category
                                    }
                                },
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            // Category checkbox
                            IconButton(
                                onClick = { onSelectionChanged(metricSelection.toggleCategory(category)) },
                                modifier = Modifier.size(40.dp),
                            ) {
                                Icon(
                                    when {
                                        metricSelection.isCategoryFullyEnabled(category) -> Icons.Filled.CheckBox
                                        metricSelection.isCategoryPartiallyEnabled(category) -> Icons.Filled.IndeterminateCheckBox
                                        else -> Icons.Filled.CheckBoxOutlineBlank
                                    },
                                    contentDescription = null,
                                    tint = if (metricSelection.isCategoryFullyEnabled(category) || metricSelection.isCategoryPartiallyEnabled(category))
                                        AppColors.accent else AppColors.textMuted,
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
                                    stringResource(R.string.metrics_enabled_category, enabledCount, totalCategoryCount),
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

                        // Expanded metrics
                        AnimatedVisibility(visible = isExpanded) {
                            Column {
                                HorizontalDivider(
                                    color = AppColors.glassBorder,
                                    modifier = Modifier.padding(vertical = Spacing.xs),
                                )
                                filteredMetrics.forEach { metric ->
                                    Row(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .clickable {
                                                onSelectionChanged(metricSelection.toggle(metric.id))
                                            }
                                            .padding(vertical = 4.dp, horizontal = 4.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                    ) {
                                        Checkbox(
                                            checked = metricSelection.isEnabled(metric.id),
                                            onCheckedChange = {
                                                onSelectionChanged(metricSelection.toggle(metric.id))
                                            },
                                            colors = CheckboxDefaults.colors(
                                                checkedColor = AppColors.accent,
                                                uncheckedColor = AppColors.textMuted,
                                                checkmarkColor = Color.White,
                                            ),
                                        )
                                        Column(modifier = Modifier.weight(1f)) {
                                            Text(
                                                metric.localizedDisplayName(),
                                                style = MaterialTheme.typography.bodyLarge,
                                                color = AppColors.textPrimary,
                                            )
                                            if (metric.unit.isNotEmpty()) {
                                                Text(
                                                    metric.unit,
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
}
