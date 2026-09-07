package com.healthmd.presentation.metrics

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import com.healthmd.R
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.i18n.displayNameRes
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch
import java.text.NumberFormat

/** Callers retain configuration protection and persistence; this screen only emits selections. */
@Composable
fun MetricSelectionScreen(
    metricSelection: MetricSelectionState,
    onSelectionChanged: (MetricSelectionState) -> Unit,
    onBack: () -> Unit,
) {
    var searchQuery by remember { mutableStateOf("") }
    var expandedCategories by remember { mutableStateOf(HealthMetrics.categories.toSet()) }
    var focusSearch by remember { mutableStateOf(false) }
    val listState = rememberLazyListState()
    val scope = rememberCoroutineScope()
    val context = LocalContext.current
    val locale = context.resources.configuration.locales[0]
    val integerFormat = remember(locale) {
        NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = false }
    }

    Column(Modifier.fillMaxSize().background(AppColors.bgPrimary).imePadding()) {
        // Only compact navigation stays fixed. The growing title/search/actions cannot
        // consume the list's height, and Search brings its editor back even from the end.
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.md, vertical = Spacing.xxs),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier.size(GeistSizes.minimumTouchTarget).testTag(MetricSelectionTags.BACK),
            ) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, stringResource(R.string.back), tint = AppColors.textPrimary)
            }
            IconButton(
                onClick = {
                    scope.launch {
                        listState.scrollToItem(SEARCH_ITEM_INDEX)
                        focusSearch = true
                    }
                },
                modifier = Modifier.size(GeistSizes.minimumTouchTarget).testTag(MetricSelectionTags.SEARCH_ACTION),
            ) {
                Icon(Icons.Filled.Search, stringResource(R.string.search), tint = AppColors.textPrimary)
            }
        }

        LazyColumn(
            state = listState,
            modifier = Modifier.fillMaxWidth().weight(1f).testTag(MetricSelectionTags.LIST),
            contentPadding = PaddingValues(horizontal = Spacing.md, vertical = Spacing.xs),
            verticalArrangement = Arrangement.spacedBy(Spacing.xs),
        ) {
            item(key = MetricSelectionTags.HEADER) {
                Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                    Text(
                        stringResource(R.string.metric_selection_title),
                        style = GeistType.heading20, color = AppColors.textPrimary,
                        modifier = Modifier.fillMaxWidth().semantics { heading() }.testTag(MetricSelectionTags.HEADER),
                    )
                    Text(
                        "${integerFormat.format(metricSelection.enabledCount)}/${integerFormat.format(HealthMetrics.totalCount)}",
                        style = GeistType.button14, color = AppColors.accent,
                        modifier = Modifier.testTag(MetricSelectionTags.COUNT),
                    )
                    LinearProgressIndicator(
                        progress = { metricSelection.enabledCount.toFloat() / HealthMetrics.totalCount },
                        modifier = Modifier.fillMaxWidth().height(Spacing.xxs)
                            .clip(RoundedCornerShape(Radii.badge)).testTag(MetricSelectionTags.PROGRESS),
                        color = AppColors.accent,
                        trackColor = AppColors.bgSecondary,
                    )
                }
            }
            item(key = MetricSelectionTags.SEARCH_FIELD) {
                MetricSelectionSearchField(
                    query = searchQuery,
                    onQueryChanged = { searchQuery = it },
                    requestFocus = focusSearch,
                    onFocusRequested = { focusSearch = false },
                )
            }
            item(key = MetricSelectionTags.BULK_ACTIONS) {
                AdaptiveActionPair(
                    primaryAction = { modifier ->
                        SecondaryButton(
                            stringResource(R.string.select_all),
                            onClick = { onSelectionChanged(metricSelection.enableAll()) },
                            modifier = modifier.testTag(MetricSelectionTags.SELECT_ALL),
                        )
                    },
                    secondaryAction = { modifier ->
                        SecondaryButton(
                            stringResource(R.string.deselect_all),
                            onClick = { onSelectionChanged(metricSelection.disableAll()) },
                            modifier = modifier.testTag(MetricSelectionTags.DESELECT_ALL),
                        )
                    },
                    modifier = Modifier.testTag(MetricSelectionTags.BULK_ACTIONS),
                )
            }

            HealthMetrics.categories.forEach { category ->
                val metrics = HealthMetrics.metricsForCategory(category)
                // Preserve the shipped localized-name, case-insensitive matching (not IDs,
                // units or category names), including the original blank-query behavior.
                val filteredMetrics = if (searchQuery.isBlank()) metrics else metrics.filter {
                    context.getString(it.displayNameRes()).contains(searchQuery, ignoreCase = true)
                }
                if (filteredMetrics.isEmpty() && searchQuery.isNotBlank()) return@forEach
                val isExpanded = category in expandedCategories

                // Separate lazy items also keep each action scrollable in short windows.
                item(key = MetricSelectionTags.expansion(category)) {
                    MetricSelectionCategoryExpansion(
                        category = category,
                        expanded = isExpanded,
                        enabledCount = metricSelection.enabledCountForCategory(category),
                        totalCount = metrics.size,
                        onExpand = {
                            expandedCategories = if (isExpanded) expandedCategories - category
                                else expandedCategories + category
                        },
                    )
                }
                item(key = MetricSelectionTags.categorySelection(category)) {
                    MetricSelectionCategoryCheckbox(
                        category = category,
                        selection = metricSelection,
                        onToggle = { onSelectionChanged(metricSelection.toggleCategory(category)) },
                    )
                }
                if (isExpanded) {
                    items(filteredMetrics, key = { MetricSelectionTags.metric(it.id) }) { metric ->
                        MetricSelectionCheckbox(
                            metric = metric,
                            checked = metricSelection.isEnabled(metric.id),
                            onToggle = { onSelectionChanged(metricSelection.toggle(metric.id)) },
                        )
                    }
                }
            }
            item { Spacer(Modifier.height(Spacing.xl)) }
        }
    }
}

private const val SEARCH_ITEM_INDEX = 1
