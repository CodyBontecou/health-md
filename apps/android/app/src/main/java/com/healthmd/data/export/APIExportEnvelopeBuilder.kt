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

data class APIExportEnvelopeBatch(
    val requestedDates: List<LocalDate>,
    val dateRangeStart: LocalDate,
    val dateRangeEnd: LocalDate,
    /** Exact UTF-8 body measured for batching and later placed in the immutable artifact plan. */
    val payload: String,
)

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
        calendarTimeZone: String = ZoneId.systemDefault().id,
    ): String {
        val calendarZone = ZoneId.of(calendarTimeZone)
        val frozenCustomization = settings.formatCustomization.forFrozenApiV4()
        val recordObjects = records.map { record ->
            val existing = parser.parseToJsonElement(
                jsonExporter.export(
                    data = record,
                    customization = frozenCustomization,
                    includeGranularData = settings.includeGranularData,
                )
            ).jsonObject
            canonicalDailyRecord(
                existing = existing,
                record = record,
                settings = settings.copy(formatCustomization = frozenCustomization),
                calendarZone = calendarZone,
            )
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
                        put("date", detail.date.atStartOfDay(calendarZone).toInstant().toString())
                        put("reason", failureReasonWireValue(detail.reason))
                        detail.errorDetails?.takeIf { it.isNotBlank() }?.let { put("errorDetails", it) }
                    })
                }
            })
        }
        return output.encodeToString(JsonObject.serializer(), envelope)
    }

    /**
     * Partitions exact encoded envelopes by requested owner date. Failure-only days are first-class
     * outcomes, and one indivisible day may exceed the byte target and is retained alone.
     */
    fun buildBatches(
        requestedDates: List<LocalDate>,
        records: List<HealthData>,
        failedDateDetails: List<FailedDateDetail>,
        settings: ExportSettings,
        exportedAt: Instant,
        calendarTimeZone: String,
        maxDaysPerBatch: Int = DEFAULT_MAX_DAYS_PER_BATCH,
        maxEncodedBytes: ULong = DEFAULT_MAX_ENCODED_BYTES,
    ): List<APIExportEnvelopeBatch> {
        require(requestedDates.isNotEmpty()) { "API export date scope is empty" }
        require(requestedDates == requestedDates.distinct().sorted()) {
            "API export date scope is invalid"
        }
        require(maxDaysPerBatch in 1..DEFAULT_MAX_DAYS_PER_BATCH) {
            "API export day bound is invalid"
        }
        require(maxEncodedBytes > 0uL) { "API export byte bound is invalid" }
        ZoneId.of(calendarTimeZone)

        val recordsByDate = records.associateBy(HealthData::date)
        val failuresByDate = failedDateDetails.associateBy(FailedDateDetail::date)
        require(recordsByDate.size == records.size && failuresByDate.size == failedDateDetails.size) {
            "API export outcomes are invalid"
        }
        require(recordsByDate.keys.intersect(failuresByDate.keys).isEmpty()) {
            "API export outcomes are invalid"
        }
        require(recordsByDate.keys + failuresByDate.keys == requestedDates.toSet()) {
            "API export outcomes do not cover the date scope"
        }

        val batches = mutableListOf<APIExportEnvelopeBatch>()
        var start = 0
        while (start < requestedDates.size) {
            var chosenEnd = start
            var chosenPayload: String? = null
            val lastCandidateEnd = minOf(requestedDates.size, start + maxDaysPerBatch)
            for (end in start + 1..lastCandidateEnd) {
                val scopedDates = requestedDates.subList(start, end)
                val payload = build(
                    records = scopedDates.mapNotNull(recordsByDate::get),
                    failedDateDetails = scopedDates.mapNotNull(failuresByDate::get),
                    settings = settings,
                    dateRangeStart = scopedDates.first(),
                    dateRangeEnd = scopedDates.last(),
                    exportedAt = exportedAt,
                    calendarTimeZone = calendarTimeZone,
                )
                val exceedsByteBound = payload.encodeToByteArray().size.toULong() > maxEncodedBytes
                if (exceedsByteBound && end > start + 1) break
                chosenEnd = end
                chosenPayload = payload
                if (exceedsByteBound) break
            }
            check(chosenEnd > start && chosenPayload != null) { "API export batch could not be built" }
            val scopedDates = requestedDates.subList(start, chosenEnd).toList()
            batches += APIExportEnvelopeBatch(
                requestedDates = scopedDates,
                dateRangeStart = scopedDates.first(),
                dateRangeEnd = scopedDates.last(),
                payload = chosenPayload,
            )
            start = chosenEnd
        }
        return batches
    }

    private fun canonicalDailyRecord(
        existing: JsonObject,
        record: HealthData,
        settings: ExportSettings,
        calendarZone: ZoneId,
    ): JsonObject {
        val units = HealthDataFields.extract(
            data = record,
            converter = UnitConverter(UnitPreference.METRIC),
            timeFormat = settings.formatCustomization.timeFormat,
            includeLegacyAndroidAliases = settings.formatCustomization.includeLegacyAndroidAliases,
            includeAndroidNativeFields = settings.formatCustomization.includeAndroidNativeFields,
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

    companion object {
        const val API_EXPORT_SCHEMA = "healthmd.api_export"
        const val API_EXPORT_SCHEMA_VERSION = 1
        const val DEFAULT_MAX_DAYS_PER_BATCH = 7
        const val DEFAULT_MAX_ENCODED_BYTES: ULong = 8_388_608uL

        internal fun failureTimestamp(date: LocalDate, calendarTimeZone: String): String =
            date.atStartOfDay(ZoneId.of(calendarTimeZone)).toInstant().toString()

        internal fun failureReasonWireValue(reason: ExportFailureReason): String = when (reason) {
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
        private val RESERVED_DAILY_RECORD_KEYS = setOf(
            "schema",
            "schema_version",
            "time_context",
            "unit_system",
            "units",
        )
    }
}
