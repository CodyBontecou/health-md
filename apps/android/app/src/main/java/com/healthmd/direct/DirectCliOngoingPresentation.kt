package com.healthmd.direct

/**
 * How the Direct CLI ongoing notification presents one connection state: the status-bar chip
 * (Android 16 promoted ongoing notifications) and whether the export finished, which swaps the
 * primary action to Open archive. Notifications never contain health values.
 */
internal enum class DirectCliOngoingStage { IDLE, CONNECTING, TRANSFERRING, COMPLETED, FAILED }

internal object DirectCliOngoingPresentation {
    fun stage(state: DirectCliConnectionState): DirectCliOngoingStage = when (state) {
        DirectCliConnectionState.Idle -> DirectCliOngoingStage.IDLE
        DirectCliConnectionState.Pairing,
        DirectCliConnectionState.WaitingForCli,
        is DirectCliConnectionState.Connected -> DirectCliOngoingStage.CONNECTING
        is DirectCliConnectionState.Transferring -> DirectCliOngoingStage.TRANSFERRING
        is DirectCliConnectionState.Completed ->
            if (state.outcome == DirectCliCompletion.ExportCompleted) {
                DirectCliOngoingStage.COMPLETED
            } else {
                DirectCliOngoingStage.IDLE
            }
        is DirectCliConnectionState.Failed -> DirectCliOngoingStage.FAILED
    }

    /** Whole-percent transfer progress, or 0 while the total is still unknown. */
    fun percent(state: DirectCliConnectionState.Transferring): Int =
        if (state.totalBytes > 0) {
            ((state.completedBytes * 100) / state.totalBytes).toInt().coerceIn(0, 100)
        } else {
            0
        }
}
