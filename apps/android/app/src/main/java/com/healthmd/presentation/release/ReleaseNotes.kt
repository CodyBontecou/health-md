package com.healthmd.presentation.release

import android.content.Context
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.core.content.pm.PackageInfoCompat
import com.healthmd.R
import com.healthmd.presentation.theme.AppColors

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
                highlights = listOf(
                    context.getString(R.string.release_notes_highlight_export_parity),
                    context.getString(R.string.release_notes_highlight_templates),
                    context.getString(R.string.release_notes_highlight_workouts),
                    context.getString(R.string.release_notes_highlight_accessibility),
                ),
            )
        }
    }
}

@Composable
fun ReleaseNotesDialog(
    notes: AndroidReleaseNotes,
    onDismiss: () -> Unit,
    onOpenSettings: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = AppColors.bgTertiary,
        title = {
            Text(
                text = stringResource(R.string.release_notes_title, notes.versionName),
                color = AppColors.textPrimary,
                fontWeight = FontWeight.SemiBold,
            )
        },
        text = {
            Column {
                notes.highlights.forEach { highlight ->
                    Text(
                        text = "• $highlight",
                        color = AppColors.textSecondary,
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(vertical = 3.dp),
                    )
                }
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = stringResource(R.string.release_notes_settings_hint),
                    color = AppColors.textMuted,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        },
        confirmButton = {
            TextButton(onClick = onOpenSettings) {
                Text(stringResource(R.string.release_notes_open_settings), color = AppColors.accent)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text(stringResource(R.string.release_notes_got_it), color = Color.White)
            }
        },
    )
}
