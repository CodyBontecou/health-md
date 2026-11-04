package com.healthmd.presentation.export

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import kotlin.math.roundToInt

/** Drag distance past which releasing the handle closes the sheet. */
private val DISMISS_DRAG = 120.dp

/** Widest the sheet grows on tablets and unfolded foldables. */
private val SHEET_MAX_WIDTH = 640.dp

/**
 * Export now as a modal bottom sheet over the screen it was opened from: a scrim that closes it,
 * a drag handle, and the sheet content (the Export now form). Shown from a dialog destination so
 * the Archive stays visible behind it.
 */
@Composable
fun ExportNowSheet(onDismiss: () -> Unit, content: @Composable () -> Unit) {
    val colors = LocalGeistColors.current
    val density = LocalDensity.current
    var dragY by remember { mutableFloatStateOf(0f) }
    val shownY by animateFloatAsState(dragY, label = "sheetDrag")
    val dismissPx = with(density) { DISMISS_DRAG.toPx() }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val maxSheetHeight = maxHeight * 0.92f
        Box(
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.32f))
                .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, onClick = onDismiss),
        )
        Surface(
            modifier = Modifier
                .align(Alignment.BottomCenter)
                .statusBarsPadding()
                .widthIn(max = SHEET_MAX_WIDTH)
                .fillMaxWidth()
                .heightIn(max = maxSheetHeight)
                .offset { IntOffset(0, shownY.roundToInt()) },
            shape = RoundedCornerShape(topStart = GeistRadii.large, topEnd = GeistRadii.large),
            color = colors.background200,
        ) {
            Column(Modifier.navigationBarsPadding().imePadding()) {
                val handleLabel = stringResource(R.string.close)
                Box(
                    Modifier
                        .fillMaxWidth()
                        .height(GeistSpacing.space8 - GeistSpacing.space1)
                        .semantics { contentDescription = handleLabel }
                        .clickable(onClickLabel = handleLabel, onClick = onDismiss)
                        .draggable(
                            orientation = Orientation.Vertical,
                            state = rememberDraggableState { delta -> dragY = (dragY + delta).coerceAtLeast(0f) },
                            onDragStopped = { if (dragY > dismissPx) onDismiss() else dragY = 0f },
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier
                            .size(width = GeistSpacing.space8, height = GeistSpacing.space1)
                            .background(colors.secondary.copy(alpha = 0.4f), RoundedCornerShape(GeistRadii.full)),
                    )
                }
                Box(Modifier.weight(1f, fill = false)) { content() }
            }
        }
    }
}

/**
 * The sheet's Profile control: which automation's settings this export uses. Selecting one makes
 * it the active profile, the same action as Make active in Automations. Two to four profiles
 * read as segmented buttons; more scroll as chips.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ExportProfileSelector(viewModel: ExportProfilesViewModel = hiltViewModel()) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val rows = state.rows
    if (rows.size < 2) return
    val colors = LocalGeistColors.current
    val protection = LocalConfigurationProtection.current
    val select: (String) -> Unit = { id ->
        if (protection.enabled) protection.onBlockedChange() else viewModel.activate(id)
    }
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
        Text(stringResource(R.string.export_profile_label), style = GeistType.heading14, color = colors.brandPrimary)
        if (rows.size <= MAX_SEGMENTS) {
            SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                rows.forEachIndexed { index, row ->
                    SegmentedButton(
                        selected = row.isActive,
                        onClick = { if (!row.isActive) select(row.profile.id) },
                        shape = SegmentedButtonDefaults.itemShape(index, rows.size),
                        colors = SegmentedButtonDefaults.colors(
                            activeContainerColor = colors.secondaryContainer,
                            activeContentColor = colors.onSecondaryContainer,
                            inactiveContentColor = colors.primary,
                            activeBorderColor = colors.gray.c700,
                            inactiveBorderColor = colors.gray.c700,
                        ),
                    ) {
                        Text(row.profile.name, style = GeistType.button14, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    }
                }
            }
        } else {
            Row(
                Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()),
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            ) {
                rows.forEach { row ->
                    FilterChip(
                        selected = row.isActive,
                        onClick = { if (!row.isActive) select(row.profile.id) },
                        label = { Text(row.profile.name, style = GeistType.button14) },
                        shape = RoundedCornerShape(GeistRadii.small),
                        colors = FilterChipDefaults.filterChipColors(
                            selectedContainerColor = colors.secondaryContainer,
                            selectedLabelColor = colors.onSecondaryContainer,
                            labelColor = colors.secondary,
                        ),
                    )
                }
            }
        }
    }
}

/** Segmented buttons hold two to five options; four keeps profile names readable on phones. */
private const val MAX_SEGMENTS = 4
