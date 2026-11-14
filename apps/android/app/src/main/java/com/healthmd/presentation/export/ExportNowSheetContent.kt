package com.healthmd.presentation.export

import android.content.Context
import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.export.components.ExportDecisionAction
import com.healthmd.presentation.export.components.ExportDecisionDialog
import com.healthmd.presentation.settings.SettingsBadge
import com.healthmd.presentation.settings.SettingsBadgeTone
import com.healthmd.presentation.settings.SettingsGroup
import com.healthmd.presentation.settings.SettingsRow
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import java.time.LocalDate
import java.time.ZoneId

/** iOS GlassBanner: an outlined tonal note with a leading symbol, a bold lead and a message. */
@Composable
internal fun ExportNowBanner(
    title: String,
    message: String? = null,
    warning: Boolean = true,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val tint: Color = if (warning) colors.warning else colors.brandPrimary
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.listGroup))
            .background(colors.gray.c200)
            .border(1.dp, tint.copy(alpha = 0.6f), RoundedCornerShape(GeistRadii.listGroup))
            .semantics(mergeDescendants = true) {}
            .padding(GeistSpacing.space4),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Icon(
            if (warning) Icons.Outlined.Schedule else Icons.Outlined.Info,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(20.dp),
        )
        Column(Modifier.weight(1f)) {
            Text(title, style = GeistType.heading14, color = colors.primary)
            message?.let { Text(it, style = GeistType.copy14, color = colors.secondary) }
        }
    }
}

/** The one action that lets a run reach its destination: choose the folder or set up the endpoint. */
@Composable
internal fun ExportDestinationSetupCard(target: ExportTarget, onSetUp: () -> Unit) {
    val colors = LocalGeistColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.listGroup))
            .background(colors.gray.c200)
            .padding(GeistSpacing.space4)
            .testTag("export.now.destinationSetup"),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Text(
            stringResource(
                when (target) {
                    ExportTarget.DEVICE_FOLDER -> R.string.export_now_setup_folder
                    ExportTarget.GOOGLE_DRIVE -> R.string.google_drive_title
                    ExportTarget.API_ENDPOINT -> R.string.export_now_setup_api
                    ExportTarget.AGENT_DATA_GATEWAY -> R.string.export_now_setup_gateway
                },
            ),
            style = GeistType.copy14,
            color = colors.secondary,
        )
        SecondaryButton(
            text = stringResource(
                when (target) {
                    ExportTarget.DEVICE_FOLDER -> R.string.folder_destination_choose
                    else -> R.string.action_configure_endpoint
                },
            ),
            onClick = onSetUp,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Where this run writes, when there are no profiles to choose between and several destinations are set up. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun ExportNowDestinationChoice(
    targets: List<ExportTarget>,
    selected: ExportTarget,
    onSelect: (ExportTarget) -> Unit,
) {
    val colors = LocalGeistColors.current
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
        Text(stringResource(R.string.export_now_destination), style = GeistType.heading14, color = colors.brandPrimary)
        SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
            targets.forEachIndexed { index, target ->
                SegmentedButton(
                    selected = target == selected,
                    onClick = { if (target != selected) onSelect(target) },
                    shape = SegmentedButtonDefaults.itemShape(index, targets.size),
                    icon = {},
                    colors = SegmentedButtonDefaults.colors(
                        activeContainerColor = colors.secondaryContainer,
                        activeContentColor = colors.onSecondaryContainer,
                        inactiveContentColor = colors.primary,
                        activeBorderColor = colors.gray.c700,
                        inactiveBorderColor = colors.gray.c700,
                    ),
                ) {
                    Text(
                        stringResource(
                            when (target) {
                                ExportTarget.DEVICE_FOLDER -> R.string.folder_page_folder
                                ExportTarget.GOOGLE_DRIVE -> R.string.google_drive_title
                                ExportTarget.API_ENDPOINT -> R.string.export_preview_api_destination
                                ExportTarget.AGENT_DATA_GATEWAY -> R.string.export_now_destination_gateway
                            },
                        ),
                        style = GeistType.button14,
                        maxLines = 1,
                    )
                }
            }
        }
    }
}

/** "Oct 24 – 30", "Oct 24": localized, without the year, as iOS's range text. */
internal fun exportRangeText(context: Context, start: LocalDate, end: LocalDate): String {
    val zone = ZoneId.systemDefault()
    fun noon(date: LocalDate) = date.atTime(12, 0).atZone(zone).toInstant().toEpochMilli()
    val first = minOf(start, end)
    val last = maxOf(start, end)
    return DateUtils.formatDateRange(
        context,
        noon(first),
        noon(last),
        DateUtils.FORMAT_SHOW_DATE or DateUtils.FORMAT_ABBREV_MONTH or DateUtils.FORMAT_NO_YEAR,
    )
}

/** The moment's done line: "Oct 24 – 30 · 14 files". */
@Composable
internal fun momentDoneSubtitle(result: ExportResult, start: LocalDate, end: LocalDate): String {
    val context = LocalContext.current
    return listOfNotNull(
        exportRangeText(context, start, end),
        result.artifactCount.takeIf { it > 0 }?.let { pluralStringResource(R.plurals.export_now_files, it, it) },
    ).joinToString(" · ")
}

/**
 * ExportResultG, inside the sheet, for a run that did not write every day: which days were
 * written, failed or left unwritten, with Retry for exactly those days and the folder to open.
 */
@Composable
internal fun ExportResultContent(
    result: ExportResult,
    rangeStart: LocalDate,
    rangeEnd: LocalDate,
    profileName: String?,
    onRetry: (LocalDate, LocalDate) -> Unit,
    onShowInFiles: (() -> Unit)?,
    onDone: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val context = LocalContext.current
    val rows = ExportResultDays.rows(
        start = rangeStart,
        end = rangeEnd,
        failed = result.failedDateDetails.associate { it.date to it.reason },
        notWritten = result.remainingDates,
        successCount = result.successCount,
    )
    val retry = ExportResultDays.retryRange(result)
    val retryText = retry?.let { exportRangeText(context, it.first, it.second) }
    var explained by remember { mutableStateOf<ExportResultDays.Row.Failed?>(null) }
    val groups = result.toDiagnosticsSummary().failureGroups

    Column(Modifier.fillMaxSize().testTag("export.result")) {
        Column(
            Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GeistSpacing.space4),
        ) {
            Text(
                stringResource(R.string.export_result_title, result.successCount, result.totalCount),
                style = GeistType.heading24,
                color = colors.primary,
                modifier = Modifier.padding(top = GeistSpacing.space2).semantics { heading() },
            )
            Text(
                listOfNotNull(
                    exportRangeText(context, rangeStart, rangeEnd),
                    profileName?.takeIf { it.isNotBlank() },
                    result.artifactCount.takeIf { it > 0 }?.let { pluralStringResource(R.plurals.export_now_files, it, it) },
                    stringResource(R.string.export_result_cancelled).takeIf { result.wasCancelled },
                ).joinToString(" · "),
                style = GeistType.copy14,
                color = colors.secondary,
            )

            if (rows.isNotEmpty()) {
                SettingsGroup(
                    title = stringResource(R.string.export_result_days),
                    rows = rows.map<_, @Composable (Shape) -> Unit> { row ->
                        { shape -> ExportResultDayRow(shape, row, context, onExplain = { explained = it }) }
                    },
                )
            }

            Column(
                Modifier.padding(top = GeistSpacing.space6),
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                if (retry != null && retryText != null) {
                    ExportNowBanner(
                        title = stringResource(
                            if (retry.first == retry.second) R.string.export_result_retry_note_one else R.string.export_result_retry_note,
                            retryText,
                        ),
                        warning = false,
                    )
                }
                groups.forEach { group ->
                    ExportNowBanner(title = group.failureReasonLabel(), message = group.guidanceText(), warning = false)
                }
            }
        }
        Column(
            Modifier
                .fillMaxWidth()
                .background(colors.background200)
                .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (retry != null && retryText != null) {
                PrimaryButton(
                    text = stringResource(R.string.export_result_retry, retryText),
                    onClick = { onRetry(retry.first, retry.second) },
                    modifier = Modifier.fillMaxWidth().testTag("export.result.retry"),
                )
            }
            if (onShowInFiles != null) {
                SecondaryButton(
                    text = stringResource(R.string.export_result_show_in_files),
                    onClick = onShowInFiles,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
            TextButton(onClick = onDone, modifier = Modifier.testTag("export.result.done")) {
                Text(stringResource(R.string.export_preview_done), style = GeistType.button14, color = colors.secondary)
            }
        }
    }

    explained?.let { failure ->
        val day = exportRangeText(context, failure.date, failure.date)
        val group = groups.firstOrNull { it.reason == failure.reason }
        ExportDecisionDialog(
            title = day,
            message = listOfNotNull(failure.reason.localizedFailureLabel(), group?.guidanceText()).joinToString("\n\n"),
            actions = listOf(
                ExportDecisionAction(
                    title = stringResource(R.string.export_result_retry, day),
                    role = ExportDecisionAction.Role.PRIMARY,
                ) {
                    explained = null
                    onRetry(failure.date, failure.date)
                },
                ExportDecisionAction(title = stringResource(R.string.cancel)) { explained = null },
            ),
        )
    }
}

@Composable
private fun ExportResultDayRow(
    shape: Shape,
    row: ExportResultDays.Row,
    context: Context,
    onExplain: (ExportResultDays.Row.Failed) -> Unit,
) {
    when (row) {
        is ExportResultDays.Row.Complete -> SettingsRow(
            shape = shape,
            title = exportRangeText(context, row.start, row.end),
            icon = null,
            badge = SettingsBadge(stringResource(R.string.export_result_complete), SettingsBadgeTone.OK),
            onClick = null,
        )
        is ExportResultDays.Row.Failed -> SettingsRow(
            shape = shape,
            title = exportRangeText(context, row.date, row.date),
            subtitle = row.reason.localizedFailureLabel(),
            icon = null,
            badge = SettingsBadge(stringResource(R.string.api_page_failed), SettingsBadgeTone.ATTENTION),
            onClick = { onExplain(row) },
            modifier = Modifier.testTag("export.result.failedDay"),
        )
        is ExportResultDays.Row.NotWritten -> SettingsRow(
            shape = shape,
            title = exportRangeText(context, row.date, row.date),
            icon = null,
            badge = SettingsBadge(stringResource(R.string.export_result_not_written), SettingsBadgeTone.OFF),
            onClick = null,
        )
    }
}
