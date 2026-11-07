package com.healthmd.presentation.metrics

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Search
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
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.HealthMetrics
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.presentation.common.AdaptiveActionPair
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.i18n.displayNameRes
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import kotlinx.coroutines.launch
import java.text.NumberFormat

/** Callers retain configuration protection and persistence; this screen only emits selections. */
@Composable
fun MetricSelectionScreen(
    metricSelection: MetricSelectionState,
    onSelectionChanged: (MetricSelectionState) -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalGeistColors.current
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

    Column(Modifier.fillMaxSize().imePadding()) {
        // The sub-screen top bar reduced to its compact navigation (DESIGN.md metric selection):
        // the growing title/search/actions join the list so they cannot consume its height, and
        // Search brings its editor back even from the end of the list.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .heightIn(min = 64.dp)
                .padding(horizontal = GeistSpacing.space1),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(
                onClick = onBack,
                modifier = Modifier.size(GeistSizes.minimumTouchTarget).testTag(MetricSelectionTags.BACK),
            ) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, stringResource(R.string.back), tint = colors.primary)
            }
            Spacer(Modifier.weight(1f))
            IconButton(
                onClick = {
                    scope.launch {
                        listState.scrollToItem(SEARCH_ITEM_INDEX)
                        focusSearch = true
                    }
                },
                modifier = Modifier.size(GeistSizes.minimumTouchTarget).testTag(MetricSelectionTags.SEARCH_ACTION),
            ) {
                Icon(Icons.Outlined.Search, stringResource(R.string.search), tint = colors.primary)
            }
        }

        Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.TopCenter) {
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .widthIn(max = GeistSizes.readableContentMaxWidth)
                    .fillMaxSize()
                    .testTag(MetricSelectionTags.LIST),
                contentPadding = PaddingValues(
                    start = GeistSpacing.space4,
                    end = GeistSpacing.space4,
                    bottom = GeistSpacing.space8,
                ),
                // Rows of one category group sit 2dp apart; items add their own group spacing.
                verticalArrangement = Arrangement.spacedBy(2.dp),
            ) {
                item(key = MetricSelectionTags.HEADER) {
                    Column(
                        Modifier.padding(bottom = GeistSpacing.space2),
                        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                    ) {
                        Text(
                            stringResource(R.string.metric_selection_title),
                            style = GeistType.heading20, color = colors.primary,
                            modifier = Modifier.fillMaxWidth().semantics { heading() }.testTag(MetricSelectionTags.HEADER),
                        )
                        Text(
                            "${integerFormat.format(metricSelection.enabledCount)}/${integerFormat.format(HealthMetrics.totalCount)}",
                            style = GeistType.button14, color = colors.brandPrimary,
                            modifier = Modifier.testTag(MetricSelectionTags.COUNT),
                        )
                        LinearProgressIndicator(
                            progress = { metricSelection.enabledCount.toFloat() / HealthMetrics.totalCount },
                            modifier = Modifier.fillMaxWidth().height(GeistSpacing.space1)
                                .clip(RoundedCornerShape(GeistRadii.full)).testTag(MetricSelectionTags.PROGRESS),
                            color = colors.brandPrimary,
                            trackColor = colors.gray.c300,
                        )
                    }
                }
                item(key = MetricSelectionTags.SEARCH_FIELD) {
                    Box(Modifier.padding(vertical = GeistSpacing.space2)) {
                        MetricSelectionSearchField(
                            query = searchQuery,
                            onQueryChanged = { searchQuery = it },
                            requestFocus = focusSearch,
                            onFocusRequested = { focusSearch = false },
                        )
                    }
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
                    // One list group per category: the tonal header, its tri-state row, then metrics.
                    val groupSize = 2 + if (isExpanded) filteredMetrics.size else 0

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
                            shape = groupRowShape(0, groupSize),
                            modifier = Modifier.padding(top = GeistSpacing.space4),
                        )
                    }
                    item(key = MetricSelectionTags.categorySelection(category)) {
                        MetricSelectionCategoryCheckbox(
                            category = category,
                            selection = metricSelection,
                            onToggle = { onSelectionChanged(metricSelection.toggleCategory(category)) },
                            shape = groupRowShape(1, groupSize),
                        )
                    }
                    if (isExpanded) {
                        itemsIndexed(filteredMetrics, key = { _, metric -> MetricSelectionTags.metric(metric.id) }) { index, metric ->
                            MetricSelectionCheckbox(
                                metric = metric,
                                checked = metricSelection.isEnabled(metric.id),
                                onToggle = { onSelectionChanged(metricSelection.toggle(metric.id)) },
                                shape = groupRowShape(index + 2, groupSize),
                            )
                        }
                    }
                }
            }
        }
    }
}

private const val SEARCH_ITEM_INDEX = 1
