package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.SleepStageEntry
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutType
import com.healthmd.domain.model.WorkoutLapData
import com.healthmd.domain.model.WorkoutSegmentData
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.time.Duration.Companion.minutes
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import org.junit.Assert.assertThrows

class WakeDateJsonProducerTest {
    private val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)

    @Test
    fun nativeSuccessorUsesExactInstantsAcrossDstFoldAndCanonicalUnitsWithoutCoreAliases() {
        // Both source instants have the SAME 01:30 wall clock during the fall-back fold.
        val first = exact("2026-11-01T05:30:00.123456789Z", "-04:00")
        val second = exact("2026-11-01T06:30:00.123456789Z", "-05:00")
        val local = LocalDateTime.of(2026, 11, 1, 1, 30, 0, 123456789)
        val identity = ExactSourceIdentity(nativeId = "synthetic-source", origin = "com.example.synthetic")
        val data = HealthData(
            LocalDate.of(2026, 11, 1),
            sleep = SleepData(
                totalDuration = 60.minutes,
                lightSleep = 60.minutes,
                sessionStart = local,
                sessionEnd = local,
                sessions = listOf(SleepSessionEntry(local, local, exactStartTime = first, exactEndTime = second, identity = identity)),
                stages = listOf(SleepStageEntry(local, local, "light", first, second, identity)),
            ),
            activity = ActivityData(steps = 1234, stepSamples = listOf(
                TimestampedSample(local, 100.0, exactTime = first, identity = identity),
                TimestampedSample(local, 200.0, exactTime = second, identity = identity),
            )),
            body = BodyData(weight = 72.125, height = 1.75),
        )
        val text = JsonExporter().export(data, FormatCustomization(unitPreference = UnitPreference.IMPERIAL),
            includeGranularData = true, captureContext = context)
        val root = Json.parseToJsonElement(text).jsonObject
        assertThat(root.getValue("schema").jsonPrimitive.content).isEqualTo("healthmd.health_data")
        assertThat(root.getValue("schema_version").jsonPrimitive.content).isEqualTo("6")
        assertThat(root.getValue("schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
        assertThat(root.getValue("unit_system").jsonPrimitive.content).isEqualTo("metric")
        assertThat(root.getValue("units").jsonObject.mapValues { it.value.jsonPrimitive.content })
            .containsAtLeast("sleep_total_hours", "hours", "sleep_light_hours", "hours",
                "steps", "steps", "weight_kg", "kg", "height_m", "m")
        assertThat(root.getValue("units").jsonObject).doesNotContainKey("sleep_core_hours")
        val time = root.getValue("time_context").jsonObject
        assertThat(time.getValue("calendar_timezone").jsonPrimitive.content).isEqualTo("America/New_York")
        assertThat(time.getValue("timestamp_timezone").jsonPrimitive.content).isEqualTo("UTC")
        assertThat(time.getValue("sleep_day_attribution").jsonPrimitive.content).isEqualTo("morning_ends")
        assertThat(time.getValue("sleep_owner_day_rule").jsonPrimitive.content).isEqualTo("session_end_date")
        assertThat(time.getValue("sleep_interval_clipping").jsonPrimitive.content).isEqualTo("none")
        val sleep = root.getValue("sleep").jsonObject
        assertThat(sleep.getValue("lightSleep").jsonPrimitive.content.toDouble()).isEqualTo(3600.0)
        assertThat(sleep.getValue("bedtimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T05:30:00.123456789Z")
        assertThat(sleep.getValue("wakeTimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T06:30:00.123456789Z")
        val stage = sleep.getValue("sleepStages").jsonArray.single().jsonObject
        assertThat(stage.getValue("startDate").jsonPrimitive.content).isEqualTo("2026-11-01T05:30:00.123456789Z")
        assertThat(stage.getValue("endDate").jsonPrimitive.content).isEqualTo("2026-11-01T06:30:00.123456789Z")
        assertThat(stage.getValue("durationSeconds").jsonPrimitive.content.toDouble()).isEqualTo(3600.0)
        val exactStart = stage.getValue("exactStartTime").jsonObject
        assertThat(exactStart.getValue("nano").jsonPrimitive.content).isEqualTo("123456789")
        assertThat(exactStart.getValue("offset").jsonPrimitive.content).isEqualTo("-04:00")
        assertThat(stage.getValue("identity").jsonObject.getValue("nativeId").jsonPrimitive.content).isEqualTo("synthetic-source")
        assertThat(root.getValue("activity").jsonObject.getValue("stepSamples").jsonArray.map {
            it.jsonObject.getValue("timestamp").jsonPrimitive.content
        }).containsExactly("2026-11-01T05:30:00.123456789Z", "2026-11-01T06:30:00.123456789Z").inOrder()
        assertThat(root.getValue("body").jsonObject.getValue("weight").jsonPrimitive.content.toDouble()).isEqualTo(72.125)
        assertThat(root.getValue("body").jsonObject.getValue("height").jsonPrimitive.content.toDouble()).isEqualTo(1.75)
        assertThat(text).doesNotContain("coreSleep")
        assertThat(text).doesNotContain("sleep_core_hours")
        assertThat(text).doesNotContain("android-analytical-v5")
    }

    @Test
    fun standaloneAndApiUnitsKeepSelectedZeroValuesAndIgnoreDisplayPreferences() {
        val day = LocalDate.of(2026, 11, 1)
        val record = HealthData(day, activity = ActivityData(steps = 0), body = BodyData(weight = 72.125, height = 1.75))
            .filtered(MetricSelectionState(enabledMetrics = setOf("steps", "weight")))
        for (preference in UnitPreference.entries) {
            val settings = ExportSettings(formatCustomization = FormatCustomization(unitPreference = preference))
            val native = Json.parseToJsonElement(JsonExporter().export(record,
                settings.formatCustomization, captureContext = context)).jsonObject
            val api = Json.parseToJsonElement(APIExportEnvelopeBuilder(JsonExporter()).buildWakeDate(
                listOf(record), emptyList(), settings, day, day, context, Instant.parse("2026-11-02T12:00:00Z")
            )).jsonObject.getValue("records").jsonArray.single().jsonObject
            for (root in listOf(native, api)) {
                assertThat(root.getValue("units").jsonObject.mapValues { it.value.jsonPrimitive.content })
                    .containsExactly("steps", "steps", "weight_kg", "kg")
                assertThat(root.getValue("activity").jsonObject.getValue("steps").jsonPrimitive.content).isEqualTo("0")
                assertThat(root.getValue("body").jsonObject.getValue("weight").jsonPrimitive.content.toDouble()).isEqualTo(72.125)
                assertThat(root.getValue("body").jsonObject).doesNotContainKey("height")
            }
        }
    }

    @Test
    fun summaryWorkoutsRetainExactSourceInstantsInsteadOfReconstructingAnEndFromWallTime() {
        val start = exact("2026-11-01T05:30:00.123456789Z", "-04:00")
        val end = exact("2026-11-01T06:30:00.987654321Z", "-05:00")
        val local = LocalDateTime.of(2026, 11, 1, 1, 30)
        val data = HealthData(LocalDate.of(2026, 11, 1), workouts = listOf(WorkoutData(
            workoutType = WorkoutType.CYCLING,
            startTime = local,
            endTime = null,
            duration = 60.minutes,
            exactStartTime = start,
            exactEndTime = end,
            identity = ExactSourceIdentity(nativeId = "synthetic-workout"),
        )))
        val root = Json.parseToJsonElement(JsonExporter().export(data, captureContext = context)).jsonObject
        val workout = root.getValue("workouts").jsonArray.single().jsonObject
        assertThat(workout.getValue("startTimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T05:30:00.123456789Z")
        assertThat(workout.getValue("endTimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T06:30:00.987654321Z")
        assertThat(workout.getValue("identity").jsonObject.getValue("nativeId").jsonPrimitive.content).isEqualTo("synthetic-workout")
        assertThat(workout.getValue("exactEndTime").jsonObject.getValue("nano").jsonPrimitive.content).isEqualTo("987654321")
    }

    @Test
    fun explicitNativeApiEnvelopeDeclaresIndependentVersionAndKeepsExactRecordAuthority() {
        val day = LocalDate.of(2026, 11, 1)
        val instant = exact("2026-11-01T06:30:00.123456789Z", "-05:00")
        val data = HealthData(day, body = BodyData(weight = 72.125), activity = ActivityData(stepSamples = listOf(
            TimestampedSample(LocalDateTime.of(2026, 11, 1, 1, 30), 7.0, exactTime = instant),
        )))
        val settings = ExportSettings(includeGranularData = true,
            formatCustomization = FormatCustomization(unitPreference = UnitPreference.IMPERIAL))
        val exportedAt = Instant.parse("2026-11-02T12:00:00Z")
        val root = Json.parseToJsonElement(APIExportEnvelopeBuilder(JsonExporter()).buildWakeDate(
            listOf(data), emptyList(), settings, day, day, context, exportedAt,
        )).jsonObject
        assertThat(root.getValue("schema_version").jsonPrimitive.content).isEqualTo("2")
        assertThat(root.getValue("daily_record_schema_version").jsonPrimitive.content).isEqualTo("6")
        assertThat(root.getValue("daily_record_schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
        assertThat(root.getValue("daily_record_time_context").jsonObject.getValue("calendar_timezone").jsonPrimitive.content)
            .isEqualTo("America/New_York")
        val record = root.getValue("records").jsonArray.single().jsonObject
        assertThat(record.getValue("schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
        assertThat(record.getValue("time_context")).isEqualTo(root.getValue("daily_record_time_context"))
        assertThat(record.getValue("activity").jsonObject.getValue("stepSamples").jsonArray.single().jsonObject
            .getValue("timestamp").jsonPrimitive.content).isEqualTo("2026-11-01T06:30:00.123456789Z")
        assertThat(record.getValue("body").jsonObject.getValue("weight").jsonPrimitive.content.toDouble()).isEqualTo(72.125)
        assertThat(record.getValue("unit_system").jsonPrimitive.content).isEqualTo("metric")
        assertThat(record.getValue("units").jsonObject.mapValues { it.value.jsonPrimitive.content })
            .containsExactly("weight_kg", "kg")
        assertThat(root.getValue("exported_at").jsonPrimitive.content).isEqualTo("2026-11-02T12:00:00Z")
    }

    @Test
    fun historicalApiEntrypointMustNotDiscardAnExplicitSuccessorCaptureContext() {
        val day = LocalDate.of(2026, 11, 1)
        val error = assertThrows(IllegalArgumentException::class.java) {
            APIExportEnvelopeBuilder(JsonExporter()).build(listOf(HealthData(day)), emptyList(),
                ExportSettings(executionSleepCaptureContext = context), day, day,
                exportedAt = Instant.parse("2026-11-02T12:00:00Z"))
        }
        assertThat(error.message).isEqualTo("historical API cannot discard successor capture authority")
    }

    @Test
    fun successorFailureOnlyBatchesKeepOneCapturedClockAndProfileAcrossPartitions() {
        val days = listOf(LocalDate.of(2026, 11, 1), LocalDate.of(2026, 11, 2))
        val batches = APIExportEnvelopeBuilder(JsonExporter()).buildBatches(days, emptyList(),
            days.map { FailedDateDetail(it, ExportFailureReason.NETWORK_ERROR) }, ExportSettings(),
            Instant.parse("2026-11-03T12:00:00Z"), context.zoneId.id, maxDaysPerBatch = 1,
            captureContext = context)
        assertThat(batches.map { it.requestedDates }).containsExactly(listOf(days[0]), listOf(days[1])).inOrder()
        val roots = batches.map { Json.parseToJsonElement(it.payload).jsonObject }
        for (root in roots) {
            assertThat(root.getValue("schema_version").jsonPrimitive.content).isEqualTo("2")
            assertThat(root.getValue("daily_record_schema_version").jsonPrimitive.content).isEqualTo("6")
            assertThat(root.getValue("daily_record_schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
            assertThat(root.getValue("record_count").jsonPrimitive.content).isEqualTo("0")
            assertThat(root.getValue("daily_record_time_context").jsonObject.getValue("calendar_timezone").jsonPrimitive.content)
                .isEqualTo("America/New_York")
        }
        assertThat(roots.map { it.getValue("failed_date_details").jsonArray.single().jsonObject.getValue("date").jsonPrimitive.content })
            .containsExactly("2026-11-01T04:00:00Z", "2026-11-02T05:00:00Z").inOrder()
    }

    @Test
    fun invalidSourceClockCannotLeakSourceValuesThroughAnEncodingException() {
        val day = LocalDate.of(2026, 11, 1)
        val source = ExactSourceTimestamp(1_793_510_000, 123, "private-invalid-offset")
        val data = HealthData(day, activity = ActivityData(stepSamples = listOf(
            TimestampedSample(day.atStartOfDay(), 7.0, exactTime = source),
        )))
        val error = assertThrows(IllegalArgumentException::class.java) {
            JsonExporter().export(data, includeGranularData = true, captureContext = context)
        }
        assertThat(error.message).isEqualTo("wake-date native JSON is incompatible")
        assertThat(error.cause).isNull()
    }

    @Test
    fun emptyNativeDayKeepsExactSelfDescribingIdentityWithoutOptionalHealthMetadata() {
        val day = LocalDate.of(2026, 11, 1)
        assertThat(JsonExporter().export(HealthData(day), FormatCustomization(),
            captureContext = context)).isEqualTo("""
            {
                "date": "2026-11-01",
                "type": "health-data",
                "schema": "healthmd.health_data",
                "schema_version": 6,
                "schema_profile": "android-sleep-v6",
                "time_context": {
                    "calendar_timezone": "America/New_York",
                    "timestamp_timezone": "UTC",
                    "sleep_day_attribution": "morning_ends",
                    "sleep_owner_day_rule": "session_end_date",
                    "sleep_interval_clipping": "none"
                },
                "unit_system": "metric",
                "units": {}
            }
        """.trimIndent())
    }

    @Test
    fun missingDraftAndConflictingClockAuthorityFailWithoutFallingBackToHistoricalOutput() {
        val day = LocalDate.of(2026, 11, 1)
        val missingSource = HealthData(day, activity = ActivityData(stepSamples = listOf(
            TimestampedSample(day.atStartOfDay(), 7.0),
        )))
        assertThat(assertThrows(IllegalArgumentException::class.java) {
            JsonExporter().export(missingSource, includeGranularData = true, captureContext = context)
        }.message).isEqualTo("wake-date native JSON is incompatible")
        val draft = AndroidCaptureContext(context.zoneId, SleepDayAttribution.MORNING_ENDS, exportProfileID = null)
        assertThat(assertThrows(IllegalArgumentException::class.java) {
            JsonExporter().export(HealthData(day), captureContext = draft)
        }.message).isEqualTo("wake-date capture authority is incompatible")
        assertThat(draft.exportProfileID).isNull()
        assertThat(assertThrows(IllegalArgumentException::class.java) {
            APIExportEnvelopeBuilder(JsonExporter()).buildBatches(listOf(day), listOf(HealthData(day)), emptyList(),
                ExportSettings(), Instant.parse("2026-11-02T12:00:00Z"), "UTC", captureContext = context)
        }.message).isEqualTo("API capture clock is incompatible")
    }

    @Test
    fun clockNormalizationDoesNotRewriteOpaqueProviderMetadataOrSourceIdentity() {
        val day = LocalDate.of(2026, 11, 1)
        val opaque = mapOf("timestamp" to "provider wall clock", "startTimeISO" to "provider literal")
        val data = HealthData(day, activity = ActivityData(stepSamples = listOf(
            TimestampedSample(day.atStartOfDay(), 7.0, metadata = opaque, context = opaque,
                exactTime = exact("2026-11-01T06:30:00.123456789Z", "-05:00"),
                identity = ExactSourceIdentity(nativeId = "synthetic-id", origin = "synthetic-origin")),
        )))
        val sample = Json.parseToJsonElement(JsonExporter().export(data, includeGranularData = true, captureContext = context))
            .jsonObject.getValue("activity").jsonObject.getValue("stepSamples").jsonArray.single().jsonObject
        for (key in listOf("metadata", "context")) {
            val source = sample.getValue(key).jsonObject
            assertThat(source.getValue("timestamp").jsonPrimitive.content).isEqualTo("provider wall clock")
            assertThat(source.getValue("startTimeISO").jsonPrimitive.content).isEqualTo("provider literal")
        }
        assertThat(sample.getValue("identity").jsonObject.getValue("origin").jsonPrimitive.content).isEqualTo("synthetic-origin")
    }

    @Test
    fun nativeWorkoutDetailsUseElapsedInstantsEvenWhenGranularSampleArraysAreDisabled() {
        val day = LocalDate.of(2026, 11, 1)
        val start = exact("2026-11-01T05:30:00.123456789Z", "-04:00")
        val end = exact("2026-11-01T06:30:00.987654321Z", "-05:00")
        val local = LocalDateTime.of(2026, 11, 1, 1, 30)
        val data = HealthData(day, workouts = listOf(WorkoutData(
            workoutType = WorkoutType.CYCLING, startTime = local, endTime = local, duration = 60.minutes,
            exactStartTime = start, exactEndTime = end,
            laps = listOf(WorkoutLapData(local, local, length = 1234.125, exactStartTime = start, exactEndTime = end)),
            segments = listOf(WorkoutSegmentData(local, local, "cycling", repetitions = 4, exactStartTime = start, exactEndTime = end)),
        )))
        val workout = Json.parseToJsonElement(JsonExporter().export(data, captureContext = context))
            .jsonObject.getValue("workouts").jsonArray.single().jsonObject
        val lap = workout.getValue("laps").jsonArray.single().jsonObject
        assertThat(lap.getValue("duration").jsonPrimitive.content.toDouble()).isEqualTo(3600.864197532)
        assertThat(lap.getValue("distance").jsonPrimitive.content.toDouble()).isEqualTo(1234.125)
        assertThat(lap.getValue("endTimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T06:30:00.987654321Z")
        val segment = workout.getValue("segments").jsonArray.single().jsonObject
        assertThat(segment.getValue("durationSeconds").jsonPrimitive.content.toDouble()).isEqualTo(3600.864197532)
        assertThat(segment.getValue("startTime").jsonPrimitive.content).isEqualTo("2026-11-01T05:30:00.123456789Z")
        assertThat(segment.getValue("endTime").jsonPrimitive.content).isEqualTo("2026-11-01T06:30:00.987654321Z")
        assertThat(segment.getValue("repetitions").jsonPrimitive.content).isEqualTo("4")
    }

    @Test
    fun quantityOnlyHeartDetailRetainsValueClockAndIdentityWithoutSummary() {
        val local = LocalDateTime.of(2026, 11, 1, 1, 30, 0, 123456789)
        val stamp = exact("2026-11-01T05:30:00.123456789Z", "-04:00")
        val sample = TimestampedSample(local, 72.125,
            metadata = mapOf("synthetic" to "quantity-precision"), exactTime = stamp,
            identity = ExactSourceIdentity(nativeId = "synthetic-heart", origin = "com.example.synthetic"))
        val data = HealthData(LocalDate.of(2026, 11, 1),
            heart = com.healthmd.domain.model.HeartData(samples = listOf(sample)))
        val root = Json.parseToJsonElement(JsonExporter().export(data,
            FormatCustomization(unitPreference = UnitPreference.IMPERIAL),
            includeGranularData = true, captureContext = context)).jsonObject
        val heart = root.getValue("heart").jsonObject
        assertThat(heart.keys).containsExactly("heartRateSamples")
        val record = heart.getValue("heartRateSamples").jsonArray.single().jsonObject
        assertThat(record.getValue("value").jsonPrimitive.content.toDouble()).isEqualTo(72.125)
        assertThat(record.getValue("timestamp").jsonPrimitive.content).isEqualTo("2026-11-01T05:30:00.123456789Z")
        assertThat(record.getValue("exactTime").jsonObject.getValue("iso8601").jsonPrimitive.content)
            .isEqualTo("2026-11-01T01:30:00.123456789-04:00")
        assertThat(record.getValue("identity").jsonObject.getValue("nativeId").jsonPrimitive.content)
            .isEqualTo("synthetic-heart")
        assertThat(record.getValue("metadata").jsonObject.getValue("synthetic").jsonPrimitive.content)
            .isEqualTo("quantity-precision")
    }

    private fun exact(instant: String, offset: String): ExactSourceTimestamp =
        ExactSourceTimestamp.from(Instant.parse(instant), ZoneOffset.of(offset))
}
