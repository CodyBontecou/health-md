package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.JsonExporter
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import java.time.Instant
import java.time.LocalDate
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class APIExportEnginePlannerTest {
    @Test
    fun nativePlanUsesExactBuilderBodiesOrderingAndArtifactIdentity() {
        val first = LocalDate.of(2026, 7, 24)
        val second = first.plusDays(1)
        val third = second.plusDays(1)
        val records = listOf(
            HealthData(first, activity = ActivityData(steps = 1)),
            HealthData(third, activity = ActivityData(steps = 3)),
        )
        val failures = listOf(FailedDateDetail(second, ExportFailureReason.NO_HEALTH_DATA))
        val settings = ExportSettings(
            formatCustomization = FormatCustomization.analyticalDefault(),
        )
        val builder = APIExportEnvelopeBuilder(JsonExporter())
        val request = FrozenAPIExportRequest.capture(
            requestedDates = listOf(first, second, third),
            records = records,
            failedDateDetails = failures,
            settings = settings,
            mode = ExportEngineMode.shadow,
            ids = APIExportIds("native-api-request", "native-api-session"),
            calendarTimeZone = "UTC",
            exportedAt = Instant.parse("2026-07-27T12:00:00Z"),
            maxDaysPerBatch = 2,
        )

        val expected = builder.buildBatches(
            requestedDates = request.requestedDates,
            records = records,
            failedDateDetails = failures,
            settings = settings,
            exportedAt = request.exportedAt,
            calendarTimeZone = "UTC",
            maxDaysPerBatch = 2,
        )
        val plan = ProductionAPIExportNativePlanBuilder(builder).plan(request)

        assertThat(request.profile).isEqualTo(AndroidExportProfile.android_frozen_v4)
        assertThat(plan.items.map { it.content.decodeToString() })
            .containsExactlyElementsIn(expected.map { it.payload }).inOrder()
        assertThat(plan.items.map { it.relativePath }).containsExactly(
            "api/native-api-request-0000.json",
            "api/native-api-request-0001.json",
        ).inOrder()
        assertThat(plan.items.all { it.writeMode == ExportArtifactWriteMode.api_post }).isTrue()
        assertThat(plan.items.all { it.mediaType == API_MEDIA_TYPE }).isTrue()
        assertThat(plan.items.map { it.artifactId }.distinct()).hasSize(2)

        val firstEnvelope = Json.parseToJsonElement(plan.items.first().content.decodeToString()).jsonObject
        assertThat(firstEnvelope.getValue("date_range").jsonObject.getValue("start").jsonPrimitive.content)
            .isEqualTo(first.toString())
        assertThat(firstEnvelope.getValue("date_range").jsonObject.getValue("end").jsonPrimitive.content)
            .isEqualTo(second.toString())
        assertThat(firstEnvelope.getValue("failed_date_details").jsonArray).hasSize(1)
    }

    @Test
    fun nativePlanRetainsFailureOnlyArtifact() {
        val date = LocalDate.of(2026, 7, 24)
        val builder = APIExportEnvelopeBuilder(JsonExporter())
        val request = FrozenAPIExportRequest.capture(
            requestedDates = listOf(date),
            records = emptyList(),
            failedDateDetails = listOf(FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA)),
            settings = ExportSettings(),
            mode = ExportEngineMode.shadow,
            ids = APIExportIds("failure-only-request", "failure-only-session"),
            calendarTimeZone = "UTC",
            exportedAt = Instant.parse("2026-07-27T12:00:00Z"),
        )

        val plan = ProductionAPIExportNativePlanBuilder(builder).plan(request)
        val body = Json.parseToJsonElement(plan.items.single().content.decodeToString()).jsonObject

        assertThat(body.getValue("record_count").jsonPrimitive.content).isEqualTo("0")
        assertThat(body.getValue("records").jsonArray).isEmpty()
        assertThat(body.getValue("failed_date_details").jsonArray).hasSize(1)
    }
}
