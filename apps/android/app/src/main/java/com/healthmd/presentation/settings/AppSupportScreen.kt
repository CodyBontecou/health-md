package com.healthmd.presentation.settings

import android.content.Context
import android.content.Intent
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.BuildConfig
import com.healthmd.R
import com.healthmd.distribution.DistributionWearSettingsCard
import com.healthmd.domain.distribution.DistributionChannel
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.ConfigurationProtectionTestTags
import com.healthmd.presentation.common.FeedbackHelper
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.presentation.theme.Spacing
import com.healthmd.widget.setup.WidgetSettingsCard
import kotlinx.coroutines.launch

/**
 * App & support (iOS SettingsMoreG): the configuration lock, setup sharing and export history,
 * privacy, help, and the Android device and about sections. The lock's navigation request
 * scrolls here and is consumed, or the blocked-change toast would keep redirecting.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun AppSupportScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    destinations: SettingsDestinationsViewModel = hiltViewModel(),
    protectionSettingsRequestId: Long? = null,
    onNavigateToSharedSetup: () -> Unit = {},
    onNavigateToDiagnostics: () -> Unit = {},
    onNavigateToMyselfClaim: () -> Unit = {},
    onReplayOnboarding: () -> Unit = {},
) {
    val context = LocalContext.current
    val colors = LocalGeistColors.current
    val coroutineScope = rememberCoroutineScope()
    val protection = LocalConfigurationProtection.current
    val distributionPolicy = viewModel.distributionPolicy
    val protectionEnabled by viewModel.preventAccidentalChanges.collectAsStateWithLifecycle()
    val history by destinations.history.collectAsStateWithLifecycle()
    val protectionRequester = remember { BringIntoViewRequester() }
    var confirmingClear by remember { mutableStateOf(false) }
    var confirmingReplay by remember { mutableStateOf(false) }

    LaunchedEffect(protectionSettingsRequestId) {
        val requestId = protectionSettingsRequestId ?: return@LaunchedEffect
        protectionRequester.bringIntoView()
        viewModel.consumeProtectionSettingsRequest(requestId)
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md)
            .padding(bottom = Spacing.xl)
            .testTag("settings.appSupport.page"),
    ) {
        SettingsGroup(
            title = stringResource(R.string.app_support_safety),
            modifier = Modifier
                .bringIntoViewRequester(protectionRequester)
                .testTag(ConfigurationProtectionTestTags.SECTION),
            rows = listOf { shape ->
                // One whole-row switch target, the explanation below it at full width.
                SettingsRow(
                    shape = shape,
                    title = stringResource(R.string.settings_lock_configuration),
                    icon = Icons.Outlined.Lock,
                    onClick = null,
                    modifier = Modifier
                        .testTag(ConfigurationProtectionTestTags.TOGGLE)
                        .toggleable(
                            value = protectionEnabled == true,
                            enabled = protectionEnabled != null,
                            role = Role.Switch,
                            onValueChange = viewModel::setPreventAccidentalChanges,
                        ),
                    trailingContent = {
                        AppSwitch(checked = protectionEnabled == true, onCheckedChange = null, enabled = protectionEnabled != null)
                    },
                    below = {
                        Text(
                            stringResource(R.string.app_support_lock_subtitle),
                            style = GeistType.copy13,
                            color = colors.secondary,
                            modifier = Modifier.fillMaxWidth().padding(vertical = GeistSpacing.space1),
                        )
                    },
                )
            },
        )

        SettingsGroup(
            title = stringResource(R.string.app_support_configuration),
            rows = listOf(
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.shared_setup_title),
                        subtitle = stringResource(R.string.shared_setup_settings_detail),
                        icon = Icons.Outlined.Share,
                        onClick = onNavigateToSharedSetup,
                        modifier = Modifier.testTag("settings.sharedSetup"),
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.app_support_clear_history),
                        subtitle = stringResource(R.string.app_support_clear_history_subtitle),
                        icon = Icons.Outlined.History,
                        onClick = {
                            if (protection.enabled) protection.onBlockedChange() else confirmingClear = true
                        },
                        enabled = history.isNotEmpty(),
                        modifier = Modifier.testTag("schedule.history.clear"),
                    )
                },
            ),
        )

        val accountRows = buildList<@Composable (Shape) -> Unit> {
            add { shape ->
                SettingsRow(
                    shape = shape,
                    title = stringResource(R.string.app_support_privacy_policy),
                    subtitle = stringResource(R.string.settings_no_analytics),
                    icon = Icons.Outlined.PanTool,
                    onClick = { openExternalUrl(context, PRIVACY_POLICY_URL) },
                    external = true,
                )
            }
            if (BuildConfig.MYSELF_CLAIM_ENABLED && distributionPolicy.purchasesAvailable) {
                add { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.myself_claim_entry),
                        subtitle = stringResource(R.string.myself_claim_entry_subtitle),
                        icon = Icons.Outlined.WorkspacePremium,
                        onClick = onNavigateToMyselfClaim,
                        modifier = Modifier.testTag("settings_myself_claim"),
                    )
                }
            }
        }
        SettingsGroup(title = stringResource(R.string.app_support_account), rows = accountRows)

        SettingsGroup(
            title = stringResource(R.string.app_support_help),
            rows = listOf(
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.feedback_discord_title),
                        icon = Icons.Outlined.Groups,
                        onClick = { FeedbackHelper.openDiscordCommunity(context) },
                        external = true,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.feedback_send_title),
                        icon = Icons.Outlined.Email,
                        onClick = { FeedbackHelper.sendFeedbackEmail(context) },
                        external = true,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.app_support_report_bug),
                        icon = Icons.Outlined.BugReport,
                        trailing = "GitHub",
                        onClick = { FeedbackHelper.openGitHubIssue(context) },
                        external = true,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.diagnostics_title),
                        subtitle = stringResource(R.string.diagnostics_entry),
                        icon = Icons.Outlined.MonitorHeart,
                        onClick = onNavigateToDiagnostics,
                        modifier = Modifier.testTag("diagnostics.entry"),
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.health_diagnostics_share_title),
                        subtitle = stringResource(R.string.health_diagnostics_description),
                        icon = Icons.Outlined.IosShare,
                        onClick = {
                            coroutineScope.launch {
                                shareRedactedDiagnostics(context, viewModel.buildRedactedDiagnosticsShareText())
                            }
                        },
                        external = true,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.app_support_replay_onboarding),
                        icon = Icons.Outlined.Replay,
                        onClick = { confirmingReplay = true },
                        modifier = Modifier.testTag("settings.replayOnboarding"),
                    )
                },
            ),
        )

        // Android-only: home-screen widgets and the watch companion.
        Spacer(Modifier.height(GeistSpacing.space6))
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            WidgetSettingsCard()
            if (distributionPolicy.wearSyncAvailable) {
                DistributionWearSettingsCard()
            }
        }

        SettingsGroup(
            title = stringResource(R.string.section_about),
            rows = listOf(
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(
                            when (distributionPolicy.channel) {
                                DistributionChannel.GOOGLE_PLAY -> R.string.distribution_channel_play
                                DistributionChannel.FDROID -> R.string.distribution_channel_fdroid
                            },
                        ),
                        subtitle = stringResource(R.string.about_license_summary),
                        icon = Icons.Outlined.Info,
                        onClick = null,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.about_source_code),
                        icon = Icons.Outlined.Code,
                        onClick = { openExternalUrl(context, SOURCE_CODE_URL) },
                        external = true,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.about_license),
                        icon = Icons.Outlined.Gavel,
                        onClick = { openExternalUrl(context, LICENSE_URL) },
                        external = true,
                    )
                },
            ),
        )
    }

    if (confirmingClear) {
        SettingsConfirmDialog(
            title = stringResource(R.string.app_support_clear_history_confirm_title),
            message = stringResource(R.string.app_support_clear_history_subtitle),
            confirm = stringResource(R.string.action_clear_history),
            onConfirm = {
                confirmingClear = false
                if (protection.enabled) protection.onBlockedChange() else destinations.clearHistory()
            },
            onDismiss = { confirmingClear = false },
        )
    }
    if (confirmingReplay) {
        SettingsConfirmDialog(
            title = stringResource(R.string.app_support_replay_onboarding_title),
            message = stringResource(R.string.app_support_replay_onboarding_body),
            confirm = stringResource(R.string.app_support_replay_onboarding),
            onConfirm = {
                confirmingReplay = false
                onReplayOnboarding()
            },
            onDismiss = { confirmingReplay = false },
        )
    }
}

/** A Geist confirmation dialog: title, explanation, a confirm action and Cancel. */
@Composable
internal fun SettingsConfirmDialog(
    title: String,
    message: String,
    confirm: String,
    onConfirm: () -> Unit,
    onDismiss: () -> Unit,
) {
    val colors = LocalGeistColors.current
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.gray.c200,
        shape = RoundedCornerShape(GeistRadii.large),
        tonalElevation = androidx.compose.ui.unit.Dp.Hairline,
        title = { Text(title, style = GeistType.heading20, color = colors.primary) },
        text = { Text(message, style = GeistType.copy14, color = colors.secondary) },
        confirmButton = {
            TextButton(onClick = onConfirm) { Text(confirm, style = GeistType.button14, color = colors.brandPrimary) }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), style = GeistType.button14) }
        },
    )
}

private const val PRIVACY_POLICY_URL = "https://healthmd.app/privacy-policy.html"
private const val SOURCE_CODE_URL = "https://github.com/CodyBontecou/health-md"
private const val LICENSE_URL = "https://github.com/CodyBontecou/health-md/blob/main/apps/android/LICENSE"

private fun shareRedactedDiagnostics(context: Context, reportText: String) {
    val sendIntent = Intent(Intent.ACTION_SEND).apply {
        type = "text/plain"
        putExtra(Intent.EXTRA_SUBJECT, context.getString(R.string.health_diagnostics_share_subject))
        putExtra(Intent.EXTRA_TEXT, reportText)
    }
    runCatching {
        context.startActivity(
            Intent.createChooser(sendIntent, context.getString(R.string.health_diagnostics_share_chooser))
                .apply { addFlags(Intent.FLAG_ACTIVITY_NEW_TASK) },
        )
    }
}
