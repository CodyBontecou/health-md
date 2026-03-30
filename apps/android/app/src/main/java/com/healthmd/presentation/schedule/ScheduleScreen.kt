package com.healthmd.presentation.schedule

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Remove
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.outlined.Schedule
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
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.presentation.common.GlassBadge
import com.healthmd.presentation.common.GlassCard
import com.healthmd.presentation.common.GlassIconButton
import com.healthmd.presentation.common.GlassIconCircle
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

@Composable
fun ScheduleScreen(
    viewModel: ScheduleViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current

    var notificationsGranted by remember {
        mutableStateOf(hasPostNotificationsPermission(context))
    }
    val notificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
    val notificationsReady = notificationsGranted && notificationsEnabled
    var hasPromptedForNotifications by rememberSaveable { mutableStateOf(false) }

    val notificationPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestPermission(),
    ) { granted ->
        notificationsGranted = granted
    }

    DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                notificationsGranted = hasPostNotificationsPermission(context)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    LaunchedEffect(uiState.isEnabled) {
        if (
            uiState.isEnabled &&
            !notificationsGranted &&
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            !hasPromptedForNotifications
        ) {
            hasPromptedForNotifications = true
            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Spacer(modifier = Modifier.height(Spacing.xl))

        SectionLabel(stringResource(R.string.section_schedule))

        Box(contentAlignment = Alignment.Center) {
            if (uiState.isEnabled) {
                Box(
                    modifier = Modifier
                        .size(120.dp)
                        .clip(CircleShape)
                        .background(AppColors.accent.copy(alpha = 0.15f)),
                )
            }
            GlassIconCircle(size = 100.dp) {
                Icon(
                    if (uiState.isEnabled) Icons.Filled.Schedule else Icons.Outlined.Schedule,
                    contentDescription = null,
                    tint = if (uiState.isEnabled) AppColors.accent else AppColors.textMuted,
                    modifier = Modifier.size(56.dp),
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.sm))

        Text(
            text = if (uiState.isEnabled) stringResource(R.string.schedule_active) else stringResource(R.string.schedule_not_set),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            letterSpacing = 3.sp,
            lineHeight = 36.sp,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        GlassCard {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column {
                    Text(stringResource(R.string.automatic_export_title), color = AppColors.textPrimary, style = MaterialTheme.typography.titleMedium)
                    Text(
                        stringResource(R.string.automatic_export_subtitle),
                        color = AppColors.textSecondary,
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                Switch(
                    checked = uiState.isEnabled,
                    onCheckedChange = { enabled ->
                        viewModel.toggleSchedule(enabled)
                        if (
                            enabled &&
                            !notificationsGranted &&
                            Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
                        ) {
                            hasPromptedForNotifications = true
                            notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                        }
                    },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = androidx.compose.ui.graphics.Color.White,
                        checkedTrackColor = AppColors.accent,
                        uncheckedThumbColor = AppColors.textMuted,
                        uncheckedTrackColor = AppColors.bgSecondary,
                        uncheckedBorderColor = AppColors.borderDefault,
                    ),
                )
            }
        }

        if (uiState.isEnabled) {
            GlassCard {
                SectionLabel(stringResource(R.string.section_cadence))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.Center,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    GlassIconButton(
                        icon = Icons.Filled.Remove,
                        onClick = { viewModel.setCadenceValue(uiState.cadenceValue - 1) },
                    )
                    Text(
                        text = uiState.cadenceValue.toString(),
                        style = MaterialTheme.typography.headlineMedium,
                        color = AppColors.textPrimary,
                        fontWeight = FontWeight.Bold,
                        modifier = Modifier.padding(horizontal = Spacing.md),
                    )
                    GlassIconButton(
                        icon = Icons.Filled.Add,
                        onClick = { viewModel.setCadenceValue(uiState.cadenceValue + 1) },
                    )
                }

                Spacer(modifier = Modifier.height(Spacing.sm))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    listOf(
                        ScheduleCadenceUnit.MINUTES to stringResource(R.string.cadence_unit_minutes),
                        ScheduleCadenceUnit.HOURS to stringResource(R.string.cadence_unit_hours),
                        ScheduleCadenceUnit.DAYS to stringResource(R.string.cadence_unit_days),
                        ScheduleCadenceUnit.WEEKS to stringResource(R.string.cadence_unit_weeks),
                    ).forEach { (unit, label) ->
                        val selected = uiState.cadenceUnit == unit
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
                                .clickable { viewModel.setCadenceUnit(unit) }
                                .padding(vertical = 12.dp),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                label,
                                color = if (selected) AppColors.accent else AppColors.textSecondary,
                                style = MaterialTheme.typography.labelLarge,
                                fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                            )
                        }
                    }
                }

                if (uiState.cadenceUnit == ScheduleCadenceUnit.MINUTES) {
                    Spacer(modifier = Modifier.height(Spacing.sm))
                    Text(
                        stringResource(R.string.cadence_minutes_minimum),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                }
            }

            if (uiState.cadenceUnit == ScheduleCadenceUnit.DAYS || uiState.cadenceUnit == ScheduleCadenceUnit.WEEKS) {
                GlassCard {
                    SectionLabel(stringResource(R.string.section_export_time))
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Column(
                            modifier = Modifier.weight(1f),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(stringResource(R.string.label_hour), style = MaterialTheme.typography.labelSmall, color = AppColors.textMuted)
                            Spacer(modifier = Modifier.height(4.dp))
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.Center,
                            ) {
                                GlassIconButton(
                                    icon = Icons.Filled.Remove,
                                    onClick = { viewModel.setHour((uiState.hour - 1 + 24) % 24) },
                                )
                                Text(
                                    String.format("%02d", uiState.hour),
                                    style = MaterialTheme.typography.headlineMedium,
                                    color = AppColors.textPrimary,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.padding(horizontal = Spacing.sm),
                                )
                                GlassIconButton(
                                    icon = Icons.Filled.Add,
                                    onClick = { viewModel.setHour((uiState.hour + 1) % 24) },
                                )
                            }
                        }

                        Text(":", style = MaterialTheme.typography.headlineMedium, color = AppColors.textMuted)

                        Column(
                            modifier = Modifier.weight(1f),
                            horizontalAlignment = Alignment.CenterHorizontally,
                        ) {
                            Text(stringResource(R.string.label_minute), style = MaterialTheme.typography.labelSmall, color = AppColors.textMuted)
                            Spacer(modifier = Modifier.height(4.dp))
                            Row(
                                verticalAlignment = Alignment.CenterVertically,
                                horizontalArrangement = Arrangement.Center,
                            ) {
                                GlassIconButton(
                                    icon = Icons.Filled.Remove,
                                    onClick = { viewModel.setMinute((uiState.minute - 1 + 60) % 60) },
                                )
                                Text(
                                    String.format("%02d", uiState.minute),
                                    style = MaterialTheme.typography.headlineMedium,
                                    color = AppColors.textPrimary,
                                    fontWeight = FontWeight.Bold,
                                    modifier = Modifier.padding(horizontal = Spacing.sm),
                                )
                                GlassIconButton(
                                    icon = Icons.Filled.Add,
                                    onClick = { viewModel.setMinute((uiState.minute + 1) % 60) },
                                )
                            }
                        }
                    }
                }
            }

            if (uiState.nextExportDescription.isNotEmpty()) {
                GlassBadge(borderColor = AppColors.accent.copy(alpha = 0.3f)) {
                    Text(
                        uiState.nextExportDescription,
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textSecondary,
                    )
                }
            }

            if (!notificationsReady) {
                GlassCard(padding = Spacing.md) {
                    Text(
                        stringResource(R.string.notifications_needed_title),
                        style = MaterialTheme.typography.titleSmall,
                        color = AppColors.warning,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Spacer(modifier = Modifier.height(Spacing.xs))
                    Text(
                        stringResource(R.string.notifications_needed_body),
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.textMuted,
                    )
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.End,
                    ) {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU && !notificationsGranted) {
                            TextButton(onClick = {
                                hasPromptedForNotifications = true
                                notificationPermissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                            }) {
                                Text(stringResource(R.string.notifications_enable_button))
                            }
                        }
                        TextButton(onClick = { openNotificationSettings(context) }) {
                            Text(stringResource(R.string.notifications_open_settings_button))
                        }
                    }
                }
            }

            GlassCard(padding = Spacing.md) {
                Text(
                    stringResource(R.string.schedule_workmanager_notice),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
    }
}

data class ScheduleUiState(
    val isEnabled: Boolean = false,
    val cadenceValue: Int = 1,
    val cadenceUnit: ScheduleCadenceUnit = ScheduleCadenceUnit.DAYS,
    val hour: Int = 6,
    val minute: Int = 0,
    val nextExportDescription: String = "",
)

private fun hasPostNotificationsPermission(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
    return ContextCompat.checkSelfPermission(
        context,
        Manifest.permission.POST_NOTIFICATIONS,
    ) == PackageManager.PERMISSION_GRANTED
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
