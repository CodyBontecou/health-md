package com.healthmd.presentation.release

import android.content.Context
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Schedule
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.content.pm.PackageInfoCompat
import com.healthmd.BuildConfig
import com.healthmd.R
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import kotlinx.coroutines.launch

object ReleaseNotesGate {
    fun shouldPresent(
        currentVersionKey: String?,
        lastPresentedVersionKey: String?,
        hasCompletedSetup: Boolean,
        suppressForAutomationOrDebug: Boolean,
    ): Boolean = !currentVersionKey.isNullOrBlank() &&
            hasCompletedSetup &&
            !suppressForAutomationOrDebug &&
            currentVersionKey != lastPresentedVersionKey
}

data class AndroidReleaseNotes(
    val versionName: String,
    val versionKey: String,
    val highlights: List<String>,
) {
    companion object {
        fun current(context: Context): AndroidReleaseNotes? {
            val packageInfo = runCatching {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(context.packageName, 0)
            }.getOrNull() ?: return null
            val versionName = packageInfo.versionName ?: return null
            val versionCode = PackageInfoCompat.getLongVersionCode(packageInfo)
            return AndroidReleaseNotes(
                versionName = versionName,
                versionKey = "$versionName+$versionCode",
                highlights = (if (BuildConfig.FLAVOR == "play") listOf(
                    context.getString(R.string.paywall_plan_choices),
                    context.getString(R.string.paywall_subscription_disclosure),
                ) else emptyList()) + listOf(
                    context.getString(R.string.release_notes_highlight_widgets),
                    context.getString(R.string.release_notes_highlight_feedback),
                    context.getString(R.string.release_notes_highlight_export_parity),
                    context.getString(R.string.release_notes_highlight_templates),
                    context.getString(R.string.release_notes_highlight_workouts),
                ),
            )
        }
    }
}

/**
 * iOS `GlassWhatsNewScreen`: the running version's notes as a sheet, shown once per version,
 * closed by Continue or a drag.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun WhatsNewSheet(
    notes: AndroidReleaseNotes,
    onContinue: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val scope = rememberCoroutineScope()
    val tiles = listOf(colors.brandPrimary, colors.blue.c900, colors.gray.c1000)
    val icons = listOf(Icons.Outlined.AutoAwesome, Icons.Outlined.Schedule, Icons.Outlined.Description)
    ModalBottomSheet(
        onDismissRequest = onContinue,
        sheetState = sheetState,
        containerColor = colors.background100,
    ) {
        Column(Modifier.fillMaxWidth().navigationBarsPadding()) {
            Column(
                modifier = Modifier
                    .weight(1f, fill = false)
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = GeistSpacing.space4),
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space6),
            ) {
                Column(
                    modifier = Modifier.fillMaxWidth().padding(top = GeistSpacing.space2),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                ) {
                    Icon(Icons.Filled.Favorite, contentDescription = null, tint = colors.brandPrimary, modifier = Modifier.size(56.dp))
                    Text(
                        text = stringResource(R.string.whats_new_title),
                        style = MaterialTheme.typography.headlineSmall,
                        fontWeight = FontWeight.Bold,
                        color = colors.primary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.semantics { heading() },
                    )
                    Text(
                        text = stringResource(R.string.whats_new_version, notes.versionName),
                        style = MaterialTheme.typography.bodyMedium,
                        color = colors.secondary,
                    )
                }
                GeistCard(padding = GeistSpacing.space4) {
                    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4)) {
                        notes.highlights.forEachIndexed { index, highlight ->
                            Row(
                                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
                                modifier = Modifier.semantics(mergeDescendants = true) {},
                            ) {
                                Box(
                                    modifier = Modifier
                                        .size(32.dp)
                                        .background(tiles[index % tiles.size], RoundedCornerShape(GeistRadii.small)),
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(
                                        icons[index % icons.size],
                                        contentDescription = null,
                                        tint = colors.background100,
                                        modifier = Modifier.size(18.dp),
                                    )
                                }
                                Text(
                                    text = highlight,
                                    style = MaterialTheme.typography.bodyMedium,
                                    color = colors.primary,
                                    modifier = Modifier.weight(1f),
                                )
                            }
                        }
                    }
                }
            }
            Button(
                onClick = { scope.launch { sheetState.hide() }.invokeOnCompletion { onContinue() } },
                shape = CircleShape,
                colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3)
                    .heightIn(min = 56.dp),
            ) { Text(stringResource(R.string.whats_new_continue), style = GeistType.button16) }
        }
    }
}
