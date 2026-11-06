package com.healthmd.presentation.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.relocation.BringIntoViewRequester
import androidx.compose.foundation.relocation.bringIntoViewRequester
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import android.widget.Toast
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.BuildConfig
import com.healthmd.R
import com.healthmd.data.health.providers.HealthProviderDirectExportStatus
import com.healthmd.data.health.providers.HealthProviderId
import com.healthmd.data.health.providers.HealthProviderState
import com.healthmd.distribution.DistributionWearSettingsCard
import com.healthmd.domain.distribution.DistributionChannel
import com.healthmd.presentation.common.*
import com.healthmd.data.health.HealthConnectIntentLauncher
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.model.HealthMetricCategory
import com.healthmd.presentation.directcli.DirectCliViewModel
import com.healthmd.presentation.export.ExportProfilesViewModel
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.lifecycle.compose.LifecycleResumeEffect
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import com.healthmd.widget.setup.WidgetSettingsCard
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class, ExperimentalFoundationApi::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    protectionSettingsRequestId: Long? = null,
    onNavigateToPaywall: () -> Unit = {},
    onNavigateToMyselfClaim: () -> Unit = {},
    onNavigateToExportProfiles: () -> Unit = {},
    onNavigateToClinicianReport: () -> Unit = {},
    onNavigateToDirectCli: () -> Unit = {},
    onNavigateToSharedSetup: () -> Unit = {},
    onNavigateToDiagnostics: () -> Unit = {},
    onNavigateToFolderDestination: () -> Unit = {},
    onNavigateToAutomations: () -> Unit = {},
    clinicAccessAvailable: Boolean = false,
    onNavigateToClinicAccess: () -> Unit = {},
    /** API endpoint and Agent Data gateway setup: the scheduled target in Schedule settings. */
    onNavigateToScheduleSettings: () -> Unit = onNavigateToAutomations,
    onNavigateToMetrics: () -> Unit = {},
    /** The entry open beside the list on wide layouts. */
    selectedEntry: SettingsEntry? = null,
) {
    val isPurchased by viewModel.isPurchased.collectAsStateWithLifecycle()
    val distributionPolicy = viewModel.distributionPolicy
    val protectionEnabled by viewModel.preventAccidentalChanges.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    val protectionRequester = remember { BringIntoViewRequester() }
    val healthProviders by viewModel.healthProviderStates.collectAsStateWithLifecycle()
    val whoopProviders = if (distributionPolicy.directCloudProvidersAvailable) {
        healthProviders.filter {
            it.provider.definition.id == HealthProviderId.WHOOP &&
                (it.isDirectConnectionConfigured || it.isConnected)
        }
    } else emptyList()
    var providerDialog by remember { mutableStateOf<HealthProviderUiState?>(null) }

    providerDialog?.let { provider ->
        AlertDialog(
            onDismissRequest = { providerDialog = null },
            title = { Text(provider.provider.definition.displayName) },
            text = {
                Column(
                    modifier = Modifier.verticalScroll(rememberScrollState()),
                    verticalArrangement = Arrangement.spacedBy(Spacing.xs),
                ) {
                    Text(stringResource(R.string.whoop_connection_description))
                    TextButton(onClick = {
                        providerDialog = null
                        viewModel.performConfigurationChange {
                            coroutineScope.launch {
                                runCatching {
                                    val intent = viewModel.getHealthProviderConnectionIntent(HealthProviderId.WHOOP)
                                        ?: error("WHOOP is not configured")
                                    context.startActivity(intent)
                                }.onFailure {
                                    Toast.makeText(context, R.string.whoop_sign_in_failed, Toast.LENGTH_LONG).show()
                                }
                            }
                        }
                    }, enabled = provider.isDirectConnectionConfigured) {
                        Text(stringResource(if (provider.isConnected) R.string.whoop_reconnect else R.string.whoop_connect))
                    }
                    if (provider.isConnected) {
                        TextButton(onClick = {
                            providerDialog = null
                            viewModel.performConfigurationChange {
                                if (provider.isSelected) viewModel.useHealthConnectForExports()
                                else viewModel.selectHealthProvider(HealthProviderId.WHOOP)
                            }
                        }) {
                            Text(stringResource(if (provider.isSelected) R.string.whoop_use_health_connect else R.string.whoop_use_for_exports))
                        }
                        TextButton(onClick = {
                            providerDialog = null
                            viewModel.performConfigurationChange { viewModel.disconnectHealthProvider(HealthProviderId.WHOOP) }
                        }) { Text(stringResource(R.string.whoop_disconnect)) }
                    }
                }
            },
            confirmButton = {
                TextButton(onClick = { providerDialog = null }) { Text(stringResource(R.string.cancel)) }
            },
        )
    }

    LaunchedEffect(protectionSettingsRequestId) {
        if (protectionSettingsRequestId != null) protectionRequester.bringIntoView()
    }

    // Trailing status values come from data the app already holds; nothing is guessed.
    val folderName = LocalAppFolderName.current
    val exportSettings by viewModel.settings.collectAsStateWithLifecycle()
    val directCli: DirectCliViewModel = hiltViewModel()
    val directCliState by directCli.uiState.collectAsStateWithLifecycle()
    val healthConnect = remember(context) { HealthConnectManager(context) }
    var healthConnectAllowed by remember { mutableStateOf<Boolean?>(null) }
    LifecycleResumeEffect(healthConnect) {
        val check = coroutineScope.launch {
            healthConnectAllowed = runCatching {
                healthConnect.isAvailable() && healthConnect.hasAllPermissions()
            }.getOrDefault(false)
        }
        onPauseOrDispose { check.cancel() }
    }
    val metricCount = HealthMetricCategory.entries.sumOf { exportSettings.metricSelection.enabledMetricCount(it) }
    val ready = stringResource(R.string.settings_status_ready)
    val off = stringResource(R.string.settings_status_off)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.md),
    ) {
        Text(
            text = stringResource(R.string.nav_settings),
            style = MaterialTheme.typography.headlineMedium,
            color = AppColors.textPrimary,
            modifier = Modifier.padding(horizontal = Spacing.xxs, vertical = Spacing.xs).semantics { heading() },
        )

        // The plan: restore or manage it on the paywall; F-Droid includes full access.
        val plan = stringResource(if (isPurchased) R.string.settings_plan_full_access else R.string.settings_plan_free)
        SettingsPlanCard(
            plan = if (distributionPolicy.purchasesAvailable) stringResource(R.string.settings_plan_manage, plan) else plan,
            onClick = if (distributionPolicy.purchasesAvailable) onNavigateToPaywall else null,
            modifier = Modifier.padding(top = Spacing.xs),
        )
        if (BuildConfig.MYSELF_CLAIM_ENABLED && distributionPolicy.purchasesAvailable) {
            SettingsGroup(
                title = stringResource(R.string.myself_claim_entry),
                rows = listOf { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.myself_claim_entry),
                        subtitle = stringResource(R.string.myself_claim_entry_subtitle),
                        icon = Icons.Outlined.WorkspacePremium,
                        onClick = onNavigateToMyselfClaim,
                        modifier = Modifier.testTag("settings_myself_claim"),
                    )
                },
            )
        }

        // Grouped as on the cross-platform Settings board: Destinations, Data, App.
        SettingsGroup(
            title = stringResource(R.string.settings_section_destinations),
            rows = listOf(
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.settings_destination_folder_title),
                        subtitle = folderName ?: stringResource(R.string.settings_destination_folder_subtitle),
                        icon = Icons.Outlined.Folder,
                        trailing = if (folderName != null) ready else null,
                        trailingTone = SettingsTrailingTone.POSITIVE,
                        onClick = onNavigateToFolderDestination,
                        selected = selectedEntry == SettingsEntry.FOLDER,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.direct_cli_title),
                        subtitle = directCliState.pairedListenerName ?: stringResource(R.string.settings_direct_cli_subtitle),
                        icon = Icons.Outlined.Terminal,
                        trailing = if (directCliState.hasTrust) stringResource(R.string.settings_status_paired) else null,
                        trailingTone = SettingsTrailingTone.POSITIVE,
                        onClick = onNavigateToDirectCli,
                        selected = selectedEntry == SettingsEntry.DIRECT_CLI,
                    )
                },
                { shape ->
                    val configured = exportSettings.apiEndpointUrl.isNotBlank()
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.export_preview_api_destination),
                        subtitle = stringResource(R.string.export_target_api_json_unconfigured_subtitle),
                        icon = Icons.Outlined.Link,
                        trailing = if (configured) ready else off,
                        trailingTone = if (configured) SettingsTrailingTone.POSITIVE else SettingsTrailingTone.NEUTRAL,
                        onClick = onNavigateToScheduleSettings,
                    )
                },
                { shape ->
                    val configured = exportSettings.agentDataGatewayUrl.isNotBlank()
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.export_preview_gateway_destination),
                        subtitle = stringResource(R.string.export_target_gateway_unconfigured_subtitle),
                        icon = Icons.Outlined.Cloud,
                        trailing = if (configured) ready else off,
                        trailingTone = if (configured) SettingsTrailingTone.POSITIVE else SettingsTrailingTone.NEUTRAL,
                        onClick = onNavigateToScheduleSettings,
                    )
                },
            ),
        )

        val dataRows = buildList<@Composable (androidx.compose.ui.graphics.Shape) -> Unit> {
            add { shape ->
                SettingsRow(
                    shape = shape,
                    title = stringResource(R.string.health_provider_label_health_connect),
                    subtitle = stringResource(R.string.settings_health_connect_subtitle),
                    icon = Icons.Outlined.FavoriteBorder,
                    trailing = when (healthConnectAllowed) {
                        true -> stringResource(R.string.settings_status_allowed)
                        false -> stringResource(R.string.settings_status_not_allowed)
                        null -> null
                    },
                    trailingTone = if (healthConnectAllowed == true) SettingsTrailingTone.POSITIVE else SettingsTrailingTone.NEUTRAL,
                    onClick = { HealthConnectIntentLauncher(context).openSettings() },
                    external = true,
                )
            }
            add { shape ->
                SettingsRow(
                    shape = shape,
                    title = stringResource(R.string.settings_default_metrics),
                    icon = Icons.Outlined.Tune,
                    trailing = metricCount.toString(),
                    onClick = onNavigateToMetrics,
                )
            }
            add { shape ->
                ExportProfilesSettingsRow(
                    shape = shape,
                    onOpen = onNavigateToExportProfiles,
                    selected = selectedEntry == SettingsEntry.EXPORT_PROFILES,
                )
            }
            whoopProviders.forEach { provider ->
                add { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.settings_connected_apps),
                        subtitle = stringResource(provider.provider.definition.summaryRes),
                        icon = Icons.Outlined.Apps,
                        trailing = provider.provider.definition.displayName,
                        trailingTone = if (provider.isConnected) SettingsTrailingTone.POSITIVE else SettingsTrailingTone.NEUTRAL,
                        onClick = { providerDialog = provider },
                    )
                }
            }
            if (clinicAccessAvailable) {
                add { shape ->
                    SettingsRow(
                        shape = shape,
                        title = "Clinic access",
                        subtitle = "Manage sponsorship and sharing",
                        icon = Icons.Outlined.Settings,
                        onClick = onNavigateToClinicAccess,
                        selected = selectedEntry == SettingsEntry.CLINIC_ACCESS,
                    )
                }
            }
            add { shape ->
                SettingsRow(
                    shape = shape,
                    title = stringResource(R.string.clinician_report_title),
                    subtitle = stringResource(R.string.clinician_report_entry_subtitle),
                    icon = Icons.Outlined.Description,
                    onClick = onNavigateToClinicianReport,
                    modifier = Modifier.testTag("clinician_report_entry"),
                    selected = selectedEntry == SettingsEntry.CLINICIAN_REPORT,
                )
            }
            add { shape ->
                SettingsRow(
                    shape = shape,
                    title = stringResource(R.string.shared_setup_title),
                    subtitle = stringResource(R.string.shared_setup_settings_detail),
                    icon = Icons.Outlined.Share,
                    onClick = onNavigateToSharedSetup,
                )
            }
        }
        SettingsGroup(title = stringResource(R.string.settings_section_data), rows = dataRows)

        SettingsGroup(
            title = stringResource(R.string.settings_section_app),
            modifier = Modifier
                .bringIntoViewRequester(protectionRequester)
                .testTag(ConfigurationProtectionTestTags.SECTION),
            rows = listOf(
                { shape ->
                    // One whole-row switch target, the explanation below it at full width.
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.configuration_protection_toggle),
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
                                stringResource(R.string.configuration_protection_description),
                                style = MaterialTheme.typography.bodySmall,
                                color = AppColors.textSecondary,
                                modifier = Modifier.fillMaxWidth().padding(top = Spacing.xxs, bottom = Spacing.xxs),
                            )
                        },
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.diagnostics_title),
                        subtitle = stringResource(R.string.diagnostics_entry),
                        icon = Icons.AutoMirrored.Outlined.HelpOutline,
                        onClick = onNavigateToDiagnostics,
                        modifier = Modifier.testTag("diagnostics.entry"),
                        selected = selectedEntry == SettingsEntry.DIAGNOSTICS,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.health_diagnostics_share_title),
                        subtitle = stringResource(R.string.health_diagnostics_description),
                        icon = Icons.Outlined.BugReport,
                        onClick = {
                            coroutineScope.launch {
                                shareRedactedDiagnostics(
                                    context = context,
                                    reportText = viewModel.buildRedactedDiagnosticsShareText(),
                                )
                            }
                        },
                        external = true,
                    )
                },
            ),
        )
        Spacer(Modifier.height(Spacing.sm))
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

        SettingsGroup(
            title = stringResource(R.string.section_feedback),
            rows = listOf(
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.feedback_send_title),
                        subtitle = stringResource(R.string.feedback_send_subtitle),
                        icon = Icons.Outlined.Email,
                        onClick = { FeedbackHelper.sendFeedbackEmail(context) },
                        external = true,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.feedback_discord_title),
                        subtitle = stringResource(R.string.feedback_discord_subtitle),
                        icon = Icons.Outlined.Groups,
                        onClick = { FeedbackHelper.openDiscordCommunity(context) },
                        external = true,
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.feedback_github_title),
                        subtitle = stringResource(R.string.feedback_github_subtitle),
                        icon = Icons.Outlined.BugReport,
                        onClick = { FeedbackHelper.openGitHubIssue(context) },
                        external = true,
                    )
                },
            ),
        )

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

/** Which entry is open beside the list on wide layouts, highlighted as on the board. */
enum class SettingsEntry { FOLDER, DIRECT_CLI, EXPORT_PROFILES, CLINIC_ACCESS, CLINICIAN_REPORT, DIAGNOSTICS }

/** The saved export profiles as a Settings row: the active one, how many, how many scheduled. */
@Composable
private fun ExportProfilesSettingsRow(
    shape: androidx.compose.ui.graphics.Shape,
    onOpen: () -> Unit,
    selected: Boolean,
    profiles: ExportProfilesViewModel = hiltViewModel(),
) {
    val state by profiles.uiState.collectAsStateWithLifecycle()
    SettingsRow(
        shape = shape,
        title = stringResource(R.string.automations_profiles_title),
        subtitle = if (state.rows.isEmpty()) {
            stringResource(R.string.automations_profiles_body)
        } else {
            val count = state.rows.size
            val scheduled = state.rows.count { it.entry?.isEnabled == true }
            stringResource(
                R.string.automations_profiles_summary,
                state.activeProfileName ?: "—",
                pluralStringResource(R.plurals.automations_profiles_count, count, count),
                pluralStringResource(R.plurals.automations_profiles_scheduled, scheduled, scheduled),
            )
        },
        icon = Icons.Outlined.Layers,
        onClick = onOpen,
        modifier = Modifier.testTag("export_profiles_entry"),
        selected = selected,
    )
}

private const val SOURCE_CODE_URL = "https://github.com/CodyBontecou/health-md"
private const val LICENSE_URL = "https://github.com/CodyBontecou/health-md/blob/main/apps/android/LICENSE"

private fun openExternalUrl(context: Context, url: String) {
    runCatching {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
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
