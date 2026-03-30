package com.healthmd.presentation.history

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.History
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.presentation.common.GlassBadge
import com.healthmd.presentation.common.GlassCard
import com.healthmd.presentation.common.GlassIconCircle
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun HistoryScreen(
    viewModel: HistoryViewModel = hiltViewModel(),
) {
    val entries by viewModel.entries.collectAsStateWithLifecycle()

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
                bottom = 100.dp, // space for nav bar
            ),
            verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            item {
                SectionLabel(stringResource(R.string.section_export_history))
            }
            items(entries, key = { it.id }) { entry ->
                HistoryEntryCard(entry = entry)
            }
        }
    }
}

@Composable
private fun HistoryEntryCard(entry: ExportHistoryEntry) {
    val dateFormat = SimpleDateFormat("MMM d, yyyy 'at' h:mm a", Locale.getDefault())
    val timestampStr = dateFormat.format(Date(entry.timestamp))

    val statusColor = when {
        entry.isFullSuccess -> AppColors.success
        entry.isPartialSuccess -> AppColors.warning
        else -> AppColors.error
    }

    GlassCard(padding = Spacing.md) {
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
                entry.source.name.lowercase().replaceFirstChar { it.uppercase() },
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
    }
}
