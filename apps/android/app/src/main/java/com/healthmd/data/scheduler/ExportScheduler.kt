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
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import java.time.ZoneId
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import timber.log.Timber

@Singleton
class ExportScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val workManager: WorkManager,
    private val settingsRepository: SettingsRepository,
    private val apiCredentialStore: APIExportCredentialStore,
    private val stateStore: ScheduledExportStateStore,
    private val timeCalculator: ScheduledExportTimeCalculator,
    private val enginePinPlanner: ExportEnginePinPlanner,
    private val generationFactory: ScheduledExportGeneration,
    private val runCoordinator: ScheduledExportRunCoordinator,
) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)
    private val mutex = Mutex()

    /** Reconciles persisted settings with one exact alarm or one delayed WorkManager fallback. */
    suspend fun reconcile(forceRecalculate: Boolean = false) {
        mutex.withLock {
            val settings = settingsRepository.getExportSettings()
            val currentZone = ZoneId.systemDefault()
            val nowMillis = System.currentTimeMillis()
            val existing = stateStore.load()

            if (!stateStore.isGenerationMigrationComplete()) {
                migrateLegacyScheduleLocked(settings, currentZone, nowMillis)
                return@withLock
            }

            if (!settings.scheduleEnabled) {
                cancelLocked(GenerationBoundaryReason.SCHEDULE_DISABLED)
                return@withLock
            }

            val persistedConfiguration = existing?.let { occurrence ->
                configurationUsingPersistedPin(settings, occurrence.configuration)
            }
            val currentSettingsMatchPersisted = existing != null &&
                persistedConfiguration?.signature == existing.configuration.signature
            val configuration = if (
                currentSettingsMatchPersisted && existing.configuration.zoneId == currentZone.id
            ) {
                requireNotNull(persistedConfiguration)
            } else {
                configurationForNewOccurrence(settings, currentZone)
            }

            val sameConfiguration = existing?.configuration?.signature == configuration.signature
            val timezoneRebase = existing != null &&
                currentSettingsMatchPersisted &&
                existing.configuration.zoneId != configuration.zoneId &&
                existing.configuration.isSameScheduleExceptZone(configuration)
            val hasActiveGeneration = existing?.generation
                ?.takeIf(ScheduledExportGeneration::isValid) != null

            if (!hasActiveGeneration || (!sameConfiguration && !timezoneRebase)) {
                val reason = when {
                    existing == null -> GenerationBoundaryReason.SCHEDULE_ENABLED
                    !hasActiveGeneration -> GenerationBoundaryReason.INVALID_ACTIVE_GENERATION
                    else -> GenerationBoundaryReason.CONFIGURATION_REPLACED
                }
                replaceGenerationLocked(configuration, nowMillis, reason)
                return@withLock
            }

            val activeOccurrence = requireNotNull(existing)
            // Remove the pre-one-shot periodic request without touching unrelated manual work.
            workManager.cancelUniqueWork(ExportWorker.WORK_NAME).await()

            // A manual clock/timezone jump must not silently discard an occurrence it passed.
            val shouldRebase = forceRecalculate || timezoneRebase
            if (
                shouldRebase &&
                timeCalculator.isOccurrenceDueAfterRebase(
                    activeOccurrence,
                    configuration,
                    nowMillis,
                )
            ) {
                enqueueExport(activeOccurrence, expedited = true, catchUpThroughMillis = nowMillis)
            }

            val occurrence = when {
                !forceRecalculate && sameConfiguration -> activeOccurrence
                sameConfiguration || timezoneRebase -> timeCalculator.rebaseOccurrence(
                    previous = activeOccurrence,
                    configuration = configuration,
                    nowMillis = nowMillis,
                )
                else -> error("Generation continuity requires the same material schedule")
            }
            // Keep any prior fallback until the replacement is durably armed. A stale occurrence
            // ID is rejected, while retaining it avoids a gap if WorkManager enqueueing fails.
            armOccurrence(occurrence)
            stateStore.save(occurrence)
            if (activeOccurrence.id != occurrence.id) {
                workManager.cancelUniqueWork(
                    "$FALLBACK_TRIGGER_WORK_PREFIX${activeOccurrence.id}",
                ).await()
            }
        }
    }

    suspend fun cancel() {
        mutex.withLock { cancelLocked(GenerationBoundaryReason.SCHEDULE_DISABLED) }
    }

    /**
     * Accepts one alarm/fallback delivery, creates exactly one export request, and arms the next
     * occurrence. Stale and duplicate deliveries are ignored.
     */
    suspend fun handleOccurrence(
        occurrence: ScheduledExportOccurrence,
        expedited: Boolean,
        isFallbackDelivery: Boolean = false,
    ): Boolean {
        return mutex.withLock {
            val settings = settingsRepository.getExportSettings()
            val currentZone = ZoneId.systemDefault()
            val nowMillis = System.currentTimeMillis()

            if (!stateStore.isGenerationMigrationComplete()) {
                migrateLegacyScheduleLocked(
                    settings = settings,
                    currentZone = currentZone,
                    nowMillis = nowMillis,
                    currentFallbackOccurrenceId = occurrence.id.takeIf { isFallbackDelivery },
                )
                return@withLock false
            }

            val persisted = stateStore.load()
            val deliveredGeneration = occurrence.generation
            if (
                deliveredGeneration == null ||
                persisted?.generation == null ||
                deliveredGeneration != persisted.generation
            ) {
                logStaleDelivery(deliveredGeneration, persisted?.generation, "generation_mismatch")
                return@withLock false
            }

            if (!settings.scheduleEnabled) {
                cancelFromDeliveryLocked(occurrence, isFallbackDelivery)
                return@withLock false
            }

            if (persisted.id != occurrence.id) {
                val canRepairInterruptedArm = occurrence.triggerAtMillis > persisted.triggerAtMillis
                if (!canRepairInterruptedArm) {
                    logStaleDelivery(deliveredGeneration, persisted.generation, "occurrence_mismatch")
                    return@withLock false
                }
                stateStore.save(occurrence)
            }

            val persistedConfiguration = configurationUsingPersistedPin(
                settings,
                occurrence.configuration,
            )
            val currentSettingsMatchOccurrence =
                persistedConfiguration?.signature == occurrence.configuration.signature
            val currentConfiguration = if (
                currentSettingsMatchOccurrence && occurrence.configuration.zoneId == currentZone.id
            ) {
                requireNotNull(persistedConfiguration)
            } else {
                configurationForNewOccurrence(settings, currentZone)
            }
            val timezoneRebase = currentSettingsMatchOccurrence &&
                occurrence.configuration.zoneId != currentConfiguration.zoneId &&
                occurrence.configuration.isSameScheduleExceptZone(currentConfiguration)

            if (
                !currentSettingsMatchOccurrence ||
                (currentConfiguration.signature != occurrence.configuration.signature && !timezoneRebase)
            ) {
                replaceGenerationLocked(
                    configuration = currentConfiguration,
                    nowMillis = nowMillis,
                    reason = GenerationBoundaryReason.DELIVERY_CONFIGURATION_REPLACED,
                    currentFallbackOccurrenceId = occurrence.id.takeIf { isFallbackDelivery },
                )
                return@withLock false
            }

            enqueueExport(
                occurrence = occurrence,
                expedited = expedited,
                catchUpThroughMillis = nowMillis,
            )

            val nextConfiguration = if (timezoneRebase) {
                currentConfiguration
            } else {
                configurationForNewOccurrence(settings, currentZone)
            }
            val next = if (nextConfiguration.zoneId == occurrence.configuration.zoneId) {
                timeCalculator.nextFutureOccurrence(occurrence, nowMillis)
                    .copy(configuration = nextConfiguration)
            } else {
                timeCalculator.rebaseOccurrence(occurrence, nextConfiguration, nowMillis)
            }
            armOccurrence(next)
            stateStore.save(next)
            if (!isFallbackDelivery && occurrence.id != next.id) {
                workManager.cancelUniqueWork(
                    "$FALLBACK_TRIGGER_WORK_PREFIX${occurrence.id}",
                ).await()
            }
            true
        }
    }

    fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    fun nextScheduledAtMillis(): Long? = stateStore.load()?.triggerAtMillis

    private suspend fun migrateLegacyScheduleLocked(
        settings: ExportSettings,
        currentZone: ZoneId,
        nowMillis: Long,
        currentFallbackOccurrenceId: String? = null,
    ) {
        runCoordinator.mutex.withLock {
            val previousGeneration = deactivateAndCancelScheduledWork(
                reason = GenerationBoundaryReason.LEGACY_MIGRATION,
                currentFallbackOccurrenceId = currentFallbackOccurrenceId,
            )
            stateStore.markGenerationMigrationComplete()
            Timber.i("Scheduled export generation migration completed")
            if (settings.scheduleEnabled) {
                val configuration = configurationForNewOccurrence(settings, currentZone)
                armFreshGeneration(
                    configuration = configuration,
                    nowMillis = nowMillis,
                    reason = GenerationBoundaryReason.LEGACY_MIGRATION,
                    previousGeneration = previousGeneration,
                )
            }
        }
    }

    private suspend fun replaceGenerationLocked(
        configuration: ScheduledExportConfiguration,
        nowMillis: Long,
        reason: GenerationBoundaryReason,
        currentFallbackOccurrenceId: String? = null,
    ) {
        runCoordinator.mutex.withLock {
            val previousGeneration = deactivateAndCancelScheduledWork(
                reason,
                currentFallbackOccurrenceId,
            )
            stateStore.markGenerationMigrationComplete()
            armFreshGeneration(configuration, nowMillis, reason, previousGeneration)
        }
    }

    private suspend fun armFreshGeneration(
        configuration: ScheduledExportConfiguration,
        nowMillis: Long,
        reason: GenerationBoundaryReason,
        previousGeneration: String?,
    ) {
        val generation = generationFactory.create().also { generated ->
            require(ScheduledExportGeneration.isValid(generated)) {
                "Scheduled export generation factory returned an invalid value."
            }
        }
        val occurrence = timeCalculator.initialOccurrence(
            configuration = configuration,
            nowMillis = nowMillis,
            generation = generation,
        )
        armOccurrence(occurrence)
        stateStore.save(occurrence)
        Timber.i(
            "Scheduled export generation armed old=%s new=%s reason=%s",
            ScheduledExportGeneration.diagnosticId(previousGeneration),
            ScheduledExportGeneration.diagnosticId(generation),
            reason.name,
        )
    }

    private suspend fun configurationForNewOccurrence(
        settings: ExportSettings,
        zoneId: ZoneId,
    ): ScheduledExportConfiguration {
        val target = settings.scheduledExportTarget
        val fingerprint = destinationFingerprint(settings, target)
        val enginePin = enginePinPlanner.forScheduledExport(settings, target, zoneId)
        val settingsSnapshot = AndroidExportSettingsSnapshot.capture(settings, enginePin, zoneId)
        return ScheduledExportConfiguration.from(
            settings = settings,
            destinationFingerprint = fingerprint,
            zoneId = zoneId,
            enginePin = enginePin,
            settingsSnapshot = settingsSnapshot,
        )
    }

    /**
     * Rebuilds the current material configuration with the already accepted engine authority.
     * Comparing its signature detects settings changes without re-resolving an existing pin.
     */
    private suspend fun configurationUsingPersistedPin(
        settings: ExportSettings,
        persisted: ScheduledExportConfiguration,
    ): ScheduledExportConfiguration? {
        val target = settings.scheduledExportTarget
        if (!enginePinPlanner.persistedPinAppliesToScheduledExport(settings, target, persisted.enginePin)) {
            return null
        }
        val persistedSnapshot = persisted.settingsSnapshot
        val zone = ZoneId.of(persisted.zoneId)
        val currentSnapshot = if (persistedSnapshot == null) {
            null
        } else {
            if (persistedSnapshot.scheduledExportTarget != target) return null
            // Validate destination plumbing before comparing only non-secret frozen output choices.
            if (runCatching { persistedSnapshot.restoreOnto(settings) }.isFailure) return null
            AndroidExportSettingsSnapshot.capture(settings, persisted.enginePin, zone)
                .takeIf { it == persistedSnapshot }
                ?: return null
        }
        return ScheduledExportConfiguration.from(
            settings = settings,
            destinationFingerprint = destinationFingerprint(settings, target),
            zoneId = zone,
            enginePin = persisted.enginePin,
            settingsSnapshot = currentSnapshot,
        )
    }

    private suspend fun destinationFingerprint(
        settings: ExportSettings,
        target: ExportTarget,
    ): String? = if (target == ExportTarget.API_ENDPOINT) {
        apiCredentialStore.destinationFingerprint(settings.apiEndpointUrl)
            ?: throw IllegalStateException("Scheduled API destination is not configured")
    } else {
        null
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
        val requestBuilder = OneTimeWorkRequestBuilder<ScheduledExportTriggerWorker>()
            .setInputData(occurrence.toWorkData())
            .setInitialDelay(delayMillis, TimeUnit.MILLISECONDS)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(FALLBACK_TRIGGER_TAG)
        occurrence.generation?.let { generation ->
            requestBuilder.addTag(generationTag(generation))
        }
        workManager.enqueueUniqueWork(
            "$FALLBACK_TRIGGER_WORK_PREFIX${occurrence.id}",
            ExistingWorkPolicy.REPLACE,
            requestBuilder.build(),
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
        occurrence.generation?.let { generation ->
            requestBuilder.addTag(generationTag(generation))
        }
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

    private suspend fun cancelLocked(reason: GenerationBoundaryReason) {
        runCoordinator.mutex.withLock {
            deactivateAndCancelScheduledWork(reason)
            stateStore.markGenerationMigrationComplete()
        }
    }

    /** Avoid canceling a fallback worker from inside that same running worker. */
    private suspend fun cancelFromDeliveryLocked(
        occurrence: ScheduledExportOccurrence,
        isFallbackDelivery: Boolean,
    ) {
        runCoordinator.mutex.withLock {
            deactivateAndCancelScheduledWork(
                reason = GenerationBoundaryReason.SCHEDULE_DISABLED,
                currentFallbackOccurrenceId = occurrence.id.takeIf { isFallbackDelivery },
            )
            stateStore.markGenerationMigrationComplete()
        }
    }

    /** Caller holds [ScheduledExportRunCoordinator.mutex], closing the worker admission race. */
    private suspend fun deactivateAndCancelScheduledWork(
        reason: GenerationBoundaryReason,
        currentFallbackOccurrenceId: String? = null,
    ): String? {
        val active = stateStore.load()
        val activeGeneration = active?.generation
        stateStore.clear()
        cancelExactAlarm()
        Timber.i(
            "Cancelling scheduled export work generation=%s reason=%s",
            ScheduledExportGeneration.diagnosticId(activeGeneration),
            reason.name,
        )
        workManager.cancelAllWorkByTag(EXPORT_OCCURRENCE_TAG).await()
        if (currentFallbackOccurrenceId == null) {
            cancelFallbackTriggers()
        } else if (active != null && active.id != currentFallbackOccurrenceId) {
            workManager.cancelUniqueWork(
                "$FALLBACK_TRIGGER_WORK_PREFIX${active.id}",
            ).await()
        }
        workManager.cancelUniqueWork(ExportWorker.WORK_NAME).await()
        Timber.i(
            "Cancelled scheduled export work generation=%s reason=%s",
            ScheduledExportGeneration.diagnosticId(activeGeneration),
            reason.name,
        )
        return activeGeneration
    }

    private fun logStaleDelivery(
        deliveredGeneration: String?,
        activeGeneration: String?,
        reason: String,
    ) {
        Timber.w(
            "Rejected stale scheduled trigger generation=%s active=%s reason=%s",
            ScheduledExportGeneration.diagnosticId(deliveredGeneration),
            ScheduledExportGeneration.diagnosticId(activeGeneration),
            reason,
        )
    }

    private fun generationTag(generation: String): String =
        "$GENERATION_TAG_PREFIX$generation"

    private enum class GenerationBoundaryReason {
        LEGACY_MIGRATION,
        SCHEDULE_ENABLED,
        SCHEDULE_DISABLED,
        INVALID_ACTIVE_GENERATION,
        CONFIGURATION_REPLACED,
        DELIVERY_CONFIGURATION_REPLACED,
    }

    companion object {
        const val ACTION_SCHEDULED_EXPORT_ALARM = "com.healthmd.android.action.SCHEDULED_EXPORT_ALARM"
        const val FALLBACK_TRIGGER_TAG = "scheduled_export_trigger"
        const val EXPORT_OCCURRENCE_TAG = "scheduled_export_occurrence"
        const val GENERATION_TAG_PREFIX = "scheduled_export_generation_"
        private const val FALLBACK_TRIGGER_WORK_PREFIX = "scheduled_export_trigger_"
        private const val EXPORT_OCCURRENCE_WORK_PREFIX = "scheduled_export_occurrence_"
        private const val EXACT_ALARM_BACKUP_DELAY_MILLIS = 15 * 60_000L
        private const val ALARM_REQUEST_CODE = 6_041
    }
}
