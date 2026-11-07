package com.healthmd.presentation.archive

import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.text.format.Formatter
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.LocalDate
import java.time.format.DateTimeFormatter

/**
 * The day page (iOS `ArchiveDayPage`): one tab per automation, its status for the date, and
 * the file it wrote, line by line, with the date's fix and Open file below.
 */
@Composable
fun DayPageScreen(
    onBack: () -> Unit,
    /** Export now preset to this date and the tab's automation (Backfill, Retry, Refresh, Re-export). */
    onFix: (LocalDate, String?) -> Unit,
    viewModel: DayPageViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val loaded by viewModel.file.collectAsStateWithLifecycle()
    val colors = LocalGeistColors.current
    val context = LocalContext.current
    val locale = currentLocale()
    val title = remember(state.date, locale) { state.date.format(DateTimeFormatter.ofPattern("EEEE, MMM d", locale)) }
    val key = state.fileKey
    val file = loaded?.takeIf { it.key == key }?.file
    val isLoading = key != null && loaded?.key != key
    val shareTitle = stringResource(R.string.day_page_share)
    val noViewer = stringResource(R.string.day_page_no_viewer)
    val share: (() -> Unit)? = file?.let { shown ->
        {
            val uri = Uri.parse(shown.documentUri)
            val send = Intent(Intent.ACTION_SEND)
                .setType(shown.mimeType ?: "text/plain")
                .putExtra(Intent.EXTRA_STREAM, uri)
                .putExtra(Intent.EXTRA_TITLE, shown.name)
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            send.clipData = ClipData.newRawUri(shown.name, uri)
            context.startActivity(Intent.createChooser(send, shareTitle))
        }
    }
    val open: (() -> Unit)? = file?.let { shown ->
        {
            val view = Intent(Intent.ACTION_VIEW)
                .setDataAndType(Uri.parse(shown.documentUri), shown.mimeType ?: "text/plain")
                .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            try {
                context.startActivity(view)
            } catch (_: ActivityNotFoundException) {
                Toast.makeText(context, noViewer, Toast.LENGTH_SHORT).show()
            }
        }
    }

    Column(Modifier.fillMaxSize().background(colors.background100)) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = GeistSpacing.space1, vertical = GeistSpacing.space2),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.back), tint = colors.primary)
            }
            Text(
                text = title,
                style = MaterialTheme.typography.titleLarge,
                color = colors.primary,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            if (share != null) {
                IconButton(onClick = share) {
                    Icon(Icons.Outlined.Share, contentDescription = shareTitle, tint = colors.secondary)
                }
            }
        }
        Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.TopCenter) {
            Column(
                modifier = Modifier
                    .widthIn(max = GeistSizes.readableContentMaxWidth)
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
            ) {
                if (state.lanes.size > 1) {
                    DayPageTabs(state, onSelect = viewModel::select)
                }
                state.lane?.let { lane ->
                    Column(
                        modifier = Modifier.padding(horizontal = GeistSpacing.space1),
                        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                    ) {
                        StatusBadge(lane.row.day.status)
                        Text(
                            text = dayNote(lane.row, if (lane.isPaused) setOf(lane.row.day.profile) else emptySet()),
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.secondary,
                        )
                    }
                    DayPageFileCard(lane, file, emptyMessage(lane, isLoading))
                }
            }
        }
        val lane = state.lane
        val secondary = state.secondaryAction
        if (lane != null && (secondary != null || open != null)) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.gray.c100)
                    .navigationBarsPadding()
                    .padding(GeistSpacing.space4),
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            ) {
                secondary?.let { action ->
                    val label = stringResource(action.labelRes())
                    if (open != null) {
                        FilledTonalButton(
                            onClick = { onFix(state.date, lane.row.automationId) },
                            modifier = Modifier.weight(1f).heightIn(min = 56.dp),
                            shape = CircleShape,
                            colors = ButtonDefaults.filledTonalButtonColors(
                                containerColor = colors.secondaryContainer,
                                contentColor = colors.onSecondaryContainer,
                            ),
                        ) { Text(label, style = GeistType.button16) }
                    } else {
                        Button(
                            onClick = { onFix(state.date, lane.row.automationId) },
                            modifier = Modifier.weight(1f).heightIn(min = 56.dp),
                            shape = CircleShape,
                            colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
                        ) { Text(label, style = GeistType.button16) }
                    }
                }
                if (open != null) {
                    Button(
                        onClick = open,
                        modifier = Modifier.weight(1.4f).heightIn(min = 56.dp),
                        shape = CircleShape,
                        colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
                    ) { Text(stringResource(R.string.day_page_open_file), style = GeistType.button16) }
                }
            }
        }
    }
}

@Composable
private fun DayPageTabs(state: DayPageUiState, onSelect: (ArchiveProfile) -> Unit) {
    val colors = LocalGeistColors.current
    val automation = stringResource(R.string.day_page_automation)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .horizontalScroll(rememberScrollState())
            .semantics { contentDescription = automation },
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
    ) {
        state.lanes.forEach { lane ->
            val profile = lane.row.day.profile
            FilterChip(
                selected = profile == state.lane?.row?.day?.profile,
                onClick = { onSelect(profile) },
                label = {
                    Text(
                        profile.name ?: state.currentSettingsName ?: stringResource(R.string.archive_filter_current_settings),
                        style = GeistType.button14,
                    )
                },
                leadingIcon = { ProfileDot(color = profileColor(colors, lane.colorIndex), filled = true) },
                colors = FilterChipDefaults.filterChipColors(
                    selectedContainerColor = colors.secondaryContainer,
                    selectedLabelColor = colors.onSecondaryContainer,
                    labelColor = colors.secondary,
                ),
                shape = RoundedCornerShape(GeistRadii.small),
            )
        }
    }
}

@Composable
private fun DayPageFileCard(lane: DayPageLane, file: ArchiveDayFile?, emptyMessage: String) {
    val colors = LocalGeistColors.current
    val context = LocalContext.current
    GeistCard(padding = GeistSpacing.space4) {
        Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3), verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = lane.row.path.orEmpty(),
                style = GeistType.label12Mono,
                color = colors.secondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            if (file != null) {
                Text(
                    text = Formatter.formatShortFileSize(context, file.byteCount),
                    style = GeistType.button12,
                    color = colors.secondary,
                )
            }
        }
        if (file == null) {
            Text(
                text = emptyMessage,
                style = MaterialTheme.typography.bodyMedium,
                color = colors.secondary,
                modifier = Modifier.padding(top = GeistSpacing.space3),
            )
            return@GeistCard
        }
        val lines = remember(file.source) { file.lines }
        val digits = maxOf(2, lines.size.toString().length)
        Column(
            modifier = Modifier
                .padding(top = GeistSpacing.space3)
                .horizontalScroll(rememberScrollState()),
        ) {
            SelectionContainer {
                Column {
                    lines.forEachIndexed { index, line ->
                        Row(modifier = Modifier.heightIn(min = 22.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(
                                text = (index + 1).toString(),
                                style = GeistType.label12Mono,
                                color = colors.gray.c700,
                                textAlign = TextAlign.End,
                                modifier = Modifier.widthIn(min = (digits * 8 + 8).dp).padding(end = GeistSpacing.space3),
                            )
                            val trimmed = line.trim()
                            Text(
                                text = line.ifEmpty { " " },
                                style = GeistType.label12Mono,
                                fontWeight = if (trimmed.startsWith("#")) FontWeight.Medium else FontWeight.Normal,
                                color = when {
                                    trimmed == "---" || trimmed == "{" || trimmed == "}" -> colors.gray.c700
                                    trimmed.startsWith("#") -> colors.primary
                                    else -> colors.secondary
                                },
                                softWrap = false,
                            )
                        }
                    }
                }
            }
        }
        if (file.isTruncated) {
            Text(
                text = stringResource(R.string.day_page_long_file),
                style = MaterialTheme.typography.bodySmall,
                color = colors.secondary,
                modifier = Modifier.padding(top = GeistSpacing.space2),
            )
        }
    }
}

/** iOS `emptyMessage`: why no file shows for the selected tab. */
@Composable
private fun emptyMessage(lane: DayPageLane, isLoading: Boolean): String {
    val row = lane.row
    val status = row.day.status
    val wasWritten = status == CoverageStatus.COMPLETE || status == CoverageStatus.PARTIAL ||
        status == CoverageStatus.IN_PROGRESS
    return when {
        isLoading -> stringResource(R.string.day_page_reading)
        !row.writesFilesOnDevice -> stringResource(R.string.day_page_not_on_device)
        // Nothing has run for today yet, so no file was ever there to go missing.
        status == CoverageStatus.IN_PROGRESS && row.day.latestEntry == null ->
            stringResource(R.string.day_page_not_written_yet)
        wasWritten -> stringResource(if (row.file != null) R.string.day_page_file_gone else R.string.day_page_no_own_file)
        status == CoverageStatus.MISSING -> stringResource(R.string.day_page_no_file)
        else -> stringResource(R.string.day_page_nothing_due)
    }
}
