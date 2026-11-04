package com.healthmd.presentation.archive

import android.content.Intent
import android.text.format.Formatter
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.presentation.i18n.localizedDisplayName
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/** The day page: the file Health.md writes for one Archive date, line by line. */
@Composable
fun DayPageScreen(
    onBack: () -> Unit,
    onReexport: (LocalDate) -> Unit,
    viewModel: DayPageViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val colors = LocalGeistColors.current
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val title = remember(state.date, locale) {
        state.date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.FULL).withLocale(locale))
    }
    val shareFile = state.selectedFile
    val shareTitle = stringResource(R.string.day_page_share)
    // An unwritten date is only a preview: nothing to share, and exporting it is the action.
    val share: (() -> Unit)? = shareFile?.takeIf { state.isWritten }?.let { file ->
        {
            val send = Intent(Intent.ACTION_SEND)
                .setType("text/plain")
                .putExtra(Intent.EXTRA_TEXT, file.content)
                .putExtra(Intent.EXTRA_TITLE, file.relativePath.substringAfterLast('/'))
            context.startActivity(Intent.createChooser(send, shareTitle))
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
            Box(Modifier.widthIn(max = GeistSizes.readableContentMaxWidth).fillMaxSize()) {
                when (val content = state.content) {
                    DayPageContent.Loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = colors.brandPrimary)
                    }
                    DayPageContent.RangeArtifactOnly -> DayPageMessage(stringResource(R.string.day_page_range_only))
                    DayPageContent.Empty -> DayPageMessage(stringResource(R.string.day_page_empty))
                    DayPageContent.Failed -> DayPageMessage(
                        stringResource(R.string.day_page_failed),
                        action = stringResource(R.string.day_page_retry) to viewModel::load,
                    )
                    is DayPageContent.Files -> DayPageFiles(
                        files = content.files,
                        selectedIndex = state.selectedIndex,
                        onSelect = viewModel::selectFile,
                    )
                }
            }
        }
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .background(colors.gray.c100)
                .navigationBarsPadding()
                .padding(GeistSpacing.space4),
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            if (state.isWritten) {
                FilledTonalButton(
                    onClick = { onReexport(state.date) },
                    modifier = Modifier.weight(1f).heightIn(min = 56.dp),
                    shape = RoundedCornerShape(GeistRadii.full),
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = colors.secondaryContainer,
                        contentColor = colors.onSecondaryContainer,
                    ),
                ) { Text(stringResource(R.string.archive_action_reexport), style = GeistType.button16) }
                Button(
                    onClick = { share?.invoke() },
                    enabled = share != null,
                    modifier = Modifier.weight(1.4f).heightIn(min = 56.dp),
                    shape = RoundedCornerShape(GeistRadii.full),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.brandPrimary,
                        contentColor = colors.brandOnPrimary,
                    ),
                ) { Text(shareTitle, style = GeistType.button16) }
            } else {
                Button(
                    onClick = { onReexport(state.date) },
                    modifier = Modifier.weight(1f).heightIn(min = 56.dp),
                    shape = RoundedCornerShape(GeistRadii.full),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.brandPrimary,
                        contentColor = colors.brandOnPrimary,
                    ),
                ) { Text(stringResource(R.string.day_page_export_day), style = GeistType.button16) }
            }
        }
    }
}

@Composable
private fun DayPageMessage(text: String, action: Pair<String, () -> Unit>? = null) {
    Column(
        modifier = Modifier.fillMaxSize().padding(GeistSpacing.space6),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text(text, style = MaterialTheme.typography.bodyLarge, color = LocalGeistColors.current.secondary, textAlign = TextAlign.Center)
        if (action != null) {
            Spacer(Modifier.heightIn(min = GeistSpacing.space3))
            TextButton(onClick = action.second) { Text(action.first, style = GeistType.button14) }
        }
    }
}

@Composable
private fun DayPageFiles(
    files: List<ExportPreviewFile>,
    selectedIndex: Int,
    onSelect: (Int) -> Unit,
) {
    val colors = LocalGeistColors.current
    val context = LocalContext.current
    val file = files.getOrNull(selectedIndex) ?: files.first()
    val lines = remember(file.content) { file.content.lines() }
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space1),
    ) {
        if (files.size > 1) {
            item {
                Row(
                    modifier = Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(vertical = GeistSpacing.space1),
                    horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                ) {
                    files.forEachIndexed { index, candidate ->
                        FilterChip(
                            selected = index == selectedIndex,
                            onClick = { onSelect(index) },
                            label = { Text(candidate.formatLabel ?: candidate.format.localizedDisplayName(), style = GeistType.button14) },
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
        }
        item {
            Text(
                text = stringResource(R.string.day_page_note),
                style = MaterialTheme.typography.bodyMedium,
                color = colors.secondary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space1, vertical = GeistSpacing.space3),
            )
        }
        item {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(topStart = GeistRadii.large, topEnd = GeistRadii.large))
                    .background(colors.gray.c100)
                    .padding(start = GeistSpacing.space6, end = GeistSpacing.space6, top = GeistSpacing.space4, bottom = GeistSpacing.space3),
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Text(
                    text = file.relativePath,
                    style = GeistType.label12Mono,
                    color = colors.secondary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = Formatter.formatShortFileSize(context, file.byteCount.toLong()),
                    style = GeistType.button12,
                    color = colors.secondary,
                )
            }
        }
        itemsIndexed(lines) { index, line ->
            val last = index == lines.lastIndex
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.gray.c100)
                    .padding(horizontal = GeistSpacing.space2)
                    .background(
                        colors.background100,
                        if (last) {
                            RoundedCornerShape(bottomStart = GeistRadii.listGroup, bottomEnd = GeistRadii.listGroup)
                        } else {
                            RoundedCornerShape(0.dp)
                        },
                    )
                    .padding(vertical = 1.dp),
            ) {
                Text(
                    text = (index + 1).toString(),
                    style = GeistType.label12Mono,
                    color = colors.gray.c700,
                    textAlign = TextAlign.End,
                    modifier = Modifier.width(40.dp).padding(end = GeistSpacing.space3),
                )
                Text(
                    text = line.ifEmpty { " " },
                    style = GeistType.label12Mono,
                    color = colors.primary,
                    softWrap = false,
                    modifier = Modifier.weight(1f).horizontalScroll(rememberScrollState()),
                )
            }
        }
        item {
            Box(
                Modifier
                    .fillMaxWidth()
                    .clip(RoundedCornerShape(bottomStart = GeistRadii.large, bottomEnd = GeistRadii.large))
                    .background(colors.gray.c100)
                    .padding(GeistSpacing.space1),
            )
        }
        if (file.previewOmittedByteCount > 0) {
            item {
                Text(
                    text = stringResource(R.string.day_page_truncated),
                    style = MaterialTheme.typography.bodySmall,
                    color = colors.secondary,
                    modifier = Modifier.padding(GeistSpacing.space2),
                )
            }
        }
    }
}
