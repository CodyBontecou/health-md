package com.healthmd.presentation.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.export.ExportViewModel
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/** The device-folder destination: the current folder, changing it, and per-automation folders. */
@Composable
fun FolderDestinationScreen(
    exportViewModel: ExportViewModel = hiltViewModel(),
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
) {
    val export by exportViewModel.uiState.collectAsStateWithLifecycle()
    val profiles by profilesViewModel.uiState.collectAsStateWithLifecycle()
    val colors = LocalGeistColors.current
    val protection = LocalConfigurationProtection.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri?.let(exportViewModel::onFolderSelected)
    }
    val folder = export.folderName?.takeIf { it.isNotBlank() }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(GeistSpacing.space4),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        GeistCard(padding = GeistSpacing.space4) {
            Text(stringResource(R.string.folder_destination_current), style = GeistType.label12, color = colors.secondary)
            Text(
                text = folder ?: stringResource(R.string.folder_destination_none),
                style = MaterialTheme.typography.titleMedium,
                color = if (folder == null) colors.coverageMissing else colors.primary,
                modifier = Modifier.padding(bottom = GeistSpacing.space4),
            )
            PrimaryButton(
                text = stringResource(if (folder == null) R.string.folder_destination_choose else R.string.folder_destination_change),
                onClick = { if (protection.enabled) protection.onBlockedChange() else picker.launch(null) },
            )
        }
        Text(
            text = stringResource(R.string.folder_destination_body),
            style = MaterialTheme.typography.bodyMedium,
            color = colors.secondary,
            modifier = Modifier.padding(horizontal = GeistSpacing.space1),
        )
        val bound = profiles.rows.filter {
            it.profile.target == ExportTarget.DEVICE_FOLDER && !it.profile.folderDisplayName.isNullOrBlank()
        }
        if (bound.isNotEmpty()) {
            SectionLabel(stringResource(R.string.folder_destination_profiles), modifier = Modifier.padding(top = GeistSpacing.space3))
            GeistCard(padding = GeistSpacing.space4) {
                bound.forEach { row ->
                    Column(Modifier.padding(vertical = GeistSpacing.space2)) {
                        Text(row.profile.name, style = GeistType.heading14, color = colors.primary)
                        Text(row.profile.folderDisplayName.orEmpty(), style = GeistType.label14Mono, color = colors.secondary)
                    }
                }
            }
        }
    }
}
