package com.healthmd.presentation.history

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.History
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.model.EXPORT_FOLDER_ROOT_TARGET_LABEL
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.GeistBadge
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.GeistIconCircle
import com.healthmd.presentation.export.failureReasonLabel
import com.healthmd.presentation.export.guidanceText
import com.healthmd.presentation.export.toDiagnosticsSummary
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.Spacing
import com.healthmd.rawexport.ExportMode
import java.text.DateFormat
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date

@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel = hiltViewModel(),
) {
    val entries by viewModel.entries.collectAsStateWithLifecycle()
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
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
        AlertDialog(
            onDismissRequest = { viewModel.dismissClearHistory() },
            title = { Text(stringResource(R.string.history_clear_title)) },
            text = { Text(stringResource(R.string.history_clear_body)) },
            confirmButton = {
                TextButton(onClick = { viewModel.clearHistory() }) {
                    Text(stringResource(R.string.action_clear_history))
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissClearHistory() }) {
                    Text(stringResource(R.string.action_keep_history))
                }
            },
        )
    }

    if (entries.isEmpty()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = Spacing.md),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            GeistIconCircle(size = 84.dp) {
                Icon(
                    Icons.Outlined.History,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                    modifier = Modifier.size(40.dp),
                )
            }
            Spacer(modifier = Modifier.height(Spacing.md))
            Text(
                stringResource(R.string.no_history_title),
                style = MaterialTheme.typography.headlineLarge,
                color = AppColors.textPrimary,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(Spacing.sm))
            Text(
                stringResource(R.string.no_history_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
            )
        }
    } else if (useTwoPane) {
        Row(
            modifier = Modifier
                .fillMaxSize()
                .padding(start = Spacing.md, end = Spacing.md, top = Spacing.lg, bottom = Spacing.lg),
            horizontalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            HistoryList(
                entries = entries,
                retryMessage = uiState.retryMessage,
                onClear = { viewModel.requestClearHistory() },
                onEntryClick = { viewModel.selectEntry(it) },
                modifier = Modifier.weight(0.42f).fillMaxHeight(),
                bottomPadding = 0.dp,
            )
            val selected = uiState.selectedEntry ?: entries.firstOrNull()
            if (selected != null) {
                HistoryDetailCard(
                    entry = selected,
                    isRetrying = uiState.isRetrying,
                    retryMessage = uiState.retryMessage,
                    onRetry = { viewModel.retry(selected) },
                    modifier = Modifier.weight(0.58f).fillMaxHeight(),
                )
            }
        }
    } else {
        HistoryList(
            entries = entries,
            retryMessage = uiState.retryMessage,
            onClear = { viewModel.requestClearHistory() },
            onEntryClick = { viewModel.selectEntry(it) },
            modifier = Modifier
                .fillMaxSize()
                .statusBarsPadding(),
            bottomPadding = 100.dp,
        )
    }
}

@Composable
private fun HistoryList(
    entries: List<ExportHistoryEntry>,
    retryMessage: HistoryUiMessage?,
    onClear: () -> Unit,
    onEntryClick: (ExportHistoryEntry) -> Unit,
    modifier: Modifier = Modifier,
    bottomPadding: androidx.compose.ui.unit.Dp,
) {
    LazyColumn(
        modifier = modifier,
        contentPadding = PaddingValues(
            start = Spacing.md,
            end = Spacing.md,
            top = 0.dp,
            bottom = bottomPadding,
        ),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        item {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.section_export_history),
                    style = MaterialTheme.typography.headlineMedium,
                    color = AppColors.textPrimary,
                )
                TextButton(onClick = onClear) {
                    Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                    Spacer(modifier = Modifier.width(Spacing.xxs))
                    Text(stringResource(R.string.action_clear_history))
                }
            }
            retryMessage?.let { message ->
                GeistBadge(borderColor = AppColors.accentBorder) {
                    Text(
                        message.localizedText(),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                    )
                }
            }
        }
        items(entries, key = { it.id }) { entry ->
            HistoryEntryCard(entry = entry, onClick = { onEntryClick(entry) })
        }
    }
}

@Composable
private fun HistoryEntryCard(entry: ExportHistoryEntry, onClick: () -> Unit) {
    val context = LocalContext.current
    val dateOnly = android.text.format.DateFormat.getMediumDateFormat(context).format(Date(entry.timestamp))
    val timeOnly = android.text.format.DateFormat.getTimeFormat(context).format(Date(entry.timestamp))
    val timestampStr = stringResource(R.string.history_timestamp_format, dateOnly, timeOnly)

    val statusColor = when {
        entry.isFullSuccess -> AppColors.success
        entry.isPartialSuccess -> AppColors.warning
        else -> AppColors.error
    }

    GeistCard(padding = Spacing.md) {
        Column(modifier = Modifier.clickable(onClick = onClick)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                GeistBadge(borderColor = AppColors.borderDefault) {
                    Text(
                        when {
                            entry.isFullSuccess -> stringResource(R.string.history_status_success)
                            entry.isPartialSuccess -> stringResource(R.string.history_status_partial)
                            else -> stringResource(R.string.history_status_failed)
                        },
                        color = statusColor,
                        style = MaterialTheme.typography.labelMedium,
                        fontWeight = FontWeight.Medium,
                    )
                }
                Text(
                    entry.source.localizedDisplayName(),
                    style = MaterialTheme.typography.labelSmall,
                    color = AppColors.textMuted,
                )
            }
            Spacer(modifier = Modifier.height(Spacing.sm))
            val startDate = localizedDate(entry.dateRangeStart)
            val endDate = localizedDate(entry.dateRangeEnd)
            Text(
                pluralStringResource(
                    if (entry.exportMode == ExportMode.RAW_SNAPSHOT) {
                        R.plurals.raw_snapshot_history_entry_actions
                    } else {
                        R.plurals.history_entry_days
                    },
                    entry.totalCount,
                    entry.successCount,
                    entry.totalCount,
                    startDate,
                    endDate,
                ),
                style = GeistType.copy14Mono,
                color = AppColors.textPrimary,
            )
            Text(
                timestampStr,
                style = GeistType.copy13Mono,
                color = AppColors.textMuted,
            )
            localizedTargetLabel(entry)?.let {
                Text(
                    stringResource(R.string.history_target_label, it),
                    style = GeistType.copy13Mono,
                    color = AppColors.textMuted,
                )
            }
            if (entry.fileCount > 0) {
                Text(
                    pluralStringResource(
                        R.plurals.history_file_count,
                        entry.fileCount,
                        entry.fileCount,
                    ),
                    style = GeistType.copy13Mono,
                    color = AppColors.textMuted,
                )
            }
            if (!entry.isFullSuccess) {
                FailureSummary(entry, statusColor)
            }
        }
    }
}

@Composable
private fun FailureSummary(entry: ExportHistoryEntry, statusColor: androidx.compose.ui.graphics.Color) {
    val summary = entry.toDiagnosticsSummary()
    val isRawSnapshot = entry.exportMode == ExportMode.RAW_SNAPSHOT
    val primaryGroup = summary.failureGroups.firstOrNull()
    Spacer(modifier = Modifier.height(Spacing.sm))
    HorizontalDivider(color = AppColors.borderDefault)
    Spacer(modifier = Modifier.height(Spacing.sm))
    Text(
        pluralStringResource(
            if (isRawSnapshot) {
                R.plurals.raw_snapshot_diagnostics_incomplete_count
            } else {
                R.plurals.export_diagnostics_failed_count
            },
            summary.failedDayCount,
            summary.failedDayCount,
        ),
        style = MaterialTheme.typography.bodySmall,
        color = statusColor,
        fontWeight = FontWeight.Medium,
    )
    if (primaryGroup != null) {
        Spacer(modifier = Modifier.height(Spacing.xs))
        Text(
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
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textPrimary,
            fontWeight = FontWeight.Medium,
        )
        Text(
            primaryGroup.guidanceText(),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
        )
        if (!isRawSnapshot && primaryGroup.sampleDates.isNotEmpty()) {
            Text(
                localizedDateSampleText(
                    dates = primaryGroup.sampleDates,
                    remainingCount = primaryGroup.remainingDateCount,
                ),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }
    } else {
        Spacer(modifier = Modifier.height(Spacing.xs))
        Text(
            stringResource(R.string.export_diagnostics_no_details),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
        )
    }
}

@Composable
private fun HistoryDetailCard(
    entry: ExportHistoryEntry,
    isRetrying: Boolean,
    retryMessage: HistoryUiMessage?,
    onRetry: () -> Unit,
    modifier: Modifier = Modifier,
) {
    GeistCard(modifier = modifier, padding = Spacing.lg) {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(
                stringResource(R.string.history_detail_title),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
                fontWeight = FontWeight.SemiBold,
            )
            HistoryDetailContent(entry = entry, retryMessage = retryMessage)
            Spacer(modifier = Modifier.weight(1f))
            Button(onClick = onRetry, enabled = !isRetrying) {
                Icon(Icons.Outlined.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(Spacing.xxs))
                Text(if (isRetrying) stringResource(R.string.action_retrying_export) else stringResource(R.string.action_retry_export))
            }
        }
    }
}

@Composable
private fun HistoryDetailContent(entry: ExportHistoryEntry, retryMessage: HistoryUiMessage?) {
    val context = LocalContext.current
    val timestamp = stringResource(
        R.string.history_timestamp_format,
        android.text.format.DateFormat.getMediumDateFormat(context).format(Date(entry.timestamp)),
        android.text.format.DateFormat.getTimeFormat(context).format(Date(entry.timestamp)),
    )
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
        DetailLine(stringResource(R.string.history_detail_source), entry.source.localizedDisplayName())
        DetailLine(stringResource(R.string.history_detail_when), timestamp)
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
        DetailLine(
            stringResource(R.string.history_detail_destination_type),
            stringResource(
                if (entry.target == ExportTarget.API_ENDPOINT) {
                    R.string.export_preview_api_destination
                } else {
                    R.string.export_preview_device_destination
                },
            ),
        )
        localizedTargetLabel(entry)?.let {
            DetailLine(stringResource(R.string.history_detail_target), it)
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
        if (entry.failedDateDetails.isNotEmpty()) {
            val isRawSnapshot = entry.exportMode == ExportMode.RAW_SNAPSHOT
            Spacer(modifier = Modifier.height(Spacing.xs))
            Text(
                stringResource(
                    if (isRawSnapshot) R.string.raw_snapshot_history_detail_diagnostics else R.string.history_detail_failed_dates,
                ),
                style = MaterialTheme.typography.labelLarge,
                color = AppColors.textPrimary,
            )
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
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                )
            }
            if (entry.failedDateDetails.size > 8) {
                val remainingCount = entry.failedDateDetails.size - 8
                Text(
                    pluralStringResource(
                        R.plurals.history_more_items,
                        remainingCount,
                        remainingCount,
                    ),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
        }
        retryMessage?.let {
            Spacer(modifier = Modifier.height(Spacing.xs))
            Text(
                it.localizedText(),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.accent,
            )
        }
    }
}

@Composable
private fun HistoryDetailDialog(
    entry: ExportHistoryEntry,
    isRetrying: Boolean,
    retryMessage: HistoryUiMessage?,
    onRetry: () -> Unit,
    onDismiss: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.history_detail_title)) },
        text = { HistoryDetailContent(entry = entry, retryMessage = retryMessage) },
        confirmButton = {
            TextButton(onClick = onRetry, enabled = !isRetrying) {
                Icon(Icons.Outlined.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(Spacing.xxs))
                Text(if (isRetrying) stringResource(R.string.action_retrying_export) else stringResource(R.string.action_retry_export))
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.close)) }
        },
    )
}

@Composable
private fun DetailLine(label: String, value: String) {
    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodySmall, color = AppColors.textMuted)
        Spacer(modifier = Modifier.width(Spacing.sm))
        Text(value, style = GeistType.copy13Mono, color = AppColors.textPrimary, textAlign = TextAlign.End)
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
        ExportFailureReason.NETWORK_ERROR -> R.string.export_failure_network_label
        ExportFailureReason.API_REJECTED -> R.string.export_failure_api_rejected_label
        ExportFailureReason.RAW_UNSUPPORTED_PROVIDER -> R.string.raw_snapshot_provider_unsupported
        ExportFailureReason.RAW_PARTIAL -> R.string.raw_snapshot_partial_label
        ExportFailureReason.RAW_CANCELLED -> R.string.raw_snapshot_cancelled_label
        ExportFailureReason.UNKNOWN -> R.string.export_failure_unknown_label
    },
)
