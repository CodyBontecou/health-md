package com.healthmd.data.scheduler

import android.content.Context
import android.content.SharedPreferences
import androidx.core.content.edit
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import javax.inject.Singleton

/** Persists the single next intended occurrence across process death and device reboot. */
@Singleton
class ScheduledExportStateStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val lock = Any()
    private val preferences = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)

    fun load(): ScheduledExportOccurrence? = synchronized(lock) {
        loadOccurrenceLocked()
    }

    fun save(occurrence: ScheduledExportOccurrence) = synchronized(lock) {
        preferences.edit(commit = true) {
            writeOccurrence(occurrence)
        }
    }

    /**
     * Atomically makes [transition.replacement] the admitted occurrence before any old alarm or
     * WorkManager request is cancelled. Old workers therefore fail their generation check even if
     * the process dies before external cleanup starts.
     */
    internal fun prepareTransition(transition: ScheduledExportTransition) = synchronized(lock) {
        preferences.edit(commit = true) {
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
            preferences.edit(commit = true) {
                putString(KEY_TRANSITION_PHASE, phase.name)
            }
            true
        }
    }

    /** Leaves the already-durable replacement occurrence in place and removes only transition data. */
    internal fun finalizeTransition(generation: String): Boolean = synchronized(lock) {
        val transition = loadTransitionLocked()
        if (
            transition?.replacement?.generation != generation ||
            transition.phase != ScheduledExportTransitionPhase.NEW_OCCURRENCE_ARMED
        ) {
            false
        } else {
            preferences.edit(commit = true) {
                TRANSITION_KEYS.forEach(::remove)
                putBoolean(KEY_GENERATION_MIGRATION_COMPLETE, true)
            }
            true
        }
    }

    fun clear() = synchronized(lock) {
        preferences.edit(commit = true) {
            OCCURRENCE_KEYS.forEach(::remove)
            TRANSITION_KEYS.forEach(::remove)
        }
    }

    fun isGenerationMigrationComplete(): Boolean = synchronized(lock) {
        preferences.getBoolean(KEY_GENERATION_MIGRATION_COMPLETE, false)
    }

    fun markGenerationMigrationComplete() = synchronized(lock) {
        preferences.edit(commit = true) {
            putBoolean(KEY_GENERATION_MIGRATION_COMPLETE, true)
        }
    }

    private fun loadOccurrenceLocked(): ScheduledExportOccurrence? {
        val data = androidx.work.Data.Builder()
            .putString(ScheduledExportOccurrence.KEY_SIGNATURE, preferences.getString(KEY_SIGNATURE, null))
            .putLong(ScheduledExportOccurrence.KEY_TRIGGER_AT_MILLIS, preferences.getLong(KEY_TRIGGER_AT_MILLIS, -1L))
            .putString(ScheduledExportOccurrence.KEY_INTENDED_LOCAL_DATE, preferences.getString(KEY_INTENDED_LOCAL_DATE, null))
            .putInt(ScheduledExportOccurrence.KEY_CADENCE_VALUE, preferences.getInt(KEY_CADENCE_VALUE, -1))
            .putString(ScheduledExportOccurrence.KEY_CADENCE_UNIT, preferences.getString(KEY_CADENCE_UNIT, null))
            .putInt(ScheduledExportOccurrence.KEY_HOUR, preferences.getInt(KEY_HOUR, -1))
            .putInt(ScheduledExportOccurrence.KEY_MINUTE, preferences.getInt(KEY_MINUTE, -1))
            .putInt(ScheduledExportOccurrence.KEY_LOOKBACK_DAYS, preferences.getInt(KEY_LOOKBACK_DAYS, -1))
            .putString(ScheduledExportOccurrence.KEY_DATE_WINDOW, preferences.getString(KEY_DATE_WINDOW, null))
            .putString(ScheduledExportOccurrence.KEY_TARGET, preferences.getString(KEY_TARGET, null))
            .putString(
                ScheduledExportOccurrence.KEY_DESTINATION_FINGERPRINT,
                preferences.getString(KEY_DESTINATION_FINGERPRINT, null),
            )
            .putString(ScheduledExportOccurrence.KEY_ZONE_ID, preferences.getString(KEY_ZONE_ID, null))
            .putString(
                ScheduledExportOccurrence.KEY_GENERATION,
                preferences.getString(KEY_GENERATION, null),
            )
            .putString(
                ScheduledExportOccurrence.KEY_ENGINE_PIN_JSON,
                preferences.getString(KEY_ENGINE_PIN_JSON, null),
            )
            .putString(
                ScheduledExportOccurrence.KEY_SETTINGS_SNAPSHOT_JSON,
                preferences.getString(KEY_SETTINGS_SNAPSHOT_JSON, null),
            )
            .build()
        return ScheduledExportOccurrence.fromWorkData(data)
    }

    private fun loadTransitionLocked(): ScheduledExportTransition? {
        val phaseName = preferences.getString(KEY_TRANSITION_PHASE, null) ?: return null
        val cleanupScopeName = preferences.getString(KEY_TRANSITION_CLEANUP_SCOPE, null) ?: return null
        val reason = preferences.getString(KEY_TRANSITION_REASON, null) ?: return null
        val replacement = loadOccurrenceLocked() ?: return null
        return runCatching {
            ScheduledExportTransition(
                replacement = replacement,
                previousGeneration = preferences.getString(
                    KEY_TRANSITION_PREVIOUS_GENERATION,
                    null,
                ),
                previousOccurrenceId = preferences.getString(
                    KEY_TRANSITION_PREVIOUS_OCCURRENCE_ID,
                    null,
                ),
                cleanupScope = ScheduledExportCleanupScope.valueOf(cleanupScopeName),
                phase = ScheduledExportTransitionPhase.valueOf(phaseName),
                reason = reason,
            )
        }.getOrNull()
    }

    private fun SharedPreferences.Editor.writeOccurrence(occurrence: ScheduledExportOccurrence) {
        val configuration = occurrence.configuration
        putString(KEY_SIGNATURE, configuration.signature)
        putLong(KEY_TRIGGER_AT_MILLIS, occurrence.triggerAtMillis)
        putString(KEY_INTENDED_LOCAL_DATE, occurrence.intendedLocalDate.toString())
        putInt(KEY_CADENCE_VALUE, configuration.cadenceValue)
        putString(KEY_CADENCE_UNIT, configuration.cadenceUnit.name)
        putInt(KEY_HOUR, configuration.hour)
        putInt(KEY_MINUTE, configuration.minute)
        putInt(KEY_LOOKBACK_DAYS, configuration.lookbackDays)
        putString(KEY_DATE_WINDOW, configuration.dateWindow.name)
        putString(KEY_TARGET, configuration.target.name)
        if (configuration.destinationFingerprint == null) {
            remove(KEY_DESTINATION_FINGERPRINT)
        } else {
            putString(KEY_DESTINATION_FINGERPRINT, configuration.destinationFingerprint)
        }
        putString(KEY_ZONE_ID, configuration.zoneId)
        if (occurrence.generation == null) {
            remove(KEY_GENERATION)
        } else {
            putString(KEY_GENERATION, occurrence.generation)
        }
        if (configuration.canonicalEnginePinJson == null) {
            remove(KEY_ENGINE_PIN_JSON)
        } else {
            putString(KEY_ENGINE_PIN_JSON, configuration.canonicalEnginePinJson)
        }
        if (configuration.canonicalSettingsSnapshotJson == null) {
            remove(KEY_SETTINGS_SNAPSHOT_JSON)
        } else {
            putString(KEY_SETTINGS_SNAPSHOT_JSON, configuration.canonicalSettingsSnapshotJson)
        }
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
    }
}
