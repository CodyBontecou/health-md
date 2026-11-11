package com.healthmd.presentation.settings

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.HelpOutline
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
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
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.health.HealthConnectIntentLauncher
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.providers.HealthProviderId
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.AgentDataGatewayEndpoint
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthMetricCategory
import com.healthmd.presentation.common.LocalAppFolderName
import com.healthmd.presentation.directcli.DirectCliViewModel
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch

/**
 * Settings, grouped as on iOS: the plan, Destinations, Data, and App. Each row opens the page
 * that owns that capability; the lock, setup sharing, privacy and help live in App & support.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = hiltViewModel(),
    /** A blocked-change toast asked for the lock: Settings opens App & support, which scrolls to it. */
    protectionSettingsRequestId: Long? = null,
    /** Settings › Subscription: the plan, Manage or cancel, and the lapsed state. */
    onNavigateToSubscription: () -> Unit = {},
    onNavigateToClinicianReport: () -> Unit = {},
    onNavigateToDirectCli: () -> Unit = {},
    onNavigateToFolderDestination: () -> Unit = {},
    clinicAccessAvailable: Boolean = false,
    onNavigateToClinicAccess: () -> Unit = {},
    onNavigateToApiEndpoint: () -> Unit = {},
    onNavigateToGateway: () -> Unit = {},
    onNavigateToConnectedApps: () -> Unit = {},
    onNavigateToAppSupport: () -> Unit = {},
    /** The app-wide schedule, scheduled target and background access. */
    onNavigateToScheduleSettings: () -> Unit = {},
    onNavigateToMetrics: () -> Unit = {},
    /** The entry open beside the list on wide layouts. */
    selectedEntry: SettingsEntry? = null,
) {
    val isPurchased by viewModel.isPurchased.collectAsStateWithLifecycle()
    val distributionPolicy = viewModel.distributionPolicy
    val protectionEnabled by viewModel.preventAccidentalChanges.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    LaunchedEffect(protectionSettingsRequestId) {
        if (protectionSettingsRequestId != null) onNavigateToAppSupport()
    }

    // Status values come from data the app already holds; nothing is guessed.
    val folderName = LocalAppFolderName.current
    val exportSettings by viewModel.settings.collectAsStateWithLifecycle()
    val directCli: DirectCliViewModel = hiltViewModel()
    val directCliState by directCli.uiState.collectAsStateWithLifecycle()
    val profiles: ExportProfilesViewModel = hiltViewModel()
    val profileState by profiles.uiState.collectAsStateWithLifecycle()
    val healthProviders by viewModel.healthProviderStates.collectAsStateWithLifecycle()
    val connectedApps = if (distributionPolicy.directCloudProvidersAvailable) {
        healthProviders.filter {
            it.provider.definition.id == HealthProviderId.WHOOP && (it.isDirectConnectionConfigured || it.isConnected)
        }
    } else {
        emptyList()
    }
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
    val ready = SettingsBadge(stringResource(R.string.settings_status_ready), SettingsBadgeTone.OK)
    val off = SettingsBadge(stringResource(R.string.settings_status_off), SettingsBadgeTone.OFF)

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.md)
            .testTag("settings.hub"),
    ) {
        Text(
            text = stringResource(R.string.nav_settings),
            style = MaterialTheme.typography.headlineMedium,
            color = AppColors.textPrimary,
            modifier = Modifier.padding(horizontal = Spacing.xxs, vertical = Spacing.xs).semantics { heading() },
        )

        // The plan: restore or manage it in Subscription; F-Droid includes full access.
        val subscriptionStatus = if (distributionPolicy.purchasesAvailable) {
            val subscription: SubscriptionViewModel = hiltViewModel()
            subscription.status.collectAsStateWithLifecycle().value
        } else {
            null
        }
        val plan = stringResource(
            when {
                subscriptionStatus is com.healthmd.domain.billing.SubscriptionStatus.Ended && !isPurchased ->
                    R.string.m3_subscription_ended_title
                isPurchased -> R.string.settings_plan_full_access
                else -> R.string.settings_plan_free
            },
        )
        SettingsPlanCard(
            plan = if (distributionPolicy.purchasesAvailable) stringResource(R.string.settings_plan_manage, plan) else plan,
            onClick = if (distributionPolicy.purchasesAvailable) onNavigateToSubscription else null,
            modifier = Modifier.padding(top = Spacing.xs),
        )

        val folderSummary = SettingsFolderSummary.of(
            defaultFolder = folderName,
            subfolder = exportSettings.subfolder,
            folderProfiles = profileState.rows
                .filter { it.profile.target == ExportTarget.DEVICE_FOLDER }
                .map { it.profile.folderUri to it.profile.folderDisplayName },
        )
        SettingsGroup(
            title = stringResource(R.string.settings_section_destinations),
            rows = listOf(
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.settings_vault_title),
                        subtitle = when (folderSummary) {
                            is SettingsFolderSummary.Several ->
                                pluralStringResource(R.plurals.settings_vault_folders, folderSummary.count, folderSummary.count)
                            is SettingsFolderSummary.Default ->
                                stringResource(R.string.settings_vault_default, folderSummary.path)
                            is SettingsFolderSummary.Own -> folderSummary.name
                            SettingsFolderSummary.None -> null
                        },
                        icon = Icons.Outlined.Folder,
                        badge = if (folderName != null) ready else off,
                        onClick = onNavigateToFolderDestination,
                        selected = selectedEntry == SettingsEntry.FOLDER,
                        modifier = Modifier.testTag("settings.folder"),
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.settings_cli_title),
                        subtitle = if (directCliState.hasTrust) stringResource(R.string.settings_cli_paired_one) else null,
                        icon = Icons.Outlined.Terminal,
                        badge = if (directCliState.hasTrust) {
                            SettingsBadge(stringResource(R.string.settings_status_paired), SettingsBadgeTone.OK)
                        } else {
                            off
                        },
                        onClick = onNavigateToDirectCli,
                        selected = selectedEntry == SettingsEntry.DIRECT_CLI,
                        modifier = Modifier.testTag("settings.cli"),
                    )
                },
                { shape ->
                    val configured = APIExportEndpoint.isConfigured(exportSettings.apiEndpointUrl)
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.export_preview_api_destination),
                        subtitle = if (configured) {
                            APIExportEndpoint.displayName(exportSettings.apiEndpointUrl)
                        } else {
                            stringResource(R.string.settings_api_subtitle_off)
                        },
                        icon = Icons.Outlined.Code,
                        badge = if (configured) ready else off,
                        onClick = onNavigateToApiEndpoint,
                        selected = selectedEntry == SettingsEntry.API,
                        modifier = Modifier.testTag("settings.api"),
                    )
                },
                { shape ->
                    val configured = AgentDataGatewayEndpoint.isConfigured(exportSettings.agentDataGatewayUrl)
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.export_preview_gateway_destination),
                        subtitle = if (configured) {
                            AgentDataGatewayEndpoint.displayName(exportSettings.agentDataGatewayUrl)
                        } else {
                            stringResource(R.string.settings_gateway_subtitle_off)
                        },
                        icon = Icons.Outlined.UploadFile,
                        badge = if (configured) ready else off,
                        onClick = onNavigateToGateway,
                        selected = selectedEntry == SettingsEntry.GATEWAY,
                        modifier = Modifier.testTag("settings.gateway"),
                    )
                },
            ),
        )

        val dataRows = buildList<@Composable (Shape) -> Unit> {
            // Health Connect has no iOS row: HealthKit access lives in the system Health app.
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
                    modifier = Modifier.testTag("settings.metrics"),
                )
            }
            add { shape ->
                SettingsRow(
                    shape = shape,
                    title = stringResource(R.string.automations_schedule_settings_title),
                    subtitle = stringResource(R.string.settings_schedule_subtitle),
                    icon = Icons.Outlined.Schedule,
                    onClick = onNavigateToScheduleSettings,
                    selected = selectedEntry == SettingsEntry.SCHEDULE,
                    modifier = Modifier.testTag("settings.schedule"),
                )
            }
            if (connectedApps.isNotEmpty()) {
                add { shape ->
                    val names = connectedApps.filter { it.isConnected }.map { it.provider.definition.displayName }.sorted()
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.settings_connected_apps),
                        icon = Icons.Outlined.Apps,
                        trailing = names.takeIf { it.isNotEmpty() }?.joinToString(", "),
                        onClick = onNavigateToConnectedApps,
                        selected = selectedEntry == SettingsEntry.CONNECTED_APPS,
                        modifier = Modifier.testTag("settings.connectedApps"),
                    )
                }
            }
            if (clinicAccessAvailable) {
                add { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.settings_clinic_access),
                        icon = Icons.Outlined.MedicalServices,
                        onClick = onNavigateToClinicAccess,
                        selected = selectedEntry == SettingsEntry.CLINIC_ACCESS,
                        modifier = Modifier.testTag("settings.clinic"),
                    )
                }
            }
            add { shape ->
                SettingsRow(
                    shape = shape,
                    title = stringResource(R.string.clinician_report_title),
                    icon = Icons.Outlined.Description,
                    onClick = onNavigateToClinicianReport,
                    modifier = Modifier.testTag("clinician_report_entry"),
                    selected = selectedEntry == SettingsEntry.CLINICIAN_REPORT,
                )
            }
        }
        SettingsGroup(title = stringResource(R.string.settings_section_data), rows = dataRows)

        // As on iOS, each App row opens App & support, which owns these controls.
        val appSupportSelected = selectedEntry == SettingsEntry.APP_SUPPORT
        SettingsGroup(
            title = stringResource(R.string.settings_section_app),
            rows = listOf(
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.settings_lock_configuration),
                        icon = Icons.Outlined.Lock,
                        trailing = when (protectionEnabled) {
                            true -> stringResource(R.string.settings_value_on)
                            false -> stringResource(R.string.settings_status_off)
                            null -> null
                        },
                        onClick = onNavigateToAppSupport,
                        selected = appSupportSelected,
                        modifier = Modifier.testTag("settings.lock"),
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.settings_privacy),
                        icon = Icons.Outlined.PanTool,
                        trailing = stringResource(R.string.settings_no_analytics),
                        onClick = onNavigateToAppSupport,
                        modifier = Modifier.testTag("settings.privacy"),
                    )
                },
                { shape ->
                    SettingsRow(
                        shape = shape,
                        title = stringResource(R.string.settings_help_diagnostics),
                        icon = Icons.AutoMirrored.Outlined.HelpOutline,
                        onClick = onNavigateToAppSupport,
                        modifier = Modifier.testTag("settings.appSupport"),
                    )
                },
            ),
        )

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

/** Which entry is open beside the list on wide layouts, highlighted as on the board. */
enum class SettingsEntry {
    FOLDER, DIRECT_CLI, API, GATEWAY, SCHEDULE, CONNECTED_APPS, CLINIC_ACCESS, CLINICIAN_REPORT, APP_SUPPORT,
}

/**
 * The folder row's subtitle. Folder automations can each write to their own folder, so it
 * says how many are in use; one default folder reads as its path, an own folder by its name.
 */
sealed interface SettingsFolderSummary {
    data object None : SettingsFolderSummary
    data class Default(val path: String) : SettingsFolderSummary
    data class Own(val name: String) : SettingsFolderSummary
    data class Several(val count: Int) : SettingsFolderSummary

    companion object {
        /** [folderProfiles] holds each folder automation's own folder (uri to display name). */
        fun of(
            defaultFolder: String?,
            subfolder: String,
            folderProfiles: List<Pair<String?, String?>>,
        ): SettingsFolderSummary {
            val own = folderProfiles.filter { it.first != null }
            val ownFolders = own.mapNotNull { it.first }.toSet()
            val usesDefault = folderProfiles.isEmpty() || folderProfiles.any { it.first == null }
            val count = ownFolders.size + if (usesDefault && defaultFolder != null) 1 else 0
            return when {
                count > 1 -> Several(count)
                usesDefault -> defaultFolder?.let { folder ->
                    val trimmed = subfolder.trim().trim('/')
                    Default(if (trimmed.isEmpty()) folder else "$folder/$trimmed")
                } ?: None
                else -> own.firstNotNullOfOrNull { it.second }?.let(::Own) ?: None
            }
        }
    }
}

internal fun openExternalUrl(context: Context, url: String) {
    runCatching {
        context.startActivity(
            Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            },
        )
    }
}
