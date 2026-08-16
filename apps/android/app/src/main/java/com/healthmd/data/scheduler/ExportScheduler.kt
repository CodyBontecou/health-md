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
    private val transitionObserver: ScheduledExportTransitionObserver,
) {
    private val alarmManager = context.getSystemService(AlarmManager::class.java)
    private val mutex = Mutex()

    /** Reconciles persisted settings with one exact alarm or one delayed WorkManager fallback. */
    suspend fun reconcile(forceRecalculate: Boolean = false) {
        mutex.withLock {
            runCoordinator.mutex.withLock coordinator@{
                val settings = settingsRepository.getExportSettings()
                val currentZone = ZoneId.systemDefault()
                val nowMillis = System.currentTimeMillis()

                if (!settings.scheduleEnabled) {
                    cancelLocked(GenerationBoundaryReason.SCHEDULE_DISABLED)
                    return@coordinator
                }

                // Recover durable external-state gaps before interpreting the active occurrence.
                resumePendingTransitionLocked()
                recoverCorruptAdmissionLocked()
                resumeAdmissionLocked()
                resumePendingArmLocked()
                val existing = stateStore.load()

                if (!stateStore.isGenerationMigrationComplete()) {
                    migrateLegacyScheduleLocked(settings, currentZone, nowMillis)
                    return@coordinator
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
                    val dueOccurrenceToPreserve = dueOccurrenceEligibleForReplacement(
                        occurrence = existing,
                        replacementConfiguration = configuration,
                        nowMillis = nowMillis,
                    )
                    val replacement = replaceGenerationLocked(
                        configuration = configuration,
                        nowMillis = nowMillis,
                        reason = reason,
                        dueOccurrenceToPreserve = dueOccurrenceToPreserve,
                    )
                    if (dueOccurrenceToPreserve != null) {
                        admitAndAdvanceOccurrenceLocked(
                            occurrence = replacement,
                            expedited = true,
                            catchUpThroughMillis = nowMillis,
                            nextOccurrence = nextOccurrence(
                                replacement,
                                configuration,
                                nowMillis,
                            ),
                            currentFallback = null,
                        )
                    }
                    return@coordinator
                }

                // Keep the already-armed next occurrence stable while one admitted worker is
                // pending or retrying. Completion reconciliation will catch it up immediately.
                if (stateStore.loadAdmission() != null) return@coordinator

                val activeOccurrence = requireNotNull(existing)
                workManager.cancelUniqueWork(ExportWorker.WORK_NAME).await()

                val shouldRebase = forceRecalculate || timezoneRebase
                val occurrence = when {
                    !forceRecalculate && sameConfiguration -> activeOccurrence
                    sameConfiguration || timezoneRebase -> timeCalculator.rebaseOccurrence(
                        previous = activeOccurrence,
                        configuration = configuration,
                        nowMillis = nowMillis,
                    )
                    else -> error("Generation continuity requires the same material schedule")
                }
                if (
                    shouldRebase &&
                    timeCalculator.isOccurrenceDueAfterRebase(
                        activeOccurrence,
                        configuration,
                        nowMillis,
                    )
                ) {
                    admitAndAdvanceOccurrenceLocked(
                        occurrence = activeOccurrence,
                        expedited = true,
                        catchUpThroughMillis = nowMillis,
                        nextOccurrence = occurrence,
                        currentFallback = null,
                    )
                    return@coordinator
                }

                check(stateStore.prepareArm(occurrence)) {
                    "Unable to persist scheduled-export arm intent."
                }
                resumePendingArmLocked()
                if (activeOccurrence.id != occurrence.id) {
                    workManager.cancelUniqueWork(
                        "$FALLBACK_TRIGGER_WORK_PREFIX${activeOccurrence.id}",
                    ).await()
                }
            }
        }
    }

    suspend fun cancel() {
        mutex.withLock {
            runCoordinator.mutex.withLock {
                cancelLocked(GenerationBoundaryReason.SCHEDULE_DISABLED)
            }
        }
    }

    /**
     * Accepts one alarm/fallback delivery, durably admits one export, and arms the next occurrence.
     * Stale and duplicate deliveries are ignored; a busy single-flight admission asks fallback
     * WorkManager delivery to retry.
     */
    suspend fun handleOccurrence(
        occurrence: ScheduledExportOccurrence,
        expedited: Boolean,
        isFallbackDelivery: Boolean = false,
    ): Boolean = handleOccurrenceDelivery(
        occurrence = occurrence,
        expedited = expedited,
        isFallbackDelivery = isFallbackDelivery,
    ) == ScheduledExportDeliveryResult.ADMITTED

    internal suspend fun handleOccurrenceDelivery(
        occurrence: ScheduledExportOccurrence,
        expedited: Boolean,
        isFallbackDelivery: Boolean = false,
    ): ScheduledExportDeliveryResult = mutex.withLock {
        runCoordinator.mutex.withLock coordinator@{
            val settings = settingsRepository.getExportSettings()
            val currentZone = ZoneId.systemDefault()
            val nowMillis = System.currentTimeMillis()
            val currentFallback = occurrence.takeIf { isFallbackDelivery }

            if (!settings.scheduleEnabled) {
                cancelFromDeliveryLocked(occurrence, isFallbackDelivery)
                return@coordinator ScheduledExportDeliveryResult.STALE
            }

            // Settings are captured only after winning the same coordinator used by workers. This
            // durable snapshot-capture point linearizes an occurrence against concurrent edits.
            resumePendingTransitionLocked(currentFallback)
            recoverCorruptAdmissionLocked()
            resumeAdmissionLocked()
            resumePendingArmLocked(currentFallback)

            if (!stateStore.isGenerationMigrationComplete()) {
                return@coordinator if (
                    migrateLegacyScheduleLocked(
                        settings = settings,
                        currentZone = currentZone,
                        nowMillis = nowMillis,
                        currentFallback = currentFallback,
                    )
                ) {
                    ScheduledExportDeliveryResult.ADMITTED
                } else {
                    ScheduledExportDeliveryResult.STALE
                }
            }

            val persisted = stateStore.load()
            val deliveredGeneration = occurrence.generation
            if (
                deliveredGeneration == null ||
                persisted?.generation == null ||
                deliveredGeneration != persisted.generation
            ) {
                logStaleDelivery(deliveredGeneration, persisted?.generation, "generation_mismatch")
                return@coordinator ScheduledExportDeliveryResult.STALE
            }

            if (persisted.id != occurrence.id) {
                val canRepairInterruptedArm = occurrence.triggerAtMillis > persisted.triggerAtMillis &&
                    stateStore.loadAdmission() == null
                if (!canRepairInterruptedArm) {
                    logStaleDelivery(deliveredGeneration, persisted.generation, "occurrence_mismatch")
                    return@coordinator ScheduledExportDeliveryResult.STALE
                }
                check(stateStore.save(occurrence)) {
                    "Unable to persist repaired scheduled-export occurrence."
                }
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
                val dueOccurrenceToPreserve = dueOccurrenceEligibleForReplacement(
                    occurrence = occurrence,
                    replacementConfiguration = currentConfiguration,
                    nowMillis = nowMillis,
                )
                val replacement = replaceGenerationLocked(
                    configuration = currentConfiguration,
                    nowMillis = nowMillis,
                    reason = GenerationBoundaryReason.DELIVERY_CONFIGURATION_REPLACED,
                    currentFallback = currentFallback,
                    dueOccurrenceToPreserve = dueOccurrenceToPreserve,
                )
                if (dueOccurrenceToPreserve == null) {
                    return@coordinator ScheduledExportDeliveryResult.STALE
                }

                admitAndAdvanceOccurrenceLocked(
                    occurrence = replacement,
                    expedited = expedited,
                    catchUpThroughMillis = nowMillis,
                    nextOccurrence = nextOccurrence(
                        replacement,
                        currentConfiguration,
                        nowMillis,
                    ),
                    currentFallback = currentFallback,
                )
                return@coordinator ScheduledExportDeliveryResult.ADMITTED
            }

            if (stateStore.loadAdmission() != null) {
                return@coordinator ScheduledExportDeliveryResult.BUSY
            }
            val next = if (timezoneRebase) {
                timeCalculator.rebaseOccurrence(occurrence, currentConfiguration, nowMillis)
            } else {
                nextOccurrence(occurrence, currentConfiguration, nowMillis)
            }
            admitAndAdvanceOccurrenceLocked(
                occurrence = occurrence,
                expedited = expedited,
                catchUpThroughMillis = nowMillis,
                nextOccurrence = next,
                currentFallback = currentFallback,
            )
            ScheduledExportDeliveryResult.ADMITTED
        }
    }

    fun canScheduleExactAlarms(): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarmManager.canScheduleExactAlarms()

    fun nextScheduledAtMillis(): Long? = stateStore.load()?.triggerAtMillis

    private suspend fun migrateLegacyScheduleLocked(
        settings: ExportSettings,
        currentZone: ZoneId,
        nowMillis: Long,
        currentFallback: ScheduledExportOccurrence? = null,
    ): Boolean {
        val configuration = configurationForNewOccurrence(settings, currentZone)
        val dueOccurrenceToPreserve = dueOccurrenceEligibleForReplacement(
            occurrence = stateStore.load()?.takeIf { it.generation == null },
            replacementConfiguration = configuration,
            nowMillis = nowMillis,
        )
        val replacement = startGenerationTransitionLocked(
            configuration = configuration,
            nowMillis = nowMillis,
            reason = GenerationBoundaryReason.LEGACY_MIGRATION,
            cleanupScope = ScheduledExportCleanupScope.LEGACY,
            currentFallback = currentFallback,
            dueOccurrenceToPreserve = dueOccurrenceToPreserve,
        )
        val admitted = dueOccurrenceToPreserve != null && admitAndAdvanceOccurrenceLocked(
            occurrence = replacement,
            expedited = true,
            catchUpThroughMillis = nowMillis,
            nextOccurrence = nextOccurrence(replacement, configuration, nowMillis),
            currentFallback = currentFallback,
        )
        Timber.i("Scheduled export generation migration completed")
        return admitted
    }

    private suspend fun replaceGenerationLocked(
        configuration: ScheduledExportConfiguration,
        nowMillis: Long,
        reason: GenerationBoundaryReason,
        currentFallback: ScheduledExportOccurrence? = null,
        dueOccurrenceToPreserve: ScheduledExportOccurrence? = null,
    ): ScheduledExportOccurrence = startGenerationTransitionLocked(
        configuration = configuration,
        nowMillis = nowMillis,
        reason = reason,
        currentFallback = currentFallback,
        dueOccurrenceToPreserve = dueOccurrenceToPreserve,
    )

    private suspend fun resumePendingTransitionLocked(
        currentFallback: ScheduledExportOccurrence? = null,
    ) {
        stateStore.loadTransition()?.let { transition ->
            finishGenerationTransitionLocked(transition, currentFallback)
        }
    }

    /** Malformed admission data is never reinterpreted; its queued export is cancelled fail-closed. */
    private suspend fun recoverCorruptAdmissionLocked() {
        if (!stateStore.hasCorruptAdmissionState()) return
        val activeGeneration = stateStore.load()?.generation
        check(stateStore.clearAdmissionState()) {
            "Unable to clear malformed scheduled-export admission."
        }
        activeGeneration?.takeIf(ScheduledExportGeneration::isValid)?.let { generation ->
            workManager.cancelAllWorkByTag(exportGenerationTag(generation)).await()
        }
        Timber.w(
            "Cleared malformed scheduled export admission generation=%s reason=invalid_admission",
            ScheduledExportGeneration.diagnosticId(activeGeneration),
        )
    }

    /** Repeats the exact admitted WorkManager enqueue after an interrupted external commit. */
    private suspend fun resumeAdmissionLocked() {
        stateStore.loadAdmission()?.let { admission ->
            enqueueExport(admission)
        }
    }

    /** Repeats next-occurrence arming until its durable marker can be cleared. */
    private suspend fun resumePendingArmLocked(
        currentFallback: ScheduledExportOccurrence? = null,
    ) {
        val occurrence = stateStore.pendingArmOccurrence() ?: return
        val fallbackProvesArm = currentFallback?.generation == occurrence.generation &&
            currentFallback?.id == occurrence.id
        if (!fallbackProvesArm) {
            armOccurrence(occurrence)
        }
        check(stateStore.completePendingArm(occurrence.id)) {
            "Unable to finalize scheduled-export occurrence arming."
        }
    }

    private fun nextOccurrence(
        occurrence: ScheduledExportOccurrence,
        configuration: ScheduledExportConfiguration,
        catchUpThroughMillis: Long,
    ): ScheduledExportOccurrence = if (configuration.zoneId == occurrence.configuration.zoneId) {
        timeCalculator.nextFutureOccurrence(occurrence, catchUpThroughMillis)
            .copy(configuration = configuration)
    } else {
        timeCalculator.rebaseOccurrence(occurrence, configuration, catchUpThroughMillis)
    }

    /**
     * Returns a due temporal anchor only when routing, cadence, window, and timezone are unchanged.
     * The transition replaces all frozen settings and engine authority with [replacementConfiguration].
     */
    private fun dueOccurrenceEligibleForReplacement(
        occurrence: ScheduledExportOccurrence?,
        replacementConfiguration: ScheduledExportConfiguration,
        nowMillis: Long,
    ): ScheduledExportOccurrence? = occurrence?.takeIf { candidate ->
        candidate.triggerAtMillis <= nowMillis &&
            candidate.configuration.zoneId == replacementConfiguration.zoneId &&
            candidate.configuration.isSameScheduleExceptZone(replacementConfiguration)
    }

    /** Caller holds [ScheduledExportRunCoordinator.mutex]. */
    private suspend fun startGenerationTransitionLocked(
        configuration: ScheduledExportConfiguration,
        nowMillis: Long,
        reason: GenerationBoundaryReason,
        cleanupScope: ScheduledExportCleanupScope? = null,
        currentFallback: ScheduledExportOccurrence? = null,
        dueOccurrenceToPreserve: ScheduledExportOccurrence? = null,
    ): ScheduledExportOccurrence {
        val previous = stateStore.load()
        val generation = generationFactory.create().also { generated ->
            require(ScheduledExportGeneration.isValid(generated)) {
                "Scheduled export generation factory returned an invalid value."
            }
        }
        val replacement = dueOccurrenceToPreserve?.let { due ->
            require(due.triggerAtMillis <= nowMillis) {
                "Only a due scheduled-export occurrence can cross a generation boundary."
            }
            require(
                due.configuration.zoneId == configuration.zoneId &&
                    due.configuration.isSameScheduleExceptZone(configuration)
            ) {
                "A due scheduled-export occurrence cannot cross a routing or schedule boundary."
            }
            due.copy(configuration = configuration, generation = generation)
        } ?: timeCalculator.initialOccurrence(
            configuration = configuration,
            nowMillis = nowMillis,
            generation = generation,
        )
        // Validate both fallback and export WorkManager envelopes before replacing durable state or
        // cancelling old work. Snapshot storage allows larger values than WorkManager transport.
        replacement.toWorkData()
        ScheduledExportAdmission.create(
            occurrence = replacement,
            catchUpThroughMillis = maxOf(nowMillis, replacement.triggerAtMillis),
            expedited = false,
        )
        val transition = ScheduledExportTransition(
            replacement = replacement,
            previousGeneration = previous?.generation,
            previousOccurrenceId = previous?.id,
            cleanupScope = cleanupScope ?: when {
                previous == null -> ScheduledExportCleanupScope.NONE
                previous.generation?.let(ScheduledExportGeneration::isValid) == true -> {
                    ScheduledExportCleanupScope.GENERATION
                }
                // With persisted pre-generation state, old rows have no narrower identity.
                else -> ScheduledExportCleanupScope.LEGACY
            },
            phase = ScheduledExportTransitionPhase.PREPARED,
            reason = reason.name,
        )

        // This atomic write is the transition invariant: old work is stale before exact alarms or
        // WorkManager are touched, and recovery retains the complete intended replacement.
        check(stateStore.prepareTransition(transition)) {
            "Unable to persist scheduled-export generation transition."
        }
        transitionObserver.onCheckpoint(ScheduledExportTransitionCheckpoint.DURABLE_TRANSITION)
        finishGenerationTransitionLocked(transition, currentFallback)
        return replacement
    }

    /** Caller holds [ScheduledExportRunCoordinator.mutex]. Every step is safe to repeat. */
    private suspend fun finishGenerationTransitionLocked(
        initial: ScheduledExportTransition,
        currentFallback: ScheduledExportOccurrence?,
    ) {
        var transition = stateStore.loadTransition() ?: return
        check(transition.replacement.generation == initial.replacement.generation) {
            "Scheduled-export transition changed while its coordinator lock was held."
        }
        val generation = requireNotNull(transition.replacement.generation)

        if (transition.phase == ScheduledExportTransitionPhase.PREPARED) {
            cancelPreviousTransitionWork(transition, currentFallback)
            // A crash here repeats only idempotent cancellation and can never lose the replacement.
            transitionObserver.onCheckpoint(
                ScheduledExportTransitionCheckpoint.OLD_WORK_CANCELLATION,
            )
            check(
                stateStore.updateTransitionPhase(
                    generation,
                    ScheduledExportTransitionPhase.OLD_WORK_CANCELLED,
                ),
            ) { "Unable to persist scheduled-export cancellation progress." }
            transition = transition.copy(
                phase = ScheduledExportTransitionPhase.OLD_WORK_CANCELLED,
            )
        }

        if (transition.phase == ScheduledExportTransitionPhase.OLD_WORK_CANCELLED) {
            val fallbackProvesArm = currentFallback?.generation == generation &&
                currentFallback.id == transition.replacement.id
            if (!fallbackProvesArm) {
                armOccurrence(transition.replacement)
            }
            // If the process dies after enqueue but before this phase write, recovery re-arms the
            // same alarm and unique fallback. A running replacement fallback itself proves enqueue.
            transitionObserver.onCheckpoint(ScheduledExportTransitionCheckpoint.NEW_OCCURRENCE_ARM)
            check(
                stateStore.updateTransitionPhase(
                    generation,
                    ScheduledExportTransitionPhase.NEW_OCCURRENCE_ARMED,
                ),
            ) { "Unable to persist scheduled-export arm progress." }
            transition = transition.copy(
                phase = ScheduledExportTransitionPhase.NEW_OCCURRENCE_ARMED,
            )
        }

        if (transition.phase == ScheduledExportTransitionPhase.NEW_OCCURRENCE_ARMED) {
            check(stateStore.finalizeTransition(generation)) {
                "Unable to finalize scheduled-export generation transition."
            }
            transitionObserver.onCheckpoint(ScheduledExportTransitionCheckpoint.FINALIZATION)
            Timber.i(
                "Scheduled export generation armed old=%s new=%s reason=%s",
                ScheduledExportGeneration.diagnosticId(transition.previousGeneration),
                ScheduledExportGeneration.diagnosticId(generation),
                transition.reason,
            )
        }
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

    private suspend fun admitAndAdvanceOccurrenceLocked(
        occurrence: ScheduledExportOccurrence,
        expedited: Boolean,
        catchUpThroughMillis: Long,
        nextOccurrence: ScheduledExportOccurrence,
        currentFallback: ScheduledExportOccurrence?,
    ): Boolean {
        if (stateStore.loadAdmission() != null) return false
        val admission = ScheduledExportAdmission.create(
            occurrence = occurrence,
            catchUpThroughMillis = catchUpThroughMillis,
            expedited = expedited,
        )
        // Validate the fallback envelope too. Neither validation may occur after durable admission.
        nextOccurrence.toWorkData()
        check(stateStore.prepareAdmission(admission, nextOccurrence)) {
            "Unable to persist scheduled-export admission."
        }

        // The atomic state commit above is the admission boundary. Both external steps are safe to
        // repeat after process death because the exact WorkRequest UUID and next occurrence persist.
        enqueueExport(admission)
        resumePendingArmLocked(currentFallback)
        if (occurrence.id != nextOccurrence.id && occurrence.id != currentFallback?.id) {
            workManager.cancelUniqueWork(
                "$FALLBACK_TRIGGER_WORK_PREFIX${occurrence.id}",
            ).await()
        }
        return true
    }

    private suspend fun enqueueExport(admission: ScheduledExportAdmission) {
        val occurrence = admission.occurrence
        val constraints = Constraints.Builder().apply {
            if (occurrence.configuration.target == ExportTarget.API_ENDPOINT) {
                setRequiredNetworkType(NetworkType.CONNECTED)
            }
        }.build()

        val requestBuilder = OneTimeWorkRequestBuilder<ExportWorker>()
            .setId(admission.workRequestId)
            .setInputData(admission.inputData)
            .setConstraints(constraints)
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.MINUTES)
            .addTag(EXPORT_OCCURRENCE_TAG)
        occurrence.generation?.let { generation ->
            requestBuilder
                .addTag(generationTag(generation))
                .addTag(exportGenerationTag(generation))
        }
        if (admission.expedited) {
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

    /** Caller holds [ScheduledExportRunCoordinator.mutex]. */
    private suspend fun cancelPreviousTransitionWork(
        transition: ScheduledExportTransition,
        currentFallback: ScheduledExportOccurrence?,
    ) {
        cancelExactAlarm()
        Timber.i(
            "Cancelling scheduled export work generation=%s reason=%s",
            ScheduledExportGeneration.diagnosticId(transition.previousGeneration),
            transition.reason,
        )
        cancelTransitionCleanup(transition, currentFallback)
        // Remove the pre-one-shot periodic request without touching unrelated manual work.
        workManager.cancelUniqueWork(ExportWorker.WORK_NAME).await()
        Timber.i(
            "Cancelled scheduled export work generation=%s reason=%s",
            ScheduledExportGeneration.diagnosticId(transition.previousGeneration),
            transition.reason,
        )
    }

    private suspend fun cancelTransitionCleanup(
        transition: ScheduledExportTransition,
        currentFallback: ScheduledExportOccurrence?,
    ) {
        when (transition.cleanupScope) {
            ScheduledExportCleanupScope.LEGACY -> cancelLegacyScheduledWork(
                previousOccurrenceId = transition.previousOccurrenceId,
                currentFallback = currentFallback,
            )
            ScheduledExportCleanupScope.GENERATION -> cancelGenerationScheduledWork(
                generation = requireNotNull(transition.previousGeneration),
                previousOccurrenceId = transition.previousOccurrenceId,
                currentFallback = currentFallback,
            )
            ScheduledExportCleanupScope.NONE -> Unit
        }
    }

    /**
     * A fallback cannot cancel its own WorkManager row and still complete recovery. In that case,
     * generation-scoped export work is cancelled separately and the current stale fallback exits
     * after observing the already-durable replacement generation.
     */
    private suspend fun cancelGenerationScheduledWork(
        generation: String,
        previousOccurrenceId: String?,
        currentFallback: ScheduledExportOccurrence?,
    ) {
        if (currentFallback?.generation == generation) {
            workManager.cancelAllWorkByTag(exportGenerationTag(generation)).await()
            if (previousOccurrenceId != null && previousOccurrenceId != currentFallback.id) {
                workManager.cancelUniqueWork(
                    "$FALLBACK_TRIGGER_WORK_PREFIX$previousOccurrenceId",
                ).await()
            }
        } else {
            workManager.cancelAllWorkByTag(generationTag(generation)).await()
        }
    }

    /** Broad tags are reserved for pre-generation/unknown cleanup before replacement work is armed. */
    private suspend fun cancelLegacyScheduledWork(
        previousOccurrenceId: String?,
        currentFallback: ScheduledExportOccurrence?,
    ) {
        workManager.cancelAllWorkByTag(EXPORT_OCCURRENCE_TAG).await()
        if (currentFallback == null) {
            cancelFallbackTriggers()
        } else if (previousOccurrenceId != null && previousOccurrenceId != currentFallback.id) {
            workManager.cancelUniqueWork(
                "$FALLBACK_TRIGGER_WORK_PREFIX$previousOccurrenceId",
            ).await()
        }
    }

    private suspend fun cancelLocked(reason: GenerationBoundaryReason) {
        deactivateAndCancelScheduledWork(reason)
        check(stateStore.markGenerationMigrationComplete()) {
            "Unable to persist scheduled-export migration completion."
        }
    }

    /** Avoid canceling a fallback worker from inside that same running worker. */
    private suspend fun cancelFromDeliveryLocked(
        occurrence: ScheduledExportOccurrence,
        isFallbackDelivery: Boolean,
    ) {
        deactivateAndCancelScheduledWork(
            reason = GenerationBoundaryReason.SCHEDULE_DISABLED,
            currentFallback = occurrence.takeIf { isFallbackDelivery },
        )
        check(stateStore.markGenerationMigrationComplete()) {
            "Unable to persist scheduled-export migration completion."
        }
    }

    /** Caller holds [ScheduledExportRunCoordinator.mutex], closing the worker admission race. */
    private suspend fun deactivateAndCancelScheduledWork(
        reason: GenerationBoundaryReason,
        currentFallback: ScheduledExportOccurrence? = null,
    ) {
        val transition = stateStore.loadTransition()
        val active = stateStore.load()
        val activeGeneration = active?.generation
        // Clearing first is the disable invariant: surviving work fails closed even if cleanup dies.
        check(stateStore.clear()) {
            "Unable to clear scheduled-export state before cancellation."
        }
        cancelExactAlarm()
        Timber.i(
            "Cancelling scheduled export work generation=%s reason=%s",
            ScheduledExportGeneration.diagnosticId(activeGeneration),
            reason.name,
        )

        if (transition != null) {
            // PREPARED is the only phase in which broad legacy cleanup can still be required. Once
            // arming may have happened, cancel only the replacement's generation-specific tags.
            if (transition.phase == ScheduledExportTransitionPhase.PREPARED) {
                cancelTransitionCleanup(transition, currentFallback)
            }
            requireNotNull(transition.replacement.generation).let { replacementGeneration ->
                cancelGenerationScheduledWork(
                    generation = replacementGeneration,
                    previousOccurrenceId = transition.replacement.id,
                    currentFallback = currentFallback,
                )
            }
        } else if (activeGeneration?.let(ScheduledExportGeneration::isValid) == true) {
            cancelGenerationScheduledWork(
                generation = activeGeneration,
                previousOccurrenceId = active.id,
                currentFallback = currentFallback,
            )
        } else {
            // No durable generation may mean interrupted legacy cleanup; scheduled-only tags remain
            // safe, while manual export work has no such tags.
            cancelLegacyScheduledWork(active?.id, currentFallback)
        }
        workManager.cancelUniqueWork(ExportWorker.WORK_NAME).await()
        Timber.i(
            "Cancelled scheduled export work generation=%s reason=%s",
            ScheduledExportGeneration.diagnosticId(activeGeneration),
            reason.name,
        )
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

    private fun exportGenerationTag(generation: String): String =
        "$EXPORT_GENERATION_TAG_PREFIX$generation"

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
        const val EXPORT_GENERATION_TAG_PREFIX = "scheduled_export_occurrence_generation_"
        private const val FALLBACK_TRIGGER_WORK_PREFIX = "scheduled_export_trigger_"
        private const val EXPORT_OCCURRENCE_WORK_PREFIX = "scheduled_export_occurrence_"
        private const val EXACT_ALARM_BACKUP_DELAY_MILLIS = 15 * 60_000L
        private const val ALARM_REQUEST_CODE = 6_041
    }
}
