package com.healthmd.widget.setup

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.HealthAndSafety
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material.icons.outlined.Widgets
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import com.healthmd.R
import com.healthmd.data.health.HealthConnectIntentLauncher
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import com.healthmd.widget.data.HealthWidgetSnapshotRepository
import com.healthmd.widget.glance.HealthWidgetFormatters
import com.healthmd.widget.data.WidgetHealthPermissionManager
import com.healthmd.widget.refresh.HealthWidgetInstanceRegistry
import com.healthmd.widget.refresh.HealthWidgetLifecycleCoordinator
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.time.Instant
import java.time.ZoneId
import javax.inject.Inject

internal enum class WidgetSettingsStatus {
    NONE_INSTALLED,
    CURRENT,
    FOREGROUND_ONLY,
    STALE,
    ACCESS_REQUIRED,
    NO_DATA,
}

internal data class WidgetSettingsUiState(
    val installedCount: Int = 0,
    val status: WidgetSettingsStatus = WidgetSettingsStatus.NONE_INSTALLED,
    val isRefreshing: Boolean = false,
)

@HiltViewModel
internal class WidgetSettingsViewModel @Inject constructor(
    private val instances: HealthWidgetInstanceRegistry,
    private val permissions: WidgetHealthPermissionManager,
    private val snapshots: HealthWidgetSnapshotRepository,
    private val lifecycle: HealthWidgetLifecycleCoordinator,
) : ViewModel() {
    private val _uiState = MutableStateFlow(WidgetSettingsUiState())
    val uiState: StateFlow<WidgetSettingsUiState> = _uiState.asStateFlow()

    fun refreshStatus() {
        viewModelScope.launch { loadStatus() }
    }

    fun refreshWidgets() {
        if (_uiState.value.isRefreshing) return
        viewModelScope.launch {
            _uiState.update { it.copy(isRefreshing = true) }
            runCatching { lifecycle.refreshFromForeground(force = true) }
            loadStatus()
            _uiState.update { it.copy(isRefreshing = false) }
        }
    }

    private suspend fun loadStatus() {
        val count = instances.installedWidgetCount()
        if (count == 0) {
            _uiState.value = WidgetSettingsUiState()
            return
        }
        val requirements = instances.requirements()
        val permissionStatus = runCatching { permissions.status(requirements) }.getOrNull()
        val snapshot = runCatching { snapshots.load() }.getOrNull()
        val now = Instant.now()
        val zoneMatches = snapshot?.capturedZoneId == ZoneId.systemDefault().id
        val status = when {
            permissionStatus?.hasAllForegroundPermissions != true -> WidgetSettingsStatus.ACCESS_REQUIRED
            zoneMatches && snapshot?.isFresh(now) == true && permissionStatus.canRefreshInBackground ->
                WidgetSettingsStatus.CURRENT
            zoneMatches && snapshot?.isFresh(now) == true -> WidgetSettingsStatus.FOREGROUND_ONLY
            zoneMatches && snapshot?.canDisplayMeasurements(now) == true -> WidgetSettingsStatus.STALE
            else -> WidgetSettingsStatus.NO_DATA
        }
        _uiState.update { it.copy(installedCount = count, status = status) }
    }
}

@Composable
internal fun WidgetSettingsCard(
    viewModel: WidgetSettingsViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val protection = LocalConfigurationProtection.current
    val locale = LocalConfiguration.current.locales[0]
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(Unit) { viewModel.refreshStatus() }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) viewModel.refreshStatus()
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    GeistCard {
        SectionLabel(stringResource(R.string.widget_settings_title))
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                Icons.Outlined.Widgets,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(24.dp),
            )
            Spacer(Modifier.width(Spacing.sm))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = if (state.installedCount == 0) {
                        stringResource(R.string.widget_settings_none)
                    } else {
                        pluralStringResource(
                            R.plurals.widget_settings_count,
                            state.installedCount,
                            HealthWidgetFormatters.integer(state.installedCount, locale),
                        )
                    },
                    style = MaterialTheme.typography.bodyLarge,
                    color = AppColors.textPrimary,
                )
                Text(
                    text = widgetStatusText(state.status),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textMuted,
                )
            }
        }

        if (state.installedCount > 0) {
            Spacer(Modifier.height(Spacing.md))
            PrimaryButton(
                text = stringResource(R.string.widget_settings_refresh),
                icon = Icons.Outlined.Refresh,
                isLoading = state.isRefreshing,
                onClick = viewModel::refreshWidgets,
            )
            Spacer(Modifier.height(Spacing.xs))
            SecondaryButton(
                text = stringResource(R.string.widget_settings_manage_access),
                icon = Icons.Outlined.HealthAndSafety,
                modifier = Modifier.fillMaxWidth(),
                onClick = {
                    if (protection.enabled) protection.onBlockedChange()
                    else HealthConnectIntentLauncher(context).openSettings()
                },
            )
        }
    }
}

@Composable
private fun widgetStatusText(status: WidgetSettingsStatus): String = stringResource(
    when (status) {
        WidgetSettingsStatus.NONE_INSTALLED -> R.string.widget_settings_add_from_home
        WidgetSettingsStatus.CURRENT -> R.string.widget_settings_current
        WidgetSettingsStatus.FOREGROUND_ONLY -> R.string.widget_settings_foreground_only
        WidgetSettingsStatus.STALE -> R.string.widget_settings_stale
        WidgetSettingsStatus.ACCESS_REQUIRED -> R.string.widget_settings_access_required
        WidgetSettingsStatus.NO_DATA -> R.string.widget_settings_no_data
    }
)
