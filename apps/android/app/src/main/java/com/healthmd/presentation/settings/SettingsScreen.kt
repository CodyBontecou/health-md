package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.outlined.Email
import androidx.compose.material.icons.outlined.BugReport
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.domain.model.*
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.platform.LocalContext

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    onNavigateToAdvancedSettings: () -> Unit = {},
) {
    val settings by viewModel.settings.collectAsStateWithLifecycle()

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Spacer(modifier = Modifier.height(Spacing.sm))

        // Settings icon header
        GlassIconCircle(size = 84.dp) {
            Icon(
                Icons.Outlined.Settings,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(40.dp),
            )
        }

        Text(
            text = "CONFIGURE\nYOUR APP",
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            letterSpacing = 2.sp,
            lineHeight = 36.sp,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        Text(
            text = "Customize export format and data types",
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Export Format
        GlassCard {
            SectionLabel("Export Format")
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                ExportFormat.entries.forEach { format ->
                    val selected = settings.exportFormat == format
                    val shape = RoundedCornerShape(100.dp)
                    Box(
                        modifier = Modifier
                            .weight(1f)
                            .clip(shape)
                            .background(if (selected) AppColors.accent.copy(alpha = 0.15f) else AppColors.bgSecondary)
                            .border(
                                1.dp,
                                if (selected) AppColors.accent.copy(alpha = 0.5f) else AppColors.glassBorder,
                                shape,
                            )
                            .clickable { viewModel.updateFormat(format) }
                            .padding(horizontal = 8.dp, vertical = 10.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            format.displayName,
                            color = if (selected) AppColors.accent else AppColors.textSecondary,
                            style = MaterialTheme.typography.labelSmall,
                            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            maxLines = 1,
                        )
                    }
                }
            }
        }

        // Write Mode
        GlassCard {
            SectionLabel("Write Mode")
            WriteMode.entries.forEach { mode ->
                val selected = settings.writeMode == mode
                val shape = RoundedCornerShape(12.dp)
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(shape)
                        .background(if (selected) AppColors.accent.copy(alpha = 0.08f) else Color.Transparent)
                        .clickable { viewModel.updateWriteMode(mode) }
                        .padding(Spacing.sm),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    RadioButton(
                        selected = selected,
                        onClick = { viewModel.updateWriteMode(mode) },
                        colors = RadioButtonDefaults.colors(
                            selectedColor = AppColors.accent,
                            unselectedColor = AppColors.textMuted,
                        ),
                    )
                    Column(modifier = Modifier.padding(start = Spacing.xs)) {
                        Text(mode.displayName, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
                        Text(mode.description, color = AppColors.textMuted, style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }

        // Filename Template
        GlassCard {
            SectionLabel("Filename Template")
            OutlinedTextField(
                value = settings.filenameFormat,
                onValueChange = { viewModel.updateFilenameFormat(it) },
                modifier = Modifier.fillMaxWidth(),
                placeholder = { Text("{date}", color = AppColors.textMuted) },
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = AppColors.accent,
                    unfocusedBorderColor = AppColors.borderDefault,
                    focusedTextColor = AppColors.textPrimary,
                    unfocusedTextColor = AppColors.textPrimary,
                    cursorColor = AppColors.accent,
                ),
                shape = RoundedCornerShape(12.dp),
                singleLine = true,
            )
            Spacer(modifier = Modifier.height(Spacing.xs))
            Text(
                "{date}, {year}, {month}, {day}, {weekday}, {monthName}, {quarter}",
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
            )
        }

        // Format options
        GlassCard {
            SectionLabel("Format Options")

            SettingsToggleRow("Include Frontmatter", settings.includeMetadata) { viewModel.updateIncludeMetadata(it) }
            SettingsToggleRow("Group by Category", settings.groupByCategory) { viewModel.updateGroupByCategory(it) }
            SettingsToggleRow("Emoji in Headers", settings.formatCustomization.markdownTemplate.useEmoji) { viewModel.updateUseEmoji(it) }

            Spacer(modifier = Modifier.height(Spacing.sm))
            Text("Units", style = MaterialTheme.typography.labelLarge, color = AppColors.textSecondary)
            Spacer(modifier = Modifier.height(Spacing.xs))
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                UnitPreference.entries.forEach { pref ->
                    val selected = settings.formatCustomization.unitPreference == pref
                    val shape = RoundedCornerShape(100.dp)
                    Box(
                        modifier = Modifier
                            .clip(shape)
                            .background(if (selected) AppColors.accent.copy(alpha = 0.15f) else AppColors.bgSecondary)
                            .border(
                                1.dp,
                                if (selected) AppColors.accent.copy(alpha = 0.5f) else AppColors.glassBorder,
                                shape,
                            )
                            .clickable { viewModel.updateUnitPreference(pref) }
                            .padding(horizontal = 16.dp, vertical = 10.dp),
                    ) {
                        Text(
                            pref.displayName,
                            color = if (selected) AppColors.accent else AppColors.textSecondary,
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
        }

        // Advanced Settings Navigation
        GlassCardClickable(onClick = onNavigateToAdvancedSettings) {
            Icon(
                Icons.Outlined.Tune,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(24.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    "Advanced Export Settings",
                    style = MaterialTheme.typography.bodyLarge,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    "Metrics, daily notes, individual tracking, format customization",
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
            Icon(
                Icons.Outlined.ChevronRight,
                contentDescription = null,
                tint = AppColors.textMuted,
            )
        }

        // Feedback
        val context = LocalContext.current
        GlassCard {
            SectionLabel("Feedback")

            GlassCardClickable(onClick = { FeedbackHelper.sendFeedbackEmail(context) }) {
                Icon(
                    Icons.Outlined.Email,
                    contentDescription = null,
                    tint = AppColors.accent,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        "Send Feedback",
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        "Opens your email client",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
                Icon(
                    Icons.Outlined.ArrowOutward,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                    modifier = Modifier.size(16.dp),
                )
            }

            Spacer(modifier = Modifier.height(Spacing.xs))

            GlassCardClickable(onClick = { FeedbackHelper.openGitHubIssue(context) }) {
                Icon(
                    Icons.Outlined.BugReport,
                    contentDescription = null,
                    tint = AppColors.accent,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        "Report a Bug on GitHub",
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        "Opens a pre-filled issue template",
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
                Icon(
                    Icons.Outlined.ArrowOutward,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                    modifier = Modifier.size(16.dp),
                )
            }
        }

        // Reset
        SecondaryButton(
            text = "Reset to Defaults",
            onClick = { viewModel.resetSettings() },
        )

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

@Composable
private fun SettingsToggleRow(
    label: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = Spacing.xs),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(label, color = AppColors.textPrimary, style = MaterialTheme.typography.bodyLarge)
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color.White,
                checkedTrackColor = AppColors.accent,
                uncheckedThumbColor = AppColors.textMuted,
                uncheckedTrackColor = AppColors.bgSecondary,
                uncheckedBorderColor = AppColors.borderDefault,
            ),
        )
    }
}
