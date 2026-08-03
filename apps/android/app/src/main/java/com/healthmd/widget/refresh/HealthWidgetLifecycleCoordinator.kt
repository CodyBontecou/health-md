package com.healthmd.widget.refresh

import com.healthmd.widget.data.HealthWidgetSnapshotRepository
import com.healthmd.widget.model.WidgetRefreshOutcome
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Instant
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration.Companion.minutes

@Singleton
class HealthWidgetLifecycleCoordinator @Inject constructor(
    private val instances: HealthWidgetInstanceRegistry,
    private val snapshots: HealthWidgetSnapshotRepository,
    private val refreshCoordinator: HealthWidgetRefreshCoordinator,
    private val scheduler: HealthWidgetRefreshScheduler,
) {
    private val foregroundRefreshLock = Mutex()

    suspend fun onInstancesChanged(
        deletedAppWidgetIds: Set<Int> = emptySet(),
        scheduleIfWidgetsRemain: Boolean = true,
    ) {
        if (!instances.hasWidgetsExcluding(deletedAppWidgetIds)) {
            runCatching { scheduler.cancel() }
            val deleted = try {
                refreshCoordinator.deleteSnapshotIfNoWidgets(deletedAppWidgetIds)
            } catch (error: Exception) {
                runCatching { scheduler.enqueueCleanup(deletedAppWidgetIds) }
                throw error
            }
            if (!deleted) {
                // A widget was added while WorkManager cancellation was still settling. Restore
                // the work that its onEnabled/onUpdate callback may have raced with cancellation.
                scheduler.enqueueImmediate()
                scheduler.reconcile()
            }
            return
        }
        if (!scheduleIfWidgetsRemain) return
        scheduler.enqueueImmediate()
        scheduler.reconcile()
    }

    suspend fun refreshFromForeground(
        force: Boolean = false,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): HealthWidgetRefreshResult = foregroundRefreshLock.withLock {
        if (!instances.hasWidgets()) return@withLock HealthWidgetRefreshResult.NO_WIDGETS
        if (!force) {
            val snapshot = runCatching { snapshots.load() }.getOrNull()
            val lastAttempt = snapshot?.lastAttemptAtEpochMillis
            val completedRead = snapshot?.lastAttemptOutcome == WidgetRefreshOutcome.SUCCESS ||
                snapshot?.lastAttemptOutcome == WidgetRefreshOutcome.NO_DATA
            if (
                completedRead &&
                lastAttempt != null &&
                now.toEpochMilli() >= lastAttempt &&
                now.toEpochMilli() - lastAttempt < FOREGROUND_REFRESH_THROTTLE.inWholeMilliseconds
            ) {
                reconcileIgnoringFailure()
                return@withLock HealthWidgetRefreshResult.UPDATED
            }
        }
        val result = refreshCoordinator.refresh(
            origin = HealthWidgetRefreshOrigin.FOREGROUND,
            now = now,
            zoneId = zoneId,
        )
        reconcileIgnoringFailure()
        result
    }

    private suspend fun reconcileIgnoringFailure() {
        try {
            scheduler.reconcile()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            // A refresh result remains valid even if WorkManager reconciliation is unavailable.
        }
    }

    private companion object {
        val FOREGROUND_REFRESH_THROTTLE = 15.minutes
    }
}
