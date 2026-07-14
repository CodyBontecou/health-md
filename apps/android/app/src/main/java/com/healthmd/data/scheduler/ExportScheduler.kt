package com.healthmd.data.scheduler

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.OutOfQuotaPolicy
import androidx.work.WorkManager
import androidx.work.await
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class ExportScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val workManager: WorkManager,
    private val settingsRepository: SettingsRepository,
    private val apiCredentialStore: APIExportCredentialStore,
    private val stateStore: ScheduledExportStateStore,
    private val timeCalculator: ScheduledExportTimeCalculator,
) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)
    private val mutex = Mutex()

    /** Reconciles persisted settings with one exact alarm or one delayed WorkManager fallback. */
    suspend fun reconcile(forceRecalculate: Boolean = false) {
        mutex.withLock {
            val settings = settingsRepository.getExportSettings()
            val configuration = if (settings.scheduleEnabled) configurationFor(settings) else null
            val nowMillis = System.currentTimeMillis()

            // Remove the legacy periodic request before installing one-occurrence scheduling.
            workManager.cancelUniqueWork(ExportWorker.WORK_NAME).await()
            if (configuration == null) {
                cancelLocked()
                return@withLock
            }

            val existing = stateStore.load()
            val sameConfiguration = existing?.configuration?.signature == configuration.signature
            val sameScheduleExceptZone = existing != null &&
                existing.configuration.copy(zoneId = configuration.zoneId).signature == configuration.signature

            // A manual clock/timezone jump must not silently discard an occurrence it passed.
            val shouldRebase = forceRecalculate || (sameScheduleExceptZone && !sameConfiguration)
            if (
                shouldRebase && existing != null &&
                timeCalculator.isOccurrenceDueAfterRebase(existing, configuration, nowMillis)
            ) {
                enqueueExport(existing, expedited = true, catchUpThroughMillis = nowMillis)
            }

            val occurrence = when {
                !forceRecalculate && sameConfiguration -> requireNotNull(existing)
                sameScheduleExceptZone -> timeCalculator.rebaseOccurrence(
                    previous = requireNotNull(existing),
                    configuration = configuration,
                    nowMillis = nowMillis,
                )
                else -> timeCalculator.initialOccurrence(configuration, nowMillis)
            }
            // Keep any prior fallback until the replacement is durably armed. Stale occurrence
            // IDs are rejected, while retaining them avoids a gap if WorkManager enqueueing fails.
            armOccurrence(occurrence)
            stateStore.save(occurrence)
            if (existing != null && existing.id != occurrence.id) {
                workManager.cancelUniqueWork(
                    "$FALLBACK_TRIGGER_WORK_PREFIX${existing.id}",
                ).await()
            }
        }
    }

    suspend fun cancel() {
        mutex.withLock { cancelLocked() }
    }

    /**
     * Accepts one alarm/fallback delivery, creates exactly one export request, and arms the next
     * occurrence. Stale and duplicate deliveries are ignored.
     */
    suspend fun handleOccurrence(
        occurrence: ScheduledExportOccurrence,
        expedited: Boolean,
    ): Boolean {
        return mutex.withLock {
            val settings = settingsRepository.getExportSettings()
            val currentConfiguration = if (settings.scheduleEnabled) configurationFor(settings) else null
            val nowMillis = System.currentTimeMillis()

            if (currentConfiguration == null) {
                cancelFromDeliveryLocked()
                return@withLock false
            }

            val persisted = stateStore.load()
            if (currentConfiguration.signature != occurrence.configuration.signature) {
                if (persisted?.configuration?.signature != currentConfiguration.signature) {
                    val replacement = timeCalculator.initialOccurrence(currentConfiguration, nowMillis)
                    // Old trigger work is harmless and must not cancel itself before replacement
                    // scheduling completes; its occurrence will be rejected by the state check.
                    armOccurrence(replacement)
                    stateStore.save(replacement)
                }
                return@withLock false
            }

            if (persisted == null || persisted.id != occurrence.id) {
                val canRepairInterruptedArm = persisted == null ||
                    persisted.configuration.signature != currentConfiguration.signature ||
                    occurrence.triggerAtMillis > persisted.triggerAtMillis
                if (!canRepairInterruptedArm) return@withLock false
                stateStore.save(occurrence)
            }

            enqueueExport(
                occurrence = occurrence,
                expedited = expedited,
                catchUpThroughMillis = nowMillis,
            )

            val next = timeCalculator.nextFutureOccurrence(occurrence, nowMillis)
            armOccurrence(next)
            stateStore.save(next)
            true
        }
    }

    fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    fun nextScheduledAtMillis(): Long? = stateStore.load()?.triggerAtMillis

    private suspend fun configurationFor(settings: ExportSettings): ScheduledExportConfiguration {
        val fingerprint = if (settings.scheduledExportTarget == ExportTarget.API_ENDPOINT) {
            apiCredentialStore.destinationFingerprint(settings.apiEndpointUrl)
                ?: throw IllegalStateException("Scheduled API destination is not configured")
        } else null
        return ScheduledExportConfiguration.from(
            settings = settings,
            destinationFingerprint = fingerprint,
            zoneId = ZoneId.systemDefault(),
        )
    }

    private suspend fun armOccurrence(occurrence: ScheduledExportOccurrence) {
        val exactAlarmArmed = canScheduleExactAlarms() && setExactAlarm(occurrence)
        if (!exactAlarmArmed) cancelExactAlarm()

        // Keep a durable backup even in exact mode. If access is later revoked, Android deletes
        // exact alarms without a revocation broadcast; this trigger prevents the schedule vanishing.
        enqueueFallbackTrigger(
            occurrence = occurrence,
            additionalDelayMillis = if (exactAlarmArmed) EXACT_ALARM_BACKUP_DELAY_MILLIS else 0L,
        )
    }

    private fun setExactAlarm(occurrence: ScheduledExportOccurrence): Boolean = try {
        alarmManager.setExactAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            occurrence.triggerAtMillis,
            alarmPendingIntent(occurrence),
        )
        true
    } catch (_: SecurityException) {
        false
    }

    private suspend fun enqueueFallbackTrigger(
        occurrence: ScheduledExportOccurrence,
        additionalDelayMillis: Long,
    ) {
        val fallbackAtMillis = occurrence.triggerAtMillis + additionalDelayMillis
        val delayMillis = (fallbackAtMillis - System.currentTimeMillis()).coerceAtLeast(0L)
        val request = OneTimeWorkRequestBuilder<ScheduledExportTriggerWorker>()
            .setInputData(occurrence.toWorkData())
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(FALLBACK_TRIGGER_TAG)
            .build()
        workManager.enqueueUniqueWork(
            "$FALLBACK_TRIGGER_WORK_PREFIX${occurrence.id}",
            ExistingWorkPolicy.REPLACE,
            request,
        ).await()
    }

    private suspend fun enqueueExport(
        occurrence: ScheduledExportOccurrence,
        expedited: Boolean,
        catchUpThroughMillis: Long,
    ) {
        val constraints = Constraints.Builder().apply {
            if (occurrence.configuration.target == ExportTarget.API_ENDPOINT) {
                setRequiredNetworkType(NetworkType.CONNECTED)
            }
        }.build()

        val requestBuilder = OneTimeWorkRequestBuilder<ExportWorker>()
            .setInputData(occurrence.toWorkData(catchUpThroughMillis))
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .addTag(EXPORT_OCCURRENCE_TAG)
        if (expedited) {
            requestBuilder.setExpedited(OutOfQuotaPolicy.RUN_AS_NON_EXPEDITED_WORK_REQUEST)
        }

        workManager.enqueueUniqueWork(
            "$EXPORT_OCCURRENCE_WORK_PREFIX${occurrence.id}",
            ExistingWorkPolicy.KEEP,
            requestBuilder.build(),
        ).await()
    }

    private fun alarmPendingIntent(occurrence: ScheduledExportOccurrence): PendingIntent {
        val intent = Intent(context, ScheduledExportAlarmReceiver::class.java).apply {
            action = ACTION_SCHEDULED_EXPORT_ALARM
        }
        occurrence.putInto(intent)
        return PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun cancelExactAlarm() {
        val intent = Intent(context, ScheduledExportAlarmReceiver::class.java).apply {
            action = ACTION_SCHEDULED_EXPORT_ALARM
        }
        val pendingIntent = PendingIntent.getBroadcast(
            context,
            ALARM_REQUEST_CODE,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        alarmManager.cancel(pendingIntent)
        pendingIntent.cancel()
    }

    private suspend fun cancelFallbackTriggers() {
        workManager.cancelAllWorkByTag(FALLBACK_TRIGGER_TAG).await()
    }

    private suspend fun cancelLocked() {
        cancelExactAlarm()
        cancelFallbackTriggers()
        workManager.cancelAllWorkByTag(EXPORT_OCCURRENCE_TAG).await()
        workManager.cancelUniqueWork(ExportWorker.WORK_NAME).await()
        stateStore.clear()
    }

    /** Avoid canceling a fallback worker from inside that same running worker. */
    private suspend fun cancelFromDeliveryLocked() {
        cancelExactAlarm()
        workManager.cancelAllWorkByTag(EXPORT_OCCURRENCE_TAG).await()
        workManager.cancelUniqueWork(ExportWorker.WORK_NAME).await()
        stateStore.clear()
    }

    companion object {
        const val ACTION_SCHEDULED_EXPORT_ALARM = "com.healthmd.android.action.SCHEDULED_EXPORT_ALARM"
        const val FALLBACK_TRIGGER_TAG = "scheduled_export_trigger"
        const val EXPORT_OCCURRENCE_TAG = "scheduled_export_occurrence"
        private const val FALLBACK_TRIGGER_WORK_PREFIX = "scheduled_export_trigger_"
        private const val EXPORT_OCCURRENCE_WORK_PREFIX = "scheduled_export_occurrence_"
        private const val EXACT_ALARM_BACKUP_DELAY_MILLIS = 15 * 60_000L
        private const val ALARM_REQUEST_CODE = 6_041
    }
}
