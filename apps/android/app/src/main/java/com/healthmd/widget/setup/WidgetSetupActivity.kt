package com.healthmd.widget.setup

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.content.Intent
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.background
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.data.health.HealthConnectFeatureAvailability
import com.healthmd.data.health.HealthConnectIntentLauncher
import com.healthmd.data.health.HealthConnectLaunchResult
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.tryLaunchHealthConnectPermissions
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.widget.data.WidgetHealthPermissionManager
import com.healthmd.widget.data.WidgetHealthPermissionStatus
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.WidgetDataRequirements
import com.healthmd.widget.refresh.HealthWidgetInstanceRegistry
import com.healthmd.widget.refresh.HealthWidgetLifecycleCoordinator
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class WidgetSetupActivity : ComponentActivity() {
    @Inject lateinit var healthConnectManager: HealthConnectManager
    @Inject lateinit var permissionManager: WidgetHealthPermissionManager
    @Inject lateinit var instanceRegistry: HealthWidgetInstanceRegistry
    @Inject lateinit var widgetLifecycle: HealthWidgetLifecycleCoordinator

    private var appWidgetId: Int = AppWidgetManager.INVALID_APPWIDGET_ID

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        appWidgetId = intent?.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        ) ?: AppWidgetManager.INVALID_APPWIDGET_ID
        val resultIntent = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        setResult(Activity.RESULT_CANCELED, resultIntent)

        val kind = instanceRegistry.kindForAppWidgetId(appWidgetId)
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID || kind == null) {
            finish()
            return
        }

        enableEdgeToEdge()
        setContent {
            HealthMdTheme {
                WidgetSetupScreen(
                    kind = kind,
                    loadState = { loadState(kind) },
                    permissionContract = healthConnectManager.getPermissionContract(),
                    onOpenHealthConnect = {
                        val launcher = HealthConnectIntentLauncher(this)
                        if (healthConnectManager.needsInstall()) {
                            launcher.openInstallOrUpdate()
                        } else {
                            launcher.openSettings()
                        }
                    },
                    onComplete = {
                        setResult(Activity.RESULT_OK, resultIntent)
                        finish()
                    },
                    refreshWidget = {
                        widgetLifecycle.refreshFromForeground(force = true)
                    },
                    onCancel = { finish() },
                )
            }
        }
    }

    private suspend fun loadState(kind: HealthWidgetKind): WidgetSetupUiState {
        if (!healthConnectManager.isAvailable()) {
            return WidgetSetupUiState(
                isLoading = false,
                healthConnectAvailable = false,
                needsInstall = healthConnectManager.needsInstall(),
            )
        }
        return runCatching {
            val requirements = WidgetDataRequirements.forKind(kind)
            WidgetSetupUiState(
                isLoading = false,
                healthConnectAvailable = true,
                permissionStatus = permissionManager.status(requirements),
            )
        }.getOrElse {
            WidgetSetupUiState(
                isLoading = false,
                healthConnectAvailable = true,
                hasError = true,
            )
        }
    }
}

private data class WidgetSetupUiState(
    val isLoading: Boolean = true,
    val healthConnectAvailable: Boolean = false,
    val needsInstall: Boolean = false,
    val permissionStatus: WidgetHealthPermissionStatus? = null,
    val hasError: Boolean = false,
)

@Composable
private fun WidgetSetupScreen(
    kind: HealthWidgetKind,
    loadState: suspend () -> WidgetSetupUiState,
    permissionContract: androidx.activity.result.contract.ActivityResultContract<Set<String>, Set<String>>,
    onOpenHealthConnect: () -> HealthConnectLaunchResult,
    refreshWidget: suspend () -> Any,
    onComplete: () -> Unit,
    onCancel: () -> Unit,
) {
    val colors = LocalGeistColors.current
    val scope = rememberCoroutineScope()
    var state by remember { mutableStateOf(WidgetSetupUiState()) }
    var reloadKey by remember { mutableIntStateOf(0) }
    var adding by remember { mutableStateOf(false) }
    var actionError by remember { mutableStateOf(false) }
    val lifecycleOwner = LocalLifecycleOwner.current

    val permissionLauncher = rememberLauncherForActivityResult(permissionContract) {
        reloadKey += 1
    }

    LaunchedEffect(reloadKey) {
        state = loadState()
    }
    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) reloadKey += 1
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(colors.background100)
            .verticalScroll(rememberScrollState())
            .systemBarsPadding()
            .padding(GeistSpacing.space6),
        verticalArrangement = Arrangement.Center,
    ) {
        Text(
            text = stringResource(R.string.widget_setup_title, widgetName(kind)),
            style = GeistType.heading24,
            color = colors.primary,
        )
        Spacer(Modifier.height(GeistSpacing.space2))
        Text(
            text = stringResource(R.string.widget_setup_body),
            style = GeistType.copy14,
            color = colors.secondary,
        )
        Spacer(Modifier.height(GeistSpacing.space6))

        when {
            state.isLoading -> CircularProgressIndicator(
                modifier = Modifier.align(Alignment.CenterHorizontally),
                color = colors.brandPrimary,
            )
            !state.healthConnectAvailable -> {
                GeistCard {
                    Text(
                        text = stringResource(
                            if (state.needsInstall) R.string.hc_required_message else R.string.hc_setup_message,
                        ),
                        style = GeistType.copy14,
                        color = colors.secondary,
                    )
                }
                Spacer(Modifier.height(GeistSpacing.space4))
                PrimaryButton(
                    text = stringResource(
                        if (state.needsInstall) R.string.hc_install_button else R.string.hc_open_button,
                    ),
                    onClick = {
                        if (onOpenHealthConnect() == HealthConnectLaunchResult.FAILED) actionError = true
                    },
                )
            }
            state.hasError -> {
                GeistCard {
                    Text(
                        text = stringResource(R.string.widget_setup_error),
                        style = GeistType.copy14,
                        color = colors.error,
                    )
                }
            }
            else -> {
                val status = state.permissionStatus
                if (status != null) {
                    WidgetAccessStatus(status)
                    Spacer(Modifier.height(GeistSpacing.space4))
                    if (!status.hasAllForegroundPermissions) {
                        PrimaryButton(
                            text = stringResource(R.string.widget_setup_foreground_access),
                            onClick = {
                                actionError = !tryLaunchHealthConnectPermissions(
                                    status.missingForegroundPermissions,
                                ) { permissionLauncher.launch(it) }
                            },
                        )
                        Spacer(Modifier.height(GeistSpacing.space2))
                    }
                    if (
                        status.hasAnyForegroundPermission &&
                        status.backgroundAvailability == HealthConnectFeatureAvailability.AVAILABLE &&
                        !status.backgroundGranted
                    ) {
                        SecondaryButton(
                            text = stringResource(R.string.widget_setup_background_access),
                            modifier = Modifier.fillMaxWidth(),
                            onClick = {
                                actionError = !tryLaunchHealthConnectPermissions(
                                    status.backgroundPermissions,
                                ) { permissionLauncher.launch(it) }
                            },
                        )
                        Spacer(Modifier.height(GeistSpacing.space2))
                    }
                    PrimaryButton(
                        text = stringResource(
                            if (adding) R.string.widget_setup_adding else R.string.widget_setup_add,
                        ),
                        enabled = status.hasAnyForegroundPermission,
                        isLoading = adding,
                        onClick = {
                            adding = true
                            scope.launch {
                                runCatching { refreshWidget() }
                                    .onSuccess { onComplete() }
                                    .onFailure {
                                        adding = false
                                        actionError = true
                                    }
                            }
                        },
                    )
                }
            }
        }

        if (actionError) {
            Spacer(Modifier.height(GeistSpacing.space3))
            Text(
                text = stringResource(R.string.widget_setup_error),
                style = GeistType.copy13,
                color = colors.error,
            )
        }
        Spacer(Modifier.height(GeistSpacing.space3))
        SecondaryButton(
            text = stringResource(R.string.cancel),
            modifier = Modifier.fillMaxWidth(),
            enabled = !adding,
            onClick = onCancel,
        )
    }
}

@Composable
private fun WidgetAccessStatus(status: WidgetHealthPermissionStatus) {
    val colors = LocalGeistColors.current
    GeistCard {
        Text(
            text = stringResource(
                if (status.hasAllForegroundPermissions) {
                    R.string.widget_setup_access_ready
                } else {
                    R.string.widget_setup_partial_access
                }
            ),
            style = GeistType.copy14,
            color = colors.primary,
        )
        if (
            status.backgroundAvailability == HealthConnectFeatureAvailability.AVAILABLE &&
            !status.backgroundGranted
        ) {
            Spacer(Modifier.height(GeistSpacing.space2))
            Text(
                text = stringResource(R.string.widget_setup_background_body),
                style = GeistType.copy13,
                color = colors.secondary,
            )
        }
    }
}

@Composable
private fun widgetName(kind: HealthWidgetKind): String = stringResource(
    when (kind) {
        HealthWidgetKind.SUMMARY -> R.string.widget_health_summary_name
        HealthWidgetKind.ACTIVITY -> R.string.widget_activity_name
        HealthWidgetKind.HEART_RANGE -> R.string.widget_heart_range_name
        HealthWidgetKind.SLEEP -> R.string.widget_sleep_name
    }
)
