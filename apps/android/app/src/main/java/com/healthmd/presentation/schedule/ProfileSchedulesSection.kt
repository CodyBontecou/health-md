package com.healthmd.presentation.schedule

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.presentation.common.ConfigurationProtectedRegion
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.Spacing
import java.time.LocalTime
import java.time.format.DateTimeFormatter
import java.util.Locale

/** Profile management only; scheduling, defaults, and persistence remain in the ViewModel. */
@Composable
fun ProfileSchedulesSection(
    viewModel: ProfileSchedulesViewModel,
    modifier: Modifier = Modifier,
) {
    val uiState by viewModel.uiState.collectAsState()
    ProfileSchedulesContent(
        uiState = uiState,
        onToggle = viewModel::setEnabled,
        onOpenEditor = viewModel::openEditor,
        onDeleteProfile = viewModel::deleteProfile,
        onAddProfile = viewModel::addProfileFromCurrentSettings,
        onSaveEntry = viewModel::saveEntry,
        modifier = modifier,
    )
}

/** Production callback seam: tests exercise the same protection wrappers as the live section. */
@Composable
internal fun ProfileSchedulesContent(
    uiState: ProfileSchedulesUiState,
    onToggle: (String, Boolean) -> Unit,
    onOpenEditor: (String?) -> Unit,
    onDeleteProfile: (String) -> Unit,
    onAddProfile: () -> Unit,
    onSaveEntry: (ScheduledProfileEntry) -> Unit,
    modifier: Modifier = Modifier,
) {
    val protection = LocalConfigurationProtection.current
    var pendingDeleteProfile by remember { mutableStateOf<ProfileScheduleRow?>(null) }

    ConfigurationProtectedRegion(modifier = modifier.fillMaxWidth()) {
        Card(
            modifier = Modifier.fillMaxWidth(),
            colors = CardDefaults.cardColors(containerColor = AppColors.bgSecondary),
        ) {
            Column(
                modifier = Modifier.padding(Spacing.md),
                verticalArrangement = Arrangement.spacedBy(Spacing.md),
            ) {
                Text(
                    stringResource(R.string.a11y_profiles_title),
                    style = MaterialTheme.typography.titleMedium, color = AppColors.textPrimary,
                )
                uiState.rows.forEach { row ->
                    ProfileScheduleRowContent(
                        row = row,
                        onToggle = { enabled -> onToggle(row.profile.id, enabled) },
                        onOpenEditor = { onOpenEditor(row.profile.id) },
                        onDelete = { pendingDeleteProfile = row },
                    )
                    HorizontalDivider(color = AppColors.borderDefault)
                }
                if (uiState.rows.isEmpty()) {
                    Text(
                        stringResource(R.string.a11y_profiles_empty),
                        style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary,
                    )
                }
                TextButton(
                    onClick = {
                        if (protection.enabled) protection.onBlockedChange() else onAddProfile()
                    },
                    modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
                        .testTag(ProfileScheduleTags.ADD),
                ) { Text(stringResource(R.string.a11y_profiles_add)) }
                if (uiState.rows.none { it.entry?.isEnabled == true }) {
                    Text(
                        stringResource(R.string.a11y_profiles_none_enabled),
                        style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary,
                    )
                }
            }
        }
    }

    // Separate windows bypass the protected region. Keep these guards live even when the
    // lock changes after opening a dialog; blocked confirms close exactly as before.
    pendingDeleteProfile?.let { row ->
        ProfileScheduleDeleteDialog(
            profileName = row.profile.name,
            onDismiss = { pendingDeleteProfile = null },
            onDelete = {
                if (protection.enabled) {
                    pendingDeleteProfile = null
                    protection.onBlockedChange()
                } else {
                    onDeleteProfile(row.profile.id)
                    pendingDeleteProfile = null
                }
            },
        )
    }
    uiState.editingProfileId?.let { profileId ->
        val row = uiState.rows.firstOrNull { it.profile.id == profileId } ?: return
        ProfileCadenceEditorDialog(
            profileId = row.profile.id,
            profileName = row.profile.name,
            entry = row.entry,
            onSave = { entry ->
                if (protection.enabled) {
                    onOpenEditor(null)
                    protection.onBlockedChange()
                } else {
                    onSaveEntry(entry)
                }
            },
            onDismiss = { onOpenEditor(null) },
        )
    }
}

internal fun cadenceSummary(entry: ScheduledProfileEntry?, refreshSummary: String? = null): String {
    if (entry == null || !entry.isEnabled) return "Not scheduled. Tap to configure."
    val time = LocalTime.of(entry.hour, entry.minute)
        .format(DateTimeFormatter.ofPattern("HH:mm", Locale.getDefault()))
    val base = when (entry.cadenceUnit) {
        ScheduledProfileCadenceUnit.DAY -> "Every ${entry.cadenceValue} day(s) at $time"
        ScheduledProfileCadenceUnit.WEEK -> {
            val weekday = java.time.DayOfWeek.of(entry.weekdayIso).name.lowercase().replaceFirstChar { it.uppercase() }
            "Every ${entry.cadenceValue} week(s) on $weekday at $time"
        }
        ScheduledProfileCadenceUnit.MONTH -> "Every ${entry.cadenceValue} month(s) at $time"
    }
    return if (entry.todayRefreshEnabled && refreshSummary != null) "$base · $refreshSummary" else base
}
