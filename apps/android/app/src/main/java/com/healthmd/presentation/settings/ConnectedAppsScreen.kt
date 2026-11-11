package com.healthmd.presentation.settings

import android.widget.Toast
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Apps
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.material.icons.outlined.LinkOff
import androidx.compose.material.icons.automirrored.outlined.Login
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.health.providers.HealthProviderId
import com.healthmd.presentation.theme.GeistSpacing
import kotlinx.coroutines.launch

/**
 * Connected apps (iOS ConnectedAppsG), a pushed page: each direct cloud provider with its
 * connection, whether exports use it, and Disconnect. Play builds only; F-Droid has none.
 */
@Composable
fun ConnectedAppsScreen(viewModel: SettingsViewModel = hiltViewModel()) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    val providers by viewModel.healthProviderStates.collectAsStateWithLifecycle()
    val shown = if (viewModel.distributionPolicy.directCloudProvidersAvailable) {
        providers.filter { it.provider.definition.id == HealthProviderId.WHOOP && (it.isDirectConnectionConfigured || it.isConnected) }
    } else {
        emptyList()
    }
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GeistSpacing.space4)
            .padding(bottom = GeistSpacing.space8)
            .testTag("settings.connectedApps.page"),
    ) {
        shown.forEach { provider ->
            val name = provider.provider.definition.displayName
            val connect: () -> Unit = {
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
            }
            val rows = buildList<@Composable (Shape) -> Unit> {
                add { shape ->
                    SettingsRow(
                        shape = shape,
                        title = name,
                        subtitle = stringResource(provider.provider.definition.summaryRes),
                        icon = Icons.Outlined.Apps,
                        badge = if (provider.isConnected) {
                            SettingsBadge(stringResource(R.string.connected_apps_connected), SettingsBadgeTone.OK)
                        } else {
                            SettingsBadge(stringResource(R.string.settings_status_off), SettingsBadgeTone.OFF)
                        },
                        onClick = null,
                    )
                }
                if (provider.isDirectConnectionConfigured) {
                    add { shape ->
                        SettingsRow(
                            shape = shape,
                            title = stringResource(if (provider.isConnected) R.string.whoop_reconnect else R.string.whoop_connect),
                            icon = Icons.AutoMirrored.Outlined.Login,
                            onClick = connect,
                            external = true,
                        )
                    }
                }
                if (provider.isConnected) {
                    add { shape ->
                        SettingsRow(
                            shape = shape,
                            title = stringResource(
                                if (provider.isSelected) R.string.whoop_use_health_connect else R.string.whoop_use_for_exports,
                            ),
                            icon = Icons.Outlined.Favorite,
                            onClick = {
                                viewModel.performConfigurationChange {
                                    if (provider.isSelected) viewModel.useHealthConnectForExports()
                                    else viewModel.selectHealthProvider(HealthProviderId.WHOOP)
                                }
                            },
                        )
                    }
                    add { shape ->
                        SettingsRow(
                            shape = shape,
                            title = stringResource(R.string.whoop_disconnect),
                            icon = Icons.Outlined.LinkOff,
                            onClick = {
                                viewModel.performConfigurationChange { viewModel.disconnectHealthProvider(HealthProviderId.WHOOP) }
                            },
                        )
                    }
                }
            }
            SettingsGroup(title = name, rows = rows)
            SettingsFootnote(stringResource(R.string.whoop_connection_description))
        }
    }
}
