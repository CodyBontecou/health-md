package com.healthmd.data.scheduler

import android.content.Intent
import androidx.work.Data
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneId

internal class ScheduledExportWorkDataTooLargeException(
    cause: IllegalStateException,
) : IllegalArgumentException(
    "Scheduled export configuration exceeds background-work limits.",
    cause,
)

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
    val enginePin: ExportEnginePin? = null,
    val settingsSnapshot: AndroidExportSettingsSnapshot? = null,
) {
    init {
        require(ZoneId.of(zoneId).id == zoneId) { "Scheduled export zone must be canonical." }
        require(enginePin == null || enginePin.engine != ExportEngineMode.legacy) {
            "Legacy scheduled exports must omit the engine pin."
        }
        require(enginePin == null || ExportEnginePinCodec.isStructurallyValid(enginePin)) {
            "Scheduled export engine pin is invalid."
        }
        require(enginePin == null || enginePin.ianaTimeZone == zoneId) {
            "Scheduled export zone must match the pinned IANA timezone."
        }
        require(
            settingsSnapshot == null ||
                AndroidExportSettingsSnapshotCodec.isStructurallyValid(settingsSnapshot)
        ) { "Scheduled export settings snapshot is invalid." }
        require(settingsSnapshot == null || settingsSnapshot.enginePin == enginePin) {
            "Scheduled export settings snapshot must match the pinned engine."
        }
        require(settingsSnapshot == null || settingsSnapshot.ianaTimeZone == zoneId) {
            "Scheduled export settings snapshot must match the pinned timezone."
        }
        require(settingsSnapshot == null || settingsSnapshot.scheduledExportTarget == target) {
            "Scheduled export settings snapshot must match the accepted target."
        }
    }

    internal val canonicalEnginePinJson: String? by lazy {
        enginePin?.let(ExportEnginePinCodec::encodeCanonical)
    }

    internal val canonicalSettingsSnapshotJson: String? by lazy {
        settingsSnapshot?.let(AndroidExportSettingsSnapshotCodec::encodeCanonical)
    }

    val signature: String by lazy {
        val legacyFields = listOf(
            cadenceValue,
            cadenceUnit.name,
            hour,
            minute,
            lookbackDays,
            dateWindow.name,
            target.name,
            destinationFingerprint.orEmpty(),
            zoneId,
        )
        // An absent snapshot appends nothing, preserving both the exact pre-M6 signature and the
        // already-durable pin-only signature introduced earlier in M6.
        val durableMetadata = listOfNotNull(canonicalEnginePinJson, canonicalSettingsSnapshotJson)
        val value = (legacyFields + durableMetadata).joinToString("|")
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
            enginePin: ExportEnginePin? = null,
            settingsSnapshot: AndroidExportSettingsSnapshot? = null,
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
            destinationFingerprint = if (settings.scheduledExportTarget != ExportTarget.DEVICE_FOLDER) {
                destinationFingerprint
            } else null,
            zoneId = zoneId.id,
            enginePin = enginePin,
            settingsSnapshot = settingsSnapshot,
        )
    }

    /** Schedule comparison used for timezone rebasing; engine authority is per occurrence. */
    fun isSameScheduleExceptZone(other: ScheduledExportConfiguration): Boolean =
        cadenceValue == other.cadenceValue &&
            cadenceUnit == other.cadenceUnit &&
            hour == other.hour &&
            minute == other.minute &&
            lookbackDays == other.lookbackDays &&
            dateWindow == other.dateWindow &&
            target == other.target &&
            destinationFingerprint == other.destinationFingerprint
}

/** A single intended schedule occurrence. Its date remains stable if execution is delayed. */
data class ScheduledExportOccurrence(
    val configuration: ScheduledExportConfiguration,
    val triggerAtMillis: Long,
    val intendedLocalDate: LocalDate,
    /** Null only while decoding pre-generation state for the one-time migration. */
    val generation: String? = null,
) {
    init {
        require(generation == null || ScheduledExportGeneration.isValid(generation)) {
            "Scheduled export generation is invalid."
        }
    }

    val id: String
        get() = buildString {
            generation?.let { append(it.take(16)).append('-') }
            append(configuration.signature.take(16)).append('-').append(triggerAtMillis)
        }

    val enginePin: ExportEnginePin?
        get() = configuration.enginePin

    val settingsSnapshot: AndroidExportSettingsSnapshot?
        get() = configuration.settingsSnapshot

    fun toWorkData(
        catchUpThroughMillis: Long = triggerAtMillis,
        admissionOperationId: String? = null,
    ): Data {
        val builder = Data.Builder()
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
        generation?.let { builder.putString(KEY_GENERATION, it) }
        admissionOperationId?.let {
            builder.putString(ScheduledExportAdmission.KEY_OPERATION_ID, it)
        }
        configuration.canonicalEnginePinJson?.let { builder.putString(KEY_ENGINE_PIN_JSON, it) }
        configuration.canonicalSettingsSnapshotJson?.let {
            builder.putString(KEY_SETTINGS_SNAPSHOT_JSON, it)
        }
        return try {
            builder.build()
        } catch (error: IllegalStateException) {
            throw ScheduledExportWorkDataTooLargeException(error)
        }
    }

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
        generation?.let {
            putExtra(KEY_GENERATION, it)
        } ?: removeExtra(KEY_GENERATION)
        configuration.canonicalEnginePinJson?.let {
            putExtra(KEY_ENGINE_PIN_JSON, it)
        } ?: removeExtra(KEY_ENGINE_PIN_JSON)
        configuration.canonicalSettingsSnapshotJson?.let {
            putExtra(KEY_SETTINGS_SNAPSHOT_JSON, it)
        } ?: removeExtra(KEY_SETTINGS_SNAPSHOT_JSON)
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
        const val KEY_GENERATION = "schedule_generation"
        const val KEY_ENGINE_PIN_JSON = "export_engine_pin_json"
        const val KEY_SETTINGS_SNAPSHOT_JSON = "android_export_settings_snapshot_json"

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
            generation = data.getString(KEY_GENERATION),
            enginePinJson = data.getString(KEY_ENGINE_PIN_JSON),
            settingsSnapshotJson = data.getString(KEY_SETTINGS_SNAPSHOT_JSON),
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
            generation = intent.getStringExtra(KEY_GENERATION),
            enginePinJson = intent.getStringExtra(KEY_ENGINE_PIN_JSON),
            settingsSnapshotJson = intent.getStringExtra(KEY_SETTINGS_SNAPSHOT_JSON),
        )

        fun hasDurableEnginePin(data: Data): Boolean = data.getString(KEY_ENGINE_PIN_JSON) != null

        fun hasDurableSettingsSnapshot(data: Data): Boolean =
            data.getString(KEY_SETTINGS_SNAPSHOT_JSON) != null

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
            generation: String?,
            enginePinJson: String?,
            settingsSnapshotJson: String?,
        ): ScheduledExportOccurrence? {
            if (signature.isNullOrBlank() || triggerAtMillis < 0L || cadenceValue < 1 ||
                hour !in 0..23 || minute !in 0..59 || lookbackDays < 1 || zoneId.isNullOrBlank() ||
                (generation != null && !ScheduledExportGeneration.isValid(generation))
            ) return null

            return runCatching {
                val enginePin = if (enginePinJson == null) {
                    null
                } else {
                    requireNotNull(ExportEnginePinCodec.decodeOrNull(enginePinJson))
                        .also { require(it.engine != ExportEngineMode.legacy) }
                }
                val settingsSnapshot = if (settingsSnapshotJson == null) {
                    null
                } else {
                    requireNotNull(
                        AndroidExportSettingsSnapshotCodec.decodeOrNull(settingsSnapshotJson),
                    )
                }
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
                    enginePin = enginePin,
                    settingsSnapshot = settingsSnapshot,
                )
                if (configuration.signature != signature) return null
                ScheduledExportOccurrence(
                    configuration = configuration,
                    triggerAtMillis = triggerAtMillis,
                    intendedLocalDate = LocalDate.parse(intendedLocalDate),
                    generation = generation,
                )
            }.getOrNull()
        }
    }
}
