package com.healthmd.data.export

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.UnitConverter
import com.healthmd.domain.model.UnitPreference
import kotlinx.serialization.json.*
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.OffsetDateTime
import java.time.ZoneId
import javax.inject.Inject

class APIExportEnvelopeBuilder @Inject constructor(
    private val jsonExporter: JsonExporter,
) {
    private val parser = Json { ignoreUnknownKeys = true }
    private val output = Json { prettyPrint = true }

    fun build(
        records: List<HealthData>,
        failedDateDetails: List<FailedDateDetail>,
        settings: ExportSettings,
        dateRangeStart: LocalDate,
        dateRangeEnd: LocalDate,
        exportedAt: Instant = Instant.now(),
    ): String {
        val recordObjects = records.map { record ->
            val existing = parser.parseToJsonElement(
                jsonExporter.export(
                    data = record,
                    customization = settings.formatCustomization,
                    includeGranularData = settings.includeGranularData,
                )
            ).jsonObject
            canonicalDailyRecord(existing, record, settings)
        }

        val envelope = buildJsonObject {
            put("schema", API_EXPORT_SCHEMA)
            put("schema_version", API_EXPORT_SCHEMA_VERSION)
            put("daily_record_schema", HealthMdExportSchema.IDENTIFIER)
            put("daily_record_schema_version", HealthMdExportSchema.VERSION)
            put("exported_at", exportedAt.toString())
            put("source", "android")
            put("date_range", buildJsonObject {
                put("start", dateRangeStart.toString())
                put("end", dateRangeEnd.toString())
            })
            put("record_count", recordObjects.size)
            put("records", buildJsonArray { recordObjects.forEach(::add) })
            put("failed_date_details", buildJsonArray {
                failedDateDetails.forEach { detail ->
                    add(buildJsonObject {
                        put("date", detail.date.atStartOfDay(ZoneId.systemDefault()).toInstant().toString())
                        put("reason", detail.reason.wireValue())
                        detail.errorDetails?.takeIf { it.isNotBlank() }?.let { put("errorDetails", it) }
                    })
                }
            })
        }
        return output.encodeToString(JsonObject.serializer(), envelope)
    }

    private fun canonicalDailyRecord(
        existing: JsonObject,
        record: HealthData,
        settings: ExportSettings,
    ): JsonObject {
        val calendarZone = ZoneId.systemDefault()
        val units = HealthDataFields.extract(
            data = record,
            converter = UnitConverter(UnitPreference.METRIC),
            timeFormat = settings.formatCustomization.timeFormat,
            includeAndroidCompatibilityKeys = settings.formatCustomization.includeAndroidCompatibilityKeys,
        ).filter { it.value != null && it.unit.isNotBlank() }
            .associate { it.key to it.unit }

        return buildJsonObject {
            existing.forEach { (key, value) ->
                if (key !in RESERVED_DAILY_RECORD_KEYS) {
                    put(key, canonicalizeTimestamps(value, key, calendarZone))
                }
            }
            put("schema", HealthMdExportSchema.IDENTIFIER)
            put("schema_version", HealthMdExportSchema.VERSION)
            put("time_context", buildJsonObject {
                put("calendar_timezone", calendarZone.id)
                put("timestamp_timezone", "UTC")
            })
            put("unit_system", "metric")
            put("units", buildJsonObject {
                units.toSortedMap().forEach { (key, unit) -> put(key, unit) }
            })
        }
    }

    private fun canonicalizeTimestamps(element: JsonElement, key: String, calendarZone: ZoneId): JsonElement =
        when (element) {
            is JsonObject -> JsonObject(element.mapValues { (childKey, value) ->
                canonicalizeTimestamps(value, childKey, calendarZone)
            })
            is JsonArray -> JsonArray(element.map { canonicalizeTimestamps(it, key, calendarZone) })
            is JsonPrimitive -> if (element.isString && key.isMachineTimestampKey()) {
                JsonPrimitive(toUtcTimestamp(element.content, calendarZone))
            } else element
            else -> element
        }

    private fun String.isMachineTimestampKey(): Boolean =
        this == "timestamp" || this == "startDate" || this == "endDate" || endsWith("ISO")

    private fun toUtcTimestamp(value: String, calendarZone: ZoneId): String {
        runCatching { return Instant.parse(value).toString() }
        runCatching { return OffsetDateTime.parse(value).toInstant().toString() }
        return runCatching { LocalDateTime.parse(value).atZone(calendarZone).toInstant().toString() }
            .getOrDefault(value)
    }

    private fun ExportFailureReason.wireValue(): String = when (this) {
        ExportFailureReason.NO_FOLDER_SELECTED -> "no_vault"
        ExportFailureReason.NO_HEALTH_DATA -> "no_health_data"
        ExportFailureReason.ACCESS_DENIED -> "access_denied"
        ExportFailureReason.FILE_WRITE_ERROR -> "file_write_error"
        ExportFailureReason.RATE_LIMITED -> "rate_limited"
        ExportFailureReason.HEALTH_CONNECT_ERROR -> "health_connect_error"
        ExportFailureReason.DEVICE_LOCKED -> "device_locked"
        ExportFailureReason.BACKGROUND_PERMISSION_DENIED -> "background_permission_denied"
        ExportFailureReason.PAYWALL_REQUIRED -> "paywall_required"
        ExportFailureReason.INVALID_API_ENDPOINT -> "invalid_api_endpoint"
        ExportFailureReason.NETWORK_ERROR -> "network_error"
        ExportFailureReason.API_REJECTED -> "api_rejected"
        ExportFailureReason.RAW_UNSUPPORTED_PROVIDER -> "raw_unsupported_provider"
        ExportFailureReason.RAW_PARTIAL -> "raw_partial"
        ExportFailureReason.RAW_CANCELLED -> "raw_cancelled"
        ExportFailureReason.UNKNOWN -> "unknown"
    }

    companion object {
        const val API_EXPORT_SCHEMA = "healthmd.api_export"
        const val API_EXPORT_SCHEMA_VERSION = 1
        private val RESERVED_DAILY_RECORD_KEYS = setOf(
            "schema",
            "schema_version",
            "time_context",
            "unit_system",
            "units",
        )
    }
}
