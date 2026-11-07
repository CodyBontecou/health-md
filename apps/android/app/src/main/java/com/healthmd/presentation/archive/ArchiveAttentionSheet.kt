package com.healthmd.presentation.archive

import android.icu.text.MessageFormat
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material3.Badge
import androidx.compose.material3.BadgedBox
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.FilledTonalIconButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.history.localizedLabel
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.text.NumberFormat
import kotlinx.coroutines.launch

/** The Archive header's Health.md heart: opens Needs attention and carries its count. */
@Composable
internal fun ArchiveAttentionButton(count: Int, onClick: () -> Unit) {
    val colors = LocalGeistColors.current
    // The app's name, as iOS labels the heart; never translated.
    val label = "Health.md"
    val state = if (count > 0) {
        pluralStringResource(R.plurals.archive_attention_count, count, count)
    } else {
        stringResource(R.string.attention_empty_title)
    }
    BadgedBox(
        badge = {
            if (count > 0) {
                Badge(containerColor = colors.coverageMissing, contentColor = colors.background100) {
                    Text(count.toString())
                }
            }
        },
        modifier = Modifier.semantics(mergeDescendants = true) {
            contentDescription = label
            stateDescription = state
        },
    ) {
        FilledTonalIconButton(
            onClick = onClick,
            colors = IconButtonDefaults.filledTonalIconButtonColors(
                containerColor = colors.secondaryContainer,
                contentColor = colors.brandPrimary,
            ),
        ) {
            Icon(Icons.Filled.Favorite, contentDescription = null)
        }
    }
}

/** iOS `AttentionScreen`: one card per live problem, each with its fix, as a bottom sheet. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ArchiveAttentionSheet(
    items: List<ArchiveAttentionItem>,
    onDismiss: () -> Unit,
    onFix: (ArchiveAttentionItem) -> Unit,
) {
    val colors = LocalGeistColors.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = colors.background100,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GeistSpacing.space4)
                .padding(bottom = GeistSpacing.space8)
                .navigationBarsPadding(),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        ) {
            Text(
                text = stringResource(R.string.attention_title),
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                color = colors.primary,
                textAlign = TextAlign.Center,
                modifier = Modifier.fillMaxWidth().semantics { heading() },
            )
            if (items.isEmpty()) {
                GeistCard(padding = GeistSpacing.space6) {
                    Column(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalAlignment = Alignment.CenterHorizontally,
                        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                    ) {
                        Icon(Icons.Filled.Favorite, contentDescription = null, tint = colors.brandPrimary, modifier = Modifier.size(40.dp))
                        Text(
                            stringResource(R.string.attention_empty_title),
                            style = MaterialTheme.typography.titleMedium,
                            color = colors.primary,
                        )
                        Text(
                            stringResource(R.string.attention_empty_body),
                            style = MaterialTheme.typography.bodyMedium,
                            color = colors.secondary,
                            textAlign = TextAlign.Center,
                        )
                    }
                }
            }
            items.forEach { item ->
                AttentionCard(item) {
                    scope.launch { sheetState.hide() }.invokeOnCompletion {
                        onDismiss()
                        onFix(item)
                    }
                }
            }
        }
    }
}

@Composable
private fun AttentionCard(item: ArchiveAttentionItem, onFix: () -> Unit) {
    val colors = LocalGeistColors.current
    val copy = attentionCopy(item)
    GeistCard(
        modifier = Modifier.border(1.dp, colors.coverageMissing.copy(alpha = 0.8f), RoundedCornerShape(GeistRadii.large)),
        padding = GeistSpacing.space4,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
            Icon(
                Icons.Outlined.ErrorOutline,
                contentDescription = null,
                tint = colors.coverageMissing,
                modifier = Modifier.padding(top = 1.dp),
            )
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                Text(copy.title, style = GeistType.heading14, color = colors.primary)
                Text(copy.message, style = MaterialTheme.typography.bodyMedium, color = colors.secondary)
                FilledTonalButton(
                    onClick = onFix,
                    shape = CircleShape,
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = colors.secondaryContainer,
                        contentColor = colors.onSecondaryContainer,
                    ),
                ) { Text(copy.action, style = GeistType.button14) }
            }
        }
    }
}

private data class AttentionCopy(val title: String, val message: String, val action: String)

@Composable
private fun attentionCopy(item: ArchiveAttentionItem): AttentionCopy = when (item) {
    ArchiveAttentionItem.HealthPermission -> AttentionCopy(
        title = stringResource(R.string.attention_health_title),
        message = stringResource(R.string.attention_health_body),
        action = stringResource(R.string.archive_setup_connect),
    )
    is ArchiveAttentionItem.FolderUnavailable -> {
        val folder = item.folderName
        val waiting = item.waiting.joinToString(", ")
        AttentionCopy(
            title = stringResource(R.string.attention_folder_title),
            message = when {
                folder != null && waiting.isNotEmpty() -> stringResource(R.string.attention_folder_body_named_waiting, folder, waiting)
                folder != null -> stringResource(R.string.attention_folder_body_named, folder)
                waiting.isNotEmpty() -> stringResource(R.string.attention_folder_body_waiting, waiting)
                else -> stringResource(R.string.attention_folder_body)
            },
            action = stringResource(R.string.attention_folder_action),
        )
    }
    is ArchiveAttentionItem.EndpointFailing -> {
        val isGateway = item.target == ExportTarget.AGENT_DATA_GATEWAY
        val host = item.host ?: stringResource(if (isGateway) R.string.attention_host_gateway else R.string.attention_host_api)
        val times = spelledCount(item.failures)
        // A status code is an identifier, not a quantity: never grouped or localized.
        val base = item.httpStatus?.let { status ->
            pluralStringResource(R.plurals.attention_endpoint_status, item.failures, host, status.toString(), times)
        } ?: pluralStringResource(
            R.plurals.attention_endpoint_failed,
            item.failures,
            host,
            (item.reason ?: ExportFailureReason.UNKNOWN).localizedLabel(),
            times,
        )
        val retry = item.profileName?.let { name ->
            when (item.retry) {
                ArchiveAttentionItem.Retry.NEXT_REFRESH -> stringResource(R.string.attention_retry_refresh, name)
                ArchiveAttentionItem.Retry.NEXT_SCHEDULED_RUN -> stringResource(R.string.attention_retry_run, name)
                null -> null
            }
        }
        AttentionCopy(
            title = stringResource(if (isGateway) R.string.attention_gateway_title else R.string.attention_endpoint_title),
            message = listOfNotNull(base, retry).joinToString(" "),
            action = stringResource(R.string.attention_endpoint_action),
        )
    }
}

/** iOS `AttentionCountText`: "three times" for one to ten, digits beyond. */
@Composable
private fun spelledCount(count: Int): String {
    val locale = currentLocale()
    return remember(count, locale) {
        if (count in 1..10) {
            runCatching { MessageFormat("{0,spellout}", locale).format(arrayOf<Any>(count)) }.getOrNull()
        } else {
            null
        } ?: NumberFormat.getIntegerInstance(locale).format(count)
    }
}
