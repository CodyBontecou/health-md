package com.healthmd.presentation.export.components

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import com.healthmd.presentation.common.dialogNavigationBarsPadding
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.healthmd.R
import com.healthmd.presentation.theme.GeistColors
import com.healthmd.presentation.theme.GeistMotion
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.rawexport.ExportMode
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

/**
 * The export moment: a full-screen progress surface while a manual export runs. A crystal
 * heart fills facet by facet as days are written; the card below states the day being
 * written and the count, and keeps Cancel export available. Back cannot dismiss a running
 * export, matching the previous blocking dialog.
 */
@Composable
fun ExportProgressDialog(
    current: Int,
    total: Int,
    currentDate: LocalDate?,
    rangeStart: LocalDate,
    rangeEnd: LocalDate,
    exportMode: ExportMode,
    onCancel: () -> Unit,
    /**
     * Set once a run finished with every day written: the moment holds its full heart and
     * offers "See in archive" and Close before the sheet shows the detailed result.
     */
    isDone: Boolean = false,
    onSeeInArchive: (() -> Unit)? = null,
    onClose: () -> Unit = {},
    /** The done line, as on iOS: "Oct 24 – 30 · 14 files". */
    doneSubtitle: String? = null,
) {
    val colors = LocalGeistColors.current
    val locale = LocalConfiguration.current.locales[0]
    val dateFormatter = DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM).withLocale(locale)
    val localizedCurrentDate = currentDate?.format(dateFormatter)
    val localizedRangeStart = rangeStart.format(dateFormatter)
    val localizedRangeEnd = rangeEnd.format(dateFormatter)
    val isRaw = exportMode == ExportMode.RAW_SNAPSHOT
    val progressStateDescription = if (isRaw) {
        pluralStringResource(R.plurals.export_progress_state_raw, total, current, total, localizedRangeStart, localizedRangeEnd)
    } else if (localizedCurrentDate != null) {
        pluralStringResource(R.plurals.export_progress_state_days_with_date, total, current, total, localizedCurrentDate)
    } else {
        pluralStringResource(R.plurals.export_progress_state_days, total, current, total)
    }
    val headline = when {
        isDone -> pluralStringResource(R.plurals.moment_done_days, total, total)
        isRaw -> stringResource(R.string.export_selected_range, localizedRangeStart, localizedRangeEnd)
        localizedCurrentDate != null -> stringResource(R.string.moment_writing, localizedCurrentDate)
        else -> stringResource(R.string.export_progress_title)
    }
    val counter = if (isRaw) {
        pluralStringResource(R.plurals.raw_snapshot_progress_actions, total, current, total)
    } else {
        pluralStringResource(R.plurals.export_progress_days_count, total, current, total)
    }
    val fraction = if (isDone) 1f else if (total > 0) (current.toFloat() / total).coerceIn(0f, 1f) else null
    val progressFraction by animateFloatAsState(
        targetValue = fraction ?: 0f,
        animationSpec = tween(GeistMotion.overlay),
        label = "momentProgress",
    )
    // Replay refills the finished heart facet by facet, as on iOS.
    var replays by remember { mutableIntStateOf(0) }
    val replay = remember { Animatable(1f) }
    LaunchedEffect(replays) {
        if (replays > 0) {
            replay.snapTo(0f)
            replay.animateTo(1f, tween(durationMillis = REPLAY_MILLIS, easing = LinearEasing))
        }
    }
    val animatedFraction = if (isDone && replays > 0) replay.value else progressFraction

    Dialog(
        onDismissRequest = { if (isDone) onClose() },
        properties = DialogProperties(
            dismissOnBackPress = isDone,
            dismissOnClickOutside = false,
            usePlatformDefaultWidth = false,
        ),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.background100)
                .safeDrawingPadding(),
        ) {
            Text(
                text = stringResource(R.string.export_now_title),
                style = MaterialTheme.typography.titleLarge,
                color = colors.primary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space6, vertical = GeistSpacing.space4),
            )
            Box(
                modifier = Modifier.weight(1f).fillMaxWidth().padding(horizontal = GeistSpacing.space6),
                contentAlignment = Alignment.Center,
            ) {
                val heartDescription = stringResource(R.string.moment_heart_description)
                CrystalHeart(
                    filledFraction = animatedFraction,
                    colors = colors,
                    modifier = Modifier
                        .widthIn(max = 320.dp)
                        .fillMaxWidth(0.75f)
                        .aspectRatio(160f / 150f)
                        .semantics { contentDescription = heartDescription },
                )
            }
            Column(
                modifier = Modifier
                    .dialogNavigationBarsPadding()
                    .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space6)
                    .widthIn(max = GeistSizes.readableContentMaxWidth)
                    .fillMaxWidth()
                    .align(Alignment.CenterHorizontally)
                    .clip(RoundedCornerShape(GeistRadii.large))
                    .background(colors.gray.c200)
                    .padding(GeistSpacing.space6)
                    .semantics {
                        liveRegion = LiveRegionMode.Polite
                        stateDescription = progressStateDescription
                    },
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                    Text(
                        text = headline,
                        style = MaterialTheme.typography.headlineSmall,
                        color = colors.primary,
                        modifier = Modifier.weight(1f),
                    )
                    Text(text = counter, style = GeistType.copy14Mono, color = colors.secondary)
                }
                val barModifier = Modifier
                    .fillMaxWidth()
                    .height(GeistSpacing.space2)
                    .clip(RoundedCornerShape(GeistRadii.full))
                if (fraction != null) {
                    LinearProgressIndicator(
                        progress = { animatedFraction },
                        modifier = barModifier,
                        color = colors.brandPrimary,
                        trackColor = colors.secondaryContainer,
                    )
                } else {
                    LinearProgressIndicator(
                        modifier = barModifier,
                        color = colors.brandPrimary,
                        trackColor = colors.secondaryContainer,
                    )
                }
                Text(
                    text = if (isDone) {
                        doneSubtitle ?: progressStateDescription
                    } else {
                        progressStateDescription + " " + stringResource(R.string.moment_keep_open)
                    },
                    style = MaterialTheme.typography.bodyMedium,
                    color = colors.secondary,
                )
                if (isDone) {
                    Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                        if (onSeeInArchive != null) {
                            Button(
                                onClick = onSeeInArchive,
                                modifier = Modifier.weight(1f).heightIn(min = GeistSizes.controlLarge),
                                shape = RoundedCornerShape(GeistRadii.full),
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = colors.brandPrimary,
                                    contentColor = colors.brandOnPrimary,
                                ),
                            ) { Text(stringResource(R.string.moment_see_in_archive), style = GeistType.button14) }
                        }
                        FilledTonalButton(
                            onClick = { replays++ },
                            modifier = Modifier.heightIn(min = GeistSizes.controlLarge),
                            shape = RoundedCornerShape(GeistRadii.full),
                            colors = ButtonDefaults.filledTonalButtonColors(
                                containerColor = colors.secondaryContainer,
                                contentColor = colors.onSecondaryContainer,
                            ),
                        ) { Text(stringResource(R.string.moment_replay), style = GeistType.button14) }
                        FilledTonalButton(
                            onClick = onClose,
                            modifier = Modifier.then(if (onSeeInArchive == null) Modifier.weight(1f) else Modifier)
                                .heightIn(min = GeistSizes.controlLarge),
                            shape = RoundedCornerShape(GeistRadii.full),
                            colors = ButtonDefaults.filledTonalButtonColors(
                                containerColor = colors.secondaryContainer,
                                contentColor = colors.onSecondaryContainer,
                            ),
                        ) { Text(stringResource(R.string.close), style = GeistType.button14) }
                    }
                } else {
                    OutlinedButton(
                        onClick = onCancel,
                        modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.controlLarge),
                        shape = RoundedCornerShape(GeistRadii.full),
                    ) {
                        Text(stringResource(R.string.action_cancel_export), style = GeistType.button14, color = colors.brandPrimary)
                    }
                }
            }
        }
    }
}

/** iOS refills ten facets 380 ms apart. */
private const val REPLAY_MILLIS = 3_800

/** Facets of the crystal heart in the design's 160×150 box (origin 40,4), in fill order. */
private val HEART_FACETS: List<List<Offset>> = listOf(
    listOf(Offset(45f, 55f), Offset(60f, 20f), Offset(95f, 55f)),
    listOf(Offset(60f, 20f), Offset(95f, 8f), Offset(95f, 55f)),
    listOf(Offset(95f, 8f), Offset(120f, 30f), Offset(95f, 55f)),
    listOf(Offset(95f, 55f), Offset(120f, 30f), Offset(145f, 55f)),
    listOf(Offset(120f, 30f), Offset(145f, 8f), Offset(145f, 55f)),
    listOf(Offset(145f, 8f), Offset(180f, 20f), Offset(145f, 55f)),
    listOf(Offset(180f, 20f), Offset(195f, 55f), Offset(145f, 55f)),
    listOf(Offset(45f, 55f), Offset(95f, 55f), Offset(120f, 150f)),
    listOf(Offset(95f, 55f), Offset(145f, 55f), Offset(120f, 150f)),
    listOf(Offset(145f, 55f), Offset(195f, 55f), Offset(120f, 150f)),
)

/**
 * Tonal step of each facet between the brand color (0) and its on-subtle (+) or subtle (−)
 * role, so the facets read as cut glass from existing tokens only.
 */
private val FACET_TONES = listOf(0.2f, -0.35f, -0.7f, 0.05f, -0.8f, -0.9f, -0.5f, 0.55f, 0.3f, 0.75f)

/** Number of filled facets for an export progress fraction; full only when the export is. */
internal fun heartFilledFacets(fraction: Float, facetCount: Int = HEART_FACETS.size): Int =
    (fraction.coerceIn(0f, 1f) * facetCount).toInt().coerceIn(0, facetCount)

@Composable
private fun CrystalHeart(filledFraction: Float, colors: GeistColors, modifier: Modifier = Modifier) {
    val filled = heartFilledFacets(filledFraction)
    val edge = colors.primary.copy(alpha = 0.4f)
    val empty = colors.primary.copy(alpha = 0.06f)
    Canvas(modifier) {
        val scale = minOf(size.width / 160f, size.height / 150f)
        fun map(p: Offset) = Offset((p.x - 40f) * scale, (p.y - 4f) * scale)
        HEART_FACETS.forEachIndexed { index, facet ->
            val path = Path().apply {
                val first = map(facet.first())
                moveTo(first.x, first.y)
                facet.drop(1).forEach { val point = map(it); lineTo(point.x, point.y) }
                close()
            }
            val tone = FACET_TONES[index]
            val fill = when {
                index >= filled -> empty
                tone >= 0f -> lerp(colors.brandPrimary, colors.brandOnSubtle, tone).copy(alpha = 0.92f)
                else -> lerp(colors.brandPrimary, colors.brandSubtle, -tone).copy(alpha = 0.92f)
            }
            drawPath(path, fill)
            drawPath(path, edge, style = Stroke(width = 0.8f * scale, join = StrokeJoin.Round))
        }
    }
}
