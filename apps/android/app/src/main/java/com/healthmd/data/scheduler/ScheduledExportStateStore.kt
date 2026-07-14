package com.healthmd.data.scheduler

import android.content.Context
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
            .build()
        ScheduledExportOccurrence.fromWorkData(data)
    }

    fun save(occurrence: ScheduledExportOccurrence) = synchronized(lock) {
        val configuration = occurrence.configuration
        preferences.edit(commit = true) {
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
        }
    }

    fun clear() = synchronized(lock) {
        preferences.edit(commit = true) { clear() }
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
    }
}
