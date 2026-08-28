package com.healthmd.data.scheduler

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.Uri
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.supervisorScope
import timber.log.Timber
import java.util.UUID

/**
 * Process-local, operation-scoped cancellation for WorkManager-owned scheduled exports.
 *
 * The notification action deliberately cancels only the exporter child job, not the owning
 * WorkRequest. Keeping the worker alive lets it durably reconcile exact residual owner dates,
 * clear its admission, and re-arm the schedule before WorkManager considers the attempt finished.
 */
internal object ScheduledExportCancellationCoordinator {
    private val lock = Any()
    private val preparedOperationIDs = mutableSetOf<UUID>()
    private val requestedOperationIDs = mutableSetOf<UUID>()
    private val activeJobs = mutableMapOf<UUID, Job>()
    private val notificationIDs = mutableMapOf<UUID, Int>()
    private var nextNotificationID = FOREGROUND_NOTIFICATION_ID_BASE

    /** Marks an operation as a valid notification target before exporter execution begins. */
    fun prepare(operationID: UUID) {
        synchronized(lock) { preparedOperationIDs += operationID }
    }

    /** Allocates a notification id that is collision-free among active WorkRequest UUIDs. */
    fun foregroundNotificationID(operationID: UUID): Int = synchronized(lock) {
        preparedOperationIDs += operationID
        notificationIDs.getOrPut(operationID) {
            var candidate = nextNotificationID
            while (candidate in notificationIDs.values) {
                candidate = if (candidate == Int.MAX_VALUE) {
                    FOREGROUND_NOTIFICATION_ID_BASE
                } else {
                    candidate + 1
                }
            }
            nextNotificationID = if (candidate == Int.MAX_VALUE) {
                FOREGROUND_NOTIFICATION_ID_BASE
            } else {
                candidate + 1
            }
            candidate
        }
    }

    /**
     * Requests cancellation for one exact active/preparing operation. Stale notification actions
     * are ignored, and a request that races exporter registration is consumed when [run] starts.
     */
    fun requestCancellation(operationID: UUID): Boolean {
        val job = synchronized(lock) {
            if (operationID !in preparedOperationIDs && operationID !in activeJobs) return false
            requestedOperationIDs += operationID
            activeJobs[operationID]
        }
        job?.cancel(CancellationException("Scheduled export cancelled by the user."))
        return true
    }

    /** Runs only the provider/destination scope as a cancellable child of the live worker. */
    suspend fun <T> run(operationID: UUID, operation: suspend () -> T): T = supervisorScope {
        var completed = false
        var completedValue: T? = null
        val child = async(start = CoroutineStart.LAZY) {
            operation().also { value ->
                synchronized(lock) {
                    completedValue = value
                    completed = true
                }
            }
        }
        val cancelImmediately = synchronized(lock) {
            preparedOperationIDs += operationID
            activeJobs[operationID] = child
            requestedOperationIDs.remove(operationID)
        }
        if (cancelImmediately) {
            child.cancel(CancellationException("Scheduled export cancelled before execution."))
        }
        try {
            child.start()
            try {
                child.await()
            } catch (cancelled: CancellationException) {
                val (captured, cancelledByUser) = synchronized(lock) {
                    val value = if (completed) CompletedValue(completedValue) else null
                    value to (cancelImmediately || operationID in requestedOperationIDs)
                }
                if (captured != null && cancelledByUser) {
                    @Suppress("UNCHECKED_CAST")
                    captured.value as T
                } else {
                    // Parent WorkManager cancellation must propagate even if an exporter managed
                    // to construct a cooperative result before its Deferred became cancelled.
                    throw cancelled
                }
            }
        } finally {
            synchronized(lock) {
                if (activeJobs[operationID] === child) activeJobs.remove(operationID)
            }
        }
    }

    /** Removes stale action state when the owning WorkRequest reaches any terminal path. */
    fun finish(operationID: UUID) {
        val active = synchronized(lock) {
            preparedOperationIDs.remove(operationID)
            requestedOperationIDs.remove(operationID)
            notificationIDs.remove(operationID)
            activeJobs.remove(operationID)
        }
        active?.cancel()
    }

    private data class CompletedValue<T>(val value: T?)

    private const val FOREGROUND_NOTIFICATION_ID_BASE = 20_000

    internal fun resetForTests() {
        val jobs = synchronized(lock) {
            val snapshot = activeJobs.values.toList()
            activeJobs.clear()
            preparedOperationIDs.clear()
            requestedOperationIDs.clear()
            notificationIDs.clear()
            nextNotificationID = FOREGROUND_NOTIFICATION_ID_BASE
            snapshot
        }
        jobs.forEach { it.cancel() }
    }
}

/** Private notification action receiver; no schedule setting, alarm, or unique work is touched. */
class ScheduledExportCancelReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_CANCEL_SCHEDULED_EXPORT) return
        val operationID = intent.getStringExtra(EXTRA_OPERATION_ID)
            ?.let { raw -> runCatching { UUID.fromString(raw) }.getOrNull() }
            ?: return
        val accepted = ScheduledExportCancellationCoordinator.requestCancellation(operationID)
        Timber.i(
            "Scheduled export cancellation requested operationId=%s accepted=%s",
            operationID,
            accepted,
        )
    }

    companion object {
        const val ACTION_CANCEL_SCHEDULED_EXPORT =
            "com.healthmd.android.action.CANCEL_SCHEDULED_EXPORT"
        const val EXTRA_OPERATION_ID = "operation_id"

        fun pendingIntent(context: Context, operationID: UUID): PendingIntent {
            val intent = Intent(context, ScheduledExportCancelReceiver::class.java).apply {
                action = ACTION_CANCEL_SCHEDULED_EXPORT
                data = Uri.parse("healthmd://scheduled-export/cancel/$operationID")
                putExtra(EXTRA_OPERATION_ID, operationID.toString())
            }
            return PendingIntent.getBroadcast(
                context,
                operationID.hashCode(),
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
