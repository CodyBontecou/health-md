package com.healthmd.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.presentation.common.SubScreen
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import androidx.compose.foundation.shape.RoundedCornerShape

@Composable
fun DailyNoteInjectionScreen(
    settings: DailyNoteInjectionSettings,
    onSettingsChanged: (DailyNoteInjectionSettings) -> Unit,
    onBack: () -> Unit,
) {
    val colors = LocalGeistColors.current
    SubScreen(title = stringResource(R.string.section_daily_note_injection), onBack = onBack) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .imePadding()
                .verticalScroll(rememberScrollState())
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space8),
        ) {
            Text(
                stringResource(R.string.daily_note_description),
                style = GeistType.copy14,
                color = colors.secondary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
            )

            Spacer(Modifier.height(GeistSpacing.space2))
            SettingsToggleRow(
                shape = RoundedCornerShape(GeistRadii.listGroup),
                title = stringResource(R.string.daily_note_enable_title),
                subtitle = stringResource(R.string.daily_note_enable_subtitle),
                checked = settings.enabled,
                onCheckedChange = { onSettingsChanged(settings.copy(enabled = it)) },
            )

            if (settings.enabled) {
                SettingsGroupHeading(stringResource(R.string.section_file_organization))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    SettingsFieldRow(shape = groupRowShape(0, 3)) {
                        // Labels wrap outside the editing field, leaving its width for input.
                        Text(stringResource(R.string.section_daily_notes_folder), style = GeistType.label16, color = colors.primary)
                        OutlinedTextField(
                            value = settings.folderPath,
                            onValueChange = { onSettingsChanged(settings.copy(folderPath = it)) },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = GeistType.copy14Mono,
                            placeholder = { Text(stringResource(R.string.daily_notes_folder_hint), style = GeistType.copy14Mono) },
                            colors = settingsTextFieldColors(),
                            shape = settingsTextFieldShape,
                            singleLine = true,
                        )
                        Text(stringResource(R.string.daily_notes_folder_help), style = GeistType.copy14, color = colors.secondary)
                    }
                    SettingsFieldRow(shape = groupRowShape(1, 3)) {
                        Text(stringResource(R.string.section_filename_pattern), style = GeistType.label16, color = colors.primary)
                        OutlinedTextField(
                            value = settings.filenamePattern,
                            onValueChange = { onSettingsChanged(settings.copy(filenamePattern = it)) },
                            modifier = Modifier.fillMaxWidth(),
                            textStyle = GeistType.copy14Mono,
                            placeholder = { Text(stringResource(R.string.filename_template_hint), style = GeistType.copy14Mono) },
                            colors = settingsTextFieldColors(),
                            shape = settingsTextFieldShape,
                            singleLine = true,
                        )
                        Text(stringResource(R.string.filename_template_tokens), style = GeistType.copy14, color = colors.secondary)
                    }
                    SettingsFieldRow(shape = groupRowShape(2, 3)) {
                        Text(stringResource(R.string.section_preview_path), style = GeistType.label16, color = colors.primary)
                        // The full path wraps so long folders stay readable.
                        Text(settings.previewPath(), style = GeistType.copy14Mono, color = colors.brandPrimary)
                    }
                }

                SettingsGroup(
                    title = stringResource(R.string.section_options),
                    rows = listOf(
                        { shape ->
                            SettingsToggleRow(
                                shape = shape,
                                title = stringResource(R.string.inject_markdown_sections_title),
                                subtitle = stringResource(R.string.inject_markdown_sections_subtitle),
                                checked = settings.injectMarkdownSections,
                                onCheckedChange = { onSettingsChanged(settings.copy(injectMarkdownSections = it)) },
                            )
                        },
                        { shape ->
                            SettingsToggleRow(
                                shape = shape,
                                title = stringResource(R.string.create_note_if_missing_title),
                                subtitle = stringResource(R.string.create_note_if_missing_subtitle),
                                checked = settings.createIfMissing,
                                onCheckedChange = { onSettingsChanged(settings.copy(createIfMissing = it)) },
                            )
                        },
                    ),
                )
            }
        }
    }
}
