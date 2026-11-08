package com.healthmd.presentation.schedule

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.text.format.DateFormat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.health.HealthConnectFeatureAvailability
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.grantedAllRequestedHealthPermissions
import com.healthmd.data.health.tryLaunchHealthConnectPermissions
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.AgentDataGatewayEndpoint
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.presentation.common.APIExportSettingsDialog
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.AgentDataGatewaySettingsDialog
import com.healthmd.presentation.common.ConfigurationProtectedRegion
import com.healthmd.presentation.common.ExportTargetSelector
import com.healthmd.presentation.common.HealthConnectActionError
import com.healthmd.presentation.common.HealthConnectErrorNotice
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.history.HistoryViewModel
import com.healthmd.presentation.settings.groupRowShape
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.util.runCatchingCancellable
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.text.ParsePosition
import java.util.Date
import java.util.Locale

/**
 * Schedule settings, opened from Automations: the app-wide schedule, the scheduled export
 * target and its endpoints, the permissions schedules need, and schedule history. Automations
 * themselves (profiles and their schedules) are on [AutomationsScreen].
 */
@Composable
fun ScheduleScreen(
    viewModel: ScheduleViewModel = hiltViewModel(),
    onNavigateToPaywall: () -> Unit = {},
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val clinicAccess: com.healthmd.presentation.clinic.ClinicAccessViewModel = hiltViewModel()
    val clinicStatus by clinicAccess.status.collectAsStateWithLifecycle()
    val independentAccess by clinicAccess.independentAccess.collectAsStateWithLifecycle()
    val managedClinicEndpoint = clinicStatus.endpoint.takeIf { clinicStatus.active && !independentAccess }
    val historyViewModel: HistoryViewModel = hiltViewModel()
    val historyUiState by historyViewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val protection = LocalConfigurationProtection.current
    val attemptConfigurationChange: (() -> Unit) -> Unit = { action ->
        if (protection.enabled) protection.onBlockedChange() else action()
    }
    val coroutineScope = rememberCoroutineScope()
    val healthConnectManager = remember { HealthConnectManager(context) }
    val configurationErrorText = uiState.configurationError?.localizedText()

    var notificationsGranted by remember {
        mutableStateOf(hasPostNotificationsPermission(context))
    }
    var showAPISettings by remember { mutableStateOf(false) }
    var showGatewaySettings by remember { mutableStateOf(false) }
    val notificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
    val notificationsReady = notificationsGranted && notificationsEnabled
    var hasPromptedForNotifications by rememberSaveable { mutableStateOf(false) }

    var backgroundReadFeatureAvailable by remember { mutableStateOf(false) }
    var backgroundReadUnsupported by remember { mutableStateOf(false) }
    var backgroundReadCheckFailed by remember { mutableStateOf(false) }
    var backgroundReadReady by remember { mutableStateOf(true) }
    var backgroundReadStateLoaded by remember { mutableStateOf(false) }
    var backgroundReadPermissions by remember { mutableStateOf<Set<String>>(emptySet()) }
    var healthConnectActionError by remember { mutableStateOf<HealthConnectActionError?>(null) }
    var hasPromptedForBackgroundRead by rememberSaveable { mutableStateOf(false) }
    var backgroundRefreshJob by remember { mutableStateOf<Job?>(null) }

    fun clearResolvedBackgroundError() {
        if (
            healthConnectActionError == HealthConnectActionError.ACCESS_CHECK_FAILED ||
            healthConnectActionError == HealthConnectActionError.BACKGROUND_ACCESS_UNAVAILABLE
        ) {
            healthConnectActionError = null
        }
    }

    fun refreshBackgroundReadPermissionState() {
        backgroundRefreshJob?.cancel()
        if (!uiState.healthProviderSelectionLoaded) {
            backgroundReadStateLoaded = false
            return
        }
        if (!uiState.requiresHealthConnectBackgroundAccess) {
            backgroundReadFeatureAvailable = false
            backgroundReadUnsupported = false
            backgroundReadCheckFailed = false
            backgroundReadReady = true
            backgroundReadPermissions = emptySet()
            backgroundReadStateLoaded = true
            clearResolvedBackgroundError()
            return
        }

        val plan = healthConnectManager.permissionPlan()
        backgroundReadPermissions = plan.backgroundReadPermissions
        when (plan.backgroundReadAvailability) {
            HealthConnectFeatureAvailability.ERROR -> {
                backgroundReadFeatureAvailable = false
                backgroundReadUnsupported = false
                backgroundReadCheckFailed = true
                backgroundReadReady = false
                backgroundReadStateLoaded = true
                healthConnectActionError = HealthConnectActionError.ACCESS_CHECK_FAILED
            }
            HealthConnectFeatureAvailability.UNAVAILABLE -> {
                backgroundReadFeatureAvailable = false
                backgroundReadUnsupported = true
                backgroundReadCheckFailed = false
                backgroundReadReady = false
                backgroundReadStateLoaded = true
                healthConnectActionError = if (uiState.isEnabled) {
                    HealthConnectActionError.BACKGROUND_ACCESS_UNAVAILABLE
                } else {
                    null
                }
            }
            HealthConnectFeatureAvailability.AVAILABLE -> {
                backgroundReadFeatureAvailable = true
                backgroundReadUnsupported = false
                backgroundReadCheckFailed = false
                backgroundReadStateLoaded = false
                backgroundRefreshJob = coroutineScope.launch {
                    runCatchingCancellable {
                        healthConnectManager.hasBackgroundReadPermission()
                    }
                        .onSuccess {
                            backgroundReadReady = it
                            backgroundReadCheckFailed = false
                            clearResolvedBackgroundError()
                        }
                        .onFailure {
                            backgroundReadReady = false
                            backgroundReadCheckFailed = true
                            healthConnectActionError = HealthConnectActionError.ACCESS_CHECK_FAILED
                        }
                    backgroundReadStateLoaded = true
                }
            }
        }
    }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { granted ->
        notificationsGranted = granted
    }

    val healthPermissionContract = remember { healthConnectManager.getPermissionContract() }
    val healthPermissionLauncher = rememberLauncherForActivityResult(
        contract = healthPermissionContract,
    ) { grantedPermissions ->
        if (
            backgroundReadPermissions.isNotEmpty() &&
            !grantedAllRequestedHealthPermissions(backgroundReadPermissions, grantedPermissions)
        ) {
            healthConnectActionError = HealthConnectActionError.PERMISSION_DENIED
        }
        refreshBackgroundReadPermissionState()
    }
    val launchBackgroundReadPermission: () -> Unit = {
        hasPromptedForBackgroundRead = true
        healthConnectActionError = null
        if (!tryLaunchHealthConnectPermissions(backgroundReadPermissions) {
                healthPermissionLauncher.launch(it)
            }) {
            healthConnectActionError = HealthConnectActionError.PERMISSION_REQUEST_FAILED
        }
    }

    DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                notificationsGranted = hasPostNotificationsPermission(context)
                refreshBackgroundReadPermissionState()
                viewModel.refreshSchedulingState()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    LaunchedEffect(
        uiState.healthProviderSelectionLoaded,
        uiState.requiresHealthConnectBackgroundAccess,
    ) {
        refreshBackgroundReadPermissionState()
        viewModel.refreshSchedulingState()
    }

    LaunchedEffect(uiState.requiresUpgrade) {
        if (uiState.requiresUpgrade) {
            viewModel.consumeUpgradeRequest()
            onNavigateToPaywall()
        }
    }

    LaunchedEffect(uiState.isEnabled, backgroundReadStateLoaded, backgroundReadFeatureAvailable, backgroundReadReady) {
        if (
            uiState.isEnabled &&
            backgroundReadStateLoaded &&
            (!uiState.requiresHealthConnectBackgroundAccess ||
                (backgroundReadFeatureAvailable && backgroundReadReady)) &&
            !notificationsGranted &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !hasPromptedForNotifications
        ) {
            hasPromptedForNotifications = true
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    LaunchedEffect(uiState.isEnabled, backgroundReadStateLoaded, backgroundReadFeatureAvailable, backgroundReadReady) {
        if (
            uiState.isEnabled &&
            backgroundReadStateLoaded &&
            uiState.requiresHealthConnectBackgroundAccess &&
            backgroundReadFeatureAvailable &&
            !backgroundReadReady &&
            !hasPromptedForBackgroundRead
        ) {
            launchBackgroundReadPermission()
        }
    }

    LaunchedEffect(
        uiState.isEnabled,
        uiState.requiresHealthConnectBackgroundAccess,
        backgroundReadStateLoaded,
        backgroundReadUnsupported,
        backgroundReadCheckFailed,
    ) {
        if (
            uiState.isEnabled &&
            uiState.requiresHealthConnectBackgroundAccess &&
            backgroundReadStateLoaded &&
            (backgroundReadUnsupported || backgroundReadCheckFailed)
        ) {
            viewModel.toggleSchedule(false)
            healthConnectActionError = if (backgroundReadCheckFailed) {
                HealthConnectActionError.ACCESS_CHECK_FAILED
            } else {
                HealthConnectActionError.BACKGROUND_ACCESS_UNAVAILABLE
            }
        }
    }

    if (historyUiState.showClearConfirmation) {
        val colors = LocalGeistColors.current
        AlertDialog(
            onDismissRequest = { historyViewModel.dismissClearHistory() },
            containerColor = colors.gray.c200,
            shape = RoundedCornerShape(GeistRadii.large),
            tonalElevation = 0.dp,
            icon = { Icon(Icons.Outlined.Delete, contentDescription = null, tint = colors.secondary) },
            title = {
                Text(
                    stringResource(R.string.history_clear_title),
                    style = GeistType.heading20,
                    color = colors.primary,
                    textAlign = TextAlign.Center,
                )
            },
            text = {
                Text(stringResource(R.string.history_clear_body), style = GeistType.copy14, color = colors.secondary)
            },
            confirmButton = {
                Button(
                    onClick = {
                        if (protection.enabled) {
                            historyViewModel.dismissClearHistory()
                            protection.onBlockedChange()
                        } else {
                            historyViewModel.clearHistory()
                        }
                    },
                    shape = RoundedCornerShape(GeistRadii.full),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = colors.brandPrimary,
                        contentColor = colors.brandOnPrimary,
                    ),
                    elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp),
                    modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
                ) {
                    Text(stringResource(R.string.action_clear_history), style = GeistType.button14)
                }
            },
            dismissButton = {
                TextButton(
                    onClick = { historyViewModel.dismissClearHistory() },
                    modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
                ) {
                    Text(stringResource(R.string.action_keep_history), style = GeistType.button14, color = LocalGeistColors.current.brandPrimary)
                }
            },
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        ScheduleSectionLabel(stringResource(R.string.automatic_export_title))

        ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
        ScheduleToggleCard(
            checked = uiState.isEnabled,
            onCheckedChange = { enabled ->
                attemptConfigurationChange {
                    if (
                        enabled &&
                        uiState.requiresHealthConnectBackgroundAccess &&
                        backgroundReadStateLoaded &&
                        (backgroundReadUnsupported || backgroundReadCheckFailed)
                    ) {
                        healthConnectActionError = if (backgroundReadCheckFailed) {
                            HealthConnectActionError.ACCESS_CHECK_FAILED
                        } else {
                            HealthConnectActionError.BACKGROUND_ACCESS_UNAVAILABLE
                        }
                    } else {
                        viewModel.toggleSchedule(enabled)
                    }
                }
            },
        )
        }

        uiState.nextExportAtMillis?.let { nextExportAtMillis ->
            val nextExport = Date(nextExportAtMillis)
            val localizedDateTime = stringResource(
                R.string.schedule_next_export_datetime,
                DateFormat.getMediumDateFormat(context).format(nextExport),
                DateFormat.getTimeFormat(context).format(nextExport),
            )
            BodyText(
                text = stringResource(
                    R.string.schedule_next_export_at_datetime,
                    localizedDateTime,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
        }

        BodyText(
            text = stringResource(R.string.schedule_automatic_export_body),
            modifier = Modifier.fillMaxWidth(),
        )

        BodyText(
            text = stringResource(R.string.schedule_exact_background_note),
            modifier = Modifier.fillMaxWidth(),
        )

        healthConnectActionError?.let { error ->
            HealthConnectErrorNotice(
                error = error,
                onDismiss = { healthConnectActionError = null },
            )
        }

        ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                ExportTargetSelector(
                    managedClinicEndpoint = managedClinicEndpoint,
                    selectedTarget = uiState.selectedTarget,
                    folderSubtitle = if (uiState.hasExportFolder) {
                        stringResource(R.string.schedule_target_folder_ready)
                    } else {
                        stringResource(R.string.schedule_target_folder_choose)
                    },
                    apiSubtitle = if (uiState.apiEndpointConfigured) {
                        stringResource(
                            R.string.schedule_target_api_configured,
                            APIExportEndpoint.displayName(uiState.apiEndpointUrl),
                        )
                    } else {
                        stringResource(R.string.schedule_target_api_unconfigured)
                    },
                    gatewaySubtitle = if (uiState.agentDataGatewayConfigured) {
                        stringResource(
                            R.string.export_target_gateway_configured_subtitle,
                            AgentDataGatewayEndpoint.displayName(uiState.agentDataGatewayUrl),
                        )
                    } else {
                        stringResource(R.string.export_target_gateway_unconfigured_subtitle)
                    },
                    onTargetSelected = { target ->
                        attemptConfigurationChange {
                            viewModel.setScheduledExportTarget(target)
                            if (target == ExportTarget.API_ENDPOINT && !uiState.apiEndpointConfigured) {
                                showAPISettings = true
                            }
                            if (target == ExportTarget.AGENT_DATA_GATEWAY && !uiState.agentDataGatewayConfigured) {
                                showGatewaySettings = true
                            }
                        }
                    },
                )

                if (uiState.selectedTarget == ExportTarget.API_ENDPOINT) {
                    EndpointSettingsButton(
                        configured = uiState.apiEndpointConfigured,
                        onClick = { attemptConfigurationChange { showAPISettings = true } },
                    )
                }

                if (uiState.selectedTarget == ExportTarget.AGENT_DATA_GATEWAY) {
                    EndpointSettingsButton(
                        configured = uiState.agentDataGatewayConfigured,
                        onClick = { attemptConfigurationChange { showGatewaySettings = true } },
                    )
                }
            }
        }

        configurationErrorText?.let { message ->
            WarningCard(
                title = stringResource(R.string.schedule_destination_not_ready_title),
                body = message,
                action = if (uiState.selectedTarget == ExportTarget.API_ENDPOINT) {
                    stringResource(R.string.action_configure_endpoint)
                } else {
                    stringResource(R.string.action_dismiss_error)
                },
                onAction = {
                    if (uiState.selectedTarget == ExportTarget.API_ENDPOINT) {
                        attemptConfigurationChange { showAPISettings = true }
                    } else {
                        viewModel.clearConfigurationError()
                    }
                },
            )
        }

        if (!uiState.isPurchased && !uiState.clinicDestinationAuthorized) {
            WarningCard(
                title = stringResource(R.string.schedule_unlock_required_title),
                body = stringResource(R.string.schedule_unlock_required_body),
                action = stringResource(R.string.unlock_button),
                onAction = onNavigateToPaywall,
            )
        }

        if (uiState.isEnabled) {
            ScheduleSectionLabel(stringResource(R.string.section_schedule))

            ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
            ScheduleSettingsCard(
                uiState = uiState,
                onFrequencyValueChange = { value -> attemptConfigurationChange { viewModel.setCadenceValue(value) } },
                onFrequencyUnitSelected = { unit -> attemptConfigurationChange { viewModel.setCadenceUnit(unit) } },
                onHourDelta = { delta -> attemptConfigurationChange { viewModel.setHour((uiState.hour + delta + 24) % 24) } },
                onMinuteDelta = { delta -> attemptConfigurationChange { viewModel.setMinute((uiState.minute + delta + 60) % 60) } },
                onTogglePeriod = {
                    attemptConfigurationChange {
                        val nextHour = if (uiState.hour < 12) uiState.hour + 12 else uiState.hour - 12
                        viewModel.setHour(nextHour)
                    }
                },
                onDateWindowSelected = { dateWindow -> attemptConfigurationChange { viewModel.setDateWindow(dateWindow) } },
                onLookbackDelta = { delta -> attemptConfigurationChange { viewModel.setLookbackDays(uiState.lookbackDays + delta) } },
            )
            }

            BodyText(
                text = when (uiState.dateWindow) {
                    ScheduleDateWindow.PAST_COMPLETE_DAYS -> pluralStringResource(
                        R.plurals.schedule_lookback_days_summary,
                        uiState.lookbackDays,
                        uiState.lookbackDays,
                    )
                    ScheduleDateWindow.PAST_COMPLETE_DAYS_THROUGH_TODAY -> stringResource(
                        R.string.schedule_through_today_summary,
                    )
                    ScheduleDateWindow.TODAY -> stringResource(R.string.schedule_today_summary)
                },
                modifier = Modifier.fillMaxWidth(),
            )

            if (!uiState.exactTimingAvailable) {
                ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
                    WarningCard(
                        title = stringResource(R.string.exact_timing_needed_title),
                        body = stringResource(R.string.exact_timing_needed_body),
                        action = stringResource(R.string.exact_timing_enable_button),
                        onAction = { openExactAlarmSettings(context) },
                    )
                }
            }

            if (backgroundReadFeatureAvailable && !backgroundReadReady) {
                ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
                    WarningCard(
                        title = stringResource(R.string.background_health_permission_needed_title),
                        body = stringResource(R.string.background_health_permission_needed_body),
                        action = stringResource(R.string.background_health_permission_enable_button),
                        onAction = {
                            launchBackgroundReadPermission()
                        },
                    )
                }
            }

            if (!notificationsReady) {
                ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
                    WarningCard(
                        title = stringResource(R.string.notifications_needed_title),
                        body = stringResource(R.string.notifications_needed_body),
                        action = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notificationsGranted) {
                            stringResource(R.string.notifications_enable_button)
                        } else {
                            stringResource(R.string.notifications_open_settings_button)
                        },
                        secondaryAction = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notificationsGranted) {
                            stringResource(R.string.notifications_open_settings_button)
                        } else {
                            null
                        },
                        onAction = {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notificationsGranted) {
                                hasPromptedForNotifications = true
                                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                            } else {
                                openNotificationSettings(context)
                            }
                        },
                        onSecondaryAction = { openNotificationSettings(context) },
                    )
                }
            }

            ScheduleHistoryHeading(
                onRequestClearHistory = {
                    attemptConfigurationChange { historyViewModel.requestClearHistory() }
                },
            )
        }

        Spacer(modifier = Modifier.height(GeistSpacing.space8))
    }

    if (showAPISettings) {
        APIExportSettingsDialog(
            managedClinicEndpoint = managedClinicEndpoint,
            initialEndpointUrl = uiState.apiEndpointUrl,
            authorizationConfigured = uiState.apiAuthorizationConfigured,
            requestHeadersConfigured = uiState.apiRequestHeadersConfigured,
            configurationError = configurationErrorText,
            onDismiss = {
                showAPISettings = false
                viewModel.clearConfigurationError()
            },
            onSave = { endpoint, authorization, headers ->
                attemptConfigurationChange {
                    viewModel.saveAPIExportConfiguration(endpoint, authorization, headers)
                }
            },
            onClearAuthorization = {
                attemptConfigurationChange(viewModel::clearAPIAuthorization)
            },
            onClearRequestHeaders = {
                attemptConfigurationChange(viewModel::clearAPIRequestHeaders)
            },
        )
    }
    if (showGatewaySettings) {
        AgentDataGatewaySettingsDialog(
            initialEndpointUrl = uiState.agentDataGatewayUrl,
            configurationError = configurationErrorText,
            onDismiss = {
                showGatewaySettings = false
                viewModel.clearConfigurationError()
            },
            onSave = { endpoint ->
                attemptConfigurationChange {
                    viewModel.saveAgentDataGatewayConfiguration(endpoint)
                }
            },
        )
    }
}

/** A list-group heading (DESIGN.md `list-group`): `heading-14` in the brand color. */
@Composable
private fun ScheduleSectionLabel(text: String) {
    Text(
        text = text,
        style = GeistType.heading14,
        color = LocalGeistColors.current.brandPrimary,
        modifier = Modifier
            .fillMaxWidth()
            .padding(start = GeistSpacing.space4, top = GeistSpacing.space2)
            .semantics { heading() },
    )
}

@Composable
private fun BodyText(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text,
        style = GeistType.copy14,
        color = LocalGeistColors.current.secondary,
        modifier = modifier.padding(horizontal = GeistSpacing.space4),
    )
}

/** Opens the selected endpoint's settings: a text action, not a second filled button. */
@Composable
private fun EndpointSettingsButton(configured: Boolean, onClick: () -> Unit) {
    TextButton(
        onClick = onClick,
        modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
    ) {
        Text(
            stringResource(if (configured) R.string.action_edit_endpoint else R.string.action_configure_endpoint),
            style = GeistType.button14,
            color = LocalGeistColors.current.brandPrimary,
        )
    }
}

/** The schedule's on/off switch as a one-row list group; the whole row is the target. */
@Composable
private fun ScheduleToggleCard(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(groupRowShape(0, 1))
            .background(colors.background200)
            .toggleable(
                value = checked,
                role = Role.Switch,
                onValueChange = onCheckedChange,
            )
            .heightIn(min = 56.dp)
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.schedule_enable_scheduled_exports),
            style = GeistType.label16,
            color = colors.primary,
            modifier = Modifier.weight(1f),
        )
        AppSwitch(checked = checked, onCheckedChange = null)
    }
}

/** A tonal warning note (no border): icon, title and color carry the status; text actions. */
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun WarningCard(
    title: String,
    body: String,
    action: String,
    onAction: () -> Unit,
    secondaryAction: String? = null,
    onSecondaryAction: (() -> Unit)? = null,
) {
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.medium))
            .background(colors.amber.c100)
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space2, top = GeistSpacing.space4, bottom = GeistSpacing.space1),
    ) {
        Row(
            modifier = Modifier.padding(end = GeistSpacing.space2),
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        ) {
            Icon(Icons.Outlined.WarningAmber, contentDescription = null, tint = colors.warning, modifier = Modifier.size(20.dp))
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
                Text(title, style = GeistType.heading14, color = colors.warning)
                Text(body, style = GeistType.copy14, color = colors.primary)
            }
        }
        FlowRow(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
        ) {
            secondaryAction?.let { label ->
                TextButton(
                    onClick = { onSecondaryAction?.invoke() },
                    modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget),
                ) {
                    Text(label, style = GeistType.button14, color = colors.brandPrimary)
                }
            }
            TextButton(onClick = onAction, modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget)) {
                Text(action, style = GeistType.button14, color = colors.brandPrimary)
            }
        }
    }
}

@Composable
private fun ScheduleUiMessage.localizedText(): String = when (this) {
    is ScheduleUiMessage.Text -> stringResource(resourceId, *arguments.toTypedArray())
}

internal fun formatInteger(value: Int, locale: Locale): String =
    NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = false }.format(value)

internal fun parseLocalizedInteger(value: String, locale: Locale): Int? {
    if (value.isBlank()) return null
    val position = ParsePosition(0)
    val parsed = NumberFormat.getIntegerInstance(locale).apply { isGroupingUsed = false }
        .parse(value, position)
    if (position.index != value.length) return null
    return parsed?.toInt()
}

internal fun localizedHourCycle(locale: Locale, use24HourTime: Boolean): Char =
    localizedTimePatternRuns(locale, use24HourTime)
        .firstOrNull { it.symbol == 'H' || it.symbol == 'h' || it.symbol == 'K' || it.symbol == 'k' }
        ?.symbol
        ?: if (use24HourTime) 'H' else 'h'

internal fun localizedDisplayHour(hour: Int, hourCycle: Char): Int {
    val normalizedHour = Math.floorMod(hour, 24)
    return when (hourCycle) {
        'h' -> ((normalizedHour + 11) % 12) + 1
        'K' -> normalizedHour % 12
        'k' -> if (normalizedHour == 0) 24 else normalizedHour
        else -> normalizedHour
    }
}

internal fun localizedDayPeriodPrecedesHour(locale: Locale): Boolean {
    val runs = localizedTimePatternRuns(locale, use24HourTime = false)
    val periodStart = runs.firstOrNull { it.symbol == 'a' }?.start ?: return false
    val hourStart = runs.firstOrNull {
        it.symbol == 'H' || it.symbol == 'h' || it.symbol == 'K' || it.symbol == 'k'
    }?.start ?: return false
    return periodStart < hourStart
}

internal fun localizedHourMinimumDigits(locale: Locale, use24HourTime: Boolean): Int =
    localizedTimePatternRuns(locale, use24HourTime)
        .firstOrNull { it.symbol == 'H' || it.symbol == 'h' || it.symbol == 'K' || it.symbol == 'k' }
        ?.length
        ?.coerceIn(1, 2)
        ?: 1

internal fun localizedTimeSeparator(locale: Locale, use24HourTime: Boolean): String {
    val pattern = localizedTimePattern(locale, use24HourTime)
    val runs = timePatternRuns(pattern)
    val hour = runs.firstOrNull {
        it.symbol == 'H' || it.symbol == 'h' || it.symbol == 'K' || it.symbol == 'k'
    } ?: return ":"
    val minute = runs.firstOrNull { it.symbol == 'm' && it.start > hour.endExclusive } ?: return ":"
    return pattern.substring(hour.endExclusive, minute.start)
        .replace("'", "")
        .ifEmpty { ":" }
}

private fun localizedTimePattern(locale: Locale, use24HourTime: Boolean): String =
    DateFormat.getBestDateTimePattern(locale, if (use24HourTime) "Hm" else "hm")

private fun localizedTimePatternRuns(
    locale: Locale,
    use24HourTime: Boolean,
): List<TimePatternRun> = timePatternRuns(localizedTimePattern(locale, use24HourTime))

private fun timePatternRuns(pattern: String): List<TimePatternRun> {
    val runs = mutableListOf<TimePatternRun>()
    var index = 0
    var quoted = false
    while (index < pattern.length) {
        val symbol = pattern[index]
        if (symbol == '\'') {
            if (index + 1 < pattern.length && pattern[index + 1] == '\'') {
                index += 2
            } else {
                quoted = !quoted
                index++
            }
            continue
        }
        if (quoted || !symbol.isLetter()) {
            index++
            continue
        }
        var end = index + 1
        while (end < pattern.length && pattern[end] == symbol) end++
        runs += TimePatternRun(symbol, index, end)
        index = end
    }
    return runs
}

private data class TimePatternRun(
    val symbol: Char,
    val start: Int,
    val endExclusive: Int,
) {
    val length: Int get() = endExclusive - start
}

private fun hasPostNotificationsPermission(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
    return ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.POST_NOTIFICATIONS,
    ) == PackageManager.PERMISSION_GRANTED
}

private fun openExactAlarmSettings(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
    val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).apply {
        data = Uri.parse("package:${context.packageName}")
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
    runCatching {
        context.startActivity(intent)
    }.onFailure {
        val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(fallbackIntent)
    }
}

private fun openNotificationSettings(context: Context) {
    val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
        putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }

    runCatching {
        context.startActivity(intent)
    }.onFailure {
        val fallbackIntent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
            data = Uri.parse("package:${context.packageName}")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(fallbackIntent)
    }
}
