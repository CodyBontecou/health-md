package com.healthmd.wear

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.Refresh
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import android.text.format.DateUtils
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import androidx.work.await
import com.healthmd.R
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class WearSettingsViewModel @Inject constructor(
    private val statusStore: WearSyncStatusStore,
    private val scheduler: WearPhoneSyncScheduler,
) : ViewModel() {
    val status = statusStore.statuses
    var busy by mutableStateOf(false); private set
    fun sync() = act {
        // The durable worker owns both publication and permission-audit reconciliation. Direct
        // ViewModel publication could be cancelled after putDataItem but before scheduling the
        // audit, leaving retained aggregates unaudited until the app was opened again.
        scheduler.enqueueManual().await()
    }
    fun clear() = act {
        // WorkManager owns the request before the worker reserves/persists the clear transaction.
        // Process death therefore cannot strand a privacy intent between two persistence systems.
        scheduler.enqueueClear().await()
    }
    private fun act(block: suspend () -> Unit) {
        if (busy) return
        viewModelScope.launch { busy = true; runCatching { block() }; busy = false }
    }
}

@Composable
fun WearSettingsCard(viewModel: WearSettingsViewModel = hiltViewModel()) {
    val status by viewModel.status.collectAsState()
    GeistCard {
        SectionLabel(stringResource(R.string.wear_settings_title))
        Text(stringResource(R.string.wear_settings_body), style = MaterialTheme.typography.bodySmall, color = AppColors.textMuted)
        status.sourceState?.let { source -> StatusLine(stringResource(R.string.wear_settings_source, stringResource(source.stringRes()))) }
        status.deliveryState?.let { delivery ->
            val at = status.lastSentEpochMillis ?: status.lastAttemptEpochMillis
            val deliveryText = when {
                wearDeliveryIsPartial(status) -> stringResource(
                    R.string.wear_delivery_partial,
                    formatWatchDeliveryProgress(
                        status.acknowledgedWatchCount,
                        status.targetedWatchCount,
                    ),
                )
                else -> stringResource(delivery.stringRes())
            }
            StatusLine(stringResource(R.string.wear_settings_delivery, deliveryText, relativeTime(at)))
        }
        if (status.targetedWatchCount > 0) {
            StatusLine(stringResource(
                R.string.wear_settings_watch_progress,
                status.acknowledgedWatchCount,
                status.targetedWatchCount,
            ))
        }
        status.result?.let { result -> StatusLine(stringResource(R.string.wear_settings_attempt, stringResource(result.stringRes()), relativeTime(status.lastAttemptEpochMillis))) }
        status.ackReason?.let { reason ->
            val sequence = status.acknowledgedSequence?.toString() ?: stringResource(R.string.wear_settings_unknown_sequence)
            StatusLine(stringResource(R.string.wear_settings_ack, sequence, stringResource(reason.stringRes())))
        }
        Spacer(Modifier.height(Spacing.sm))
        PrimaryButton(text = stringResource(R.string.wear_settings_sync), icon = Icons.Outlined.Refresh, isLoading = viewModel.busy, onClick = viewModel::sync)
        Spacer(Modifier.height(Spacing.xs))
        SecondaryButton(text = stringResource(R.string.wear_settings_clear), icon = Icons.Outlined.DeleteSweep, modifier = Modifier.fillMaxWidth(), onClick = viewModel::clear)
    }
}

internal fun wearDeliveryIsPartial(status: WearPhoneSyncStatus): Boolean =
    status.deliveryState == WearDeliveryState.REACHABLE && status.targetedWatchCount > 1 &&
        status.acknowledgedWatchCount < status.targetedWatchCount

internal fun formatWatchDeliveryProgress(acknowledged: Int, targeted: Int): String =
    "$acknowledged/$targeted"

@Composable private fun StatusLine(value: String) = Text(value, style = MaterialTheme.typography.labelSmall, color = AppColors.textSecondary)
@Composable private fun relativeTime(epochMillis: Long?): String {
    if (epochMillis == null) return stringResource(R.string.wear_settings_never)
    return DateUtils.getRelativeTimeSpanString(epochMillis, System.currentTimeMillis(), DateUtils.MINUTE_IN_MILLIS).toString()
}

private fun com.healthmd.wearable.contract.WearPermissionState.stringRes() = when (this) {
    com.healthmd.wearable.contract.WearPermissionState.READY -> R.string.wear_source_ready
    com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED -> R.string.wear_source_permission
    com.healthmd.wearable.contract.WearPermissionState.HEALTH_CONNECT_UNAVAILABLE -> R.string.wear_source_unavailable
}
private fun WearDeliveryState.stringRes() = when (this) {
    WearDeliveryState.REACHABLE -> R.string.wear_delivery_reachable
    WearDeliveryState.QUEUED -> R.string.wear_delivery_queued
    WearDeliveryState.CLEAR_REQUESTED -> R.string.wear_delivery_clear_requested
}
private fun WearPhoneSyncResult.stringRes() = when (this) {
    WearPhoneSyncResult.SENT -> R.string.wear_status_sent
    WearPhoneSyncResult.QUEUED -> R.string.wear_status_queued
    WearPhoneSyncResult.NO_WATCH -> R.string.wear_status_no_watch
    WearPhoneSyncResult.UNREACHABLE -> R.string.wear_status_unreachable
    WearPhoneSyncResult.PERMISSION_REQUIRED -> R.string.wear_status_permission
    WearPhoneSyncResult.HEALTH_CONNECT_UNAVAILABLE -> R.string.wear_status_unavailable
    WearPhoneSyncResult.RETRY -> R.string.wear_status_retry
    WearPhoneSyncResult.CLEARED -> R.string.wear_status_cleared
}
private fun com.healthmd.wearable.contract.WearAckReason.stringRes() = when (this) {
    com.healthmd.wearable.contract.WearAckReason.APPLIED -> R.string.wear_ack_applied
    com.healthmd.wearable.contract.WearAckReason.DUPLICATE -> R.string.wear_ack_duplicate
    com.healthmd.wearable.contract.WearAckReason.OUT_OF_ORDER -> R.string.wear_ack_out_of_order
    com.healthmd.wearable.contract.WearAckReason.INVALID -> R.string.wear_ack_invalid
    com.healthmd.wearable.contract.WearAckReason.VERSION_MISMATCH -> R.string.wear_ack_version
    com.healthmd.wearable.contract.WearAckReason.DELETED -> R.string.wear_ack_deleted
}
