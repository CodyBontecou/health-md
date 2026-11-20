package com.healthmd.presentation.schedule

import android.Manifest
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.core.app.NotificationManagerCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.healthmd.R
import com.healthmd.data.health.HealthConnectFeatureAvailability
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.tryLaunchHealthConnectPermissions
import com.healthmd.presentation.common.ConfigurationProtectedRegion
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.util.runCatchingCancellable

/** Which scheduling readiness warnings a schedule page shows. */
internal data class ScheduleWarnings(
    val exactTiming: Boolean,
    val backgroundRead: Boolean,
    val notifications: Boolean,
) {
    companion object {
        val None = ScheduleWarnings(exactTiming = false, backgroundRead = false, notifications = false)
    }
}

/**
 * The visibility rule shared by Schedule settings (app-wide schedule) and an automation's
 * Schedule page: a warning shows only while that schedule is enabled and the capability it
 * needs is missing.
 */
internal fun scheduleWarnings(
    scheduleEnabled: Boolean,
    exactTimingAvailable: Boolean,
    backgroundReadFeatureAvailable: Boolean,
    backgroundReadReady: Boolean,
    notificationsReady: Boolean,
): ScheduleWarnings {
    if (!scheduleEnabled) return ScheduleWarnings.None
    return ScheduleWarnings(
        exactTiming = !exactTimingAvailable,
        backgroundRead = backgroundReadFeatureAvailable && !backgroundReadReady,
        notifications = !notificationsReady,
    )
}

/**
 * The exact-timing, background-read and notification warning cards. Emits into the caller's
 * layout so it keeps the caller's spacing.
 *
 * @param canRequestNotificationsInApp true when the runtime POST_NOTIFICATIONS prompt can
 *   still be shown (Android 13+ and not yet granted); otherwise the card opens settings.
 */
@Composable
internal fun ScheduleWarningCards(
    warnings: ScheduleWarnings,
    canRequestNotificationsInApp: Boolean,
    onAllowExactTiming: () -> Unit,
    onAllowBackgroundRead: () -> Unit,
    onRequestNotifications: () -> Unit,
    onOpenNotificationSettings: () -> Unit,
) {
    if (warnings.exactTiming) {
        ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
            WarningCard(
                title = stringResource(R.string.exact_timing_needed_title),
                body = stringResource(R.string.exact_timing_needed_body),
                action = stringResource(R.string.exact_timing_enable_button),
                onAction = onAllowExactTiming,
            )
        }
    }

    if (warnings.backgroundRead) {
        ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
            WarningCard(
                title = stringResource(R.string.background_health_permission_needed_title),
                body = stringResource(R.string.background_health_permission_needed_body),
                action = stringResource(R.string.background_health_permission_enable_button),
                onAction = onAllowBackgroundRead,
            )
        }
    }

    if (warnings.notifications) {
        ConfigurationProtectedRegion(modifier = Modifier.fillMaxWidth()) {
            WarningCard(
                title = stringResource(R.string.notifications_needed_title),
                body = stringResource(R.string.notifications_needed_body),
                action = if (canRequestNotificationsInApp) {
                    stringResource(R.string.notifications_enable_button)
                } else {
                    stringResource(R.string.notifications_open_settings_button)
                },
                secondaryAction = if (canRequestNotificationsInApp) {
                    stringResource(R.string.notifications_open_settings_button)
                } else {
                    null
                },
                onAction = {
                    if (canRequestNotificationsInApp) onRequestNotifications() else onOpenNotificationSettings()
                },
                onSecondaryAction = onOpenNotificationSettings,
            )
        }
    }
}

/**
 * The warning cards for an automation's schedule. Readiness is re-read on resume, so the
 * cards clear after the user grants access in system settings. Unlike Schedule settings, this
 * page never prompts on its own; the cards are the entry point.
 */
@Composable
internal fun AutomationScheduleWarningCards(
    scheduleEnabled: Boolean,
    exactTimingAvailable: Boolean,
    requiresHealthConnectBackgroundAccess: Boolean,
    onRefreshSchedulingState: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val healthConnectManager = remember { HealthConnectManager(context) }

    var notificationsGranted by remember { mutableStateOf(hasPostNotificationsPermission(context)) }
    var notificationsEnabled by remember {
        mutableStateOf(NotificationManagerCompat.from(context).areNotificationsEnabled())
    }
    var backgroundReadFeatureAvailable by remember { mutableStateOf(false) }
    var backgroundReadReady by remember { mutableStateOf(true) }
    var backgroundReadPermissions by remember { mutableStateOf<Set<String>>(emptySet()) }
    var refreshTick by remember { mutableStateOf(0) }

    LaunchedEffect(requiresHealthConnectBackgroundAccess, refreshTick) {
        if (!requiresHealthConnectBackgroundAccess) {
            backgroundReadFeatureAvailable = false
            backgroundReadReady = true
            return@LaunchedEffect
        }
        val plan = healthConnectManager.permissionPlan()
        backgroundReadPermissions = plan.backgroundReadPermissions
        backgroundReadFeatureAvailable =
            plan.backgroundReadAvailability == HealthConnectFeatureAvailability.AVAILABLE
        if (backgroundReadFeatureAvailable) {
            backgroundReadReady = runCatchingCancellable { healthConnectManager.hasBackgroundReadPermission() }
                .getOrDefault(false)
        }
    }

    DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                notificationsGranted = hasPostNotificationsPermission(context)
                notificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
                refreshTick++
                onRefreshSchedulingState()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { granted -> notificationsGranted = granted }
    val healthPermissionContract = remember { healthConnectManager.getPermissionContract() }
    val healthPermissionLauncher = rememberLauncherForActivityResult(contract = healthPermissionContract) {
        refreshTick++
    }

    val warnings = scheduleWarnings(
        scheduleEnabled = scheduleEnabled,
        exactTimingAvailable = exactTimingAvailable,
        backgroundReadFeatureAvailable = backgroundReadFeatureAvailable,
        backgroundReadReady = backgroundReadReady,
        notificationsReady = notificationsGranted && notificationsEnabled,
    )
    if (warnings == ScheduleWarnings.None) return
    Column(modifier = modifier, verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
        ScheduleWarningCards(
            warnings = warnings,
            canRequestNotificationsInApp = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notificationsGranted,
            onAllowExactTiming = { openExactAlarmSettings(context) },
            onAllowBackgroundRead = {
                tryLaunchHealthConnectPermissions(backgroundReadPermissions) { healthPermissionLauncher.launch(it) }
            },
            onRequestNotifications = { notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS) },
            onOpenNotificationSettings = { openNotificationSettings(context) },
        )
    }
}
