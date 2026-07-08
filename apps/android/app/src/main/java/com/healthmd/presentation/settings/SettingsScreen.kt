package com.healthmd.presentation.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.health.providers.HealthProviderDirectExportStatus
import com.healthmd.data.health.providers.HealthProviderId
import com.healthmd.data.health.providers.HealthProviderState
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    onNavigateToPaywall: () -> Unit = {},
) {
    val isPurchased by viewModel.isPurchased.collectAsStateWithLifecycle()
    val healthProviderStates by viewModel.healthProviderStates.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        viewModel.refreshHealthProviders()
    }

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

        HealthProviderSupportSection(
            providers = healthProviderStates,
            onOpenProvider = { providerState ->
                coroutineScope.launch {
                    val provider = providerState.provider
                    val providerId = provider.definition.id
                    if (providerState.isConnected || provider.definition.directExportStatus == HealthProviderDirectExportStatus.Available) {
                        viewModel.selectHealthProvider(providerId)
                        if (providerState.isConnected) return@launch
                    }
                    val oauthIntent = if (!providerState.isConnected && providerState.isOAuthConfigured) {
                        viewModel.getHealthProviderConnectionIntent(providerId)
                    } else {
                        null
                    }
                    openProviderSetup(context, provider, oauthIntent)
                }
            },
        )

        HealthDiagnosticsSection(
            onShareDiagnostics = {
                coroutineScope.launch {
                    shareRedactedDiagnostics(
                        context = context,
                        reportText = viewModel.buildRedactedDiagnosticsShareText(),
                    )
                }
            },
        )

        // Feedback
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

@Composable
private fun HealthProviderSupportSection(
    providers: List<HealthProviderUiState>,
    onOpenProvider: (HealthProviderUiState) -> Unit,
) {
    GlassCard {
        SectionLabel(stringResource(R.string.section_health_sources))

        Text(
            text = stringResource(R.string.health_sources_description),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textMuted,
            lineHeight = 18.sp,
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        providers.forEachIndexed { index, provider ->
            HealthProviderRow(providerState = provider, onClick = { onOpenProvider(provider) })
            if (index != providers.lastIndex) {
                Spacer(modifier = Modifier.height(Spacing.xs))
                HorizontalDivider(color = AppColors.glassBorder.copy(alpha = 0.45f))
                Spacer(modifier = Modifier.height(Spacing.xs))
            }
        }
    }
}

@Composable
private fun HealthDiagnosticsSection(
    onShareDiagnostics: () -> Unit,
) {
    GlassCard {
        SectionLabel(stringResource(R.string.section_health_diagnostics))

        Text(
            text = stringResource(R.string.health_diagnostics_description),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textMuted,
            lineHeight = 18.sp,
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        GlassCardClickable(onClick = onShareDiagnostics) {
            Icon(
                Icons.Outlined.Share,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(24.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.health_diagnostics_share_title),
                    style = MaterialTheme.typography.bodyLarge,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    stringResource(R.string.health_diagnostics_share_subtitle),
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
}

@Composable
private fun HealthProviderRow(
    providerState: HealthProviderUiState,
    onClick: () -> Unit,
) {
    val provider = providerState.provider
    val definition = provider.definition
    GlassCardClickable(
        onClick = onClick,
        padding = Spacing.sm,
    ) {
        Icon(
            imageVector = when (definition.id) {
                HealthProviderId.HEALTH_CONNECT -> Icons.Outlined.Favorite
                HealthProviderId.SAMSUNG_HEALTH,
                HealthProviderId.HUAWEI_HEALTH -> Icons.Outlined.PhoneAndroid
                else -> Icons.Outlined.Dataset
            },
            contentDescription = null,
            tint = if (providerState.isSelected || providerState.isConnected || provider.isInstalled || definition.directExportStatus == HealthProviderDirectExportStatus.Available) {
                AppColors.success
            } else {
                AppColors.accent
            },
            modifier = Modifier.size(24.dp),
        )
        Spacer(modifier = Modifier.width(Spacing.sm))
        Column(modifier = Modifier.weight(1f)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = definition.displayName,
                    style = MaterialTheme.typography.bodyLarge,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Text(
                    text = when {
                        providerState.isSelected -> stringResource(R.string.health_provider_status_selected)
                        providerState.isConnected -> stringResource(R.string.status_connected)
                        provider.isInstalled -> stringResource(R.string.health_provider_status_installed)
                        providerState.isOAuthConfigured -> stringResource(R.string.health_provider_status_ready_to_connect)
                        else -> definition.directExportStatus.label
                    },
                    style = MaterialTheme.typography.labelSmall,
                    color = if (providerState.isSelected || providerState.isConnected || provider.isInstalled) AppColors.success else AppColors.textMuted,
                    maxLines = 1,
                )
            }
            Text(
                text = definition.summary,
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
                maxLines = 2,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(modifier = Modifier.height(2.dp))
            Text(
                text = stringResource(
                    R.string.health_provider_integration_details,
                    definition.integrationKind.label,
                    definition.setupDescription,
                ),
                style = MaterialTheme.typography.labelSmall,
                color = AppColors.textSecondary,
                maxLines = 3,
                overflow = TextOverflow.Ellipsis,
            )
        }
        Spacer(modifier = Modifier.width(Spacing.xs))
        Icon(
            Icons.Outlined.ArrowOutward,
            contentDescription = null,
            tint = AppColors.textMuted,
            modifier = Modifier.size(16.dp),
        )
    }
}

private fun shareRedactedDiagnostics(
    context: Context,
    reportText: String,
) {
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.health_diagnostics_share_subject))
        putExtra(Intent.EXTRA_TEXT, reportText)
    }
    runCatching {
        context.startActivity(
            Intent.createChooser(
                sendIntent,
                context.getString(R.string.health_diagnostics_share_chooser),
            ).apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) }
        )
    }
}

private fun openProviderSetup(
    context: Context,
    provider: HealthProviderState,
    preferredIntent: Intent? = null,
) {
    val setupIntent = preferredIntent ?: provider.setupIntent
    if (setupIntent != null && runCatching { context.startActivity(setupIntent) }.isSuccess) {
        return
    }

    val fallbackUri = provider.definition.webSetupUri
        ?: provider.definition.setupPackageName?.let { "https://play.google.com/store/apps/details?id=$it" }
        ?: return

    runCatching {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(fallbackUri)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        )
    }
}
