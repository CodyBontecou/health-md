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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.presentation.common.GlassBadge
import com.healthmd.presentation.common.GlassCard
import com.healthmd.presentation.common.GlassIconCircle
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.export.dateSampleText
import com.healthmd.presentation.export.failureReasonLabel
import com.healthmd.presentation.export.guidanceText
import com.healthmd.presentation.export.toDiagnosticsSummary
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import java.text.DateFormat
import java.util.Date

@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel = hiltViewModel(),
) {
    val entries by viewModel.entries.collectAsStateWithLifecycle()
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()

    uiState.selectedEntry?.let { entry ->
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
                    Text(stringResource(R.string.clear))
                }
            },
            dismissButton = {
                TextButton(onClick = { viewModel.dismissClearHistory() }) {
                    Text(stringResource(R.string.cancel))
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
            GlassIconCircle(size = 84.dp) {
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
                fontWeight = FontWeight.Bold,
                color = AppColors.textPrimary,
                letterSpacing = 3.sp,
                lineHeight = 36.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(modifier = Modifier.height(Spacing.sm))
            Text(
                stringResource(R.string.no_history_subtitle),
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
            )
        }
    } else {
        LazyColumn(
            modifier = Modifier.fillMaxSize(),
            contentPadding = PaddingValues(
                start = Spacing.md,
                end = Spacing.md,
                top = Spacing.lg,
                bottom = 100.dp,
            ),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    SectionLabel(stringResource(R.string.section_export_history))
                    TextButton(onClick = { viewModel.requestClearHistory() }) {
                        Icon(Icons.Outlined.Delete, contentDescription = null, modifier = Modifier.size(18.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(stringResource(R.string.clear))
                    }
                }
                uiState.retryMessage?.let { message ->
                    GlassBadge(borderColor = AppColors.accent.copy(alpha = 0.35f)) {
                        Text(message, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
                    }
                }
            }
            items(entries, key = { it.id }) { entry ->
                HistoryEntryCard(entry = entry, onClick = { viewModel.selectEntry(entry) })
            }
        }
    }
}

@Composable
private fun HistoryEntryCard(entry: ExportHistoryEntry, onClick: () -> Unit) {
    val dateOnly = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(entry.timestamp))
    val timeOnly = DateFormat.getTimeInstance(DateFormat.SHORT).format(Date(entry.timestamp))
    val timestampStr = stringResource(R.string.history_timestamp_format, dateOnly, timeOnly)

    val statusColor = when {
        entry.isFullSuccess -> AppColors.success
        entry.isPartialSuccess -> AppColors.warning
        else -> AppColors.error
    }

    GlassCard(padding = Spacing.md) {
        Column(modifier = Modifier.clickable(onClick = onClick)) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                GlassBadge(borderColor = statusColor.copy(alpha = 0.5f)) {
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
            Text(
                stringResource(R.string.history_entry_days, entry.successCount, entry.totalCount, entry.dateRangeStart, entry.dateRangeEnd),
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textPrimary,
            )
            Text(
                timestampStr,
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
            entry.targetLabel?.let {
                Text(
                    stringResource(R.string.history_target_label, it),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
            if (entry.fileCount > 0) {
                Text(
                    stringResource(R.string.history_file_count, entry.fileCount),
                    style = MaterialTheme.typography.bodySmall,
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
    val primaryGroup = summary.failureGroups.firstOrNull()
    Spacer(modifier = Modifier.height(Spacing.sm))
    HorizontalDivider(color = AppColors.glassBorder)
    Spacer(modifier = Modifier.height(Spacing.sm))
    Text(
        stringResource(R.string.export_diagnostics_failed_count, summary.failedDayCount),
        style = MaterialTheme.typography.bodySmall,
        color = statusColor,
        fontWeight = FontWeight.Medium,
    )
    if (primaryGroup != null) {
        Spacer(modifier = Modifier.height(Spacing.xs))
        Text(
            stringResource(
                R.string.export_diagnostics_reason_count,
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
        if (primaryGroup.sampleDates.isNotEmpty()) {
            Text(
                primaryGroup.dateSampleText(),
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
private fun HistoryDetailDialog(
    entry: ExportHistoryEntry,
    isRetrying: Boolean,
    retryMessage: String?,
    onRetry: () -> Unit,
    onDismiss: () -> Unit,
) {
    val timestamp = DateFormat.getDateTimeInstance(DateFormat.MEDIUM, DateFormat.SHORT).format(Date(entry.timestamp))
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.history_detail_title)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                DetailLine(stringResource(R.string.history_detail_source), entry.source.localizedDisplayName())
                DetailLine(stringResource(R.string.history_detail_when), timestamp)
                DetailLine(stringResource(R.string.history_detail_range), "${entry.dateRangeStart} → ${entry.dateRangeEnd}")
                DetailLine(stringResource(R.string.history_detail_counts), "${entry.successCount}/${entry.totalCount}")
                entry.targetLabel?.let { DetailLine(stringResource(R.string.history_detail_target), it) }
                DetailLine(stringResource(R.string.history_detail_files), entry.fileCount.toString())
                entry.failureReason?.let { DetailLine(stringResource(R.string.history_detail_failure), it.name) }
                entry.warningSummary?.let { DetailLine(stringResource(R.string.history_detail_warning), it) }
                if (entry.failedDateDetails.isNotEmpty()) {
                    Spacer(modifier = Modifier.height(Spacing.xs))
                    Text(stringResource(R.string.history_detail_failed_dates), style = MaterialTheme.typography.labelLarge, color = AppColors.textPrimary)
                    entry.failedDateDetails.take(8).forEach { detail ->
                        Text(
                            "${detail.date}: ${detail.reason.name}",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.textSecondary,
                        )
                    }
                    if (entry.failedDateDetails.size > 8) {
                        Text(
                            "+${entry.failedDateDetails.size - 8} more",
                            style = MaterialTheme.typography.bodySmall,
                            color = AppColors.textMuted,
                        )
                    }
                }
                retryMessage?.let {
                    Spacer(modifier = Modifier.height(Spacing.xs))
                    Text(it, style = MaterialTheme.typography.bodySmall, color = AppColors.accent)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onRetry, enabled = !isRetrying) {
                Icon(Icons.Outlined.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(4.dp))
                Text(if (isRetrying) stringResource(R.string.retrying) else stringResource(R.string.retry))
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
        Text(value, style = MaterialTheme.typography.bodySmall, color = AppColors.textPrimary, textAlign = TextAlign.End)
    }
}
