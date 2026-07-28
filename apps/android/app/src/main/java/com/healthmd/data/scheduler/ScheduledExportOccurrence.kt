package com.healthmd.data.scheduler

import android.content.Intent
import androidx.work.Data
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneId

/** Immutable schedule configuration captured for one intended export occurrence. */
data class ScheduledExportConfiguration(
    val cadenceValue: Int,
    val cadenceUnit: ScheduleCadenceUnit,
    val hour: Int,
    val minute: Int,
    val lookbackDays: Int,
    val dateWindow: ScheduleDateWindow,
    val target: ExportTarget,
    val destinationFingerprint: String?,
    val zoneId: String,
) {
    val signature: String by lazy {
        val value = listOf(
            cadenceValue,
            cadenceUnit.name,
            hour,
            minute,
            lookbackDays,
            dateWindow.name,
            target.name,
            destinationFingerprint.orEmpty(),
            zoneId,
        ).joinToString("|")
        MessageDigest.getInstance("SHA-256")
            .digest(value.toByteArray(StandardCharsets.UTF_8))
            .joinToString("") { byte ->
                (byte.toInt() and 0xff).toString(16).padStart(2, '0')
            }
    }

    companion object {
        fun from(
            settings: ExportSettings,
            destinationFingerprint: String?,
            zoneId: ZoneId = ZoneId.systemDefault(),
        ): ScheduledExportConfiguration = ScheduledExportConfiguration(
            cadenceValue = when (settings.scheduleCadenceUnit) {
                ScheduleCadenceUnit.MINUTES -> settings.scheduleCadenceValue.coerceAtLeast(15)
                else -> settings.scheduleCadenceValue.coerceAtLeast(1)
            },
            cadenceUnit = settings.scheduleCadenceUnit,
            hour = settings.scheduleHour.coerceIn(0, 23),
            minute = settings.scheduleMinute.coerceIn(0, 59),
            lookbackDays = settings.scheduleLookbackDays.coerceAtLeast(1),
            dateWindow = settings.scheduleDateWindow,
            target = settings.scheduledExportTarget,
            destinationFingerprint = if (settings.scheduledExportTarget == ExportTarget.API_ENDPOINT) {
                destinationFingerprint
            } else null,
            zoneId = zoneId.id,
        )
    }
}

/** A single intended schedule occurrence. Its date remains stable if execution is delayed. */
data class ScheduledExportOccurrence(
    val configuration: ScheduledExportConfiguration,
    val triggerAtMillis: Long,
    val intendedLocalDate: LocalDate,
) {
    val id: String
        get() = "${configuration.signature.take(16)}-$triggerAtMillis"

    fun toWorkData(catchUpThroughMillis: Long = triggerAtMillis): Data = Data.Builder()
        .putString(KEY_SIGNATURE, configuration.signature)
        .putLong(KEY_TRIGGER_AT_MILLIS, triggerAtMillis)
        .putLong(KEY_CATCH_UP_THROUGH_MILLIS, catchUpThroughMillis.coerceAtLeast(triggerAtMillis))
        .putString(KEY_INTENDED_LOCAL_DATE, intendedLocalDate.toString())
        .putInt(KEY_CADENCE_VALUE, configuration.cadenceValue)
        .putString(KEY_CADENCE_UNIT, configuration.cadenceUnit.name)
        .putInt(KEY_HOUR, configuration.hour)
        .putInt(KEY_MINUTE, configuration.minute)
        .putInt(KEY_LOOKBACK_DAYS, configuration.lookbackDays)
        .putString(KEY_DATE_WINDOW, configuration.dateWindow.name)
        .putString(KEY_TARGET, configuration.target.name)
        .putString(KEY_DESTINATION_FINGERPRINT, configuration.destinationFingerprint.orEmpty())
        .putString(KEY_ZONE_ID, configuration.zoneId)
        .build()

    fun putInto(intent: Intent): Intent = intent.apply {
        putExtra(KEY_SIGNATURE, configuration.signature)
        putExtra(KEY_TRIGGER_AT_MILLIS, triggerAtMillis)
        putExtra(KEY_INTENDED_LOCAL_DATE, intendedLocalDate.toString())
        putExtra(KEY_CADENCE_VALUE, configuration.cadenceValue)
        putExtra(KEY_CADENCE_UNIT, configuration.cadenceUnit.name)
        putExtra(KEY_HOUR, configuration.hour)
        putExtra(KEY_MINUTE, configuration.minute)
        putExtra(KEY_LOOKBACK_DAYS, configuration.lookbackDays)
        putExtra(KEY_DATE_WINDOW, configuration.dateWindow.name)
        putExtra(KEY_TARGET, configuration.target.name)
        putExtra(KEY_DESTINATION_FINGERPRINT, configuration.destinationFingerprint.orEmpty())
        putExtra(KEY_ZONE_ID, configuration.zoneId)
    }

    companion object {
        const val KEY_SIGNATURE = "schedule_signature"
        const val KEY_TRIGGER_AT_MILLIS = "intended_run_at_millis"
        const val KEY_CATCH_UP_THROUGH_MILLIS = "catch_up_through_millis"
        const val KEY_INTENDED_LOCAL_DATE = "intended_run_local_date"
        const val KEY_CADENCE_VALUE = "schedule_cadence_value"
        const val KEY_CADENCE_UNIT = "schedule_cadence_unit"
        const val KEY_HOUR = "schedule_hour"
        const val KEY_MINUTE = "schedule_minute"
        const val KEY_LOOKBACK_DAYS = "schedule_lookback_days"
        const val KEY_DATE_WINDOW = "schedule_date_window"
        const val KEY_TARGET = "export_target"
        const val KEY_DESTINATION_FINGERPRINT = "destination_fingerprint"
        const val KEY_ZONE_ID = "schedule_zone_id"

        fun fromWorkData(data: Data): ScheduledExportOccurrence? = fromValues(
            signature = data.getString(KEY_SIGNATURE),
            triggerAtMillis = data.getLong(KEY_TRIGGER_AT_MILLIS, -1L),
            intendedLocalDate = data.getString(KEY_INTENDED_LOCAL_DATE),
            cadenceValue = data.getInt(KEY_CADENCE_VALUE, -1),
            cadenceUnit = data.getString(KEY_CADENCE_UNIT),
            hour = data.getInt(KEY_HOUR, -1),
            minute = data.getInt(KEY_MINUTE, -1),
            lookbackDays = data.getInt(KEY_LOOKBACK_DAYS, -1),
            dateWindow = data.getString(KEY_DATE_WINDOW),
            target = data.getString(KEY_TARGET),
            destinationFingerprint = data.getString(KEY_DESTINATION_FINGERPRINT),
            zoneId = data.getString(KEY_ZONE_ID),
        )

        fun fromIntent(intent: Intent): ScheduledExportOccurrence? = fromValues(
            signature = intent.getStringExtra(KEY_SIGNATURE),
            triggerAtMillis = intent.getLongExtra(KEY_TRIGGER_AT_MILLIS, -1L),
            intendedLocalDate = intent.getStringExtra(KEY_INTENDED_LOCAL_DATE),
            cadenceValue = intent.getIntExtra(KEY_CADENCE_VALUE, -1),
            cadenceUnit = intent.getStringExtra(KEY_CADENCE_UNIT),
            hour = intent.getIntExtra(KEY_HOUR, -1),
            minute = intent.getIntExtra(KEY_MINUTE, -1),
            lookbackDays = intent.getIntExtra(KEY_LOOKBACK_DAYS, -1),
            dateWindow = intent.getStringExtra(KEY_DATE_WINDOW),
            target = intent.getStringExtra(KEY_TARGET),
            destinationFingerprint = intent.getStringExtra(KEY_DESTINATION_FINGERPRINT),
            zoneId = intent.getStringExtra(KEY_ZONE_ID),
        )

        private fun fromValues(
            signature: String?,
            triggerAtMillis: Long,
            intendedLocalDate: String?,
            cadenceValue: Int,
            cadenceUnit: String?,
            hour: Int,
            minute: Int,
            lookbackDays: Int,
            dateWindow: String?,
            target: String?,
            destinationFingerprint: String?,
            zoneId: String?,
        ): ScheduledExportOccurrence? {
            if (signature.isNullOrBlank() || triggerAtMillis < 0L || cadenceValue < 1 ||
                hour !in 0..23 || minute !in 0..59 || lookbackDays < 1 || zoneId.isNullOrBlank()
            ) return null

            return runCatching {
                val configuration = ScheduledExportConfiguration(
                    cadenceValue = cadenceValue,
                    cadenceUnit = ScheduleCadenceUnit.valueOf(requireNotNull(cadenceUnit)),
                    hour = hour,
                    minute = minute,
                    lookbackDays = lookbackDays,
                    dateWindow = ScheduleDateWindow.valueOf(requireNotNull(dateWindow)),
                    target = ExportTarget.valueOf(requireNotNull(target)),
                    destinationFingerprint = destinationFingerprint?.takeIf { it.isNotBlank() },
                    zoneId = ZoneId.of(zoneId).id,
                )
                if (configuration.signature != signature) return null
                ScheduledExportOccurrence(
                    configuration = configuration,
                    triggerAtMillis = triggerAtMillis,
                    intendedLocalDate = LocalDate.parse(intendedLocalDate),
                )
            }.getOrNull()
        }
    }
}
