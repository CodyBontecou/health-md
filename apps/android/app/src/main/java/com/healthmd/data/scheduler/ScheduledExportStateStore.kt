package com.healthmd.data.scheduler

import android.content.Context
import android.content.SharedPreferences
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton

/** Persists the next intended occurrence and one single-flight admission across process death. */
@Singleton
class ScheduledExportStateStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val lock = Any()
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): ScheduledExportOccurrence? = synchronized(lock) {
        loadOccurrenceLocked()
    }

    fun save(occurrence: ScheduledExportOccurrence): Boolean = synchronized(lock) {
        commitPreferences { writeOccurrence(occurrence) }
    }

    /**
     * Atomically advances the schedule while retaining the exact occurrence that still needs to be
     * enqueued or completed. Recovery can therefore repeat external enqueue/arming without losing
     * or readmitting the occurrence.
     */
    internal fun prepareAdmission(
        admission: ScheduledExportAdmission,
        nextOccurrence: ScheduledExportOccurrence,
    ): Boolean = synchronized(lock) {
        if (loadOccurrenceLocked() != admission.occurrence || loadAdmissionLocked() != null) {
            false
        } else {
            commitPreferences {
                writeOccurrence(nextOccurrence)
                writeOccurrence(admission.occurrence, ADMISSION_PREFIX)
                putLong(KEY_ADMISSION_CATCH_UP_THROUGH_MILLIS, admission.catchUpThroughMillis)
                putBoolean(KEY_ADMISSION_EXPEDITED, admission.expedited)
                putString(KEY_ADMISSION_OPERATION_ID, admission.operationId)
                putString(KEY_ADMISSION_WORK_REQUEST_ID, admission.workRequestId.toString())
                putString(KEY_ADMISSION_PHASE, ScheduledExportAdmissionPhase.ACTIVE.name)
                putString(KEY_PENDING_ARM_OCCURRENCE_ID, nextOccurrence.id)
            }
        }
    }

    internal fun loadAdmission(): ScheduledExportAdmission? = synchronized(lock) {
        loadAdmissionLocked()
    }

    internal fun hasCorruptAdmissionState(): Boolean = synchronized(lock) {
        ADMISSION_KEYS.any(preferences::contains) && loadAdmissionLocked() == null
    }

    internal fun clearAdmissionState(): Boolean = synchronized(lock) {
        commitPreferences { ADMISSION_KEYS.forEach(::remove) }
    }

    internal fun matchesAdmission(
        occurrence: ScheduledExportOccurrence,
        operationId: String,
        workRequestId: UUID,
    ): Boolean = synchronized(lock) {
        loadAdmissionLocked()?.let { admission ->
            admission.phase == ScheduledExportAdmissionPhase.ACTIVE &&
                admission.occurrence == occurrence &&
                admission.operationId == operationId &&
                admission.workRequestId == workRequestId
        } == true
    }

    internal fun isAdmissionExecutionCompleted(
        occurrence: ScheduledExportOccurrence,
        operationId: String,
        workRequestId: UUID,
    ): Boolean = synchronized(lock) {
        loadAdmissionLocked()?.let { admission ->
            admission.phase == ScheduledExportAdmissionPhase.EXECUTION_COMPLETED &&
                admission.occurrence == occurrence &&
                admission.operationId == operationId &&
                admission.workRequestId == workRequestId
        } == true
    }

    internal fun markAdmissionExecutionCompleted(
        occurrence: ScheduledExportOccurrence,
        operationId: String,
        workRequestId: UUID,
    ): Boolean = synchronized(lock) {
        val admission = loadAdmissionLocked()
        if (
            admission?.phase != ScheduledExportAdmissionPhase.ACTIVE ||
            admission.occurrence != occurrence ||
            admission.operationId != operationId ||
            admission.workRequestId != workRequestId
        ) {
            false
        } else {
            commitPreferences {
                putString(
                    KEY_ADMISSION_PHASE,
                    ScheduledExportAdmissionPhase.EXECUTION_COMPLETED.name,
                )
            }
        }
    }

    internal fun completeAdmission(
        occurrence: ScheduledExportOccurrence,
        operationId: String,
        workRequestId: UUID,
    ): Boolean = synchronized(lock) {
        if (!matchesAdmissionLocked(occurrence, operationId, workRequestId)) {
            false
        } else {
            commitPreferences { ADMISSION_KEYS.forEach(::remove) }
        }
    }

    internal fun prepareArm(occurrence: ScheduledExportOccurrence): Boolean = synchronized(lock) {
        commitPreferences {
            writeOccurrence(occurrence)
            putString(KEY_PENDING_ARM_OCCURRENCE_ID, occurrence.id)
        }
    }

    internal fun pendingArmOccurrence(): ScheduledExportOccurrence? = synchronized(lock) {
        val expectedId = safeString(KEY_PENDING_ARM_OCCURRENCE_ID) ?: return@synchronized null
        loadOccurrenceLocked()?.takeIf { it.id == expectedId }
    }

    internal fun completePendingArm(occurrenceId: String): Boolean = synchronized(lock) {
        if (safeString(KEY_PENDING_ARM_OCCURRENCE_ID) != occurrenceId) {
            false
        } else {
            commitPreferences { remove(KEY_PENDING_ARM_OCCURRENCE_ID) }
        }
    }

    /**
     * Atomically makes [transition.replacement] the active occurrence before any old alarm or
     * WorkManager request is cancelled. Any prior admission is stale at the same commit boundary.
     */
    internal fun prepareTransition(
        transition: ScheduledExportTransition,
    ): Boolean = synchronized(lock) {
        commitPreferences {
            ADMISSION_KEYS.forEach(::remove)
            remove(KEY_PENDING_ARM_OCCURRENCE_ID)
            writeOccurrence(transition.replacement)
            putString(KEY_TRANSITION_PHASE, transition.phase.name)
            putString(KEY_TRANSITION_CLEANUP_SCOPE, transition.cleanupScope.name)
            putString(KEY_TRANSITION_REASON, transition.reason)
            if (transition.previousGeneration == null) {
                remove(KEY_TRANSITION_PREVIOUS_GENERATION)
            } else {
                putString(KEY_TRANSITION_PREVIOUS_GENERATION, transition.previousGeneration)
            }
            if (transition.previousOccurrenceId == null) {
                remove(KEY_TRANSITION_PREVIOUS_OCCURRENCE_ID)
            } else {
                putString(KEY_TRANSITION_PREVIOUS_OCCURRENCE_ID, transition.previousOccurrenceId)
            }
        }
    }

    internal fun loadTransition(): ScheduledExportTransition? = synchronized(lock) {
        loadTransitionLocked()
    }

    internal fun updateTransitionPhase(
        generation: String,
        phase: ScheduledExportTransitionPhase,
    ): Boolean = synchronized(lock) {
        val transition = loadTransitionLocked()
        if (transition?.replacement?.generation != generation) {
            false
        } else {
            commitPreferences { putString(KEY_TRANSITION_PHASE, phase.name) }
        }
    }

    /** Leaves the already-durable replacement occurrence in place and removes transition data. */
    internal fun finalizeTransition(generation: String): Boolean = synchronized(lock) {
        val transition = loadTransitionLocked()
        if (
            transition?.replacement?.generation != generation ||
            transition.phase != ScheduledExportTransitionPhase.NEW_OCCURRENCE_ARMED
        ) {
            false
        } else {
            commitPreferences {
                TRANSITION_KEYS.forEach(::remove)
                putBoolean(KEY_GENERATION_MIGRATION_COMPLETE, true)
            }
        }
    }

    fun clear(): Boolean = synchronized(lock) {
        commitPreferences {
            OCCURRENCE_KEYS.forEach(::remove)
            TRANSITION_KEYS.forEach(::remove)
            ADMISSION_KEYS.forEach(::remove)
            remove(KEY_PENDING_ARM_OCCURRENCE_ID)
        }
    }

    fun isGenerationMigrationComplete(): Boolean = synchronized(lock) {
        runCatching { preferences.getBoolean(KEY_GENERATION_MIGRATION_COMPLETE, false) }
            .getOrDefault(false)
    }

    fun markGenerationMigrationComplete(): Boolean = synchronized(lock) {
        commitPreferences { putBoolean(KEY_GENERATION_MIGRATION_COMPLETE, true) }
    }

    private fun loadOccurrenceLocked(prefix: String = ""): ScheduledExportOccurrence? = runCatching {
        val data = androidx.work.Data.Builder()
            .putString(ScheduledExportOccurrence.KEY_SIGNATURE, safeString(prefix + KEY_SIGNATURE))
            .putLong(
                ScheduledExportOccurrence.KEY_TRIGGER_AT_MILLIS,
                safeLong(prefix + KEY_TRIGGER_AT_MILLIS, -1L),
            )
            .putString(
                ScheduledExportOccurrence.KEY_INTENDED_LOCAL_DATE,
                safeString(prefix + KEY_INTENDED_LOCAL_DATE),
            )
            .putInt(
                ScheduledExportOccurrence.KEY_CADENCE_VALUE,
                safeInt(prefix + KEY_CADENCE_VALUE, -1),
            )
            .putString(
                ScheduledExportOccurrence.KEY_CADENCE_UNIT,
                safeString(prefix + KEY_CADENCE_UNIT),
            )
            .putInt(ScheduledExportOccurrence.KEY_HOUR, safeInt(prefix + KEY_HOUR, -1))
            .putInt(ScheduledExportOccurrence.KEY_MINUTE, safeInt(prefix + KEY_MINUTE, -1))
            .putInt(
                ScheduledExportOccurrence.KEY_LOOKBACK_DAYS,
                safeInt(prefix + KEY_LOOKBACK_DAYS, -1),
            )
            .putString(
                ScheduledExportOccurrence.KEY_DATE_WINDOW,
                safeString(prefix + KEY_DATE_WINDOW),
            )
            .putString(ScheduledExportOccurrence.KEY_TARGET, safeString(prefix + KEY_TARGET))
            .putString(
                ScheduledExportOccurrence.KEY_DESTINATION_FINGERPRINT,
                safeString(prefix + KEY_DESTINATION_FINGERPRINT),
            )
            .putString(ScheduledExportOccurrence.KEY_ZONE_ID, safeString(prefix + KEY_ZONE_ID))
            .putString(
                ScheduledExportOccurrence.KEY_GENERATION,
                safeString(prefix + KEY_GENERATION),
            )
            .putString(
                ScheduledExportOccurrence.KEY_ENGINE_PIN_JSON,
                safeString(prefix + KEY_ENGINE_PIN_JSON),
            )
            .putString(
                ScheduledExportOccurrence.KEY_SETTINGS_SNAPSHOT_JSON,
                safeString(prefix + KEY_SETTINGS_SNAPSHOT_JSON),
            )
            .build()
        ScheduledExportOccurrence.fromWorkData(data)
    }.getOrNull()

    private fun loadAdmissionLocked(): ScheduledExportAdmission? = runCatching {
        val occurrence = loadOccurrenceLocked(ADMISSION_PREFIX) ?: return@runCatching null
        ScheduledExportAdmission(
            occurrence = occurrence,
            catchUpThroughMillis = safeLong(KEY_ADMISSION_CATCH_UP_THROUGH_MILLIS, -1L),
            expedited = requireNotNull(safeBooleanOrNull(KEY_ADMISSION_EXPEDITED)),
            operationId = requireNotNull(safeString(KEY_ADMISSION_OPERATION_ID)),
            workRequestId = UUID.fromString(
                requireNotNull(safeString(KEY_ADMISSION_WORK_REQUEST_ID)),
            ),
            phase = ScheduledExportAdmissionPhase.valueOf(
                requireNotNull(safeString(KEY_ADMISSION_PHASE)),
            ),
        ).also { it.inputData }
    }.getOrNull()

    private fun matchesAdmissionLocked(
        occurrence: ScheduledExportOccurrence,
        operationId: String,
        workRequestId: UUID,
    ): Boolean = loadAdmissionLocked()?.let { admission ->
        admission.occurrence == occurrence &&
            admission.operationId == operationId &&
            admission.workRequestId == workRequestId
    } == true

    private fun loadTransitionLocked(): ScheduledExportTransition? = runCatching {
        val phaseName = safeString(KEY_TRANSITION_PHASE) ?: return@runCatching null
        val cleanupScopeName = safeString(KEY_TRANSITION_CLEANUP_SCOPE) ?: return@runCatching null
        val reason = safeString(KEY_TRANSITION_REASON) ?: return@runCatching null
        val replacement = loadOccurrenceLocked() ?: return@runCatching null
        ScheduledExportTransition(
            replacement = replacement,
            previousGeneration = safeString(KEY_TRANSITION_PREVIOUS_GENERATION),
            previousOccurrenceId = safeString(KEY_TRANSITION_PREVIOUS_OCCURRENCE_ID),
            cleanupScope = ScheduledExportCleanupScope.valueOf(cleanupScopeName),
            phase = ScheduledExportTransitionPhase.valueOf(phaseName),
            reason = reason,
        )
    }.getOrNull()

    private fun SharedPreferences.Editor.writeOccurrence(
        occurrence: ScheduledExportOccurrence,
        prefix: String = "",
    ) {
        val configuration = occurrence.configuration
        putString(prefix + KEY_SIGNATURE, configuration.signature)
        putLong(prefix + KEY_TRIGGER_AT_MILLIS, occurrence.triggerAtMillis)
        putString(prefix + KEY_INTENDED_LOCAL_DATE, occurrence.intendedLocalDate.toString())
        putInt(prefix + KEY_CADENCE_VALUE, configuration.cadenceValue)
        putString(prefix + KEY_CADENCE_UNIT, configuration.cadenceUnit.name)
        putInt(prefix + KEY_HOUR, configuration.hour)
        putInt(prefix + KEY_MINUTE, configuration.minute)
        putInt(prefix + KEY_LOOKBACK_DAYS, configuration.lookbackDays)
        putString(prefix + KEY_DATE_WINDOW, configuration.dateWindow.name)
        putString(prefix + KEY_TARGET, configuration.target.name)
        if (configuration.destinationFingerprint == null) {
            remove(prefix + KEY_DESTINATION_FINGERPRINT)
        } else {
            putString(prefix + KEY_DESTINATION_FINGERPRINT, configuration.destinationFingerprint)
        }
        putString(prefix + KEY_ZONE_ID, configuration.zoneId)
        if (occurrence.generation == null) {
            remove(prefix + KEY_GENERATION)
        } else {
            putString(prefix + KEY_GENERATION, occurrence.generation)
        }
        if (configuration.canonicalEnginePinJson == null) {
            remove(prefix + KEY_ENGINE_PIN_JSON)
        } else {
            putString(prefix + KEY_ENGINE_PIN_JSON, configuration.canonicalEnginePinJson)
        }
        if (configuration.canonicalSettingsSnapshotJson == null) {
            remove(prefix + KEY_SETTINGS_SNAPSHOT_JSON)
        } else {
            putString(prefix + KEY_SETTINGS_SNAPSHOT_JSON, configuration.canonicalSettingsSnapshotJson)
        }
    }

    private inline fun commitPreferences(
        update: SharedPreferences.Editor.() -> Unit,
    ): Boolean {
        val before = preferences.all.mapValues { (_, value) ->
            if (value is Set<*>) value.toSet() else value
        }
        val editor = preferences.edit()
        editor.update()
        if (editor.commit()) return true

        // SharedPreferences updates its process-local map before disk I/O reports failure. Restore
        // that map synchronously so no caller can mistake a failed durability boundary for success.
        val rollback = preferences.edit().clear()
        before.forEach { (key, value) -> rollback.putStoredValue(key, value) }
        rollback.commit()
        return false
    }

    @Suppress("UNCHECKED_CAST")
    private fun SharedPreferences.Editor.putStoredValue(
        key: String,
        value: Any?,
    ) {
        when (value) {
            null -> remove(key)
            is Boolean -> putBoolean(key, value)
            is Float -> putFloat(key, value)
            is Int -> putInt(key, value)
            is Long -> putLong(key, value)
            is String -> putString(key, value)
            is Set<*> -> putStringSet(key, value as Set<String>)
            else -> error("Unsupported scheduled-export preference type.")
        }
    }

    private fun safeString(key: String): String? = runCatching { preferences.getString(key, null) }
        .getOrNull()

    private fun safeLong(key: String, default: Long): Long =
        runCatching { preferences.getLong(key, default) }.getOrDefault(default)

    private fun safeInt(key: String, default: Int): Int =
        runCatching { preferences.getInt(key, default) }.getOrDefault(default)

    private fun safeBoolean(key: String, default: Boolean): Boolean =
        runCatching { preferences.getBoolean(key, default) }.getOrDefault(default)

    private fun safeBooleanOrNull(key: String): Boolean? {
        if (!preferences.contains(key)) return null
        return runCatching { preferences.getBoolean(key, false) }.getOrNull()
    }

    private companion object {
        const val PREFERENCES_NAME = "health_md_scheduled_export_state"
        const val KEY_SIGNATURE = "signature"
        const val KEY_TRIGGER_AT_MILLIS = "trigger_at_millis"
        const val KEY_INTENDED_LOCAL_DATE = "intended_local_date"
        const val KEY_CADENCE_VALUE = "cadence_value"
        const val KEY_CADENCE_UNIT = "cadence_unit"
        const val KEY_HOUR = "hour"
        const val KEY_MINUTE = "minute"
        const val KEY_LOOKBACK_DAYS = "lookback_days"
        const val KEY_DATE_WINDOW = "date_window"
        const val KEY_TARGET = "target"
        const val KEY_DESTINATION_FINGERPRINT = "destination_fingerprint"
        const val KEY_ZONE_ID = "zone_id"
        const val KEY_GENERATION = "generation"
        const val KEY_ENGINE_PIN_JSON = "engine_pin_json"
        const val KEY_SETTINGS_SNAPSHOT_JSON = "settings_snapshot_json"
        const val KEY_GENERATION_MIGRATION_COMPLETE = "generation_migration_complete_v1"
        const val KEY_TRANSITION_PHASE = "generation_transition_phase_v1"
        const val KEY_TRANSITION_CLEANUP_SCOPE = "generation_transition_cleanup_scope_v1"
        const val KEY_TRANSITION_PREVIOUS_GENERATION = "generation_transition_previous_generation_v1"
        const val KEY_TRANSITION_PREVIOUS_OCCURRENCE_ID = "generation_transition_previous_occurrence_id_v1"
        const val KEY_TRANSITION_REASON = "generation_transition_reason_v1"

        const val ADMISSION_PREFIX = "admission_v2_"
        const val KEY_ADMISSION_CATCH_UP_THROUGH_MILLIS = "admission_v2_catch_up_through_millis"
        const val KEY_ADMISSION_EXPEDITED = "admission_v2_expedited"
        const val KEY_ADMISSION_OPERATION_ID = "admission_v2_operation_id"
        const val KEY_ADMISSION_WORK_REQUEST_ID = "admission_v2_work_request_id"
        const val KEY_ADMISSION_PHASE = "admission_v2_phase"
        const val KEY_PENDING_ARM_OCCURRENCE_ID = "admission_v2_pending_arm_occurrence_id"

        val OCCURRENCE_KEYS = setOf(
            KEY_SIGNATURE,
            KEY_TRIGGER_AT_MILLIS,
            KEY_INTENDED_LOCAL_DATE,
            KEY_CADENCE_VALUE,
            KEY_CADENCE_UNIT,
            KEY_HOUR,
            KEY_MINUTE,
            KEY_LOOKBACK_DAYS,
            KEY_DATE_WINDOW,
            KEY_TARGET,
            KEY_DESTINATION_FINGERPRINT,
            KEY_ZONE_ID,
            KEY_GENERATION,
            KEY_ENGINE_PIN_JSON,
            KEY_SETTINGS_SNAPSHOT_JSON,
        )
        val TRANSITION_KEYS = setOf(
            KEY_TRANSITION_PHASE,
            KEY_TRANSITION_CLEANUP_SCOPE,
            KEY_TRANSITION_PREVIOUS_GENERATION,
            KEY_TRANSITION_PREVIOUS_OCCURRENCE_ID,
            KEY_TRANSITION_REASON,
        )
        val ADMISSION_KEYS = OCCURRENCE_KEYS.mapTo(mutableSetOf()) { ADMISSION_PREFIX + it }
            .apply {
                add(KEY_ADMISSION_CATCH_UP_THROUGH_MILLIS)
                add(KEY_ADMISSION_EXPEDITED)
                add(KEY_ADMISSION_OPERATION_ID)
                add(KEY_ADMISSION_WORK_REQUEST_ID)
                add(KEY_ADMISSION_PHASE)
            }
    }
}
