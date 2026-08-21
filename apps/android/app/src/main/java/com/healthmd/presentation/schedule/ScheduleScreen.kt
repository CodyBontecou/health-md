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
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
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
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
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
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.presentation.common.APIExportSettingsDialog
import com.healthmd.presentation.common.ConfigurationProtectedRegion
import com.healthmd.presentation.common.ExportTargetSelector
import com.healthmd.presentation.common.HealthConnectActionError
import com.healthmd.presentation.common.HealthConnectErrorNotice
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.history.HistoryViewModel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing
import com.healthmd.util.runCatchingCancellable
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import java.text.DateFormatSymbols
import java.text.NumberFormat
import java.text.ParsePosition
import java.util.Date
import java.util.Locale

@Composable
fun ScheduleScreen(
    viewModel: ScheduleViewModel = hiltViewModel(),
    onNavigateToPaywall: () -> Unit = {},
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val historyViewModel: HistoryViewModel = hiltViewModel()
    val historyUiState by historyViewModel.uiState.collectAsStateWithLifecycle()
    val profileSchedulesViewModel: ProfileSchedulesViewModel = hiltViewModel()
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
        AlertDialog(
            onDismissRequest = { historyViewModel.dismissClearHistory() },
            title = { Text(stringResource(R.string.history_clear_title)) },
            text = { Text(stringResource(R.string.history_clear_body)) },
            confirmButton = {
                TextButton(onClick = {
                    if (protection.enabled) {
                        historyViewModel.dismissClearHistory()
                        protection.onBlockedChange()
                    } else {
                        historyViewModel.clearHistory()
                    }
                }) {
                    Text(stringResource(R.string.action_clear_history))
                }
            },
            dismissButton = {
                TextButton(onClick = { historyViewModel.dismissClearHistory() }) {
                    Text(stringResource(R.string.action_keep_history))
                }
            },
        )
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Spacer(modifier = Modifier.height(Spacing.md))

        Text(
            text = stringResource(R.string.section_schedule),
            style = MaterialTheme.typography.headlineMedium,
            color = AppColors.textPrimary,
            modifier = Modifier.fillMaxWidth(),
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        ProfileSchedulesSection(viewModel = profileSchedulesViewModel)

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
        ExportTargetSelector(
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
            driveSubtitle = when {
                !uiState.googleDriveConfigurationAvailable -> stringResource(R.string.google_drive_configuration_missing)
                uiState.googleDriveConfigured -> stringResource(R.string.google_drive_target_ready_generic)
                else -> stringResource(R.string.google_drive_target_not_connected)
            },
            onTargetSelected = { target ->
                attemptConfigurationChange {
                    viewModel.setScheduledExportTarget(target)
                    if (target == ExportTarget.API_ENDPOINT && !uiState.apiEndpointConfigured) {
                        showAPISettings = true
                    }
                }
            },
        )

        if (uiState.selectedTarget == ExportTarget.API_ENDPOINT) {
            TextButton(onClick = {
                attemptConfigurationChange { showAPISettings = true }
            }) {
                Text(
                    stringResource(
                        if (uiState.apiEndpointConfigured) {
                            R.string.action_edit_endpoint
                        } else {
                            R.string.action_configure_endpoint
                        },
                    ),
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

        if (!uiState.isPurchased) {
            WarningCard(
                title = stringResource(R.string.schedule_unlock_required_title),
                body = stringResource(R.string.schedule_unlock_required_body),
                action = stringResource(R.string.unlock_button),
                onAction = onNavigateToPaywall,
            )
        }

        if (uiState.isEnabled) {
            Spacer(modifier = Modifier.height(Spacing.xs))

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

            Spacer(modifier = Modifier.height(Spacing.sm))

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.section_export_history),
                    style = MaterialTheme.typography.titleMedium,
                    color = AppColors.textSecondary,
                    fontWeight = FontWeight.Medium,
                )
                ConfigurationProtectedRegion {
                    Text(
                        text = stringResource(R.string.action_clear_history),
                        style = MaterialTheme.typography.titleSmall,
                        color = AppColors.textMuted,
                        modifier = Modifier
                            .clip(RoundedCornerShape(Radii.card))
                            .clickable {
                                attemptConfigurationChange { historyViewModel.requestClearHistory() }
                            }
                            .padding(horizontal = Spacing.xs, vertical = Spacing.xxs),
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
    }

    if (showAPISettings) {
        APIExportSettingsDialog(
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
}

@Composable
private fun ScheduleSectionLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.titleMedium,
        color = AppColors.textSecondary,
        fontWeight = FontWeight.Normal,
        modifier = Modifier.fillMaxWidth(),
    )
}

@Composable
private fun BodyText(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyLarge,
        color = AppColors.textSecondary,
        modifier = modifier,
    )
}

@Composable
private fun ScheduleToggleCard(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val shape = RoundedCornerShape(Radii.card)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppColors.bgPrimary)
            .border(1.dp, AppColors.borderDefault, shape)
            .toggleable(
                value = checked,
                role = Role.Switch,
                onValueChange = onCheckedChange,
            )
            .padding(Spacing.md),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.schedule_enable_scheduled_exports),
            style = MaterialTheme.typography.titleMedium,
            color = AppColors.textPrimary,
            modifier = Modifier.weight(1f),
        )
        GeistSwitch(checked = checked)
    }
}

@Composable
private fun GeistSwitch(
    checked: Boolean,
) {
    Switch(
        checked = checked,
        onCheckedChange = null,
        colors = SwitchDefaults.colors(
            checkedThumbColor = AppColors.onAccent,
            checkedTrackColor = AppColors.accent,
            checkedBorderColor = AppColors.accent,
            uncheckedThumbColor = AppColors.textSecondary,
            uncheckedTrackColor = AppColors.bgPrimary,
            uncheckedBorderColor = AppColors.borderStrong,
        ),
    )
}

@Composable
private fun ScheduleSettingsCard(
    uiState: ScheduleUiState,
    onFrequencyValueChange: (Int) -> Unit,
    onFrequencyUnitSelected: (ScheduleCadenceUnit) -> Unit,
    onHourDelta: (Int) -> Unit,
    onMinuteDelta: (Int) -> Unit,
    onTogglePeriod: () -> Unit,
    onDateWindowSelected: (ScheduleDateWindow) -> Unit,
    onLookbackDelta: (Int) -> Unit,
) {
    val shape = RoundedCornerShape(Radii.card)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppColors.bgPrimary)
            .border(1.dp, AppColors.borderDefault, shape)
            .padding(Spacing.md),
    ) {
        FrequencyRow(
            value = uiState.cadenceValue,
            unit = uiState.cadenceUnit,
            onValueChange = onFrequencyValueChange,
            onUnitSelected = onFrequencyUnitSelected,
        )

        ScheduleDivider()

        DateWindowRow(
            dateWindow = uiState.dateWindow,
            onDateWindowSelected = onDateWindowSelected,
        )

        if (uiState.cadenceUnit == ScheduleCadenceUnit.DAYS || uiState.cadenceUnit == ScheduleCadenceUnit.WEEKS) {
            ScheduleDivider()

            Text(
                text = stringResource(R.string.schedule_time),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
            )

            Spacer(modifier = Modifier.height(Spacing.sm))

            TimeRow(
                hour = uiState.hour,
                minute = uiState.minute,
                onHourDelta = onHourDelta,
                onMinuteDelta = onMinuteDelta,
                onTogglePeriod = onTogglePeriod,
            )
        }

        if (uiState.dateWindow == ScheduleDateWindow.PAST_COMPLETE_DAYS) {
            ScheduleDivider()

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = stringResource(R.string.schedule_export_past_days),
                    style = MaterialTheme.typography.titleLarge,
                    color = AppColors.textPrimary,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Text(
                        text = localizedInteger(uiState.lookbackDays),
                        style = MaterialTheme.typography.titleLarge,
                        color = AppColors.textSecondary,
                    )
                    SegmentedStepper(
                        onDecrease = { onLookbackDelta(-1) },
                        onIncrease = { onLookbackDelta(1) },
                        decreaseDescription = stringResource(R.string.schedule_decrease_lookback_days),
                        increaseDescription = stringResource(R.string.schedule_increase_lookback_days),
                    )
                }
            }
        }
    }
}

@Composable
private fun DateWindowRow(
    dateWindow: ScheduleDateWindow,
    onDateWindowSelected: (ScheduleDateWindow) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val options = listOf(
        DateWindowOption(
            value = ScheduleDateWindow.PAST_COMPLETE_DAYS,
            label = stringResource(R.string.schedule_date_window_past_complete_days),
        ),
        DateWindowOption(
            value = ScheduleDateWindow.TODAY,
            label = stringResource(R.string.schedule_date_window_today),
        ),
    )
    val selectedLabel = options.firstOrNull { it.value == dateWindow }?.label.orEmpty()

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.schedule_date_window),
            style = MaterialTheme.typography.titleLarge,
            color = AppColors.textPrimary,
        )
        Box(modifier = Modifier.wrapContentSize(Alignment.TopEnd)) {
            Row(
                modifier = Modifier
                    .clip(RoundedCornerShape(Radii.card))
                    .clickable { expanded = true }
                    .padding(horizontal = Spacing.xxs, vertical = Spacing.xxs),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = selectedLabel,
                    style = MaterialTheme.typography.titleLarge,
                    color = AppColors.accentHover,
                )
                Spacer(modifier = Modifier.width(Spacing.xxs))
                Column {
                    Icon(Icons.Filled.KeyboardArrowUp, contentDescription = null, tint = AppColors.accentHover, modifier = Modifier.size(18.dp))
                    Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = AppColors.accentHover, modifier = Modifier.size(18.dp))
                }
            }
            DropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
            ) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option.label) },
                        onClick = {
                            expanded = false
                            onDateWindowSelected(option.value)
                        },
                    )
                }
            }
        }
    }
}

@Composable
private fun FrequencyRow(
    value: Int,
    unit: ScheduleCadenceUnit,
    onValueChange: (Int) -> Unit,
    onUnitSelected: (ScheduleCadenceUnit) -> Unit,
) {
    Column(modifier = Modifier.fillMaxWidth()) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = stringResource(R.string.schedule_frequency),
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.textPrimary,
            )
            Row(
                horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                FrequencyValueField(
                    value = value,
                    unit = unit,
                    onValueChange = onValueChange,
                )
                FrequencyUnitDropdown(
                    value = value,
                    unit = unit,
                    onUnitSelected = onUnitSelected,
                )
            }
        }

        if (unit == ScheduleCadenceUnit.MINUTES) {
            Spacer(modifier = Modifier.height(Spacing.xs))
            Text(
                text = stringResource(R.string.cadence_minutes_minimum),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
                textAlign = TextAlign.End,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun FrequencyValueField(
    value: Int,
    unit: ScheduleCadenceUnit,
    onValueChange: (Int) -> Unit,
) {
    val locale = LocalConfiguration.current.locales[0]
    var text by rememberSaveable(locale) { mutableStateOf(formatInteger(value, locale)) }
    var isFocused by remember { mutableStateOf(false) }
    val minimumValue = minimumCadenceValue(unit)

    LaunchedEffect(value, unit, isFocused) {
        if (!isFocused) {
            text = formatInteger(value, locale)
        }
    }

    fun commitValue() {
        val committed = parseLocalizedInteger(text, locale)?.coerceAtLeast(minimumValue) ?: minimumValue
        text = formatInteger(committed, locale)
        onValueChange(committed)
    }

    Box(
        modifier = Modifier
            .width(76.dp)
            .height(48.dp)
            .clip(RoundedCornerShape(Radii.card))
            .background(AppColors.bgPrimary)
            .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card))
            .padding(horizontal = Spacing.xs),
        contentAlignment = Alignment.Center,
    ) {
        BasicTextField(
            value = text,
            onValueChange = { raw ->
                val digits = raw.filter { it.isDigit() }.take(MAX_FREQUENCY_DIGITS)
                text = digits
                parseLocalizedInteger(digits, locale)
                    ?.takeIf { it >= minimumValue }
                    ?.let(onValueChange)
            },
            singleLine = true,
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
            textStyle = MaterialTheme.typography.titleLarge.copy(
                color = AppColors.textPrimary,
                textAlign = TextAlign.Center,
            ),
            modifier = Modifier
                .fillMaxWidth()
                .onFocusChanged { focusState ->
                    val wasFocused = isFocused
                    isFocused = focusState.isFocused
                    if (wasFocused && !focusState.isFocused) {
                        commitValue()
                    }
                },
        )
    }
}

@Composable
private fun FrequencyUnitDropdown(
    value: Int,
    unit: ScheduleCadenceUnit,
    onUnitSelected: (ScheduleCadenceUnit) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val options = listOf(
        ScheduleCadenceUnit.MINUTES to pluralStringResource(
            R.plurals.schedule_cadence_unit_minutes,
            value,
        ),
        ScheduleCadenceUnit.HOURS to pluralStringResource(
            R.plurals.schedule_cadence_unit_hours,
            value,
        ),
        ScheduleCadenceUnit.DAYS to pluralStringResource(
            R.plurals.schedule_cadence_unit_days,
            value,
        ),
        ScheduleCadenceUnit.WEEKS to pluralStringResource(
            R.plurals.schedule_cadence_unit_weeks,
            value,
        ),
    )
    val selectedLabel = options.firstOrNull { it.first == unit }?.second.orEmpty()

    Box(modifier = Modifier.wrapContentSize(Alignment.TopEnd)) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(Radii.card))
                .clickable { expanded = true }
                .padding(horizontal = Spacing.xxs, vertical = Spacing.xxs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = selectedLabel,
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.accentHover,
            )
            Spacer(modifier = Modifier.width(Spacing.xxs))
            Column {
                Icon(Icons.Filled.KeyboardArrowUp, contentDescription = null, tint = AppColors.accentHover, modifier = Modifier.size(18.dp))
                Icon(Icons.Filled.KeyboardArrowDown, contentDescription = null, tint = AppColors.accentHover, modifier = Modifier.size(18.dp))
            }
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            options.forEach { (option, label) ->
                DropdownMenuItem(
                    text = { Text(label) },
                    onClick = {
                        expanded = false
                        onUnitSelected(option)
                    },
                )
            }
        }
    }
}

private fun minimumCadenceValue(unit: ScheduleCadenceUnit): Int = when (unit) {
    ScheduleCadenceUnit.MINUTES -> 15
    ScheduleCadenceUnit.HOURS,
    ScheduleCadenceUnit.DAYS,
    ScheduleCadenceUnit.WEEKS -> 1
}

@Composable
private fun TimeRow(
    hour: Int,
    minute: Int,
    onHourDelta: (Int) -> Unit,
    onMinuteDelta: (Int) -> Unit,
    onTogglePeriod: () -> Unit,
) {
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    val use24HourTime = DateFormat.is24HourFormat(context)
    val hourCycle = localizedHourCycle(locale, use24HourTime)
    val displayHour = localizedDisplayHour(hour, hourCycle)
    val period = DateFormatSymbols.getInstance(locale).amPmStrings[if (hour < 12) 0 else 1]
    val periodPrecedesTime = !use24HourTime && localizedDayPeriodPrecedesHour(locale)
    val hourFormat = remember(locale, use24HourTime) {
        NumberFormat.getIntegerInstance(locale).apply {
            isGroupingUsed = false
            minimumIntegerDigits = localizedHourMinimumDigits(locale, use24HourTime)
        }
    }
    val minuteFormat = remember(locale) {
        NumberFormat.getIntegerInstance(locale).apply {
            isGroupingUsed = false
            minimumIntegerDigits = 2
        }
    }

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (periodPrecedesTime) {
            PickerPill(
                label = period,
                onIncrement = onTogglePeriod,
                onDecrement = onTogglePeriod,
                incrementDescription = stringResource(R.string.schedule_toggle_time_period),
                decrementDescription = stringResource(R.string.schedule_toggle_time_period),
                modifier = Modifier.weight(1f),
            )
        }
        PickerPill(
            label = hourFormat.format(displayHour),
            onIncrement = { onHourDelta(1) },
            onDecrement = { onHourDelta(-1) },
            incrementDescription = stringResource(R.string.schedule_increase_hour),
            decrementDescription = stringResource(R.string.schedule_decrease_hour),
            modifier = Modifier.weight(1f),
        )
        Text(
            text = localizedTimeSeparator(locale, use24HourTime),
            style = MaterialTheme.typography.headlineMedium,
            color = AppColors.textSecondary,
        )
        PickerPill(
            label = minuteFormat.format(minute),
            onIncrement = { onMinuteDelta(1) },
            onDecrement = { onMinuteDelta(-1) },
            incrementDescription = stringResource(R.string.schedule_increase_minute),
            decrementDescription = stringResource(R.string.schedule_decrease_minute),
            modifier = Modifier.weight(1f),
        )
        if (!use24HourTime && !periodPrecedesTime) {
            PickerPill(
                label = period,
                onIncrement = onTogglePeriod,
                onDecrement = onTogglePeriod,
                incrementDescription = stringResource(R.string.schedule_toggle_time_period),
                decrementDescription = stringResource(R.string.schedule_toggle_time_period),
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun PickerPill(
    label: String,
    onIncrement: () -> Unit,
    onDecrement: () -> Unit,
    incrementDescription: String,
    decrementDescription: String,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(Radii.card)
    Row(
        modifier = modifier
            .height(48.dp)
            .clip(shape)
            .background(AppColors.bgPrimary)
            .border(1.dp, AppColors.borderDefault, shape)
            .padding(horizontal = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.titleLarge,
            color = AppColors.textPrimary,
        )
        Spacer(modifier = Modifier.width(Spacing.xxs))
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                Icons.Filled.KeyboardArrowUp,
                contentDescription = incrementDescription,
                tint = AppColors.accentHover,
                modifier = Modifier
                    .size(20.dp)
                    .clickable { onIncrement() },
            )
            Icon(
                Icons.Filled.KeyboardArrowDown,
                contentDescription = decrementDescription,
                tint = AppColors.accentHover,
                modifier = Modifier
                    .size(20.dp)
                    .clickable { onDecrement() },
            )
        }
    }
}

@Composable
private fun SegmentedStepper(
    onDecrease: () -> Unit,
    onIncrease: () -> Unit,
    decreaseDescription: String,
    increaseDescription: String,
) {
    val shape = RoundedCornerShape(Radii.card)
    Row(
        modifier = Modifier
            .height(48.dp)
            .clip(shape)
            .background(AppColors.bgPrimary)
            .border(1.dp, AppColors.borderDefault, shape),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepperIcon(Icons.Filled.Remove, decreaseDescription, onDecrease)
        Box(
            modifier = Modifier
                .width(1.dp)
                .height(32.dp)
                .background(AppColors.borderDefault),
        )
        StepperIcon(Icons.Filled.Add, increaseDescription, onIncrease)
    }
}

@Composable
private fun StepperIcon(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    contentDescription: String,
    onClick: () -> Unit,
) {
    Box(
        modifier = Modifier
            .width(48.dp)
            .height(48.dp)
            .clickable { onClick() },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = contentDescription,
            tint = AppColors.textPrimary,
            modifier = Modifier.size(24.dp),
        )
    }
}

@Composable
private fun ScheduleDivider() {
    Spacer(modifier = Modifier.height(Spacing.md))
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(AppColors.borderDefault),
    )
    Spacer(modifier = Modifier.height(Spacing.md))
}

@Composable
private fun WarningCard(
    title: String,
    body: String,
    action: String,
    onAction: () -> Unit,
    secondaryAction: String? = null,
    onSecondaryAction: (() -> Unit)? = null,
) {
    val shape = RoundedCornerShape(Radii.card)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppColors.bgPrimary)
            .border(1.dp, AppColors.warningBorder, shape)
            .padding(Spacing.md),
    ) {
        Text(
            title,
            style = MaterialTheme.typography.titleSmall,
            color = AppColors.warning,
            fontWeight = FontWeight.SemiBold,
        )
        Spacer(modifier = Modifier.height(Spacing.xs))
        Text(
            body,
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textMuted,
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
        ) {
            secondaryAction?.let { label ->
                TextButton(onClick = { onSecondaryAction?.invoke() }) {
                    Text(label)
                }
            }
            TextButton(onClick = onAction) {
                Text(action)
            }
        }
    }
}

@Composable
private fun ScheduleUiMessage.localizedText(): String = when (this) {
    is ScheduleUiMessage.Text -> stringResource(resourceId, *arguments.toTypedArray())
}

@Composable
private fun localizedInteger(value: Int): String =
    formatInteger(value, LocalConfiguration.current.locales[0])

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

private const val MAX_FREQUENCY_DIGITS = 5

private data class DateWindowOption(
    val value: ScheduleDateWindow,
    val label: String,
)

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
