package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.JsonExporter
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.TimestampedSample
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

class APIExportEnvelopeBuilderTest {
    @Test
    fun buildsIosCompatibleEnvelopeAroundCanonicalDailyRecords() {
        val first = LocalDate.of(2026, 7, 10)
        val second = LocalDate.of(2026, 7, 11)
        val payload = APIExportEnvelopeBuilder(JsonExporter()).build(
            records = listOf(HealthData(date = first, activity = ActivityData(steps = 1234))),
            failedDateDetails = listOf(FailedDateDetail(second, ExportFailureReason.NO_HEALTH_DATA)),
            settings = ExportSettings(),
            dateRangeStart = first,
            dateRangeEnd = second,
            exportedAt = Instant.parse("2026-07-12T12:00:00Z"),
        )

        val root = Json.parseToJsonElement(payload).jsonObject
        assertThat(root.getValue("schema").jsonPrimitive.content).isEqualTo("healthmd.api_export")
        assertThat(root.getValue("schema_version").jsonPrimitive.content).isEqualTo("1")
        assertThat(root.getValue("daily_record_schema").jsonPrimitive.content).isEqualTo("healthmd.health_data")
        assertThat(root.getValue("source").jsonPrimitive.content).isEqualTo("android")
        assertThat(root.getValue("record_count").jsonPrimitive.content).isEqualTo("1")

        val record = root.getValue("records").jsonArray.single().jsonObject
        assertThat(record.getValue("schema").jsonPrimitive.content).isEqualTo("healthmd.health_data")
        assertThat(record.getValue("schema_version").jsonPrimitive.content).isEqualTo("4")
        assertThat(record.getValue("date").jsonPrimitive.content).isEqualTo("2026-07-10")
        assertThat(record.getValue("unit_system").jsonPrimitive.content).isEqualTo("metric")
        assertThat(record.getValue("time_context").jsonObject.getValue("timestamp_timezone").jsonPrimitive.content)
            .isEqualTo("UTC")
        assertThat(record.getValue("units").jsonObject.getValue("steps").jsonPrimitive.content)
            .isEqualTo("count")
        assertThat(record.getValue("activity").jsonObject.getValue("steps").jsonPrimitive.content)
            .isEqualTo("1234")

        val failure = root.getValue("failed_date_details").jsonArray.single().jsonObject
        assertThat(failure.getValue("date").jsonPrimitive.content).isEqualTo(
            second.atStartOfDay(ZoneId.systemDefault()).toInstant().toString()
        )
        assertThat(failure.getValue("reason").jsonPrimitive.content).isEqualTo("no_health_data")
    }

    @Test
    fun batchesRetainFailureOnlyDaysAndScopeExactDateRanges() {
        val first = LocalDate.of(2026, 7, 10)
        val second = first.plusDays(1)
        val third = second.plusDays(1)
        val builder = APIExportEnvelopeBuilder(JsonExporter())
        val batches = builder.buildBatches(
            requestedDates = listOf(first, second, third),
            records = listOf(
                HealthData(first, activity = ActivityData(steps = 1)),
                HealthData(third, activity = ActivityData(steps = 3)),
            ),
            failedDateDetails = listOf(
                FailedDateDetail(second, ExportFailureReason.NO_HEALTH_DATA),
            ),
            settings = ExportSettings(),
            exportedAt = Instant.parse("2026-07-13T12:00:00Z"),
            calendarTimeZone = "UTC",
            maxDaysPerBatch = 2,
        )

        assertThat(batches).hasSize(2)
        assertThat(batches[0].requestedDates).containsExactly(first, second).inOrder()
        assertThat(batches[0].dateRangeStart).isEqualTo(first)
        assertThat(batches[0].dateRangeEnd).isEqualTo(second)
        val firstBody = Json.parseToJsonElement(batches[0].payload).jsonObject
        assertThat(firstBody.getValue("record_count").jsonPrimitive.content).isEqualTo("1")
        assertThat(firstBody.getValue("failed_date_details").jsonArray).hasSize(1)
        assertThat(batches[1].requestedDates).containsExactly(third)
        val secondRange = Json.parseToJsonElement(batches[1].payload).jsonObject
            .getValue("date_range").jsonObject
        assertThat(secondRange.getValue("start").jsonPrimitive.content).isEqualTo(third.toString())
        assertThat(secondRange.getValue("end").jsonPrimitive.content).isEqualTo(third.toString())

        val failureOnly = builder.buildBatches(
            requestedDates = listOf(second),
            records = emptyList(),
            failedDateDetails = listOf(FailedDateDetail(second, ExportFailureReason.NO_HEALTH_DATA)),
            settings = ExportSettings(),
            exportedAt = Instant.parse("2026-07-13T12:00:00Z"),
            calendarTimeZone = "UTC",
        )
        val failureOnlyBody = Json.parseToJsonElement(failureOnly.single().payload).jsonObject
        assertThat(failureOnlyBody.getValue("record_count").jsonPrimitive.content).isEqualTo("0")
        assertThat(failureOnlyBody.getValue("failed_date_details").jsonArray).hasSize(1)
    }

    @Test
    fun batchingUsesFinalEncodedUtf8BodyBytes() {
        val first = LocalDate.of(2026, 7, 10)
        val second = first.plusDays(1)
        val records = listOf(
            HealthData(first, activity = ActivityData(steps = 1)),
            HealthData(second, activity = ActivityData(steps = 2)),
        )
        val builder = APIExportEnvelopeBuilder(JsonExporter())
        val exportedAt = Instant.parse("2026-07-13T12:00:00Z")
        val combined = builder.build(
            records = records,
            failedDateDetails = emptyList(),
            settings = ExportSettings(),
            dateRangeStart = first,
            dateRangeEnd = second,
            exportedAt = exportedAt,
            calendarTimeZone = "UTC",
        )
        val exactBytes = combined.encodeToByteArray().size.toULong()

        val atLimit = builder.buildBatches(
            requestedDates = listOf(first, second),
            records = records,
            failedDateDetails = emptyList(),
            settings = ExportSettings(),
            exportedAt = exportedAt,
            calendarTimeZone = "UTC",
            maxEncodedBytes = exactBytes,
        )
        val belowLimit = builder.buildBatches(
            requestedDates = listOf(first, second),
            records = records,
            failedDateDetails = emptyList(),
            settings = ExportSettings(),
            exportedAt = exportedAt,
            calendarTimeZone = "UTC",
            maxEncodedBytes = exactBytes - 1uL,
        )

        assertThat(atLimit).hasSize(1)
        assertThat(atLimit.single().payload.encodeToByteArray().size.toULong()).isEqualTo(exactBytes)
        assertThat(belowLimit).hasSize(2)
        assertThat(belowLimit.map { it.requestedDates.single() })
            .containsExactly(first, second).inOrder()
    }

    @Test
    fun individualTrackingFetchRequirementDoesNotExposeGranularApiData() {
        val date = LocalDate.of(2026, 7, 10)
        val sample = TimestampedSample(LocalDateTime.of(2026, 7, 10, 12, 0), 72.0)
        val record = HealthData(date, heart = HeartData(averageHeartRate = 72.0, samples = listOf(sample)))
        val tracking = IndividualTrackingSettings(globalEnabled = true, enabledMetrics = setOf("avg_hr"))
        assertThat(tracking.requiresGranularData).isTrue()

        val privatePayload = APIExportEnvelopeBuilder(JsonExporter()).build(
            records = listOf(record),
            failedDateDetails = emptyList(),
            settings = ExportSettings(individualTracking = tracking, includeGranularData = false),
            dateRangeStart = date,
            dateRangeEnd = date,
        )
        val privateRecord = Json.parseToJsonElement(privatePayload).jsonObject
            .getValue("records").jsonArray.single().jsonObject
        assertThat(privateRecord.getValue("heart").jsonObject.containsKey("heartRateSamples")).isFalse()

        val detailedPayload = APIExportEnvelopeBuilder(JsonExporter()).build(
            records = listOf(record),
            failedDateDetails = emptyList(),
            settings = ExportSettings(individualTracking = tracking, includeGranularData = true),
            dateRangeStart = date,
            dateRangeEnd = date,
        )
        val detailedRecord = Json.parseToJsonElement(detailedPayload).jsonObject
            .getValue("records").jsonArray.single().jsonObject
        assertThat(detailedRecord.getValue("heart").jsonObject.getValue("heartRateSamples").jsonArray).hasSize(1)
    }
}
