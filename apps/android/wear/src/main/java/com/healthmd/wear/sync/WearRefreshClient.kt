package com.healthmd.wear.sync

import android.content.Context
import com.google.android.gms.tasks.Task
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Wearable
import com.healthmd.wearable.contract.WearDataPaths
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withTimeoutOrNull
import java.util.concurrent.Executor
import kotlin.coroutines.resume

class WearRefreshClient(
    context: Context,
    private val capabilityClient: CapabilityClient = Wearable.getCapabilityClient(context),
    private val messageClient: MessageClient = Wearable.getMessageClient(context),
) {
    suspend fun requestRefresh(timeoutMillis: Long = REFRESH_TIMEOUT_MILLIS): Boolean {
        // A manual refresh is an immediate message and therefore must target a reachable node.
        // FILTER_ALL can return an installed-but-offline phone and produce a misleading success.
        val capability = capabilityClient
            .getCapability(WearDataPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE)
            .awaitOrNull() ?: return false
        val node = capability.nodes.firstOrNull { it.isNearby }
            ?: capability.nodes.firstOrNull()
            ?: return false
        val priorSequence = WearSnapshotRepository.snapshots.value?.sequence ?: -1L
        if (!messageClient.sendMessage(node.id, WearDataPaths.REFRESH, ByteArray(0)).awaitSucceeded()) return false
        // Message delivery only means the phone accepted the request. Report success once a newer
        // durable snapshot actually reaches this repository; retain last-good data on timeout.
        return withTimeoutOrNull(timeoutMillis) {
            WearSnapshotRepository.snapshots.filter { (it?.sequence ?: -1L) > priorSequence }.first()
            true
        } ?: false
    }

    companion object { const val REFRESH_TIMEOUT_MILLIS = 30_000L }
}

// Direct executor avoids coupling this cancellable bridge to an Activity/main looper.
private val directExecutor = Executor { it.run() }

private suspend fun <T> Task<T>.awaitOrNull(): T? = suspendCancellableCoroutine { continuation ->
    addOnSuccessListener(directExecutor) { if (continuation.isActive) continuation.resume(it) }
    addOnFailureListener(directExecutor) { if (continuation.isActive) continuation.resume(null) }
    // Play Services transport cancellation is a failed refresh, not cancellation of the caller's
    // UI coroutine. Parent coroutine cancellation still cancels this bridge normally.
    addOnCanceledListener(directExecutor) { if (continuation.isActive) continuation.resume(null) }
}

private suspend fun Task<Int>.awaitSucceeded(): Boolean = suspendCancellableCoroutine { continuation ->
    addOnSuccessListener(directExecutor) { if (continuation.isActive) continuation.resume(true) }
    addOnFailureListener(directExecutor) { if (continuation.isActive) continuation.resume(false) }
    addOnCanceledListener(directExecutor) { if (continuation.isActive) continuation.resume(false) }
}
