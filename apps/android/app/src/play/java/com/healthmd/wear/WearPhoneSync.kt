package com.healthmd.wear

import android.content.Context
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.work.*
import com.google.android.gms.tasks.Task
import com.google.android.gms.wearable.*
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.widget.data.WidgetHealthDataSource
import com.healthmd.wearable.contract.*
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.suspendCancellableCoroutine
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeoutOrNull
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

internal object WearDataPermissionPolicy {
    val steps = HealthPermission.getReadPermission(StepsRecord::class)
    val activeCalories = HealthPermission.getReadPermission(ActiveCaloriesBurnedRecord::class)
    val exerciseSessions = HealthPermission.getReadPermission(ExerciseSessionRecord::class)
    val sleepSessions = HealthPermission.getReadPermission(SleepSessionRecord::class)
    val heartRate = HealthPermission.getReadPermission(HeartRateRecord::class)
    val restingHeartRate = HealthPermission.getReadPermission(RestingHeartRateRecord::class)
    val hrvRmssd = HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class)
    val oxygenSaturation = HealthPermission.getReadPermission(OxygenSaturationRecord::class)
    val all = setOf(
        steps, activeCalories, exerciseSessions, sleepSessions, heartRate,
        restingHeartRate, hrvRmssd, oxygenSaturation,
    )

    fun selection(granted: Set<String>) = HealthConnectWidgetReadSelection(
        steps = steps in granted,
        activeCalories = activeCalories in granted,
        exerciseSessions = exerciseSessions in granted,
        sleepSessions = sleepSessions in granted,
        heartRate = heartRate in granted,
        restingHeartRate = restingHeartRate in granted,
        hrvRmssd = hrvRmssd in granted,
        oxygenSaturation = oxygenSaturation in granted,
    )

    /** Permission names whose aggregate categories are actually present in the durable snapshot. */
    fun representedBy(snapshot: WearHealthSnapshot): Set<String> = buildSet {
        snapshot.days.forEach { day ->
            if (day.steps != null) add(steps)
            if (day.moveKilocalories != null) add(activeCalories)
            if (day.exerciseMinutes != null) add(exerciseSessions)
            if (day.sleepMinutes != null) add(sleepSessions)
            if (day.averageHeartRateBpm != null) add(heartRate)
            if (day.restingHeartRateBpm != null) add(restingHeartRate)
            if (day.hrvRmssdMillis != null) add(hrvRmssd)
            if (day.bloodOxygenPercent != null) add(oxygenSaturation)
        }
    }

    /** Strip each category whose grant disappeared while Health Connect records were being read. */
    fun redactRevoked(snapshot: WearHealthSnapshot, granted: Set<String>): WearHealthSnapshot = snapshot.copy(
        days = snapshot.days.map { day ->
            day.copy(
                steps = day.steps.takeIf { steps in granted },
                moveKilocalories = day.moveKilocalories.takeIf { activeCalories in granted },
                exerciseMinutes = day.exerciseMinutes.takeIf { exerciseSessions in granted },
                sleepMinutes = day.sleepMinutes.takeIf { sleepSessions in granted },
                averageHeartRateBpm = day.averageHeartRateBpm.takeIf { heartRate in granted },
                restingHeartRateBpm = day.restingHeartRateBpm.takeIf { restingHeartRate in granted },
                hrvRmssdMillis = day.hrvRmssdMillis.takeIf { hrvRmssd in granted },
                bloodOxygenPercent = day.bloodOxygenPercent.takeIf { oxygenSaturation in granted },
            )
        }.filter(WearHealthDay::hasAnyData),
        permissionState = if (granted.containsAll(all)) WearPermissionState.READY else WearPermissionState.PERMISSION_REQUIRED,
    )
}

@Singleton
class WearSnapshotProducer @Inject constructor(
    @ApplicationContext private val context: Context,
    private val healthConnect: HealthConnectManager,
    private val source: WidgetHealthDataSource,
) {
    suspend fun produce(now: Instant = Instant.now(), zone: ZoneId = ZoneId.systemDefault()): WearHealthSnapshot {
        val sequence = reserveSequence(now.toEpochMilli())
        if (!source.isAvailable()) return stateSnapshot(sequence, now, zone, WearPermissionState.HEALTH_CONNECT_UNAVAILABLE)
        val granted = healthConnect.getGrantedPermissions()
        val selection = WearDataPermissionPolicy.selection(granted)
        if (!selection.hasAny) return stateSnapshot(sequence, now, zone, WearPermissionState.PERMISSION_REQUIRED)
        val allGranted = granted.containsAll(WearDataPermissionPolicy.all)
        val days = source.readRecentDays(LocalDate.now(zone), selection, zoneId = zone).map { data ->
            // Session duration includes awake stages. Prefer actual asleep stages when provided.
            val stagedSleep = data.sleep.deepSleep + data.sleep.remSleep + data.sleep.lightSleep
            val sleep = stagedSleep.takeIf { it > kotlin.time.Duration.ZERO } ?: data.sleep.totalDuration
            WearHealthDay(
                localDate = data.date.toString(), steps = data.activity.steps,
                moveKilocalories = data.activity.activeCalories, exerciseMinutes = data.activity.exerciseMinutes,
                sleepMinutes = sleep.takeIf { it.isFinite() && it > kotlin.time.Duration.ZERO }?.inWholeMilliseconds?.div(60_000.0),
                restingHeartRateBpm = data.heart.restingHeartRate,
                averageHeartRateBpm = data.heart.averageHeartRate,
                hrvRmssdMillis = data.heart.hrv,
                bloodOxygenPercent = data.vitals.bloodOxygenAvg?.times(100.0),
            )
        }
        return WearHealthSnapshot(
            sequence = sequence, capturedAtEpochMillis = now.toEpochMilli(), capturedZoneId = zone.id,
            days = days, permissionState = if (allGranted) WearPermissionState.READY else WearPermissionState.PERMISSION_REQUIRED,
        )
    }

    private fun stateSnapshot(sequence: Long, now: Instant, zone: ZoneId, state: WearPermissionState) =
        WearHealthSnapshot(sequence = sequence, capturedAtEpochMillis = now.toEpochMilli(), capturedZoneId = zone.id, days = emptyList(), permissionState = state)

    /** Recheck every category immediately before publication, after potentially slow record reads. */
    internal suspend fun redactRevokedFields(snapshot: WearHealthSnapshot): WearHealthSnapshot =
        WearDataPermissionPolicy.redactRevoked(snapshot, healthConnect.getGrantedPermissions())

    internal suspend fun grantedDataPermissions(): Set<String> = healthConnect.getGrantedPermissions()

    /** Dedicated privacy work must never perform Health Connect reads or retain any aggregate. */
    internal fun producePermissionRedaction(
        now: Instant = Instant.now(),
        zone: ZoneId = ZoneId.systemDefault(),
    ): WearHealthSnapshot = stateSnapshot(
        sequence = reserveSequence(now.toEpochMilli()),
        now = now,
        zone = zone,
        state = WearPermissionState.PERMISSION_REQUIRED,
    )

    /** Reserve a barrier newer than every snapshot this phone has produced, even if status lagged. */
    internal fun reserveSequence(clock: Long = System.currentTimeMillis()): Long = synchronized(sequenceLock) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val next = maxOf(clock, prefs.getLong(SEQUENCE, 0L) + 1L)
        check(prefs.edit().putLong(SEQUENCE, next).commit())
        next
    }

    private companion object { const val PREFS = "wear-sync-private"; const val SEQUENCE = "sequence"; val sequenceLock = Any() }
}

@Singleton
class WearSyncStatusStore @Inject constructor(@ApplicationContext context: Context) {
    private val prefs = context.getSharedPreferences("wear-sync-private", Context.MODE_PRIVATE)
    private val clearAcknowledgements = MutableStateFlow<Map<String, WearSnapshotAck>>(emptyMap())
    private val transitionLock = Any()
    private val nodeAcknowledgements = MutableStateFlow<Map<String, WearSnapshotAck>>(emptyMap())
    private val mutableStatus = MutableStateFlow(readStatus())
    val statuses: StateFlow<WearPhoneSyncStatus> = mutableStatus.asStateFlow()

    private inline fun persist(edit: android.content.SharedPreferences.Editor.() -> Unit) {
        check(prefs.edit().apply(edit).commit())
        mutableStatus.value = readStatus()
    }

    fun recordAttempt(result: WearPhoneSyncResult, at: Long = System.currentTimeMillis()) {
        persist { putString("result", result.name).putLong("attempt", at) }
    }
    fun recordSource(state: WearPermissionState, hasAggregates: Boolean = false) {
        recordSource(state, hasAggregates, representedPermissions = null)
    }
    fun recordSource(snapshot: WearHealthSnapshot) {
        recordSource(
            snapshot.permissionState,
            snapshot.days.any(WearHealthDay::hasAnyData),
            WearDataPermissionPolicy.representedBy(snapshot),
        )
    }
    /**
     * Persist a fail-closed candidate before DataClient publication. A failed aggregate-free write
     * must not erase knowledge of aggregates still retained by the previous durable DataItem.
     */
    fun recordSourceCandidate(snapshot: WearHealthSnapshot) {
        val hasRecordedSource = prefs.contains("sourceState") || prefs.contains("sourceHasAggregates")
        val previousHasAggregates = when {
            !hasRecordedSource -> false
            !prefs.contains("sourceHasAggregates") -> true
            else -> prefs.getBoolean("sourceHasAggregates", true)
        }
        val hasRepresentedPermissions = prefs.contains("sourceRepresentedPermissions")
        val previousRepresented = prefs.getStringSet("sourceRepresentedPermissions", emptySet()).orEmpty()
        val representedStateIsAmbiguous = previousHasAggregates &&
            (!hasRepresentedPermissions || previousRepresented.isEmpty())
        val candidateRepresented = WearDataPermissionPolicy.representedBy(snapshot)
        val conservative = previousRepresented + candidateRepresented
        recordSource(
            state = if (previousHasAggregates) WearPermissionState.PERMISSION_REQUIRED else snapshot.permissionState,
            hasAggregates = previousHasAggregates || snapshot.days.any(WearHealthDay::hasAnyData),
            // A legacy aggregate-bearing DataItem may represent unknown categories. Keep that
            // ambiguity until a successful put replaces the durable bytes; a failed candidate
            // write must not convert unknown retained data into a proven aggregate-free state.
            representedPermissions = if (representedStateIsAmbiguous) null else conservative,
        )
    }
    private fun recordSource(
        state: WearPermissionState,
        hasAggregates: Boolean,
        representedPermissions: Set<String>?,
    ) {
        persist {
            putString("sourceState", state.name)
            putBoolean("sourceHasAggregates", hasAggregates)
            if (representedPermissions != null) {
                putStringSet("sourceRepresentedPermissions", representedPermissions)
            } else {
                // Existing callers and legacy preferences do not prove which categories were
                // retained. Preserve that ambiguity so permission reconciliation fails closed.
                remove("sourceRepresentedPermissions")
            }
        }
    }
    fun sourceNeedsPermissionRedaction(grantedPermissions: Set<String> = emptySet()): Boolean {
        // A truly fresh install has no known retained DataItem. Older records with source state but
        // no aggregate/category markers are ambiguous and migrate fail-closed.
        if (!prefs.contains("sourceState") && !prefs.contains("sourceHasAggregates")) return false
        if (!prefs.contains("sourceHasAggregates")) return true
        if (!prefs.getBoolean("sourceHasAggregates", true)) return false
        if (!prefs.contains("sourceRepresentedPermissions")) return true
        val represented = prefs.getStringSet("sourceRepresentedPermissions", emptySet()).orEmpty()
        return represented.isEmpty() || !grantedPermissions.containsAll(represented)
    }
    /** Whether a durable DataItem may still contain health aggregates and needs permission audit. */
    fun sourceMayContainAggregates(): Boolean = when {
        !prefs.contains("sourceState") && !prefs.contains("sourceHasAggregates") -> false
        !prefs.contains("sourceHasAggregates") -> true // Ambiguous legacy state fails closed.
        else -> prefs.getBoolean("sourceHasAggregates", true)
    }
    fun recordSourceRemoved() {
        persist {
            remove("sourceState").remove("sourceHasAggregates").remove("sourceRepresentedPermissions")
        }
    }
    /** Persist ACK correlation before DataClient publication so a fast watch ACK is never lost. */
    fun beginSend(sequence: Long, targetNodeIds: Set<String>) {
        if (sequence > prefs.getLong("sentSequence", -1L)) {
            nodeAcknowledgements.value = emptyMap()
            persist {
                putLong("sentSequence", sequence)
                    .putStringSet("sentTargetNodeIds", targetNodeIds)
                    .putStringSet("sentAckNodeIds", emptySet())
            }
        }
    }
    fun completeSend(
        sequence: Long,
        delivery: WearDeliveryState,
        at: Long = System.currentTimeMillis(),
    ) {
        if (sequence == prefs.getLong("sentSequence", -1L)) {
            persist { putLong("sentAt", at).putString("deliveryState", delivery.name) }
        }
    }
    fun recordSent(
        sequence: Long,
        delivery: WearDeliveryState,
        at: Long = System.currentTimeMillis(),
        targetNodeIds: Set<String> = emptySet(),
    ) {
        beginSend(sequence, targetNodeIds)
        completeSend(sequence, delivery, at)
    }
    fun recordClearRequested(
        sequence: Long,
        at: Long = System.currentTimeMillis(),
        targetNodeIds: Set<String> = emptySet(),
        workRequestId: String? = null,
    ) {
        persist {
            putLong("clearRequestedAt", at).putLong("clearSequence", sequence)
            if (workRequestId != null) putString("clearWorkRequestId", workRequestId)
            prefs.getString("deliveryState", null)?.let { putString("deliveryStateBeforeClear", it) }
                ?: remove("deliveryStateBeforeClear")
            putStringSet("clearTargetNodeIds", targetNodeIds)
            putStringSet("clearAckNodeIds", emptySet())
            putString("clearPhase", WearClearPhase.REQUESTED.name)
            putString("deliveryState", WearDeliveryState.CLEAR_REQUESTED.name)
        }
    }
    fun lastSentTargetNodeIds(): Set<String> =
        prefs.getStringSet("sentTargetNodeIds", emptySet()).orEmpty().toSet()
    fun attachClearWorkRequest(workRequestId: String) {
        if (pendingClear() != null) persist { putString("clearWorkRequestId", workRequestId) }
    }
    fun clearWorkRequestCompleted(workRequestId: String): Boolean =
        prefs.getString("completedClearWorkRequestId", null) == workRequestId
    fun completedClearResult(): WearPhoneSyncResult =
        prefs.getString("completedClearWorkRequestResult", null)
            ?.let { runCatching { WearPhoneSyncResult.valueOf(it) }.getOrNull() }
            ?: WearPhoneSyncResult.QUEUED
    fun addClearTargets(nodeIds: Set<String>) {
        if (nodeIds.isEmpty() || pendingClear() == null) return
        persist {
            putStringSet("clearTargetNodeIds", prefs.getStringSet("clearTargetNodeIds", emptySet()).orEmpty() + nodeIds)
        }
    }
    fun recordClearTombstoneStored() {
        if (pendingClear()?.phase == WearClearPhase.REQUESTED) {
            persist { putString("clearPhase", WearClearPhase.TOMBSTONE_STORED.name) }
        }
    }
    fun recordClearSnapshotRemoved() {
        val pending = pendingClear() ?: return
        if (pending.phase != WearClearPhase.SNAPSHOT_REMOVED) {
            persist { putString("clearPhase", WearClearPhase.SNAPSHOT_REMOVED.name) }
        }
    }
    fun pendingClear(): WearPendingClear? {
        val sequence = prefs.getLong("clearSequence", -1L)
        val phase = prefs.getString("clearPhase", null)?.let {
            runCatching { WearClearPhase.valueOf(it) }.getOrNull()
        }
        return if (sequence >= 0L && phase != null) WearPendingClear(sequence, phase) else null
    }
    fun beginClearAcknowledgements() {
        clearAcknowledgements.value = emptyMap()
    }
    suspend fun awaitClearAcknowledgements(nodeIds: Set<String>, sequence: Long, timeoutMillis: Long = 10_000L): Long? =
        withTimeoutOrNull(timeoutMillis) {
            clearAcknowledgements.filter { acknowledgements ->
                nodeIds.all { nodeId ->
                    acknowledgements[nodeId]?.let { it.accepted && it.reason == WearAckReason.DELETED && it.sequence >= sequence } == true
                }
            }.first().values.maxOf { it.sequence }
        }
    fun completeClear(clearedThroughSequence: Long): Boolean = synchronized(transitionLock) {
        val targets = prefs.getStringSet("clearTargetNodeIds", emptySet()).orEmpty()
        val acknowledgements = prefs.getStringSet("clearAckNodeIds", emptySet()).orEmpty()
        // A reachable subset cannot stand in for an offline capable watch. Global confirmation is
        // derived only from the complete persisted target inventory.
        val confirmed = targets.isNotEmpty() && acknowledgements.containsAll(targets)
        persist {
            putLong("clearedThroughSequence", clearedThroughSequence)
                .apply {
                    prefs.getString("clearWorkRequestId", null)?.let {
                        putString("completedClearWorkRequestId", it)
                        putString(
                            "completedClearWorkRequestResult",
                            if (confirmed) WearPhoneSyncResult.CLEARED.name else WearPhoneSyncResult.QUEUED.name,
                        )
                    }
                }
                .remove("clearRequestedAt").remove("clearSequence").remove("clearPhase")
                .remove("clearWorkRequestId").remove("deliveryStateBeforeClear")
                // Snapshot delivery counts describe data that no longer exists. Clear surfaces use
                // the independent clear target/ACK inventory until confirmation.
                .remove("sentTargetNodeIds").remove("sentAckNodeIds")
            if (confirmed) {
                remove("deliveryState").remove("clearTargetNodeIds").remove("clearAckNodeIds")
                putLong("ackSequence", clearedThroughSequence)
                putBoolean("ackAccepted", true)
                putString("ackReason", WearAckReason.DELETED.name)
            } else {
                // Phone state is gone and an aggregate-free tombstone is durable, but an offline
                // watch has not confirmed local deletion yet. Keep target inventory for late ACKs.
                putString("deliveryState", WearDeliveryState.CLEAR_REQUESTED.name)
                remove("ackSequence").remove("ackAccepted").remove("ackReason")
            }
        }
        confirmed
    }
    fun recordAck(ack: WearSnapshotAck) = recordAck(nodeId = null, ack)
    fun recordAck(nodeId: String?, ack: WearSnapshotAck) = synchronized(transitionLock) {
        val sent = prefs.getLong("sentSequence", -1L)
        val clearSequence = prefs.getLong("clearSequence", -1L)
        val clearedThrough = prefs.getLong("clearedThroughSequence", -1L)
        val clearTargets = prefs.getStringSet("clearTargetNodeIds", emptySet()).orEmpty()
        // Node-less ACKs are only a unit-test/convenience seam. Runtime ACKs must be attributable
        // to the capable-watch inventory persisted for the clear; an arbitrary Wear node must not
        // be able to resolve an active privacy transaction.
        val activeClearAck = clearSequence >= 0L && ack.reason == WearAckReason.DELETED && ack.accepted &&
            ack.sequence >= clearSequence && (nodeId == null || nodeId in clearTargets)
        val lateClearAck = clearSequence < 0L && clearedThrough >= 0L && nodeId != null && nodeId in clearTargets &&
            ack.reason == WearAckReason.DELETED && ack.accepted && ack.sequence >= clearedThrough
        val isPotentialClearAck = activeClearAck || lateClearAck
        if (nodeId != null && !isPotentialClearAck) {
            val targets = prefs.getStringSet("sentTargetNodeIds", emptySet()).orEmpty()
            // Ordinary acknowledgements describe only the current published transaction.
            if (ack.sequence != sent || nodeId !in targets) return
        }
        if (nodeId != null) {
            nodeAcknowledgements.update { current ->
                val existing = current[nodeId]
                val replaces = existing == null || ack.sequence > existing.sequence ||
                    (ack.sequence == existing.sequence && acknowledgementPrecedence(ack) > acknowledgementPrecedence(existing))
                if (replaces) current + (nodeId to ack) else current
            }
        }
        if (nodeId != null && ack.accepted && ack.reason == WearAckReason.DELETED) {
            clearAcknowledgements.update { it + (nodeId to ack) }
            if (isPotentialClearAck) {
                val acknowledgedNodes = prefs.getStringSet("clearAckNodeIds", emptySet()).orEmpty() + nodeId
                val confirmedLate = lateClearAck && clearTargets.isNotEmpty() && acknowledgedNodes.containsAll(clearTargets)
                persist {
                    putStringSet("clearAckNodeIds", acknowledgedNodes)
                    // While the transaction is active, awaitClearAcknowledgements/completeClear own
                    // aggregate completion. Only a post-transaction ACK directly resolves UI state.
                    if (confirmedLate) {
                        remove("clearTargetNodeIds").remove("clearAckNodeIds")
                        // A delayed privacy confirmation resolves only the retained clear inventory.
                        // Never let it erase or regress a newer snapshot transaction's delivery/ACK
                        // state after ordinary publication has advanced beyond the clear barrier.
                        if (sent <= clearedThrough) {
                            remove("deliveryState")
                            putLong("ackSequence", maxOf(ack.sequence, clearedThrough))
                            putBoolean("ackAccepted", true)
                            putString("ackReason", WearAckReason.DELETED.name)
                        }
                    }
                }
            }
        }
        val previous = prefs.getLong("ackSequence", -1L)
        // The watch reports the durable cleared-through ordering barrier. It must be at or above
        // the pre-persisted phone target before it can participate in clear completion.
        val isClearAck = isPotentialClearAck
        // Clear completion is aggregate across the connected-node inventory captured by the active
        // transaction. Do not expose an individual node's DELETED ACK as global success.
        if (isClearAck) return
        // Normal ACKs are strictly monotonic and correlated to a sent snapshot. A clear ACK may
        // advance beyond the last applied sequence when the phone target is newer than local cache.
        // Retain the cleared-through target after the pending request is removed: delayed ACKs for
        // pre-clear snapshots cannot replace DELETED, while a later sent sequence can report its
        // ordinary ACK and return Settings to truthful synchronized state.
        if (!isClearAck && (ack.sequence > sent || ack.sequence < previous || ack.sequence <= clearedThrough)) return
        val effective = if (nodeId == null || isClearAck) ack else {
            val received = nodeAcknowledgements.value.values.filter { it.sequence == ack.sequence }
                .maxByOrNull { acknowledgementPrecedence(it) } ?: ack
            val persisted = status().takeIf { it.acknowledgedSequence == ack.sequence }?.let {
                WearSnapshotAck(ack.sequence, it.acknowledged, it.ackReason)
            }
            listOfNotNull(received, persisted).maxBy { acknowledgementPrecedence(it) }
        }
        persist {
            putLong("ackSequence", effective.sequence).putBoolean("ackAccepted", effective.accepted)
                .putString("ackReason", effective.reason?.name)
            if (nodeId != null && effective.sequence == sent) {
                putStringSet("sentAckNodeIds", prefs.getStringSet("sentAckNodeIds", emptySet()).orEmpty() + nodeId)
            }
        }
    }
    fun status(): WearPhoneSyncStatus = mutableStatus.value
    private fun readStatus(): WearPhoneSyncStatus {
        val delivery = prefs.getString("deliveryState", null)
            ?.let { runCatching { WearDeliveryState.valueOf(it) }.getOrNull() }
        val clearVisible = delivery == WearDeliveryState.CLEAR_REQUESTED
        val targetKey = if (clearVisible) "clearTargetNodeIds" else "sentTargetNodeIds"
        val acknowledgementKey = if (clearVisible) "clearAckNodeIds" else "sentAckNodeIds"
        return WearPhoneSyncStatus(
            result = prefs.getString("result", null)?.let { runCatching { WearPhoneSyncResult.valueOf(it) }.getOrNull() },
            sourceState = prefs.getString("sourceState", null)?.let { runCatching { WearPermissionState.valueOf(it) }.getOrNull() },
            deliveryState = delivery,
            lastAttemptEpochMillis = prefs.getLong("attempt", 0L).takeIf { it > 0 },
            lastSentEpochMillis = prefs.getLong("sentAt", 0L).takeIf { it > 0 },
            sentSequence = prefs.getLong("sentSequence", -1L).takeIf { it >= 0 },
            acknowledgedSequence = prefs.getLong("ackSequence", -1L).takeIf { it >= 0 },
            acknowledged = prefs.getBoolean("ackAccepted", false),
            ackReason = prefs.getString("ackReason", null)?.let { runCatching { WearAckReason.valueOf(it) }.getOrNull() },
            targetedWatchCount = prefs.getStringSet(targetKey, emptySet()).orEmpty().size,
            acknowledgedWatchCount = prefs.getStringSet(acknowledgementKey, emptySet()).orEmpty().size,
        )
    }
}

internal fun syncFailureResult(
    redactRetainedState: Boolean,
    error: Throwable,
): WearPhoneSyncResult = when {
    redactRetainedState -> WearPhoneSyncResult.RETRY
    error is SecurityException -> WearPhoneSyncResult.PERMISSION_REQUIRED
    else -> WearPhoneSyncResult.RETRY
}

internal fun workerResult(result: WearPhoneSyncResult): ListenableWorker.Result =
    if (result == WearPhoneSyncResult.RETRY) ListenableWorker.Result.retry() else ListenableWorker.Result.success()

internal suspend fun runPermissionAudit(
    sync: WearPhoneSync,
    scheduler: WearPhoneSyncScheduler,
): ListenableWorker.Result = when (val eligibility = scheduler.permissionAuditEligibility()) {
    WearPhoneSyncScheduler.Eligibility.UNKNOWN -> ListenableWorker.Result.retry()
    WearPhoneSyncScheduler.Eligibility.PERMISSION_REVOKED -> runPermissionRedaction(sync, scheduler)
    else -> {
        // Grants still cover every represented category. Re-evaluate full current eligibility
        // instead of letting a stale audit force INELIGIBLE and cancel newly available periodic
        // synchronization after background access or watch capability changes.
        scheduler.reconcile()
        ListenableWorker.Result.success()
    }
}

internal suspend fun runPermissionRedaction(
    sync: WearPhoneSync,
    scheduler: WearPhoneSyncScheduler,
): ListenableWorker.Result {
    val result = sync.sync(redactRetainedState = true)
    // Re-evaluate after successful replacement so still-granted categories may resume periodic
    // delivery when background access remains available. A retry remains fail-closed and queued.
    if (result == WearPhoneSyncResult.RETRY) {
        scheduler.reconcile(WearPhoneSyncScheduler.Eligibility.INELIGIBLE)
    } else {
        scheduler.reconcile()
    }
    return workerResult(result)
}

private fun acknowledgementPrecedence(ack: WearSnapshotAck): Int = when (ack.reason) {
    WearAckReason.VERSION_MISMATCH -> 6
    WearAckReason.INVALID -> 5
    WearAckReason.OUT_OF_ORDER -> 4
    WearAckReason.DELETED -> 3
    WearAckReason.APPLIED -> 2
    WearAckReason.DUPLICATE -> 1
    null -> 0
}

data class WearPhoneSyncStatus(
    val result: WearPhoneSyncResult?, val sourceState: WearPermissionState?, val deliveryState: WearDeliveryState?,
    val lastAttemptEpochMillis: Long?, val lastSentEpochMillis: Long?, val sentSequence: Long?,
    val acknowledgedSequence: Long?, val acknowledged: Boolean, val ackReason: WearAckReason?,
    val targetedWatchCount: Int = 0, val acknowledgedWatchCount: Int = 0,
)
data class WearPendingClear(val sequence: Long, val phase: WearClearPhase)
enum class WearClearPhase { REQUESTED, TOMBSTONE_STORED, SNAPSHOT_REMOVED }
enum class WearDeliveryState { REACHABLE, QUEUED, CLEAR_REQUESTED }
enum class WearPhoneSyncResult { SENT, QUEUED, NO_WATCH, UNREACHABLE, PERMISSION_REQUIRED, HEALTH_CONNECT_UNAVAILABLE, RETRY, CLEARED }

@Singleton
class WearPhoneSync @Inject constructor(
    @ApplicationContext private val context: Context,
    private val producer: WearSnapshotProducer,
    private val status: WearSyncStatusStore,
) {
    internal var capabilityClientFactory: (Context) -> CapabilityClient = Wearable::getCapabilityClient
    internal var dataClientFactory: (Context) -> DataClient = Wearable::getDataClient
    internal var messageClientFactory: (Context) -> MessageClient = Wearable::getMessageClient
    // Serialize the full produce/write and clear transactions. Otherwise a slow older producer can
    // overwrite the single durable DataItem after a newer sync, or a sync can repopulate it while
    // the user is clearing watch data.
    private val transactionMutex = Mutex()

    suspend fun sync(
        userInitiated: Boolean = false,
        redactRetainedState: Boolean = false,
    ): WearPhoneSyncResult = transactionMutex.withLock {
        // An explicit privacy request always wins, including against an already-enqueued worker that
        // races application startup. Finish it under the same transaction lock before any produce.
        status.pendingClear()?.let { return@withLock clearWatchDataLocked(it.sequence) }
        var privacyOperation = redactRetainedState
        val result = try {
            val capabilityClient = capabilityClientFactory(context)
            val installed = capabilityClient.getCapability(WearDataPaths.CAPABILITY_WATCH, CapabilityClient.FILTER_ALL).awaitResult()
                ?: return record(WearPhoneSyncResult.RETRY)
            // Permission revocation must overwrite an aggregate-bearing durable DataItem even when
            // no capable watch is currently installed. DataClient retains that aggregate-free
            // state for future linked nodes, closing delivery-before-capability-redaction races.
            val privacyRedaction = redactRetainedState ||
                status.sourceNeedsPermissionRedaction(producer.grantedDataPermissions())
            privacyOperation = privacyRedaction
            if (installed.nodes.isEmpty() && !privacyRedaction) {
                return record(WearPhoneSyncResult.NO_WATCH)
            }
            // Reachability is presentation-only for a dedicated privacy replacement. Requiring a
            // second capability query before DataClient.putDataItem could leave revoked aggregates
            // durable even though the aggregate-free write path itself is healthy. Conservatively
            // report that replacement as queued and let node-correlated ACKs refine status later.
            val reachable = if (privacyRedaction) null else {
                capabilityClient.getCapability(
                    WearDataPaths.CAPABILITY_WATCH,
                    CapabilityClient.FILTER_REACHABLE,
                ).awaitResult() ?: return record(WearPhoneSyncResult.RETRY)
            }
            val produced = if (privacyRedaction) {
                // Dedicated redaction bypasses record reads entirely, including when only one
                // category was revoked and background Health Connect access is unavailable.
                producer.producePermissionRedaction()
            } else {
                try {
                    producer.produce()
                } catch (error: SecurityException) {
                    // A permission can disappear during a slow Health Connect read. Replace any
                    // retained aggregate in this same serialized transaction rather than waiting
                    // for a later lifecycle or periodic reconciliation.
                    producer.producePermissionRedaction()
                }
            }
            // Record reads may outlive individual grants observed at their start. Recheck every
            // category under the publication mutex immediately before constructing the DataItem.
            val snapshot = if (privacyRedaction || produced.days.none(WearHealthDay::hasAnyData)) {
                produced
            } else {
                try {
                    producer.redactRevokedFields(produced)
                } catch (error: SecurityException) {
                    producer.producePermissionRedaction()
                }
            }
            // DataClient queues durable state for all capable installed watches, including those
            // currently offline. Persist that inventory so reconnect ACKs remain attributable.
            val targetNodeIds = installed.nodes.mapTo(linkedSetOf()) { it.id }
            status.beginSend(snapshot.sequence, targetNodeIds)
            // Persist the exact represented category set before publishing durable bytes. If the
            // process dies after DataClient accepts the item, subsequent permission reconciliation
            // must conservatively know what may be retained. A failed put can cause only an
            // unnecessary aggregate-free replacement, never missed redaction.
            status.recordSourceCandidate(snapshot)
            val request = PutDataMapRequest.create(WearDataPaths.SNAPSHOT).apply {
                dataMap.putByteArray("snapshot", WearHealthSnapshotCodec.encode(snapshot)); dataMap.putLong("sequence", snapshot.sequence)
            }.asPutDataRequest().let { if (userInitiated) it.setUrgent() else it }
            dataClientFactory(context).putDataItem(request).awaitRequired()
            // Only a successful durable put can replace the conservative pre-publication record.
            status.recordSource(snapshot)
            // A newer accepted snapshot supersedes any prior durable clear tombstone. Remove it
            // only after the replacement DataItem is stored so reconnecting watches cannot observe
            // an empty ordering gap.
            dataClientFactory(context).deleteDataItems(UriBuilder.tombstone(), DataClient.FILTER_LITERAL).awaitRequired()
            val reachableNow = reachable?.nodes?.isNotEmpty() == true
            status.completeSend(
                snapshot.sequence,
                if (reachableNow) WearDeliveryState.REACHABLE else WearDeliveryState.QUEUED,
            )
            if (!reachableNow) WearPhoneSyncResult.QUEUED else when (snapshot.permissionState) {
                WearPermissionState.PERMISSION_REQUIRED -> WearPhoneSyncResult.PERMISSION_REQUIRED
                WearPermissionState.HEALTH_CONNECT_UNAVAILABLE -> WearPhoneSyncResult.HEALTH_CONNECT_UNAVAILABLE
                WearPermissionState.READY -> WearPhoneSyncResult.SENT
            }
        } catch (error: CancellationException) { throw error } catch (error: Exception) {
            syncFailureResult(privacyOperation, error)
        }
        record(result)
    }

    /**
     * Begin or resume a clear from its already-durable WorkManager owner. The worker exists before
     * this method reserves/persists the privacy transaction, so process death cannot strand an
     * intent between SharedPreferences and WorkManager. A sync that finishes before this worker is
     * ordered before the newly reserved barrier; once REQUESTED is persisted, every sync resumes it.
     */
    suspend fun startOrResumeClear(workRequestId: String): WearPhoneSyncResult = transactionMutex.withLock {
        require(workRequestId.isNotBlank())
        if (status.clearWorkRequestCompleted(workRequestId)) {
            return@withLock record(status.completedClearResult())
        }
        val pending = status.pendingClear()
        val targetSequence = pending?.sequence?.also { status.attachClearWorkRequest(workRequestId) }
            ?: producer.reserveSequence().also { sequence ->
                // Seed from the last durable target inventory before capability discovery; a
                // transient lookup failure must not make reconnect ACKs unattributable.
                status.recordClearRequested(
                    sequence,
                    targetNodeIds = status.lastSentTargetNodeIds(),
                    workRequestId = workRequestId,
                )
            }
        clearWatchDataLocked(targetSequence)
    }

    /** Resume a privacy transaction whose durable phase survived process death. */
    suspend fun resumePendingClear(): WearPhoneSyncResult? = transactionMutex.withLock {
        val pending = status.pendingClear() ?: return@withLock null
        clearWatchDataLocked(pending.sequence)
    }

    private suspend fun clearWatchDataLocked(targetSequence: Long): WearPhoneSyncResult = try {
        val dataClient = dataClientFactory(context)
        val pending = status.pendingClear() ?: return record(WearPhoneSyncResult.RETRY)
        val request = WearDeleteRequestCodec.encode(WearDeleteRequest(targetSequence))
        if (pending.phase == WearClearPhase.REQUESTED) {
            // Capture reachable targets before publication so an immediate tombstone ACK is
            // attributable, but capability failure is not proof that no watch exists.
            val initialTargets = capabilityClientFactory(context)
                .getCapability(WearDataPaths.CAPABILITY_WATCH, CapabilityClient.FILTER_ALL).awaitResult()
                ?.nodes?.mapTo(linkedSetOf()) { it.id }.orEmpty()
            status.addClearTargets(initialTargets)
        }
        status.beginClearAcknowledgements()
        if (pending.phase == WearClearPhase.REQUESTED) {
            // Persist the aggregate-free tombstone first. This phase is committed before continuing
            // so cancellation/process death can never restore pre-clear delivery status afterward.
            val tombstone = PutDataMapRequest.create(WearDataPaths.TOMBSTONE).apply {
                dataMap.putByteArray("request", request)
            }.asPutDataRequest().setUrgent()
            dataClient.putDataItem(tombstone).awaitRequired()
            status.recordClearTombstoneStored()
        }
        if (status.pendingClear()?.phase != WearClearPhase.SNAPSHOT_REMOVED) {
            // Wildcard authority removes durable snapshots regardless of their originating node.
            dataClient.deleteDataItems(UriBuilder.snapshot(), DataClient.FILTER_LITERAL).awaitRequired()
            status.recordClearSnapshotRemoved()
        }
        // Once the durable snapshot path is absent, no aggregate-bearing permission audit is needed.
        // Repeat this after process recreation when SNAPSHOT_REMOVED was already persisted.
        status.recordSourceRemoved()
        // Capability discovery is acceleration/confirmation only. The privacy action above remains
        // durable even if Play services cannot currently enumerate a watch.
        val connectedNodes = capabilityClientFactory(context)
            .getCapability(WearDataPaths.CAPABILITY_WATCH, CapabilityClient.FILTER_REACHABLE).awaitResult()
            ?.nodes.orEmpty()
        val nodeIds = connectedNodes.mapTo(linkedSetOf()) { it.id }
        status.addClearTargets(nodeIds)
        val messagedNodeIds = linkedSetOf<String>()
        connectedNodes.forEach { node ->
            val delivered = runCatching {
                messageClientFactory(context).sendMessage(node.id, WearDataPaths.DELETE, request).awaitRequired()
            }.isSuccess
            if (delivered) messagedNodeIds += node.id
        }
        // Wait briefly only for messages accepted by Play services. Missing ACK remains visibly
        // unconfirmed while the durable tombstone continues to cover offline/reconnecting watches.
        val watchClearedThrough = if (messagedNodeIds.isEmpty()) null else {
            status.awaitClearAcknowledgements(messagedNodeIds, targetSequence, timeoutMillis = 1_000L)
        }
        val confirmed = status.completeClear(
            clearedThroughSequence = maxOf(targetSequence, watchClearedThrough ?: targetSequence),
        )
        record(if (confirmed) WearPhoneSyncResult.CLEARED else WearPhoneSyncResult.QUEUED)
    } catch (error: CancellationException) {
        // Google Play services Tasks can complete after coroutine cancellation. Retain even a
        // REQUESTED phase so startup/next sync idempotently finishes the privacy transaction.
        throw error
    } catch (_: Exception) {
        // A failed/cancelled Play services Task can race an underlying operation completing. Retain
        // even REQUESTED rather than guessing no mutation occurred; startup or the next sync retries
        // the idempotent clear before any health snapshot can be produced.
        record(WearPhoneSyncResult.RETRY)
    }
    private fun record(value: WearPhoneSyncResult): WearPhoneSyncResult = value.also(status::recordAttempt)
}

internal object UriBuilder {
    fun snapshot() = android.net.Uri.Builder().scheme("wear").authority("*").path(WearDataPaths.SNAPSHOT).build()
    fun tombstone() = android.net.Uri.Builder().scheme("wear").authority("*").path(WearDataPaths.TOMBSTONE).build()
}
private class PlayServicesTaskCanceledException : Exception("Google Play services Task was cancelled")

private suspend fun <T> Task<T>.awaitResult(): T? {
    if (isComplete) return if (isSuccessful) result else null
    return suspendCancellableCoroutine { continuation ->
        addOnSuccessListener { continuation.resume(it) }
        addOnFailureListener { continuation.resume(null) }
        // Transport cancellation is a transient API result, not cancellation of the owning worker.
        addOnCanceledListener { continuation.resume(null) }
    }
}
private suspend fun <T> Task<T>.awaitRequired(): T {
    if (isComplete) {
        if (isSuccessful) return result
        if (isCanceled) throw PlayServicesTaskCanceledException()
        throw exception ?: IllegalStateException("Google Play services Task failed without an exception")
    }
    return suspendCancellableCoroutine { continuation ->
        addOnSuccessListener { continuation.resume(it) }
        addOnFailureListener(continuation::resumeWithException)
        addOnCanceledListener { continuation.resumeWithException(PlayServicesTaskCanceledException()) }
    }
}

class WearPhoneSyncWorker(context: Context, params: WorkerParameters) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result {
        val entry = dagger.hilt.android.EntryPointAccessors.fromApplication(applicationContext, WearSyncEntryPoint::class.java)
        val user = inputData.getBoolean(USER_INITIATED, false)
        val clearRequest = inputData.getBoolean(CLEAR_REQUEST, false)
        val clearRecovery = inputData.getBoolean(CLEAR_RECOVERY, false)
        val permissionRedaction = inputData.getBoolean(PERMISSION_REDACTION, false)
        val permissionAudit = inputData.getBoolean(PERMISSION_AUDIT, false)
        // A user clear is first made durable as this WorkRequest; only its worker reserves and
        // persists REQUESTED. Recovery bypasses Health Connect/background eligibility and retries
        // until the durable tombstone and phone snapshot removal have completed.
        if (clearRequest) {
            val requestId = inputData.getString(CLEAR_REQUEST_ID) ?: return Result.failure()
            val result = entry.sync().startOrResumeClear(requestId)
            if (result != WearPhoneSyncResult.RETRY) entry.scheduler().reconcile()
            return workerResult(result)
        }
        if (clearRecovery || entry.status().pendingClear() != null) {
            val result = entry.sync().resumePendingClear() ?: return Result.success()
            if (result != WearPhoneSyncResult.RETRY) entry.scheduler().reconcile()
            return workerResult(result)
        }
        if (permissionRedaction) {
            return runPermissionRedaction(entry.sync(), entry.scheduler())
        }
        if (permissionAudit) {
            return runPermissionAudit(entry.sync(), entry.scheduler())
        }
        if (!user) {
            when (val eligibility = entry.scheduler().backgroundEligibility()) {
                WearPhoneSyncScheduler.Eligibility.UNKNOWN -> return Result.retry()
                WearPhoneSyncScheduler.Eligibility.PERMISSION_REVOKED -> {
                    // Replace retained aggregates even if capability inventory became empty after
                    // eligibility was evaluated. This path performs no record reads.
                    return runPermissionRedaction(entry.sync(), entry.scheduler())
                }
                WearPhoneSyncScheduler.Eligibility.INELIGIBLE -> {
                    entry.scheduler().reconcile(eligibility)
                    return Result.success()
                }
                WearPhoneSyncScheduler.Eligibility.ELIGIBLE -> Unit
            }
        }
        val result = entry.sync().sync(user)
        // A user-initiated foreground publication may be allowed without background Health Connect
        // access. Reconcile afterward so a permission-only periodic audit remains durable.
        entry.scheduler().reconcile()
        return workerResult(result)
    }
    companion object {
        const val USER_INITIATED = "wear-user-initiated"
        const val CLEAR_REQUEST = "wear-clear-request"
        const val CLEAR_REQUEST_ID = "wear-clear-request-id"
        const val CLEAR_RECOVERY = "wear-clear-recovery"
        const val PERMISSION_REDACTION = "wear-permission-redaction"
        const val PERMISSION_AUDIT = "wear-permission-audit"
    }
}

@Singleton
class WearPhoneSyncScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val healthConnect: HealthConnectManager,
    private val status: WearSyncStatusStore,
) {
    internal var workManagerOverride: WorkManager? = null
    private val workManager get() = workManagerOverride ?: WorkManager.getInstance(context)

    enum class Eligibility { ELIGIBLE, INELIGIBLE, PERMISSION_REVOKED, UNKNOWN }

    internal fun eligibility(
        hasWatch: Boolean,
        backgroundGranted: Boolean,
        anyDataGranted: Boolean,
        retainedStateNeedsRedaction: Boolean = !anyDataGranted,
    ): Eligibility = when {
        // Revocation of any category represented in the durable snapshot is a privacy transition,
        // even if another data permission remains or no watch is currently discoverable.
        retainedStateNeedsRedaction -> Eligibility.PERMISSION_REVOKED
        !anyDataGranted || !hasWatch -> Eligibility.INELIGIBLE
        backgroundGranted -> Eligibility.ELIGIBLE
        else -> Eligibility.INELIGIBLE
    }

    suspend fun backgroundEligibility(): Eligibility {
        // Evaluate Health Connect first: absence of a capable watch must not suppress removal of a
        // previously retained aggregate-bearing DataItem after full permission revocation.
        val granted = runCatching { healthConnect.getGrantedPermissions() }.getOrElse { return Eligibility.UNKNOWN }
        val background = healthConnect.permissionPlan().backgroundReadPermissions
        val anyDataGranted = WearDataPermissionPolicy.all.any(granted::contains)
        val retainedStateNeedsRedaction = status.sourceNeedsPermissionRedaction(granted)
        if (retainedStateNeedsRedaction) return Eligibility.PERMISSION_REVOKED
        if (!anyDataGranted) return Eligibility.INELIGIBLE
        val capability = Wearable.getCapabilityClient(context)
            .getCapability(WearDataPaths.CAPABILITY_WATCH, CapabilityClient.FILTER_ALL).awaitResult()
            ?: return Eligibility.UNKNOWN
        return eligibility(
            hasWatch = capability.nodes.isNotEmpty(),
            backgroundGranted = background.isNotEmpty() && granted.containsAll(background),
            anyDataGranted = true,
            retainedStateNeedsRedaction = false,
        )
    }

    /** Permission-only audit: never reads Health Connect records or requires background access. */
    internal suspend fun permissionAuditEligibility(): Eligibility {
        val granted = runCatching { healthConnect.getGrantedPermissions() }.getOrElse { return Eligibility.UNKNOWN }
        return if (status.sourceNeedsPermissionRedaction(granted)) {
            Eligibility.PERMISSION_REVOKED
        } else {
            Eligibility.INELIGIBLE
        }
    }

    suspend fun reconcile(knownEligibility: Eligibility? = null) {
        val eligibility = knownEligibility ?: backgroundEligibility()
        // Normal periodic sync already audits grants before every read. When it cannot remain
        // scheduled (most importantly, after a foreground publication without background access),
        // retain a lightweight worker that checks only permission names and redacts if necessary.
        if (status.sourceMayContainAggregates() && eligibility != Eligibility.ELIGIBLE) {
            workManager.enqueueUniquePeriodicWork(
                PERMISSION_AUDIT_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                PeriodicWorkRequestBuilder<WearPhoneSyncWorker>(30, TimeUnit.MINUTES)
                    .setInputData(workDataOf(WearPhoneSyncWorker.PERMISSION_AUDIT to true))
                    .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                    .build(),
            )
        } else {
            workManager.cancelUniqueWork(PERMISSION_AUDIT_WORK_NAME)
        }
        when (eligibility) {
            Eligibility.UNKNOWN -> return // Transient API failures must not destroy valid periodic state.
            Eligibility.INELIGIBLE -> { workManager.cancelUniqueWork(PERIODIC_WORK_NAME); return }
            Eligibility.PERMISSION_REVOKED -> {
                workManager.cancelUniqueWork(PERIODIC_WORK_NAME)
                if (status.sourceNeedsPermissionRedaction()) {
                    workManager.enqueueUniqueWork(
                        PERMISSION_REDACTION_WORK_NAME,
                        ExistingWorkPolicy.KEEP,
                        OneTimeWorkRequestBuilder<WearPhoneSyncWorker>()
                            .setInputData(workDataOf(WearPhoneSyncWorker.PERMISSION_REDACTION to true))
                            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                            .build(),
                    )
                }
                return
            }
            Eligibility.ELIGIBLE -> Unit
        }
        workManager.enqueueUniquePeriodicWork(
            PERIODIC_WORK_NAME, ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<WearPhoneSyncWorker>(30, TimeUnit.MINUTES)
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS).build(),
        )
    }

    fun enqueueManual() = workManager.enqueueUniqueWork(
        MANUAL_WORK_NAME, ExistingWorkPolicy.REPLACE,
        OneTimeWorkRequestBuilder<WearPhoneSyncWorker>()
            .setInputData(workDataOf(WearPhoneSyncWorker.USER_INITIATED to true)).build(),
    )

    /** Persist the user privacy action in WorkManager before any clear transaction side effect. */
    fun enqueueClear() = workManager.enqueueUniqueWork(
        CLEAR_WORK_NAME,
        ExistingWorkPolicy.REPLACE,
        OneTimeWorkRequestBuilder<WearPhoneSyncWorker>()
            .setInputData(workDataOf(
                WearPhoneSyncWorker.CLEAR_REQUEST to true,
                WearPhoneSyncWorker.CLEAR_REQUEST_ID to UUID.randomUUID().toString(),
            ))
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .build(),
    )

    companion object {
        fun enqueueClearRecovery(context: Context) = WorkManager.getInstance(context).enqueueUniqueWork(
            CLEAR_WORK_NAME,
            ExistingWorkPolicy.KEEP,
            OneTimeWorkRequestBuilder<WearPhoneSyncWorker>()
                .setInputData(workDataOf(WearPhoneSyncWorker.CLEAR_RECOVERY to true))
                .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
                .build(),
        )
        const val PERIODIC_WORK_NAME = "wear-health-phone-sync-v1"
        const val MANUAL_WORK_NAME = "wear-health-phone-sync-manual-v1"
        const val CLEAR_WORK_NAME = "wear-health-phone-clear-v1"
        const val PERMISSION_REDACTION_WORK_NAME = "wear-health-phone-permission-redaction-v1"
        const val PERMISSION_AUDIT_WORK_NAME = "wear-health-phone-permission-audit-v1"
    }
}

@dagger.hilt.EntryPoint @dagger.hilt.InstallIn(dagger.hilt.components.SingletonComponent::class)
interface WearSyncEntryPoint {
    fun sync(): WearPhoneSync
    fun status(): WearSyncStatusStore
    fun scheduler(): WearPhoneSyncScheduler
}

class WearPhoneDataLayerService : WearableListenerService() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private fun entry() = dagger.hilt.android.EntryPointAccessors.fromApplication(applicationContext, WearSyncEntryPoint::class.java)

    override fun onMessageReceived(event: MessageEvent) {
        if (event.path == WearDataPaths.REFRESH) entry().scheduler().enqueueManual()
        if (event.path == WearDataPaths.ACK) WearSnapshotAckCodec.decode(event.data)?.let { ack ->
            entry().status().recordAck(event.sourceNodeId, ack)
        }
    }

    override fun onCapabilityChanged(info: CapabilityInfo) {
        if (info.name == WearDataPaths.CAPABILITY_WATCH) scope.launch { entry().scheduler().reconcile() }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
