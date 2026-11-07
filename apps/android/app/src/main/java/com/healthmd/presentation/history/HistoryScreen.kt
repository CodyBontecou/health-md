package com.healthmd.presentation.history

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.model.EXPORT_FOLDER_ROOT_TARGET_LABEL
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.ConfigurationProtectedRegion
import com.healthmd.presentation.common.EdgeToEdgeDialogWindow
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.LocalFloatingActionClearance
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.dialogNavigationBarsPadding
import com.healthmd.presentation.export.failureReasonLabel
import com.healthmd.presentation.export.guidanceText
import com.healthmd.presentation.export.toDiagnosticsSummary
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.rawexport.ExportMode
import java.text.DateFormat
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth
import java.time.ZoneId
import java.time.format.DateTimeFormatter
import java.util.Date
import java.util.Locale

@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel = hiltViewModel(),
) {
    val entries by viewModel.entries.collectAsStateWithLifecycle()
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val protection = LocalConfigurationProtection.current
    val requestClear: () -> Unit = {
        if (protection.enabled) protection.onBlockedChange() else viewModel.requestClearHistory()
    }
    val useTwoPane = LocalConfiguration.current.screenWidthDp >= 840

    if (!useTwoPane) uiState.selectedEntry?.let { entry ->
        HistoryDetailDialog(
            entry = entry,
            isRetrying = uiState.isRetrying,
            retryMessage = uiState.retryMessage,
            onRetry = { viewModel.retry(entry) },
            onDismiss = { viewModel.dismissEntryDetails() },
        )
    }

    if (uiState.showClearConfirmation) {
        ClearHistoryDialog(
            onConfirm = {
                if (protection.enabled) {
                    viewModel.dismissClearHistory()
                    protection.onBlockedChange()
                } else {
                    viewModel.clearHistory()
                }
            },
            onDismiss = { viewModel.dismissClearHistory() },
        )
    }

    if (entries.isEmpty()) {
        HistoryEmptyState()
    } else if (useTwoPane) {
        val selected = uiState.selectedEntry ?: entries.firstOrNull()
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = GeistSpacing.space4),
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space6),
        ) {
            HistoryList(
                entries = entries,
                selectedId = selected?.id,
                retryMessage = uiState.retryMessage,
                onClear = requestClear,
                onEntryClick = { viewModel.selectEntry(it) },
                modifier = Modifier.weight(0.42f).fillMaxHeight(),
                horizontalPadding = 0.dp,
                bottomPadding = GeistSpacing.space6,
            )
            if (selected != null) {
                HistoryDetailPane(
                    entry = selected,
                    isRetrying = uiState.isRetrying,
                    retryMessage = uiState.retryMessage,
                    onRetry = { viewModel.retry(selected) },
                    modifier = Modifier.weight(0.58f).fillMaxHeight(),
                )
            }
        }
    } else {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
            HistoryList(
                entries = entries,
                selectedId = null,
                retryMessage = uiState.retryMessage,
                onClear = requestClear,
                onEntryClick = { viewModel.selectEntry(it) },
                modifier = Modifier
                    .widthIn(max = GeistSizes.readableContentMaxWidth)
                    .fillMaxSize(),
                horizontalPadding = GeistSpacing.space4,
                // Clears the floating Export now button where one is shown.
                bottomPadding = LocalFloatingActionClearance.current + GeistSpacing.space6,
            )
        }
    }
}

/** Empty state: a centered icon on the brand-subtle circle, a heading-20 title, copy-14 body. */
@Composable
private fun HistoryEmptyState() {
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space6),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(
            Modifier
                .size(GeistSpacing.space16)
                .background(colors.brandSubtle, CircleShape),
            contentAlignment = Alignment.Center,
        ) {
            Icon(
                Icons.Outlined.History,
                contentDescription = null,
                tint = colors.brandOnSubtle,
                modifier = Modifier.size(32.dp),
            )
        }
        Spacer(modifier = Modifier.height(GeistSpacing.space4))
        Text(
            stringResource(R.string.no_history_title).replace('\n', ' '),
            style = GeistType.heading20,
            color = colors.primary,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Spacer(modifier = Modifier.height(GeistSpacing.space2))
        Text(
            stringResource(R.string.no_history_subtitle),
            style = GeistType.copy14,
            color = colors.secondary,
            textAlign = TextAlign.Center,
        )
    }
}

/** Entries as list groups under a month heading, newest first, then the protected Clear action. */
@Composable
private fun HistoryList(
    entries: List<ExportHistoryEntry>,
    selectedId: Long?,
    retryMessage: HistoryUiMessage?,
    onClear: () -> Unit,
    onEntryClick: (ExportHistoryEntry) -> Unit,
    modifier: Modifier = Modifier,
    horizontalPadding: androidx.compose.ui.unit.Dp,
    bottomPadding: androidx.compose.ui.unit.Dp,
) {
    val colors = LocalGeistColors.current
    val locale = LocalConfiguration.current.locales[0] ?: Locale.getDefault()
    val monthFormatter = remember(locale) {
        DateTimeFormatter.ofPattern(
            android.text.format.DateFormat.getBestDateTimePattern(locale, "MMMMyyyy"),
            locale,
        )
    }
    val groups = remember(entries) {
        entries.groupBy {
            YearMonth.from(Instant.ofEpochMilli(it.timestamp).atZone(ZoneId.systemDefault()))
        }.toList()
    }
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(
            start = horizontalPadding,
            end = horizontalPadding,
            top = 0.dp,
            bottom = bottomPadding,
        ),
    ) {
        retryMessage?.let { message ->
            item(key = "retry-message") {
                HistoryNote(
                    tone = HistoryNoteTone.INFO,
                    title = null,
                    message = message.localizedText(),
                    modifier = Modifier.padding(top = GeistSpacing.space2),
                )
            }
        }
        groups.forEach { (month, monthEntries) ->
            item(key = "month-$month") {
                Text(
                    text = month.format(monthFormatter),
                    style = GeistType.heading14,
                    color = colors.brandPrimary,
                    modifier = Modifier
                        .padding(start = GeistSpacing.space4, top = GeistSpacing.space6, bottom = GeistSpacing.space2)
                        .semantics { heading() },
                )
            }
            itemsIndexed(monthEntries, key = { _, entry -> entry.id }) { index, entry ->
                HistoryEntryRow(
                    entry = entry,
                    shape = groupRowShape(index, monthEntries.size),
                    selected = entry.id == selectedId,
                    onClick = { onEntryClick(entry) },
                    modifier = if (index > 0) Modifier.padding(top = 2.dp) else Modifier,
                )
            }
        }
        item(key = "clear-history") {
            ConfigurationProtectedRegion(modifier = Modifier.padding(top = GeistSpacing.space6)) {
                SecondaryButton(
                    text = stringResource(R.string.action_clear_history),
                    onClick = onClear,
                    icon = Icons.Outlined.Delete,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

private enum class HistoryStatus { SUCCESS, PARTIAL, FAILED }

private val ExportHistoryEntry.status: HistoryStatus
    get() = when {
        isFullSuccess -> HistoryStatus.SUCCESS
        isPartialSuccess -> HistoryStatus.PARTIAL
        else -> HistoryStatus.FAILED
    }

/** Status is carried by icon and text as well as color, never color alone. */
private data class StatusStyle(val icon: ImageVector, val label: String, val color: Color, val container: Color)

@Composable
private fun HistoryStatus.style(): StatusStyle {
    val colors = LocalGeistColors.current
    return when (this) {
        HistoryStatus.SUCCESS -> StatusStyle(
            Icons.Outlined.CheckCircle, stringResource(R.string.m3_history_status_success), colors.success, colors.green.c100,
        )
        HistoryStatus.PARTIAL -> StatusStyle(
            Icons.Outlined.WarningAmber, stringResource(R.string.m3_history_status_partial), colors.warning, colors.amber.c100,
        )
        HistoryStatus.FAILED -> StatusStyle(
            Icons.Outlined.ErrorOutline, stringResource(R.string.m3_history_status_failed), colors.error, colors.red.c100,
        )
    }
}

@Composable
private fun entryTimestamp(entry: ExportHistoryEntry): String {
    val context = LocalContext.current
    return stringResource(
        R.string.history_timestamp_format,
        android.text.format.DateFormat.getMediumDateFormat(context).format(Date(entry.timestamp)),
        android.text.format.DateFormat.getTimeFormat(context).format(Date(entry.timestamp)),
    )
}

@Composable
private fun entryCounts(entry: ExportHistoryEntry): String =
    if (entry.exportMode == ExportMode.RAW_SNAPSHOT) {
        pluralStringResource(R.plurals.m3_history_snapshot_actions, entry.totalCount, entry.successCount, entry.totalCount)
    } else {
        pluralStringResource(R.plurals.history_detail_exported_days, entry.totalCount, entry.successCount, entry.totalCount)
    }

@Composable
private fun destinationTypeLabel(entry: ExportHistoryEntry): String = stringResource(
    when (entry.target) {
        ExportTarget.API_ENDPOINT -> R.string.export_preview_api_destination
        ExportTarget.AGENT_DATA_GATEWAY -> R.string.export_preview_gateway_destination
        ExportTarget.DEVICE_FOLDER -> R.string.export_preview_device_destination
    },
)

/**
 * One export as a list-group row: a status icon circle, the date range, the status and time,
 * and the day count with its destination. The whole row opens the details.
 */
@Composable
private fun HistoryEntryRow(
    entry: ExportHistoryEntry,
    shape: Shape,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val status = entry.status.style()
    val range = stringResource(
        R.string.history_date_range,
        localizedDate(entry.dateRangeStart),
        localizedDate(entry.dateRangeEnd),
    )
    val statusLine = listOf(status.label, entryTimestamp(entry), entry.source.localizedDisplayName())
        .joinToString(SEPARATOR)
    val detailLine = listOfNotNull(
        entryCounts(entry),
        localizedTargetLabel(entry) ?: destinationTypeLabel(entry),
        entry.profileName?.takeIf { it.isNotBlank() },
    ).joinToString(SEPARATOR)
    val textColor = if (selected) colors.onSecondaryContainer else colors.primary
    val secondaryColor = if (selected) colors.onSecondaryContainer else colors.secondary

    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(if (selected) colors.secondaryContainer else colors.background200)
            .clickable(role = Role.Button, onClick = onClick)
            .then(if (selected) Modifier.semantics { this.selected = true } else Modifier)
            .heightIn(min = 72.dp)
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space3, top = GeistSpacing.space3, bottom = GeistSpacing.space3),
    ) {
        // Reading-first at narrow widths per font scale: the icon circle gives its width to the text.
        val reading = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
        ) {
            if (!reading) {
                Box(
                    Modifier
                        .size(GeistSizes.control)
                        .background(status.container, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(status.icon, contentDescription = null, tint = status.color, modifier = Modifier.size(22.dp))
                }
            }
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(range, style = GeistType.label16, color = textColor)
                Row(verticalAlignment = Alignment.CenterVertically) {
                    if (reading) {
                        Icon(
                            status.icon,
                            contentDescription = null,
                            tint = status.color,
                            modifier = Modifier.padding(end = GeistSpacing.space1).size(16.dp),
                        )
                    }
                    Text(statusLine, style = GeistType.label14, color = if (selected) textColor else status.color)
                }
                Text(detailLine, style = GeistType.copy14, color = secondaryColor)
            }
            Icon(
                Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = secondaryColor,
                modifier = Modifier.size(24.dp),
            )
        }
    }
}

private const val SEPARATOR = " · "

/** Wide windows: the selected entry's details beside the list, retry above the content. */
@Composable
private fun HistoryDetailPane(
    entry: ExportHistoryEntry,
    isRetrying: Boolean,
    retryMessage: HistoryUiMessage?,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    Column(
        modifier = modifier
            .verticalScroll(rememberScrollState())
            .padding(top = GeistSpacing.space6, bottom = GeistSpacing.space6),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Text(
            stringResource(R.string.history_detail_title),
            style = GeistType.heading20,
            color = colors.primary,
            modifier = Modifier.semantics { heading() },
        )
        // Retry stays above the content so the primary recovery action
        // is reachable without scrolling through long failure lists.
        RetryButton(isRetrying = isRetrying, onRetry = onRetry)
        HistoryDetailContent(entry = entry, retryMessage = retryMessage)
    }
}

@Composable
private fun RetryButton(isRetrying: Boolean, onRetry: () -> Unit) {
    PrimaryButton(
        text = if (isRetrying) stringResource(R.string.action_retrying_export) else stringResource(R.string.action_retry_export),
        onClick = onRetry,
        icon = Icons.Outlined.Refresh,
        enabled = !isRetrying,
    )
}

@Composable
private fun HistoryDetailContent(entry: ExportHistoryEntry, retryMessage: HistoryUiMessage?) {
    val colors = LocalGeistColors.current
    val status = entry.status.style()
    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4)) {
        retryMessage?.let {
            HistoryNote(tone = HistoryNoteTone.INFO, title = null, message = it.localizedText())
        }
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            Icon(status.icon, contentDescription = null, tint = status.color, modifier = Modifier.size(20.dp))
            Text(status.label, style = GeistType.heading16, color = status.color)
        }

        // Summary card: label/value rows on background-200.
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.listGroup))
                .background(colors.background200)
                .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
        ) {
            DetailLine(stringResource(R.string.history_detail_source), entry.source.localizedDisplayName())
            entry.profileName?.takeIf { it.isNotBlank() }?.let {
                DetailLine(stringResource(R.string.history_detail_profile), it)
            }
            DetailLine(stringResource(R.string.history_detail_when), entryTimestamp(entry))
            DetailLine(
                stringResource(R.string.history_detail_range),
                stringResource(
                    R.string.history_date_range,
                    localizedDate(entry.dateRangeStart),
                    localizedDate(entry.dateRangeEnd),
                ),
            )
            DetailLine(
                stringResource(R.string.history_detail_counts),
                pluralStringResource(
                    R.plurals.history_detail_exported_days,
                    entry.totalCount,
                    entry.successCount,
                    entry.totalCount,
                ),
            )
            DetailLine(stringResource(R.string.history_detail_destination_type), destinationTypeLabel(entry))
            localizedTargetLabel(entry)?.let {
                DetailLine(
                    stringResource(
                        if (entry.target == ExportTarget.DEVICE_FOLDER) {
                            R.string.export_folder_label
                        } else {
                            R.string.history_detail_target
                        },
                    ),
                    it,
                    mono = true,
                )
            }
            if (entry.target == ExportTarget.DEVICE_FOLDER) {
                DetailLine(
                    stringResource(R.string.history_detail_files),
                    pluralStringResource(R.plurals.history_detail_file_count, entry.fileCount, entry.fileCount),
                )
            }
            entry.failureReason?.let {
                DetailLine(stringResource(R.string.history_detail_failure), it.localizedLabel())
            }
            localizedWarningSummary(entry)?.let {
                DetailLine(stringResource(R.string.history_detail_warning), it)
            }
        }

        if (!entry.isFullSuccess) {
            FailureSummaryNote(entry)
        }

        if (entry.failedDateDetails.isNotEmpty()) {
            FailedDatesCard(entry)
        }
    }
}

/** The primary failure group and its guidance as a tonal warning or error note. */
@Composable
private fun FailureSummaryNote(entry: ExportHistoryEntry) {
    val summary = entry.toDiagnosticsSummary()
    val isRawSnapshot = entry.exportMode == ExportMode.RAW_SNAPSHOT
    val primaryGroup = summary.failureGroups.firstOrNull()
    val title = pluralStringResource(
        if (isRawSnapshot) {
            R.plurals.raw_snapshot_diagnostics_incomplete_count
        } else {
            R.plurals.export_diagnostics_failed_count
        },
        summary.failedDayCount,
        summary.failedDayCount,
    )
    val message = if (primaryGroup != null) {
        listOfNotNull(
            pluralStringResource(
                if (isRawSnapshot) {
                    R.plurals.raw_snapshot_diagnostics_reason_count
                } else {
                    R.plurals.export_diagnostics_reason_count
                },
                primaryGroup.count,
                primaryGroup.failureReasonLabel(),
                primaryGroup.count,
            ),
            primaryGroup.guidanceText(),
            if (!isRawSnapshot && primaryGroup.sampleDates.isNotEmpty()) {
                localizedDateSampleText(
                    dates = primaryGroup.sampleDates,
                    remainingCount = primaryGroup.remainingDateCount,
                )
            } else {
                null
            },
        ).joinToString("\n")
    } else {
        stringResource(R.string.export_diagnostics_no_details)
    }
    HistoryNote(
        tone = if (entry.isPartialSuccess) HistoryNoteTone.WARNING else HistoryNoteTone.ERROR,
        title = title,
        message = message,
    )
}

/** Up to eight failed dates (or snapshot diagnostics) as rows on background-200. */
@Composable
private fun FailedDatesCard(entry: ExportHistoryEntry) {
    val colors = LocalGeistColors.current
    val isRawSnapshot = entry.exportMode == ExportMode.RAW_SNAPSHOT
    Column(Modifier.fillMaxWidth()) {
        Text(
            stringResource(
                if (isRawSnapshot) R.string.raw_snapshot_history_detail_diagnostics else R.string.history_detail_failed_dates,
            ),
            style = GeistType.heading14,
            color = colors.brandPrimary,
            modifier = Modifier
                .padding(start = GeistSpacing.space4, top = GeistSpacing.space2, bottom = GeistSpacing.space2)
                .semantics { heading() },
        )
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.listGroup))
                .background(colors.background200)
                .padding(GeistSpacing.space4),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            entry.failedDateDetails.take(8).forEach { detail ->
                Text(
                    if (isRawSnapshot) {
                        detail.reason.localizedLabel()
                    } else {
                        stringResource(
                            R.string.history_failed_date_reason,
                            localizedDate(detail.date),
                            detail.reason.localizedLabel(),
                        )
                    },
                    style = GeistType.copy14,
                    color = colors.primary,
                )
            }
            if (entry.failedDateDetails.size > 8) {
                val remainingCount = entry.failedDateDetails.size - 8
                Text(
                    pluralStringResource(R.plurals.history_more_items, remainingCount, remainingCount),
                    style = GeistType.copy14,
                    color = colors.secondary,
                )
            }
        }
    }
}

/** Phones: the details as a full-screen dialog with Close, scrolling content and pinned Retry. */
@Composable
private fun HistoryDetailDialog(
    entry: ExportHistoryEntry,
    isRetrying: Boolean,
    retryMessage: HistoryUiMessage?,
    onRetry: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalGeistColors.current
    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
    ) {
        EdgeToEdgeDialogWindow(fullScreenPage = true)
        Surface(modifier = Modifier.fillMaxSize(), color = colors.background100) {
            Column(
                Modifier
                    .fillMaxSize()
                    .windowInsetsPadding(WindowInsets.statusBars.union(WindowInsets.displayCutout))
                    .dialogNavigationBarsPadding(),
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .heightIn(min = 64.dp)
                        .padding(horizontal = GeistSpacing.space1),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    IconButton(onClick = onDismiss, modifier = Modifier.size(GeistSizes.minimumTouchTarget)) {
                        Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.close), tint = colors.primary)
                    }
                    Text(
                        stringResource(R.string.history_detail_title),
                        style = GeistType.heading20,
                        color = colors.primary,
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = GeistSpacing.space1, vertical = GeistSpacing.space2)
                            .semantics { heading() },
                    )
                }
                Box(
                    Modifier
                        .weight(1f)
                        .fillMaxWidth(),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    Column(
                        Modifier
                            .widthIn(max = GeistSizes.readableContentMaxWidth)
                            .fillMaxSize()
                            .verticalScroll(rememberScrollState())
                            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
                    ) {
                        HistoryDetailContent(entry = entry, retryMessage = retryMessage)
                        Spacer(Modifier.height(GeistSpacing.space4))
                    }
                }
                Box(
                    Modifier
                        .fillMaxWidth()
                        .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(Modifier.widthIn(max = GeistSizes.readableContentMaxWidth)) {
                        RetryButton(isRetrying = isRetrying, onRetry = onRetry)
                    }
                }
            }
        }
    }
}

/** The protected Clear history confirmation: M3 dialog container, filled confirm, text dismiss. */
@Composable
private fun ClearHistoryDialog(onConfirm: () -> Unit, onDismiss: () -> Unit) {
    val colors = LocalGeistColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.gray.c200,
        shape = RoundedCornerShape(GeistRadii.large),
        tonalElevation = 0.dp,
        icon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = colors.secondary) },
        title = {
            Text(
                stringResource(R.string.history_clear_title),
                style = GeistType.heading20,
                color = colors.primary,
                textAlign = TextAlign.Center,
            )
        },
        text = {
            Text(stringResource(R.string.history_clear_body), style = GeistType.copy14, color = colors.secondary)
        },
        confirmButton = {
            Button(
                onClick = onConfirm,
                shape = RoundedCornerShape(GeistRadii.full),
                colors = ButtonDefaults.buttonColors(
                    containerColor = colors.brandPrimary,
                    contentColor = colors.brandOnPrimary,
                ),
                elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp),
                modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
            ) {
                Text(stringResource(R.string.action_clear_history), style = GeistType.button14)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget)) {
                Text(stringResource(R.string.action_keep_history), style = GeistType.button14, color = colors.brandPrimary)
            }
        },
    )
}

private enum class HistoryNoteTone { INFO, WARNING, ERROR }

/** A tonal note (no border) whose tone is carried by its icon and title as well as color. */
@Composable
private fun HistoryNote(
    tone: HistoryNoteTone,
    title: String?,
    message: String,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val (container, accent, icon) = when (tone) {
        HistoryNoteTone.INFO -> Triple(colors.gray.c200, colors.secondary, Icons.Outlined.Info)
        HistoryNoteTone.WARNING -> Triple(colors.amber.c100, colors.warning, Icons.Outlined.WarningAmber)
        HistoryNoteTone.ERROR -> Triple(colors.red.c100, colors.error, Icons.Outlined.ErrorOutline)
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.medium))
            .background(container)
            .padding(GeistSpacing.space4),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Icon(icon, contentDescription = null, tint = accent, modifier = Modifier.size(20.dp))
        Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
            title?.let { Text(it, style = GeistType.heading14, color = accent) }
            Text(message, style = GeistType.copy14, color = colors.primary)
        }
    }
}

/** A label/value row in the summary card; values wrap rather than truncate. */
@Composable
private fun DetailLine(label: String, value: String, mono: Boolean = false) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = 40.dp)
            .padding(vertical = GeistSpacing.space2),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, style = GeistType.copy14, color = colors.secondary)
        Text(
            value,
            modifier = Modifier
                .weight(1f, fill = false)
                .padding(start = GeistSpacing.space4),
            style = if (mono) GeistType.label13Mono else GeistType.label14,
            color = colors.primary,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun HistoryUiMessage.localizedText(): String = when (this) {
    is HistoryUiMessage.Text -> stringResource(resourceId, *arguments.toTypedArray())
    is HistoryUiMessage.Plural -> pluralStringResource(
        resourceId,
        quantity,
        *arguments.toTypedArray(),
    )
}

@Composable
private fun localizedDate(date: LocalDate): String =
    formatLocalDate(date, android.text.format.DateFormat.getMediumDateFormat(LocalContext.current))

private fun formatLocalDate(date: LocalDate, formatter: DateFormat): String {
    val instant = date.atStartOfDay(ZoneId.systemDefault()).toInstant()
    return formatter.format(Date.from(instant))
}

@Composable
private fun localizedDateSampleText(
    dates: List<LocalDate>,
    remainingCount: Int,
): String {
    val formatter = android.text.format.DateFormat.getMediumDateFormat(LocalContext.current)
    val localizedDates = dates.joinToString(", ") { formatLocalDate(it, formatter) }
    return if (remainingCount > 0) {
        pluralStringResource(
            R.plurals.history_failed_date_sample_more,
            remainingCount,
            localizedDates,
            remainingCount,
        )
    } else {
        stringResource(R.string.export_diagnostics_date_list, localizedDates)
    }
}

@Composable
private fun localizedTargetLabel(entry: ExportHistoryEntry): String? {
    val targetLabel = entry.targetLabel ?: return null
    if (entry.target != ExportTarget.DEVICE_FOLDER) return targetLabel

    val localizedRoot = stringResource(R.string.export_folder_root_label)
    return when {
        targetLabel == EXPORT_FOLDER_ROOT_TARGET_LABEL -> localizedRoot
        targetLabel.startsWith("$EXPORT_FOLDER_ROOT_TARGET_LABEL/") ->
            localizedRoot + targetLabel.removePrefix(EXPORT_FOLDER_ROOT_TARGET_LABEL)
        else -> targetLabel
    }
}

@Composable
private fun localizedWarningSummary(entry: ExportHistoryEntry): String? = when {
    entry.failureReason == ExportFailureReason.RAW_CANCELLED ->
        stringResource(R.string.export_diagnostics_title_cancelled)
    entry.failedDateDetails.isNotEmpty() -> pluralStringResource(
        R.plurals.history_warning_failed_dates,
        entry.failedDateDetails.size,
        entry.failedDateDetails.size,
    )
    !entry.isFullSuccess && entry.warningSummary != null ->
        stringResource(R.string.history_warning_details_unavailable)
    else -> null
}

@Composable
private fun ExportFailureReason.localizedLabel(): String = stringResource(
    when (this) {
        ExportFailureReason.NO_FOLDER_SELECTED -> R.string.export_failure_no_folder_label
        ExportFailureReason.NO_HEALTH_DATA -> R.string.export_failure_no_data_label
        ExportFailureReason.ACCESS_DENIED -> R.string.export_failure_access_denied_label
        ExportFailureReason.FILE_WRITE_ERROR -> R.string.export_failure_file_write_label
        ExportFailureReason.RATE_LIMITED -> R.string.export_failure_rate_limited_label
        ExportFailureReason.HEALTH_CONNECT_ERROR -> R.string.export_failure_health_connect_label
        ExportFailureReason.DEVICE_LOCKED -> R.string.export_failure_device_locked_label
        ExportFailureReason.BACKGROUND_PERMISSION_DENIED -> R.string.export_failure_background_permission_label
        ExportFailureReason.PAYWALL_REQUIRED -> R.string.export_failure_paywall_label
        ExportFailureReason.INVALID_API_ENDPOINT -> R.string.export_failure_invalid_api_endpoint_label
        ExportFailureReason.GATEWAY_FORMAT_UNSUPPORTED -> R.string.export_failure_gateway_format_label
        ExportFailureReason.NETWORK_ERROR -> R.string.export_failure_network_label
        ExportFailureReason.API_REJECTED -> R.string.export_failure_api_rejected_label
        ExportFailureReason.RAW_UNSUPPORTED_PROVIDER -> R.string.raw_snapshot_provider_unsupported
        ExportFailureReason.RAW_PARTIAL -> R.string.raw_snapshot_partial_label
        ExportFailureReason.RAW_CANCELLED -> R.string.raw_snapshot_cancelled_label
        ExportFailureReason.UNKNOWN -> R.string.export_failure_unknown_label
    },
)
