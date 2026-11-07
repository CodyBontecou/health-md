package com.healthmd.presentation.settings

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CreateNewFolder
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.export.ExportViewModel
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/**
 * The device-folder destination (iOS FolderDestG): the folder and subfolder, which automations
 * write there and when it was last written, and the automations that use a folder of their own.
 */
@Composable
fun FolderDestinationScreen(
    exportViewModel: ExportViewModel = hiltViewModel(),
    profilesViewModel: ExportProfilesViewModel = hiltViewModel(),
    destinations: SettingsDestinationsViewModel = hiltViewModel(),
) {
    val export by exportViewModel.uiState.collectAsStateWithLifecycle()
    val profiles by profilesViewModel.uiState.collectAsStateWithLifecycle()
    val history by destinations.history.collectAsStateWithLifecycle()
    val colors = LocalGeistColors.current
    val protection = LocalConfigurationProtection.current
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
        uri?.let(exportViewModel::onFolderSelected)
    }
    var editingSubfolder by remember { mutableStateOf(false) }
    val guarded: (() -> Unit) -> Unit = { action -> if (protection.enabled) protection.onBlockedChange() else action() }
    val folder = export.folderName?.takeIf { it.isNotBlank() }
    val folderProfiles = profiles.rows.filter { it.profile.target == ExportTarget.DEVICE_FOLDER }
    val defaultUsers = folderProfiles.filter { it.profile.folderUri == null }.map { it.profile.name }
    val ownFolders = folderProfiles.filter { !it.profile.folderDisplayName.isNullOrBlank() && it.profile.folderUri != null }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GeistSpacing.space4)
            .padding(bottom = GeistSpacing.space8)
            .testTag("settings.folderDestination"),
    ) {
        SettingsGroup(
            title = stringResource(R.string.folder_page_folder),
            rows = listOf(
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.folder_page_folder),
                        icon = Icons.Outlined.Folder,
                        trailing = folder ?: stringResource(R.string.folder_page_none),
                        onClick = { guarded { picker.launch(null) } },
                        modifier = Modifier.testTag("settings.folderDestination.choose"),
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.folder_page_subfolder),
                        icon = Icons.Outlined.CreateNewFolder,
                        trailing = export.settings.subfolder,
                        onClick = { guarded { editingSubfolder = true } },
                        modifier = Modifier.testTag("settings.folderDestination.subfolder"),
                    )
                },
            ),
        )

        if (folder != null) {
            SettingsGroup(
                title = stringResource(R.string.folder_page_activity),
                rows = listOf<@Composable (Shape) -> Unit>(
                    { shape ->
                        SettingsValueRow(
                            shape = shape,
                            title = stringResource(R.string.folder_page_used_by),
                            value = defaultUsers.takeIf { it.isNotEmpty() }?.joinToString(", ")
                                ?: stringResource(R.string.folder_page_no_automations),
                        )
                    },
                    { shape ->
                        SettingsValueRow(
                            shape = shape,
                            title = stringResource(R.string.folder_page_last_write),
                            value = SettingsDestinationActivity.lastSuccess(ExportTarget.DEVICE_FOLDER, history)
                                ?.let { settingsTimestampText(it) }
                                ?: stringResource(R.string.settings_none_yet),
                        )
                    },
                ),
            )
        }

        if (ownFolders.isNotEmpty()) {
            SettingsGroup(
                title = stringResource(R.string.folder_destination_profiles),
                rows = ownFolders.map<_, @Composable (Shape) -> Unit> { row ->
                    { shape ->
                        SettingsRow(
                            shape = shape,
                            title = row.profile.name,
                            subtitle = row.profile.folderDisplayName,
                            icon = Icons.Outlined.FolderOpen,
                            onClick = null,
                        )
                    }
                },
            )
        }

        Text(
            text = stringResource(R.string.folder_destination_body),
            style = GeistType.copy13,
            color = colors.secondary,
            modifier = Modifier.padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space4),
        )
    }

    if (editingSubfolder) {
        SettingsTextFieldDialog(
            title = stringResource(R.string.folder_page_subfolder),
            initialValue = export.settings.subfolder,
            onSave = { value ->
                editingSubfolder = false
                guarded { exportViewModel.updateSubfolder(value) }
            },
            onDismiss = { editingSubfolder = false },
        )
    }
}
