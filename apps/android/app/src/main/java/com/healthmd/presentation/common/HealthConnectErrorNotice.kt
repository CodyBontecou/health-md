package com.healthmd.presentation.common

import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import com.healthmd.R
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

enum class HealthConnectActionError {
    ACCESS_CHECK_FAILED,
    PERMISSION_REQUEST_FAILED,
    PERMISSION_DENIED,
    SETTINGS_LAUNCH_FAILED,
    INSTALL_LAUNCH_FAILED,
    HISTORY_UNAVAILABLE,
    BACKGROUND_ACCESS_UNAVAILABLE,
}

@Composable
fun HealthConnectErrorNotice(
    error: HealthConnectActionError,
    onDismiss: () -> Unit,
) {
    val message = when (error) {
        HealthConnectActionError.ACCESS_CHECK_FAILED ->
            stringResource(R.string.health_connect_error_access_check)
        HealthConnectActionError.PERMISSION_REQUEST_FAILED ->
            stringResource(R.string.health_connect_error_permission_request)
        HealthConnectActionError.PERMISSION_DENIED ->
            stringResource(R.string.health_connect_error_permission_denied)
        HealthConnectActionError.SETTINGS_LAUNCH_FAILED ->
            stringResource(R.string.health_connect_error_settings_launch)
        HealthConnectActionError.INSTALL_LAUNCH_FAILED ->
            stringResource(R.string.health_connect_error_install_launch)
        HealthConnectActionError.HISTORY_UNAVAILABLE ->
            stringResource(R.string.health_connect_error_history_unavailable)
        HealthConnectActionError.BACKGROUND_ACCESS_UNAVAILABLE ->
            stringResource(R.string.health_connect_error_background_unavailable)
    }

    GeistCard {
        Text(
            text = stringResource(R.string.health_connect_error_title),
            style = MaterialTheme.typography.titleMedium,
            color = AppColors.error,
        )
        Spacer(modifier = Modifier.height(Spacing.xs))
        Text(
            text = message,
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
        )
        Spacer(modifier = Modifier.height(Spacing.xs))
        TextButton(onClick = onDismiss) {
            Text(stringResource(R.string.action_dismiss_error))
        }
    }
}
