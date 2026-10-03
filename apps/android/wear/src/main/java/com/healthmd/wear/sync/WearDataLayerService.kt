package com.healthmd.wear.sync

import android.content.Context
import com.google.android.gms.wearable.*
import com.healthmd.wear.surface.invalidateAllWearSurfaces
import com.healthmd.wearable.contract.*

class WearDataLayerService : WearableListenerService() {
    override fun onDataChanged(events: DataEventBuffer) {
        events.forEach { event ->
            val path = event.dataItem.uri.path
            val nodeId = event.dataItem.uri.host ?: return@forEach
            if (event.type == DataEvent.TYPE_DELETED) {
                // Explicit user deletion is ordered through DELETE/TOMBSTONE controls. Ignore
                // payload-free removals so a late callback cannot erase a later explicit resync.
                return@forEach
            }
            val map = runCatching { DataMapItem.fromDataItem(event.dataItem).dataMap }.getOrNull() ?: return@forEach
            when (path) {
                WearDataPaths.SNAPSHOT -> deliverOutcome(
                    nodeId,
                    applyWearSnapshotPayload(this, map.getLong("sequence", -1L), map.getByteArray("snapshot")),
                )
                WearDataPaths.TOMBSTONE -> {
                    val request = map.getByteArray("request")?.let(WearDeleteRequestCodec::decode) ?: return@forEach
                    deliverOutcome(nodeId, deleteLocalWearData(this, request.clearedThroughSequence))
                }
            }
        }
    }

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path != WearDataPaths.DELETE) return
        val request = WearDeleteRequestCodec.decode(event.data) ?: return
        deliverOutcome(event.sourceNodeId, deleteLocalWearData(this, request.clearedThroughSequence))
    }

    private fun deliverOutcome(nodeId: String, outcome: WearDeliveryOutcome) {
        outcome.ack?.let { ack ->
            Wearable.getMessageClient(this).sendMessage(nodeId, WearDataPaths.ACK, WearSnapshotAckCodec.encode(ack))
        }
        if (outcome.invalidateSurfaces) invalidateAllWearSurfaces(this)
    }
}

internal data class WearDeliveryOutcome(val ack: WearSnapshotAck?, val invalidateSurfaces: Boolean)

/** Production delivery policy isolated for deterministic contract/repository verification. */
internal fun applyWearSnapshotPayload(
    context: Context,
    declaredSequence: Long,
    bytes: ByteArray?,
): WearDeliveryOutcome {
    val decoded = bytes?.let(WearHealthSnapshotCodec::decodeResult)
    if (decoded !is WearSnapshotDecodeResult.Valid) {
        val reason = (decoded as? WearSnapshotDecodeResult.Rejected)?.reason ?: WearAckReason.INVALID
        val mismatchRecorded = if (reason == WearAckReason.VERSION_MISMATCH && declaredSequence >= 0L) {
            runCatching { WearSnapshotRepository.recordVersionMismatch(context, declaredSequence) }.getOrDefault(false)
        } else false
        val ack = declaredSequence.takeIf { it >= 0L }?.let {
            WearSnapshotAck(
                it,
                false,
                if (reason == WearAckReason.VERSION_MISMATCH && !mismatchRecorded) WearAckReason.OUT_OF_ORDER else reason,
            )
        }
        return WearDeliveryOutcome(ack, invalidateSurfaces = mismatchRecorded)
    }

    val snapshot = decoded.snapshot
    if (declaredSequence != snapshot.sequence) {
        return WearDeliveryOutcome(
            declaredSequence.takeIf { it >= 0L }?.let { WearSnapshotAck(it, false, WearAckReason.INVALID) },
            invalidateSurfaces = false,
        )
    }
    val result = runCatching { WearSnapshotRepository.apply(context, snapshot) }.getOrNull()
    val ack = when (result) {
        WearSnapshotRepository.ApplyResult.APPLIED -> WearSnapshotAck(snapshot.sequence, true, WearAckReason.APPLIED)
        WearSnapshotRepository.ApplyResult.DUPLICATE -> WearSnapshotAck(snapshot.sequence, true, WearAckReason.DUPLICATE)
        WearSnapshotRepository.ApplyResult.OUT_OF_ORDER -> WearSnapshotAck(snapshot.sequence, false, WearAckReason.OUT_OF_ORDER)
        WearSnapshotRepository.ApplyResult.FAILED_CLOSED -> WearSnapshotAck(snapshot.sequence, false, WearAckReason.INVALID)
        null -> WearSnapshotAck(snapshot.sequence, false, WearAckReason.INVALID)
    }
    return WearDeliveryOutcome(
        ack,
        invalidateSurfaces = result == WearSnapshotRepository.ApplyResult.APPLIED ||
            result == WearSnapshotRepository.ApplyResult.FAILED_CLOSED,
    )
}

internal fun deleteLocalWearData(context: Context, clearedThroughSequence: Long): WearDeliveryOutcome {
    val result = runCatching {
        WearSnapshotRepository.clearThrough(context, clearedThroughSequence)
    }.getOrNull()
    val deleted = result?.deleted == true
    val barrierCommitted = result?.barrierCommitted == true
    return WearDeliveryOutcome(
        WearSnapshotAck(
            result?.sequence ?: clearedThroughSequence.coerceAtLeast(0L),
            deleted,
            when {
                deleted -> WearAckReason.DELETED
                barrierCommitted -> WearAckReason.INVALID
                result != null -> WearAckReason.OUT_OF_ORDER
                else -> WearAckReason.INVALID
            },
        ),
        // A committed privacy barrier hides the observable cache. Invalidate every host surface
        // even when physical file cleanup needs a later retry; reordered old tombstones do neither.
        invalidateSurfaces = barrierCommitted,
    )
}
