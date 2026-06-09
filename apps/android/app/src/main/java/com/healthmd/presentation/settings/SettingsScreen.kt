package com.healthmd.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    onNavigateToPaywall: () -> Unit = {},
) {
    val isPurchased by viewModel.isPurchased.collectAsStateWithLifecycle()

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
            text = stringResource(R.string.settings_title),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            letterSpacing = 2.sp,
            lineHeight = 36.sp,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
        )
        Text(
            text = stringResource(R.string.settings_subtitle),
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
        )

        // Premium upgrade (show at top for free users)
        if (!isPurchased) {
            GlassCardClickable(onClick = onNavigateToPaywall) {
                Icon(
                    Icons.Outlined.WorkspacePremium,
                    contentDescription = null,
                    tint = AppColors.accent,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.settings_upgrade_title),
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        stringResource(R.string.settings_upgrade_subtitle),
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
        }

        Spacer(modifier = Modifier.height(Spacing.sm))


        // Feedback
        val context = LocalContext.current
        GlassCard {
            SectionLabel(stringResource(R.string.section_feedback))

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
                        stringResource(R.string.feedback_send_title),
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        stringResource(R.string.feedback_send_subtitle),
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

            GlassCardClickable(onClick = { FeedbackHelper.openDiscordCommunity(context) }) {
                Icon(
                    Icons.Outlined.Groups,
                    contentDescription = null,
                    tint = AppColors.accent,
                    modifier = Modifier.size(24.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        stringResource(R.string.feedback_discord_title),
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        stringResource(R.string.feedback_discord_subtitle),
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
                        stringResource(R.string.feedback_github_title),
                        style = MaterialTheme.typography.bodyLarge,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium,
                    )
                    Text(
                        stringResource(R.string.feedback_github_subtitle),
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

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}
