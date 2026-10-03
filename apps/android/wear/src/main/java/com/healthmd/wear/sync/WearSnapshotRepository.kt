package com.healthmd.wear.sync

import android.content.Context
import android.util.AtomicFile
import com.healthmd.wearable.contract.WearHealthSnapshot
import com.healthmd.wearable.contract.WearHealthSnapshotCodec
import java.io.File
import java.security.MessageDigest
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** Atomic, no-backup, process-local cache shared by the app, Tiles, and complications. */
object WearSnapshotRepository {
    @Volatile private var applicationContext: Context? = null
    private val lock = Any()
    private val mutableSnapshots = MutableStateFlow<WearHealthSnapshot?>(null)
    private val mutableVersionMismatch = MutableStateFlow(false)
    private val mutableOrderingCorrupt = MutableStateFlow(false)
    val snapshots: StateFlow<WearHealthSnapshot?> = mutableSnapshots.asStateFlow()
    val versionMismatch: StateFlow<Boolean> = mutableVersionMismatch.asStateFlow()
    /** A privacy/order marker was present but unreadable; measurements remain fail-closed. */
    val orderingCorrupt: StateFlow<Boolean> = mutableOrderingCorrupt.asStateFlow()
    enum class ApplyResult { APPLIED, DUPLICATE, OUT_OF_ORDER, FAILED_CLOSED }
    data class ClearResult(
        val sequence: Long,
        val deleted: Boolean,
        /** True once the durable clear barrier committed, even if physical cleanup needs retry. */
        val barrierCommitted: Boolean = deleted,
    )
    /** Test seam for a physical cleanup failure after the durable privacy barrier is committed. */
    internal var deleteSnapshotOverride: ((File) -> Boolean)? = null
    /** Test seam for a cache replacement failure after the monotonic floor is durable. */
    internal var writeSnapshotOverride: ((File, ByteArray) -> Unit)? = null
    data class DiagnosticState(
        val cacheFilePresent: Boolean,
        val cacheSize: Long?,
        val cacheSha256: String?,
        val mismatchMarkerPresent: Boolean,
        val clearTombstonePresent: Boolean,
        val orderingCorrupt: Boolean,
    )

    fun diagnosticState(context: Context): DiagnosticState = synchronized(lock) {
        val snapshot = snapshotFile(context)
        val present = snapshot.isFile && snapshot.length() in 1..WearHealthSnapshot.MAX_ENCODED_BYTES.toLong()
        val digest = if (present) runCatching {
            MessageDigest.getInstance("SHA-256").digest(snapshot.readBytes())
                .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        }.getOrNull() else null
        val clearState = readMarkerState(clearedThroughFile(context))
        val mismatchState = readMarkerState(mismatchFile(context))
        val lastAppliedState = readMarkerState(lastAppliedFile(context))
        DiagnosticState(
            cacheFilePresent = present,
            cacheSize = snapshot.length().takeIf { present },
            cacheSha256 = digest,
            mismatchMarkerPresent = mismatchState is MarkerState.Valid,
            clearTombstonePresent = clearState is MarkerState.Valid,
            orderingCorrupt = clearState is MarkerState.Corrupt || mismatchState is MarkerState.Corrupt ||
                lastAppliedState is MarkerState.Corrupt,
        )
    }

    fun initialize(context: Context) {
        applicationContext = context.applicationContext
        synchronized(lock) {
            mutableSnapshots.value = loadUnlocked(context)
            mutableVersionMismatch.value = readMarkerState(mismatchFile(context)) is MarkerState.Valid
        }
    }

    fun reload(context: Context? = applicationContext) {
        val resolved = context ?: return
        synchronized(lock) {
            mutableSnapshots.value = loadUnlocked(resolved)
            mutableVersionMismatch.value = readMarkerState(mismatchFile(resolved)) is MarkerState.Valid
        }
    }

    fun load(context: Context? = applicationContext): WearHealthSnapshot? = synchronized(lock) {
        val snapshot = loadUnlocked(context ?: return@synchronized null)
        // Tiles/complications can be the first readers to discover runtime corruption. Publish the
        // fail-closed result so an already-open dashboard cannot retain stale measurements.
        mutableSnapshots.value = snapshot
        snapshot
    }

    fun apply(context: Context, snapshot: WearHealthSnapshot): ApplyResult = synchronized(lock) {
        val current = loadUnlocked(context)
        val clearMarker = readMarkerState(clearedThroughFile(context))
        val mismatchMarker = readMarkerState(mismatchFile(context))
        val lastAppliedMarker = readMarkerState(lastAppliedFile(context))
        if (clearMarker is MarkerState.Corrupt || mismatchMarker is MarkerState.Corrupt ||
            lastAppliedMarker is MarkerState.Corrupt
        ) {
            mutableOrderingCorrupt.value = true
            return@synchronized ApplyResult.OUT_OF_ORDER
        }
        val privacyFloor = maxOf(clearMarker.sequenceOrMinusOne(), mismatchMarker.sequenceOrMinusOne())
        // A user deletion and a known incompatible producer both establish durable ordering floors.
        // A delayed DataItem must never repopulate deleted data or clear newer mismatch guidance.
        if (snapshot.sequence <= privacyFloor) return@synchronized ApplyResult.OUT_OF_ORDER
        if (current?.sequence == snapshot.sequence) {
            clearMismatchUnlocked(context)
            return@synchronized ApplyResult.DUPLICATE
        }
        // The snapshot cache can be corrupted independently of its ordering metadata. Never accept
        // an equal/older delayed payload merely because the only displayable cache was removed.
        if (snapshot.sequence <= lastAppliedMarker.sequenceOrMinusOne()) {
            return@synchronized ApplyResult.OUT_OF_ORDER
        }
        if (current != null && current.sequence > snapshot.sequence) return@synchronized ApplyResult.OUT_OF_ORDER

        val bytes = WearHealthSnapshotCodec.encode(snapshot)
        val target = snapshotFile(context)
        check(target.parentFile?.exists() == true || target.parentFile?.mkdirs() == true)
        // Commit the monotonic floor first. A crash before replacing the cache then hides the older
        // file rather than allowing it (or a delayed pre-redaction event) to become authoritative.
        writeMarkerSequence(lastAppliedFile(context), snapshot.sequence)
        // The old observable cache is no longer authoritative once the newer floor commits. Hide it
        // before replacement so a disk failure cannot leave pre-redaction values on an open screen.
        mutableSnapshots.value = null
        try {
            writeSnapshotOverride?.invoke(target, bytes) ?: writeAtomic(target, bytes)
        } catch (_: Exception) {
            // loadUnlocked will remove any restored/older AtomicFile bytes using the durable floor.
            return@synchronized ApplyResult.FAILED_CLOSED
        }
        mutableSnapshots.value = snapshot
        clearMismatchUnlocked(context)
        clearMarkerUnlocked(clearedThroughFile(context))
        mutableOrderingCorrupt.value = false
        ApplyResult.APPLIED
    }

    /**
     * Explicit user deletion. The maximum of the phone target and locally cached sequence becomes a
     * durable no-backup tombstone before measurement bytes are removed, so delayed pre-clear writes
     * cannot resurrect health data. A later sequence can replace the tombstone normally.
     */
    fun clearThrough(context: Context, sequence: Long): ClearResult = synchronized(lock) {
        require(sequence >= 0L)
        val prior = loadUnlocked(context)?.sequence ?: 0L
        val existingState = readMarkerState(clearedThroughFile(context))
        val mismatchState = readMarkerState(mismatchFile(context))
        val lastAppliedState = readMarkerState(lastAppliedFile(context))
        val existing = (existingState as? MarkerState.Valid)?.sequence ?: 0L
        val lastApplied = (lastAppliedState as? MarkerState.Valid)?.sequence ?: -1L
        // DataItems on distinct paths are not an ordering channel. A delayed tombstone from an old
        // clear must never erase a newer snapshot that already superseded it, including when its
        // display cache was lost but its independently fsynced ordering floor remains.
        if (maxOf(prior, lastApplied) > sequence) {
            return@synchronized ClearResult(maxOf(prior, lastApplied), deleted = false)
        }
        val mismatchFloor = (mismatchState as? MarkerState.Valid)?.sequence ?: -1L
        // Preserve incompatibility guidance and its ordering floor. Explicit deletion removes health
        // measurements; only a newer compatible payload proves the version issue is resolved.
        val clearedThrough = maxOf(sequence, prior, existing, mismatchFloor, lastApplied)
        writeMarkerSequence(clearedThroughFile(context), clearedThrough)
        // The fsynced barrier is the privacy commit point. Hide in-memory measurements immediately;
        // physical cleanup can fail and be retried, but an open dashboard must never retain them.
        mutableSnapshots.value = null
        mutableVersionMismatch.value = mismatchState is MarkerState.Valid
        mutableOrderingCorrupt.value = false
        val snapshot = snapshotFile(context)
        val removed = !snapshot.exists() || (deleteSnapshotOverride?.invoke(snapshot) ?: snapshot.delete())
        if (removed) {
            // A valid explicit clear target is the recovery path for unreadable ordering metadata.
            // The clear barrier now owns monotonicity, so corrupt auxiliary floors can be discarded
            // only after that barrier is fsynced and measurements are gone.
            if (mismatchState is MarkerState.Corrupt) clearMarkerUnlocked(mismatchFile(context))
            if (lastAppliedState is MarkerState.Corrupt) clearMarkerUnlocked(lastAppliedFile(context))
        }
        ClearResult(clearedThrough, deleted = removed, barrierCommitted = true)
    }

    /** Test/local reset which removes all repository state, including the deletion tombstone. */
    fun clear(context: Context) = synchronized(lock) {
        deleteSnapshotOverride = null
        writeSnapshotOverride = null
        snapshotFile(context).parentFile?.let { check(!it.exists() || it.deleteRecursively()) }
        mutableSnapshots.value = null
        mutableVersionMismatch.value = false
        mutableOrderingCorrupt.value = false
    }

    /** Returns false for a reordered mismatch older than already accepted compatible data. */
    fun recordVersionMismatch(context: Context, sequence: Long): Boolean = synchronized(lock) {
        require(sequence >= 0L)
        val currentSequence = loadUnlocked(context)?.sequence ?: -1L
        val clearState = readMarkerState(clearedThroughFile(context))
        val lastAppliedState = readMarkerState(lastAppliedFile(context))
        if (clearState is MarkerState.Corrupt || lastAppliedState is MarkerState.Corrupt) {
            mutableOrderingCorrupt.value = true
            return@synchronized false
        }
        val clearFloor = clearState.sequenceOrMinusOne()
        if (sequence <= maxOf(currentSequence, clearFloor, lastAppliedState.sequenceOrMinusOne())) {
            return@synchronized false
        }
        val mismatchState = readMarkerState(mismatchFile(context))
        if (mismatchState is MarkerState.Corrupt) {
            mutableOrderingCorrupt.value = true
            return@synchronized false
        }
        val existing = mismatchState.sequenceOrMinusOne()
        writeMarkerSequence(mismatchFile(context), maxOf(sequence, existing))
        mutableVersionMismatch.value = true
        true
    }

    private fun loadUnlocked(context: Context): WearHealthSnapshot? {
        val file = snapshotFile(context)
        val clearState = readMarkerState(clearedThroughFile(context))
        val mismatchState = readMarkerState(mismatchFile(context))
        val lastAppliedState = readMarkerState(lastAppliedFile(context))
        val corruptOrdering = clearState is MarkerState.Corrupt || mismatchState is MarkerState.Corrupt ||
            lastAppliedState is MarkerState.Corrupt
        mutableOrderingCorrupt.value = corruptOrdering
        if (corruptOrdering) {
            // Marker absence is distinct from malformed marker state. If an ordering barrier cannot
            // be trusted, hide and remove measurements rather than treating it as no deletion.
            runCatching { file.delete() }
            return null
        }
        if (!file.isFile) return null
        if (file.length() !in 1..WearHealthSnapshot.MAX_ENCODED_BYTES.toLong()) {
            runCatching { file.delete() }
            return null
        }
        val snapshot = WearHealthSnapshotCodec.decodeStored(
            runCatching { AtomicFile(file).readFully() }.getOrNull() ?: return null,
        ) ?: run {
            runCatching { file.delete() }
            return null
        }
        val clearedThrough = clearState.sequenceOrMinusOne()
        val lastApplied = lastAppliedState.sequenceOrMinusOne()
        // Ordering markers are fsynced before their associated cache mutation. If a process dies or
        // deletion/replacement fails in between, never reload older data; finish cleanup best-effort.
        if (snapshot.sequence <= clearedThrough || (lastApplied >= 0L && snapshot.sequence < lastApplied)) {
            runCatching { file.delete() }
            return null
        }
        // Migrate a structurally valid pre-marker cache on first read so later byte corruption cannot
        // erase the only monotonic floor and resurrect an older Data Layer event.
        if (lastAppliedState is MarkerState.Absent) {
            writeMarkerSequence(lastAppliedFile(context), snapshot.sequence)
        }
        return snapshot
    }

    private fun clearMismatchUnlocked(context: Context) {
        clearMarkerUnlocked(mismatchFile(context))
        mutableVersionMismatch.value = false
    }

    private fun writeMarkerSequence(target: File, sequence: Long) {
        check(target.parentFile?.exists() == true || target.parentFile?.mkdirs() == true)
        writeAtomic(target, "$sequence\n".encodeToByteArray())
    }

    private sealed interface MarkerState {
        data object Absent : MarkerState
        data class Valid(val sequence: Long) : MarkerState
        data object Corrupt : MarkerState
    }

    private fun MarkerState.sequenceOrMinusOne(): Long = (this as? MarkerState.Valid)?.sequence ?: -1L

    private fun readMarkerState(target: File): MarkerState {
        if (!target.exists()) return MarkerState.Absent
        if (!target.isFile || target.length() !in 1..32) return MarkerState.Corrupt
        val sequence = runCatching { AtomicFile(target).readFully().decodeToString().trim().toLong() }
            .getOrNull()?.takeIf { it >= 0L }
        return sequence?.let(MarkerState::Valid) ?: MarkerState.Corrupt
    }

    private fun writeAtomic(target: File, bytes: ByteArray) {
        val atomic = AtomicFile(target)
        val output = atomic.startWrite()
        try {
            output.write(bytes)
            output.flush()
            output.fd.sync()
            atomic.finishWrite(output)
        } catch (error: Exception) {
            atomic.failWrite(output)
            throw error
        }
    }

    private fun clearMarkerUnlocked(marker: File) = check(!marker.exists() || marker.delete())
    private fun snapshotFile(context: Context) = File(context.noBackupFilesDir, "wear-health/snapshot-v1.json")
    private fun mismatchFile(context: Context) = File(context.noBackupFilesDir, "wear-health/version-mismatch-v1")
    private fun clearedThroughFile(context: Context) = File(context.noBackupFilesDir, "wear-health/cleared-through-v1")
    private fun lastAppliedFile(context: Context) = File(context.noBackupFilesDir, "wear-health/last-applied-sequence-v1")
}
