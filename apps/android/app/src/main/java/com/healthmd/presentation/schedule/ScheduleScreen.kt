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
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
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
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentSize
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.presentation.history.HistoryViewModel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch
import java.util.Locale

@Composable
fun ScheduleScreen(
    viewModel: ScheduleViewModel = hiltViewModel(),
    onNavigateToPaywall: () -> Unit = {},
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val historyViewModel: HistoryViewModel = hiltViewModel()
    val historyUiState by historyViewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val coroutineScope = rememberCoroutineScope()
    val healthConnectManager = remember { HealthConnectManager(context) }

    var notificationsGranted by remember {
        mutableStateOf(hasPostNotificationsPermission(context))
    }
    val notificationsEnabled = NotificationManagerCompat.from(context).areNotificationsEnabled()
    val notificationsReady = notificationsGranted && notificationsEnabled
    var hasPromptedForNotifications by rememberSaveable { mutableStateOf(false) }

    var backgroundReadFeatureAvailable by remember { mutableStateOf(false) }
    var backgroundReadReady by remember { mutableStateOf(true) }
    var backgroundReadStateLoaded by remember { mutableStateOf(false) }
    var hasPromptedForBackgroundRead by rememberSaveable { mutableStateOf(false) }

    fun refreshBackgroundReadPermissionState() {
        backgroundReadFeatureAvailable = healthConnectManager.isBackgroundReadFeatureAvailable()
        coroutineScope.launch {
            backgroundReadReady = healthConnectManager.hasBackgroundReadPermission()
            backgroundReadStateLoaded = true
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
    ) {
        refreshBackgroundReadPermissionState()
    }

    DisposableEffect(lifecycleOwner, context) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                notificationsGranted = hasPostNotificationsPermission(context)
                refreshBackgroundReadPermissionState()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose {
            lifecycleOwner.lifecycle.removeObserver(observer)
        }
    }

    LaunchedEffect(Unit) {
        refreshBackgroundReadPermissionState()
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
            (!backgroundReadFeatureAvailable || backgroundReadReady) &&
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
            backgroundReadFeatureAvailable &&
            !backgroundReadReady &&
            !hasPromptedForBackgroundRead
        ) {
            hasPromptedForBackgroundRead = true
            healthPermissionLauncher.launch(healthConnectManager.backgroundReadPermissions)
        }
    }

    if (historyUiState.showClearConfirmation) {
        AlertDialog(
            onDismissRequest = { historyViewModel.dismissClearHistory() },
            title = { Text(stringResource(R.string.history_clear_title)) },
            text = { Text(stringResource(R.string.history_clear_body)) },
            confirmButton = {
                TextButton(onClick = { historyViewModel.clearHistory() }) {
                    Text(stringResource(R.string.clear))
                }
            },
            dismissButton = {
                TextButton(onClick = { historyViewModel.dismissClearHistory() }) {
                    Text(stringResource(R.string.cancel))
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
            style = MaterialTheme.typography.headlineSmall,
            color = AppColors.textPrimary,
            fontWeight = FontWeight.Bold,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        ScheduleSectionLabel(stringResource(R.string.automatic_export_title))

        ScheduleToggleCard(
            checked = uiState.isEnabled,
            onCheckedChange = { enabled -> viewModel.toggleSchedule(enabled) },
        )

        if (uiState.nextExportDescription.isNotEmpty()) {
            BodyText(
                text = uiState.nextExportDescription,
                modifier = Modifier.fillMaxWidth(),
            )
        }

        BodyText(
            text = stringResource(R.string.schedule_automatic_export_body),
            modifier = Modifier.fillMaxWidth(),
        )

        BodyText(
            text = stringResource(R.string.schedule_background_note),
            modifier = Modifier.fillMaxWidth(),
        )

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

            ScheduleSettingsCard(
                uiState = uiState,
                onFrequencyValueChange = { value -> viewModel.setCadenceValue(value) },
                onFrequencyUnitSelected = { unit -> viewModel.setCadenceUnit(unit) },
                onHourDelta = { delta -> viewModel.setHour((uiState.hour + delta + 24) % 24) },
                onMinuteDelta = { delta -> viewModel.setMinute((uiState.minute + delta + 60) % 60) },
                onTogglePeriod = {
                    val nextHour = if (uiState.hour < 12) uiState.hour + 12 else uiState.hour - 12
                    viewModel.setHour(nextHour)
                },
                onDateWindowSelected = { dateWindow -> viewModel.setDateWindow(dateWindow) },
                onLookbackDelta = { delta -> viewModel.setLookbackDays(uiState.lookbackDays + delta) },
            )

            BodyText(
                text = when (uiState.dateWindow) {
                    ScheduleDateWindow.PAST_COMPLETE_DAYS -> if (uiState.lookbackDays == 1) {
                        stringResource(R.string.schedule_lookback_ios_single)
                    } else {
                        stringResource(R.string.schedule_lookback_ios_plural, uiState.lookbackDays)
                    }
                    ScheduleDateWindow.TODAY -> stringResource(R.string.schedule_today_summary)
                },
                modifier = Modifier.fillMaxWidth(),
            )

            if (backgroundReadFeatureAvailable && !backgroundReadReady) {
                WarningCard(
                    title = stringResource(R.string.background_health_permission_needed_title),
                    body = stringResource(R.string.background_health_permission_needed_body),
                    action = stringResource(R.string.background_health_permission_enable_button),
                    onAction = {
                        hasPromptedForBackgroundRead = true
                        healthPermissionLauncher.launch(healthConnectManager.backgroundReadPermissions)
                    },
                )
            }

            if (!notificationsReady) {
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
                Text(
                    text = stringResource(R.string.clear),
                    style = MaterialTheme.typography.titleSmall,
                    color = AppColors.textMuted,
                    modifier = Modifier
                        .clip(RoundedCornerShape(8.dp))
                        .clickable { historyViewModel.requestClearHistory() }
                        .padding(horizontal = 8.dp, vertical = 4.dp),
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))
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
        lineHeight = 24.sp,
        modifier = modifier,
    )
}

@Composable
private fun ScheduleToggleCard(
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit,
) {
    val shape = RoundedCornerShape(28.dp)
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppColors.bgSecondary)
            .border(1.dp, AppColors.borderSubtle, shape)
            .clickable(role = Role.Switch) { onCheckedChange(!checked) }
            .padding(horizontal = Spacing.md, vertical = 18.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = stringResource(R.string.schedule_enable_scheduled_exports),
            style = MaterialTheme.typography.titleLarge,
            color = AppColors.textPrimary,
            fontWeight = FontWeight.Normal,
            modifier = Modifier.weight(1f),
        )
        IosStyleSwitch(checked = checked)
    }
}

@Composable
private fun IosStyleSwitch(
    checked: Boolean,
) {
    val trackWidth = 64.dp
    val trackHeight = 36.dp
    val thumbSize = 30.dp
    val thumbOffset by animateDpAsState(
        targetValue = if (checked) trackWidth - thumbSize - 3.dp else 3.dp,
        animationSpec = tween(durationMillis = 180),
        label = "switchThumbOffset",
    )

    Box(
        modifier = Modifier
            .width(trackWidth)
            .height(trackHeight)
            .clip(RoundedCornerShape(trackHeight / 2))
            .background(if (checked) AppColors.accent else AppColors.bgTertiary)
            .border(1.dp, Color.White.copy(alpha = if (checked) 0.12f else 0.18f), RoundedCornerShape(trackHeight / 2)),
        contentAlignment = Alignment.CenterStart,
    ) {
        Box(
            modifier = Modifier
                .offset(x = thumbOffset)
                .size(thumbSize)
                .shadow(2.dp, CircleShape, ambientColor = Color.Black.copy(alpha = 0.25f), spotColor = Color.Black.copy(alpha = 0.25f))
                .clip(CircleShape)
                .background(Color.White),
        )
    }
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
    val shape = RoundedCornerShape(28.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppColors.bgSecondary)
            .border(1.dp, AppColors.borderSubtle, shape)
            .padding(horizontal = Spacing.md, vertical = 18.dp),
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
                        text = uiState.lookbackDays.toString(),
                        style = MaterialTheme.typography.titleLarge,
                        color = AppColors.textSecondary,
                    )
                    SegmentedStepper(
                        onDecrease = { onLookbackDelta(-1) },
                        onIncrease = { onLookbackDelta(1) },
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
                    .clip(RoundedCornerShape(12.dp))
                    .clickable { expanded = true }
                    .padding(horizontal = 4.dp, vertical = 2.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = selectedLabel,
                    style = MaterialTheme.typography.titleLarge,
                    color = AppColors.accentHover,
                )
                Spacer(modifier = Modifier.width(2.dp))
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
    var text by rememberSaveable { mutableStateOf(value.toString()) }
    var isFocused by remember { mutableStateOf(false) }
    val minimumValue = minimumCadenceValue(unit)

    LaunchedEffect(value, unit, isFocused) {
        if (!isFocused) {
            text = value.toString()
        }
    }

    fun commitValue() {
        val committed = text.toIntOrNull()?.coerceAtLeast(minimumValue) ?: minimumValue
        text = committed.toString()
        onValueChange(committed)
    }

    Box(
        modifier = Modifier
            .width(76.dp)
            .height(48.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(Color.White.copy(alpha = 0.08f))
            .border(1.dp, Color.White.copy(alpha = 0.16f), RoundedCornerShape(14.dp))
            .padding(horizontal = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        BasicTextField(
            value = text,
            onValueChange = { raw ->
                val digits = raw.filter { it.isDigit() }.take(MAX_FREQUENCY_DIGITS)
                text = digits
                digits.toIntOrNull()
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
    unit: ScheduleCadenceUnit,
    onUnitSelected: (ScheduleCadenceUnit) -> Unit,
) {
    var expanded by remember { mutableStateOf(false) }
    val options = listOf(
        ScheduleCadenceUnit.MINUTES to stringResource(R.string.cadence_unit_minutes),
        ScheduleCadenceUnit.HOURS to stringResource(R.string.cadence_unit_hours),
        ScheduleCadenceUnit.DAYS to stringResource(R.string.cadence_unit_days),
        ScheduleCadenceUnit.WEEKS to stringResource(R.string.cadence_unit_weeks),
    )
    val selectedLabel = options.firstOrNull { it.first == unit }?.second.orEmpty()

    Box(modifier = Modifier.wrapContentSize(Alignment.TopEnd)) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(12.dp))
                .clickable { expanded = true }
                .padding(horizontal = 4.dp, vertical = 2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = selectedLabel,
                style = MaterialTheme.typography.titleLarge,
                color = AppColors.accentHover,
            )
            Spacer(modifier = Modifier.width(2.dp))
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
    val displayHour = ((hour + 11) % 12) + 1
    val period = if (hour < 12) stringResource(R.string.schedule_time_period_am) else stringResource(R.string.schedule_time_period_pm)

    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        PickerPill(
            label = displayHour.toString(),
            onIncrement = { onHourDelta(1) },
            onDecrement = { onHourDelta(-1) },
            modifier = Modifier.weight(1f),
        )
        Text(
            text = ":",
            style = MaterialTheme.typography.headlineMedium,
            color = AppColors.textSecondary,
        )
        PickerPill(
            label = String.format(Locale.getDefault(), "%02d", minute),
            onIncrement = { onMinuteDelta(1) },
            onDecrement = { onMinuteDelta(-1) },
            modifier = Modifier.weight(1f),
        )
        PickerPill(
            label = period,
            onIncrement = onTogglePeriod,
            onDecrement = onTogglePeriod,
            modifier = Modifier.weight(1f),
        )
    }
}

@Composable
private fun PickerPill(
    label: String,
    onIncrement: () -> Unit,
    onDecrement: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(16.dp)
    Row(
        modifier = modifier
            .height(58.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.08f))
            .border(1.dp, Color.White.copy(alpha = 0.16f), shape)
            .padding(horizontal = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.headlineSmall,
            color = AppColors.textPrimary,
            fontWeight = FontWeight.Normal,
        )
        Spacer(modifier = Modifier.width(4.dp))
        Column(
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            Icon(
                Icons.Filled.KeyboardArrowUp,
                contentDescription = stringResource(R.string.increase),
                tint = AppColors.accentHover,
                modifier = Modifier
                    .size(20.dp)
                    .clickable { onIncrement() },
            )
            Icon(
                Icons.Filled.KeyboardArrowDown,
                contentDescription = stringResource(R.string.decrease),
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
) {
    val shape = RoundedCornerShape(100.dp)
    Row(
        modifier = Modifier
            .height(44.dp)
            .clip(shape)
            .background(Color.White.copy(alpha = 0.08f))
            .border(1.dp, Color.White.copy(alpha = 0.08f), shape),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        StepperIcon(Icons.Filled.Remove, stringResource(R.string.decrease), onDecrease)
        Box(
            modifier = Modifier
                .width(1.dp)
                .height(28.dp)
                .background(Color.White.copy(alpha = 0.20f)),
        )
        StepperIcon(Icons.Filled.Add, stringResource(R.string.increase), onIncrease)
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
            .height(44.dp)
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
    Spacer(modifier = Modifier.height(18.dp))
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .height(1.dp)
            .background(Color.White.copy(alpha = 0.12f)),
    )
    Spacer(modifier = Modifier.height(18.dp))
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
    val shape = RoundedCornerShape(20.dp)
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(AppColors.bgSecondary)
            .border(1.dp, AppColors.borderSubtle, shape)
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
