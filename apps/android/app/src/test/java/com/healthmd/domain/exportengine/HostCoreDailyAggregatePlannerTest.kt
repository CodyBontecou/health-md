package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import com.healthmd.core.HealthMdCoreService
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.AndroidCaptureContext
import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.model.DataTypeSelection
import io.mockk.coEvery
import io.mockk.mockk
import java.time.Instant
import java.time.ZoneOffset
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.TimeFormatPreference
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.NutritionData
import com.healthmd.domain.model.VitalsData
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepDayAttribution
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import kotlin.time.Duration.Companion.minutes
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

/**
 * Opt-in real host UniFFI/JNA qualification of the concrete Android planner.
 * SDK-boundary cases substitute only Health Connect IPC; no real provider, device library or destination is used.
 */
class HostCoreDailyAggregatePlannerTest {
    @Test
    fun successorHonorsDisabledAndroidNativeFieldsLikeTheHistoricalWriter() = runTest {
        val data = HealthData(LocalDate.of(2026, 3, 15),
            body = BodyData(weight = 72.125, bodyWaterMass = 40.625, boneMass = 3.125))
        val customization = FormatCustomization.analyticalDefault().copy(includeAndroidNativeFields = false)
        val historical = com.healthmd.data.export.JsonExporter().export(data, customization)
        assertThat(historical).contains("weight")
        assertThat(historical).doesNotContain("bodyWaterMass")
        assertThat(historical).doesNotContain("boneMass")
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), formatCustomization = customization,
            metricSelection = MetricSelectionState(enabledMetrics = setOf("weight", "body_water_mass", "bone_mass")),
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
        val request = FrozenDailyAggregateExportRequest.capture(data, settings, AndroidExportProfile.android_sleep_v6,
            ExportEngineMode.rust, DailyAggregateExportIds("native-switch-off", "native-switch-off-session"))
        val plan = HealthMdRustDailyAggregatePlanner().plan(request).plan
        assertThat(plan.items).hasSize(4)
        for (item in plan.items) {
            val text = item.content.decodeToString()
            for (key in listOf("bodyWaterMass", "boneMass", "body_water_mass", "bone_mass", "Body Water", "Bone Mass")) {
                assertWithMessage(item.relativePath).that(text).doesNotContain(key)
            }
        }
    }

    @Test
    fun successorKeepsRemainingNativeDetailRecordsAcrossFormatsAndApi() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 3, 15)
        val start = Instant.parse("2026-03-15T10:00:00.125Z")
        val end = start.plusSeconds(60).plusMillis(250)
        val from = start.atZone(context.zoneId).toLocalDateTime(); val to = end.atZone(context.zoneId).toLocalDateTime()
        fun exact(value: Instant) = com.healthmd.domain.model.ExactSourceTimestamp.from(value, ZoneOffset.UTC)
        fun sample(value: Double, marker: String) = com.healthmd.domain.model.TimestampedSample(from, value,
            metadata = mapOf("synthetic" to marker), exactTime = exact(start))
        val data = HealthData(date,
            vitals = VitalsData(bodyTemperatureSamples = listOf(sample(36.125, "body-temperature-source")),
                basalBodyTemperatureSamples = listOf(sample(36.25, "basal-temperature-source")),
                skinTemperatureDeltas = listOf(sample(-0.125, "skin-delta-source"))),
            nutrition = NutritionData(meals = listOf(com.healthmd.domain.model.NutritionMealEntry(from, to,
                name = "Synthetic captured meal", dietaryEnergy = 250.5, protein = 12.25,
                metadata = mapOf("synthetic" to "meal-source"), exactStartTime = exact(start), exactEndTime = exact(end)))),
            reproductiveHealth = com.healthmd.domain.model.ReproductiveHealthData(menstruationPeriods = listOf(
                com.healthmd.domain.model.MenstruationPeriodEntry(from, to, kotlin.time.Duration.parse("60.25s"),
                    metadata = mapOf("synthetic" to "period-source"), exactStartTime = exact(start), exactEndTime = exact(end)))))
        val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
            metricSelection = MetricSelectionState(enabledMetrics = setOf("body_temp", "basal_body_temp", "skin_temperature",
                "nutrition_meals", "menstruation_periods", "menstruation_period_days")),
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
        for (metadata in listOf(false, true)) {
            val request = FrozenDailyAggregateExportRequest.capture(data, settings.copy(includeMetadata = metadata),
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("native-extra-$metadata", "native-extra-session-$metadata"))
            val plan = HealthMdRustDailyAggregatePlanner().plan(request).plan
            assertThat(plan.items).hasSize(4)
            for (item in plan.items) for (marker in listOf("body-temperature-source", "basal-temperature-source", "skin-delta-source", "meal-source", "period-source")) {
                assertWithMessage(item.relativePath).that(item.content.decodeToString()).contains(marker)
            }
            val record = Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()).jsonObject
            assertThat(record.getValue("vitals").jsonObject.getValue("skinTemperatureDeltas").jsonArray.single().jsonObject
                .getValue("value").jsonPrimitive.content.toDouble()).isEqualTo(-0.125)
            assertThat(record.getValue("nutrition").jsonObject.getValue("meals").jsonArray.single().jsonObject
                .getValue("startTimeISO").jsonPrimitive.content).isEqualTo(start.toString())
            assertThat(record.getValue("reproductiveHealth").jsonObject.getValue("menstruationPeriods").jsonArray.single().jsonObject
                .getValue("duration").jsonPrimitive.content.toDouble()).isEqualTo(60.25)
        }
        val apiRequest = FrozenAPIExportRequest.capture(listOf(date), listOf(data), emptyList(), settings, ExportEngineMode.rust,
            APIExportIds("native-extra-api", "native-extra-api-session"), context.zoneId.id, Instant.parse("2026-03-16T00:00:00Z"))
        val api = HealthMdRustAPIExportPlanner().plan(apiRequest)
        validateAPIPlan(api.plan, apiRequest)
        for (marker in listOf("body-temperature-source", "basal-temperature-source", "skin-delta-source", "meal-source", "period-source")) {
            assertThat(api.plan.items.single().content.decodeToString()).contains(marker)
        }
        suspend fun rejects(candidate: HealthData) {
            val request = FrozenDailyAggregateExportRequest.capture(candidate, settings,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("invalid-native-extra", "invalid-native-extra-session"))
            assertThat(runCatching { HealthMdRustDailyAggregatePlanner().plan(request) }.isFailure).isTrue()
        }
        rejects(data.copy(vitals = data.vitals.copy(bodyTemperatureSamples = listOf(sample(Double.NaN, "nonfinite")))))
        rejects(data.copy(vitals = data.vitals.copy(bodyTemperatureSamples = listOf(
            com.healthmd.domain.model.TimestampedSample(from.minusDays(1), 36.5, exactTime = exact(start.minusSeconds(86_400)))))))
        rejects(data.copy(nutrition = data.nutrition.copy(meals = listOf(data.nutrition.meals.single().copy(exactStartTime = null)))))
        rejects(data.copy(nutrition = data.nutrition.copy(meals = listOf(data.nutrition.meals.single().copy(
            startTime = to, endTime = from, exactStartTime = exact(end), exactEndTime = exact(start))))))
        rejects(data.copy(reproductiveHealth = data.reproductiveHealth.copy(menstruationPeriods = listOf(
            data.reproductiveHealth.menstruationPeriods.single().copy(duration = kotlin.time.Duration.INFINITE)))))
    }

    @Test
    fun successorHonorsLegacyAliasChoiceWithoutCreatingCoreSleep() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 3, 15)
        val start = Instant.parse("2026-03-14T23:30:00Z")
        val end = Instant.parse("2026-03-15T00:00:00Z")
        val from = start.atZone(context.zoneId).toLocalDateTime()
        val to = end.atZone(context.zoneId).toLocalDateTime()
        val exactStart = com.healthmd.domain.model.ExactSourceTimestamp.from(start, ZoneOffset.UTC)
        val exactEnd = com.healthmd.domain.model.ExactSourceTimestamp.from(end, ZoneOffset.UTC)
        val data = HealthData(date, activity = ActivityData(wheelchairPushes = 12),
            nutrition = NutritionData(iodine = 150.0),
            mobility = com.healthmd.domain.model.MobilityData(powerAvg = 123.0),
            sleep = SleepData(totalDuration = 30.minutes, lightSleep = 30.minutes, sessionStart = from, sessionEnd = to,
                sessions = listOf(com.healthmd.domain.model.SleepSessionEntry(from, to, exactStartTime = exactStart, exactEndTime = exactEnd)),
                stages = listOf(com.healthmd.domain.model.SleepStageEntry(from, to, "light", exactStart, exactEnd))))
        for (aliases in listOf(false, true)) for (metadata in listOf(false, true)) {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeMetadata = metadata,
                formatCustomization = FormatCustomization.analyticalDefault().copy(includeLegacyAndroidAliases = aliases),
                metricSelection = MetricSelectionState(enabledMetrics = setOf("wheelchair_pushes", "iodine", "power_avg",
                    "sleep_total", "sleep_light", "sleep_bedtime", "sleep_wake")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data, settings, AndroidExportProfile.android_sleep_v6,
                ExportEngineMode.rust, DailyAggregateExportIds("aliases-$aliases-$metadata", "aliases-session-$aliases-$metadata"))
            val plan = HealthMdRustDailyAggregatePlanner().plan(request).plan
            System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { folder ->
                for (item in plan.items) {
                    val output = File(folder, "android-v6-aliases-$aliases-$metadata/${item.relativePath}")
                    val parent = requireNotNull(output.parentFile); check(parent.mkdirs() || parent.isDirectory)
                    output.writeBytes(item.content)
                }
            }
            val byFormat = ExportFormat.entries.associateWith { format ->
                plan.items.single { it.relativePath == request.relativePath(format) }.content.decodeToString()
            }
            val document = Json.parseToJsonElement(byFormat.getValue(ExportFormat.JSON)).jsonObject
            assertThat(document.getValue("sleep").jsonObject.getValue("lightSleep").jsonPrimitive.content.toDouble()).isEqualTo(1800.0)
            assertThat(document.getValue("activity").jsonObject.containsKey("wheelchairPushes")).isEqualTo(aliases)
            assertThat(document.getValue("mobility").jsonObject.containsKey("powerAvg")).isEqualTo(aliases)
            for (format in listOf(ExportFormat.MARKDOWN, ExportFormat.OBSIDIAN_BASES)) {
                assertThat(byFormat.getValue(format).contains("\niodine_mcg: 150.0"))
                    .isEqualTo(aliases && (format == ExportFormat.OBSIDIAN_BASES || metadata))
                assertThat(byFormat.getValue(format).contains("\npower_avg: 123.0"))
                    .isEqualTo(aliases && (format == ExportFormat.OBSIDIAN_BASES || metadata))
            }
            assertThat(byFormat.getValue(ExportFormat.CSV).contains(",Mobility,Average Power,123.0,W,")).isEqualTo(aliases)
            for (text in byFormat.values) {
                assertThat(text).doesNotContain("sleep_core_hours")
                assertThat(text).doesNotContain("coreSleep")
                assertThat(text).doesNotContain(",Core Sleep,")
            }
        }
    }

    @Test
    fun successorKeepsFrozenProviderProvenanceInEveryFormatAndApi() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 3, 15)
        for (metadata in listOf(false, true)) {
            val ids = mutableListOf("health_connect", "synthetic-provider")
            val detailIds = mutableListOf("synthetic-record")
            val detailMap = mutableMapOf<String, List<String>>("route" to detailIds)
            val provenance = com.healthmd.domain.model.CompatibilityProvenance(providerIdsAttempted = ids,
                providerIdsSucceeded = ids,
                categorySelections = listOf(com.healthmd.domain.model.CategoryMergeProvenance("activity", "health_connect")),
                workoutDetailSources = listOf(com.healthmd.domain.model.WorkoutDetailSourceProvenance("synthetic-workout", detailMap)),
                mergePolicyId = "synthetic-merge-policy")
            val data = HealthData(date, activity = ActivityData(steps = 42), compatibilityProvenance = provenance)
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeMetadata = metadata,
                includeGranularData = true, metricSelection = MetricSelectionState(enabledMetrics = setOf("steps")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data, settings, AndroidExportProfile.android_sleep_v6,
                ExportEngineMode.rust, DailyAggregateExportIds("provenance-$metadata", "provenance-session-$metadata"))
            val apiRequest = FrozenAPIExportRequest.capture(listOf(date), listOf(data), emptyList(), settings,
                ExportEngineMode.rust, APIExportIds("provenance-api-$metadata", "provenance-api-session-$metadata"),
                context.zoneId.id, Instant.parse("2026-03-16T00:00:00Z"))
            ids.clear(); ids += "later-source"
            detailIds.clear(); detailIds += "later-source"
            detailMap["route"] = listOf("later-source")
            val plan = HealthMdRustDailyAggregatePlanner().plan(request).plan
            System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { folder ->
                for (item in plan.items) {
                    val output = File(folder, "android-v6-provenance-$metadata/${item.relativePath}")
                    val parent = requireNotNull(output.parentFile); check(parent.mkdirs() || parent.isDirectory)
                    output.writeBytes(item.content)
                }
                if (!metadata) File(folder, "provenance-metadata-off-night-control.md").writeText(
                    com.healthmd.data.export.MarkdownExporter().export(request.data, includeMetadata = false))
            }
            for (item in plan.items) {
                val text = item.content.decodeToString()
                assertWithMessage(item.relativePath).that(text).contains("synthetic-merge-policy")
                assertWithMessage(item.relativePath).that(text).contains("synthetic-provider")
                assertWithMessage(item.relativePath).that(text).contains("synthetic-record")
                assertThat(text).doesNotContain("later-source")
            }
            val document = Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }
                .content.decodeToString()).jsonObject
            assertThat(document.getValue("activity").jsonObject.getValue("steps").jsonPrimitive.content).isEqualTo("42")
            assertThat(document.getValue("metadata").jsonObject.getValue("provenance").jsonObject
                .getValue("providerIdsAttempted").jsonArray.map { it.jsonPrimitive.content })
                .containsExactly("health_connect", "synthetic-provider").inOrder()
            val api = HealthMdRustAPIExportPlanner().plan(apiRequest)
            validateAPIPlan(api.plan, apiRequest)
            val record = Json.parseToJsonElement(api.plan.items.single().content.decodeToString()).jsonObject
                .getValue("records").jsonArray.single().jsonObject
            assertThat(record.getValue("metadata").jsonObject.getValue("provenance").jsonObject
                .getValue("mergePolicyId").jsonPrimitive.content).isEqualTo("synthetic-merge-policy")
            assertThat(api.plan.items.single().content.decodeToString()).doesNotContain("later-source")
        }
    }

    @Test
    fun successorPreservesPlannedWorkoutsAndFhirInEveryFormatAndApi() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 3, 15)
        val start = Instant.parse("2026-03-15T10:00:00.125Z")
        val end = start.plusSeconds(60)
        val fhir = """{"resourceType":"Observation","id":"synthetic-observation","valueString":"literal | ` < & text"}"""
        val data = HealthData(date,
            plannedWorkouts = listOf(com.healthmd.domain.model.PlannedExerciseData(
                workoutType = com.healthmd.domain.model.WorkoutType.RUNNING,
                startTime = start.atZone(context.zoneId).toLocalDateTime(),
                endTime = end.atZone(context.zoneId).toLocalDateTime(), duration = 1.minutes,
                hasExplicitTime = true, exerciseTypeRaw = 56, title = "Synthetic planned run",
                blockDescriptions = listOf("Retain the complete planned block"),
                exactStartTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start, ZoneOffset.UTC),
                exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end, ZoneOffset.UTC))),
            medicalResources = com.healthmd.domain.model.MedicalResourcesData(listOf(
                com.healthmd.domain.model.MedicalResourceData("Observation", 1, "synthetic-source", "synthetic-resource",
                    "4.0.1", "Observation", 1, "synthetic-observation", fhir)), mapOf("Observation" to 1)))
        val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(),
            metricSelection = MetricSelectionState(enabledMetrics = setOf("planned_workouts", "medical_resources")),
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
        for (metadata in listOf(false, true)) for (granular in listOf(false, true)) {
            val customization = settings.formatCustomization.copy(frontmatterConfig =
                com.healthmd.domain.model.FrontmatterConfiguration(fields = listOf(
                    com.healthmd.domain.model.CustomFrontmatterField("planned_workout_count", isEnabled = metadata),
                    com.healthmd.domain.model.CustomFrontmatterField("medical_resource_count", isEnabled = metadata))))
            val request = FrozenDailyAggregateExportRequest.capture(data,
                settings.copy(includeMetadata = metadata, includeGranularData = granular, formatCustomization = customization),
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("planned-medical-$metadata-$granular", "planned-medical-session-$metadata-$granular"))
            val result = HealthMdRustDailyAggregatePlanner().plan(request)
            assertThat(result.plan.items).hasSize(4)
            System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { folder ->
                result.plan.items.forEach { item ->
                    val output = File(folder, "android-v6-planned-medical-$metadata-$granular/${item.relativePath}")
                    val parent = requireNotNull(output.parentFile)
                    check(parent.mkdirs() || parent.isDirectory)
                    output.writeBytes(item.content)
                }
            }
            for (item in result.plan.items) {
                val text = item.content.decodeToString()
                assertWithMessage(item.relativePath).that(text).contains("Synthetic planned run")
                assertWithMessage(item.relativePath).that(text).contains("synthetic-observation")
                assertWithMessage(item.relativePath).that(text).contains("Retain the complete planned block")
            }
            val document = Json.parseToJsonElement(result.plan.items.single { it.relativePath.endsWith(".json") }
                .content.decodeToString()).jsonObject
            assertThat(document.getValue("plannedWorkouts").jsonArray.single().jsonObject
                .getValue("startTimeISO").jsonPrimitive.content).isEqualTo(start.toString())
            val medical = document.getValue("medicalResources").jsonObject
            assertThat(medical.getValue("resources").jsonArray.single().jsonObject
                .getValue("fhirResourceJson").jsonPrimitive.content).isEqualTo(fhir)
            // The pinned registry defines planned-workout count as dimensionless.
            assertThat(document.getValue("units").jsonObject).doesNotContainKey("planned_workout_count")
            assertThat(document.getValue("units").jsonObject.getValue("medical_resource_count").jsonPrimitive.content).isEqualTo("count")
            for (item in result.plan.items) {
                val expected = when {
                    item.relativePath.endsWith(".csv") -> medical.toString().replace("\"", "\"\"")
                    item.relativePath == request.relativePath(ExportFormat.MARKDOWN) -> medical.toString().replace("|", "\\u007c")
                        .replace("`", "\\u0060").replace("<", "\\u003c").replace(">", "\\u003e").replace("&", "\\u0026")
                    else -> medical.toString()
                }
                // JSON is pretty printed; its decoded document was checked above.
                if (!item.relativePath.endsWith(".json")) assertWithMessage(item.relativePath)
                    .that(item.content.decodeToString()).contains(expected)
            }
        }
        val apiRequest = FrozenAPIExportRequest.capture(listOf(date), listOf(data), emptyList(), settings,
            ExportEngineMode.rust, APIExportIds("planned-medical-api", "planned-medical-api-session"),
            context.zoneId.id, Instant.parse("2026-03-16T00:00:00Z"))
        val api = HealthMdRustAPIExportPlanner().plan(apiRequest)
        validateAPIPlan(api.plan, apiRequest)
        val record = Json.parseToJsonElement(api.plan.items.single().content.decodeToString()).jsonObject
            .getValue("records").jsonArray.single().jsonObject
        assertThat(record.getValue("plannedWorkouts").jsonArray.single().jsonObject
            .getValue("title").jsonPrimitive.content).isEqualTo("Synthetic planned run")
        assertThat(record.getValue("medicalResources").jsonObject.getValue("resources").jsonArray.single().jsonObject
            .getValue("fhirResourceJson").jsonPrimitive.content).isEqualTo(fhir)
    }

    @Test
    fun denseSuccessorApiRetainsNativeRecordsAndBatchesFinalBytes() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val first = LocalDate.of(2026, 3, 15)
        val dates = listOf(first, first.plusDays(1))
        val source = dates.map { date ->
            val start = date.atStartOfDay(context.zoneId).toInstant()
            HealthData(date, heart = HeartData(averageHeartRate = 72.0, samples = (0..<2200).map { index ->
                val instant = start.plusSeconds(index.toLong())
                com.healthmd.domain.model.TimestampedSample(instant.atZone(context.zoneId).toLocalDateTime(),
                    Math.nextUp(72.125), source = "synthetic", metadata = mapOf("synthetic" to "x".repeat(600)),
                    exactTime = com.healthmd.domain.model.ExactSourceTimestamp.from(instant, ZoneOffset.UTC),
                    identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "dense-api-$date-$index"))
            }))
        }
        val settings = ExportSettings(includeGranularData = true, includeMetadata = true,
            formatCustomization = FormatCustomization.analyticalDefault().copy(unitPreference = UnitPreference.IMPERIAL),
            metricSelection = MetricSelectionState(enabledMetrics = setOf("avg_hr")),
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
        val request = FrozenAPIExportRequest.capture(dates, source, emptyList(), settings, ExportEngineMode.rust,
            APIExportIds("dense-api", "dense-api-session"), context.zoneId.id, Instant.parse("2026-03-18T00:00:00Z"),
            maxEncodedBytes = 4_000_000uL)
        val result = HealthMdRustAPIExportPlanner().plan(request)
        validateAPIPlan(result.plan, request)
        assertThat(result.plan.items).hasSize(2)
        result.plan.items.forEachIndexed { index, item ->
            System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf { it.isNotBlank() }?.let { folder ->
                val output = File(folder, "android-v6-dense-api/batch-$index.json")
                check(output.parentFile.mkdirs() || output.parentFile.isDirectory)
                output.writeBytes(item.content)
            }
            val root = Json.parseToJsonElement(item.content.decodeToString()).jsonObject
            val record = root.getValue("records").jsonArray.single().jsonObject
            val oracle = Json.parseToJsonElement(com.healthmd.data.export.JsonExporter().export(source[index],
                request.settings.formatCustomization, true, captureContext = context)).jsonObject
            assertThat(record.getValue("heart").jsonObject.getValue("heartRateSamples"))
                .isEqualTo(oracle.getValue("heart").jsonObject.getValue("heartRateSamples"))
            assertThat(record.getValue("summary").jsonObject.getValue("heart").jsonObject
                .getValue("average_heart_rate").jsonPrimitive.content.toDouble()).isEqualTo(72.0)
            assertThat(record.getValue("units").jsonObject.getValue("average_heart_rate").jsonPrimitive.content).isEqualTo("bpm")
            assertThat(record.getValue("unit_system").jsonPrimitive.content).isEqualTo("metric")
            assertThat(item.byteCount <= request.maxEncodedBytes).isTrue()
            assertThat(item.byteCount).isEqualTo(item.content.size.toULong())
            assertThat(item.sha256).isEqualTo(sha256Hex(item.content))
            val mutable = item.content
            mutable.fill(0)
            assertThat(item.sha256).isEqualTo(sha256Hex(item.content))
            assertThat(root.getValue("date_range").jsonObject.getValue("start").jsonPrimitive.content).isEqualTo(dates[index].toString())
        }
        assertThat(result.plan.items.sumOf { it.byteCount } > request.maxEncodedBytes).isTrue()
        val summaryRequest = FrozenAPIExportRequest.capture(dates, source, emptyList(), settings.copy(includeGranularData = false),
            ExportEngineMode.rust, APIExportIds("dense-summary-api", "dense-summary-session"), context.zoneId.id,
            request.exportedAt, maxEncodedBytes = request.maxEncodedBytes)
        val summary = HealthMdRustAPIExportPlanner().plan(summaryRequest)
        validateAPIPlan(summary.plan, summaryRequest)
        assertThat(summary.plan.items).hasSize(1)
        val records = Json.parseToJsonElement(summary.plan.items.single().content.decodeToString()).jsonObject.getValue("records").jsonArray
        assertThat(records).hasSize(2)
        records.forEach { record ->
            assertThat(record.jsonObject.getValue("heart").jsonObject["heartRateSamples"]).isNull()
            assertThat(record.jsonObject.getValue("summary").jsonObject.getValue("heart").jsonObject
                .getValue("average_heart_rate").jsonPrimitive.content.toDouble()).isEqualTo(72.0)
        }
    }

    @Test
    fun denseWakeDatePressureActivityAndMindfulnessRemainCompleteAcrossFormats() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T01:00:00.123456789Z")
        fun exact(value: Instant) = com.healthmd.domain.model.ExactSourceTimestamp.from(value, ZoneOffset.UTC)
        val pressure = (0 until 2_000).map { index ->
            val a = start.plusSeconds(index.toLong())
            com.healthmd.domain.model.BloodPressureSample(a.atZone(context.zoneId).toLocalDateTime(), Math.nextUp(120.125), Math.nextUp(80.125),
                measurementLocation = "left_arm", bodyPosition = "sitting", source = "synthetic", metadata = mapOf("synthetic" to "pressure-$index"),
                exactTime = exact(a), identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-pressure-$index"))
        }
        val steps = pressure.mapIndexed { index, sample ->
            val a = start.plusSeconds(index.toLong())
            com.healthmd.domain.model.TimestampedSample(sample.time, 2_147_483_648.0, source = "synthetic", metadata = mapOf("synthetic" to "steps-$index"),
                exactTime = exact(a), exactEndTime = exact(a.plusNanos(500_000_000)),
                identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-steps-$index"))
        }
        val intensity = steps.mapIndexed { index, sample ->
            val end = start.plusSeconds(index.toLong()).plusNanos(500_000_000)
            com.healthmd.domain.model.ActivityIntensityEntry(sample.time, end.atZone(context.zoneId).toLocalDateTime(), kotlin.time.Duration.parse("0.5s"),
                "moderate", source = "synthetic", metadata = mapOf("synthetic" to "intensity|`source-$index"),
                exactStartTime = sample.exactTime, exactEndTime = sample.exactEndTime,
                identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-intensity-$index"))
        }
        val mind = intensity.mapIndexed { index, value -> com.healthmd.domain.model.MindfulnessSessionEntry(value.startTime, value.endTime,
            sessionType = "meditation", title = "Synthetic|session", notes = "notes `source`", source = "synthetic", metadata = mapOf("synthetic" to "mind-$index"),
            exactStartTime = value.exactStartTime, exactEndTime = value.exactEndTime,
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-mind-$index")) }
        val data = HealthData(LocalDate.of(2026, 11, 1), vitals = VitalsData(bloodPressureSamples = pressure),
            activity = ActivityData(stepSamples = steps, activityIntensityEntries = intensity),
            mindfulness = com.healthmd.domain.model.MindfulnessData(sessions = mind))
        val selection = MetricSelectionState(enabledMetrics = setOf("bp_systolic", "bp_diastolic", "steps", "activity_intensity_minutes", "mindful_minutes"))
        for (metadata in listOf(false, true)) {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true, includeMetadata = metadata,
                metricSelection = selection, executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data.filtered(selection, context), settings, AndroidExportProfile.android_sleep_v6,
                ExportEngineMode.rust, DailyAggregateExportIds("dense-native", "dense-native-session"))
            val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request).plan
            val native = Json.parseToJsonElement(com.healthmd.data.export.JsonExporter().export(request.data,
                request.customization, true, captureContext = context)).jsonObject
            assertThat(plan.items).hasSize(4)
            for (item in plan.items) {
                val text = item.content.decodeToString()
                if (item.relativePath.endsWith(".json")) {
                    val root = Json.parseToJsonElement(text).jsonObject
                    for ((category, field) in listOf("vitals" to "bloodPressureSamples", "activity" to "stepSamples",
                        "activity" to "activityIntensity", "mindfulness" to "sessions")) {
                        assertThat(root.getValue(category).jsonObject.getValue(field)).isEqualTo(native.getValue(category).jsonObject.getValue(field))
                    }
                    assertThat(root.getValue("activity").jsonObject["steps"]).isNull()
                    assertThat(root.getValue("mindfulness").jsonObject["mindfulMinutes"]).isNull()
                } else if (item.relativePath.endsWith(".csv")) {
                    assertThat(text.lineSequence().count { it.contains(",Native Detail,") }).isEqualTo(8_000)
                } else if (item.relativePath.endsWith("-bases.md")) {
                    for (key in listOf("native_correlation_details", "native_activity_details", "native_mindfulness_details")) assertThat(text).contains("$key:")
                }
                System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { directory ->
                    val output = File(directory, "android-v6-dense-native-$metadata/${item.relativePath}")
                    val parent = checkNotNull(output.parentFile); check(parent.mkdirs() || parent.isDirectory); output.writeBytes(item.content)
                }
            }
        }
    }

    @Test
    fun nativePressureActivityAndMindfulnessKeepHiddenFrontmatterSourcesAndRejectInvalidRecords() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T01:00:00.123456789Z"); val end = start.plusSeconds(1)
        fun exact(value: Instant) = com.healthmd.domain.model.ExactSourceTimestamp.from(value, ZoneOffset.UTC)
        val localStart = start.atZone(context.zoneId).toLocalDateTime(); val localEnd = end.atZone(context.zoneId).toLocalDateTime()
        val pressure = com.healthmd.domain.model.BloodPressureSample(localStart, 120.125, 80.125, exactTime = exact(start))
        val step = com.healthmd.domain.model.TimestampedSample(localStart, 42.0, exactTime = exact(start), exactEndTime = exact(end))
        val intensity = com.healthmd.domain.model.ActivityIntensityEntry(localStart, localEnd, kotlin.time.Duration.parse("1s"),
            "moderate", exactStartTime = exact(start), exactEndTime = exact(end))
        val mind = com.healthmd.domain.model.MindfulnessSessionEntry(localStart, localEnd, exactStartTime = exact(start), exactEndTime = exact(end))
        val data = HealthData(LocalDate.of(2026, 11, 1), vitals = VitalsData(bloodPressureSamples = listOf(pressure)),
            activity = ActivityData(stepSamples = listOf(step), activityIntensityEntries = listOf(intensity)),
            mindfulness = com.healthmd.domain.model.MindfulnessData(sessions = listOf(mind)), heart = HeartData(averageHeartRate = 72.125))
        suspend fun plan(candidate: HealthData, enabled: Set<String>, disabled: List<String> = emptyList()): ExportArtifactPlan {
            val selection = MetricSelectionState(enabledMetrics = enabled)
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
                metricSelection = selection, executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
                formatCustomization = FormatCustomization(frontmatterConfig = com.healthmd.domain.model.FrontmatterConfiguration(
                    fields = disabled.map { com.healthmd.domain.model.CustomFrontmatterField(it, isEnabled = false) })))
            val request = FrozenDailyAggregateExportRequest.capture(candidate.filtered(selection, context), settings, AndroidExportProfile.android_sleep_v6,
                ExportEngineMode.rust, DailyAggregateExportIds("native-boundary", "native-boundary-session"))
            return HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request).plan
        }
        for ((selection, disabled) in listOf(setOf("bp_systolic", "bp_diastolic") to listOf("blood_pressure_systolic"),
            setOf("steps") to listOf("steps"), setOf("activity_intensity_minutes") to listOf("activity_intensity_minutes"),
            setOf("mindful_minutes") to listOf("mindful_minutes", "mindful_sessions"))) {
            val result = plan(data, selection, disabled)
            assertThat(result.items).hasSize(4)
            val document = Json.parseToJsonElement(result.items.single { it.relativePath.endsWith(".json") }
                .content.decodeToString()).jsonObject
            val (category, field) = when {
                "bp_systolic" in selection -> "vitals" to "bloodPressureSamples"
                "steps" in selection -> "activity" to "stepSamples"
                "activity_intensity_minutes" in selection -> "activity" to "activityIntensity"
                else -> "mindfulness" to "sessions"
            }
            assertThat(document.getValue(category).jsonObject.getValue(field).jsonArray).hasSize(1)
            for (item in result.items.filter { it.relativePath.endsWith(".md") }) for (key in disabled) {
                assertThat(item.content.decodeToString()).doesNotContain("\n$key:")
            }
        }
        val badPressure = data.copy(vitals = VitalsData(bloodPressureSamples = listOf(pressure.copy(systolic = Double.NaN))))
        assertThat(runCatching { plan(badPressure, setOf("bp_systolic", "bp_diastolic")) }.isFailure).isTrue()
        val badSteps = data.copy(activity = data.activity.copy(stepSamples = listOf(step.copy(value = 1.5))))
        assertThat(runCatching { plan(badSteps, setOf("steps")) }.isFailure).isTrue()
        val badIntensity = data.copy(activity = data.activity.copy(activityIntensityEntries = listOf(intensity.copy(
            endTime = localStart.minusSeconds(1), exactEndTime = exact(start.minusSeconds(1))))))
        assertThat(runCatching { plan(badIntensity, setOf("activity_intensity_minutes")) }.isFailure).isTrue()
        val badMind = data.copy(mindfulness = com.healthmd.domain.model.MindfulnessData(sessions = listOf(mind.copy(
            endTime = localStart, exactEndTime = exact(start)))))
        assertThat(runCatching { plan(badMind, setOf("mindful_minutes")) }.isFailure).isTrue()
        for (candidate in listOf(badPressure, badSteps, badIntensity, badMind)) {
            val plan = plan(candidate, setOf("avg_hr"))
            assertThat(plan.items).hasSize(4)
            for (item in plan.items) for (label in listOf("native_activity_details", "native_mindfulness_details", "native_correlation_details")) {
                assertThat(item.content.decodeToString()).doesNotContain(label)
            }
        }
    }

    @Test
    fun denseWakeDateWorkoutRecordsRemainCompleteAcrossEveryFormat() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = start.plusSeconds(3600).plusNanos(864197532)
        fun exact(value: Instant) = com.healthmd.domain.model.ExactSourceTimestamp.from(value, context.zoneId.rules.getOffset(value))
        val samples = (0 until 2_000).map { index ->
            val instant = start.plusSeconds(index.toLong())
            com.healthmd.domain.model.TimestampedSample(instant.atZone(context.zoneId).toLocalDateTime(), Math.nextUp(160.125),
                metadata = mapOf("synthetic" to "dense-workout-$index"), context = mapOf("synthetic" to "context|value"),
                exactTime = exact(instant), identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-workout-sample-$index"))
        }
        val route = samples.mapIndexed { index, sample -> com.healthmd.domain.model.WorkoutRoutePointData(sample.time,
            40.125, -70.875, altitude = Math.nextUp(12.125), horizontalAccuracy = 2.125, verticalAccuracy = 3.125,
            exactTime = sample.exactTime, identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-route-$index")) }
        val workout = com.healthmd.domain.model.WorkoutData(com.healthmd.domain.model.WorkoutType.RUNNING,
            start.atZone(context.zoneId).toLocalDateTime(), end.atZone(context.zoneId).toLocalDateTime(), duration = kotlin.time.Duration.parse("1800.5s"),
            metadata = mapOf("synthetic" to "workout `source` | notes"), route = route,
            routeAccess = com.healthmd.domain.model.WorkoutRouteAccess.DATA, heartRateSamples = samples,
            speedSamples = samples.take(2), cyclingCadenceSamples = samples.take(2), stepsCadenceSamples = samples.take(2),
            powerSamples = samples.take(2), elevationSamples = samples.take(2), exactStartTime = exact(start), exactEndTime = exact(end),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-dense-workout"),
            correlatedSourceIds = mapOf("heart_rate" to listOf("synthetic-correlated-id")),
            laps = listOf(com.healthmd.domain.model.WorkoutLapData(start.atZone(context.zoneId).toLocalDateTime(),
                end.atZone(context.zoneId).toLocalDateTime(), length = 1000.125, exactStartTime = exact(start), exactEndTime = exact(end))),
            segments = listOf(com.healthmd.domain.model.WorkoutSegmentData(start.atZone(context.zoneId).toLocalDateTime(),
                end.atZone(context.zoneId).toLocalDateTime(), type = "running", exactStartTime = exact(start), exactEndTime = exact(end))),
            splits = listOf(com.healthmd.domain.model.WorkoutSplitData(1, start.atZone(context.zoneId).toLocalDateTime(),
                end.atZone(context.zoneId).toLocalDateTime(), duration = kotlin.time.Duration.parse("1800.5s"), distance = 1000.125,
                exactStartTime = exact(start), exactEndTime = exact(end))))
        val data = HealthData(LocalDate.of(2026, 11, 1), workouts = listOf(workout))
        for (metadata in listOf(false, true)) for (granular in listOf(false, true)) {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = granular,
                includeMetadata = metadata, metricSelection = MetricSelectionState(enabledMetrics = setOf("workouts")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data, settings, AndroidExportProfile.android_sleep_v6,
                ExportEngineMode.rust, DailyAggregateExportIds("dense-workout", "dense-workout-session"))
            val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request).plan
            val native = Json.parseToJsonElement(com.healthmd.data.export.JsonExporter().export(request.data,
                request.customization, granular, captureContext = context)).jsonObject.getValue("workouts").jsonArray
            assertThat(plan.items).hasSize(4)
            for (item in plan.items) {
                val text = item.content.decodeToString()
                if (item.relativePath.endsWith(".json")) {
                    val actual = Json.parseToJsonElement(text).jsonObject.getValue("workouts").jsonArray
                    assertThat(actual).isEqualTo(native)
                    assertThat(actual.single().jsonObject["avgHeartRate"]).isNull()
                }
                if (granular) {
                    if (item.relativePath.endsWith(".json")) assertThat(text).contains("synthetic-route-1999")
                    if (item.relativePath.endsWith(".csv")) assertThat(text.lineSequence().count { it.contains(",Native Detail,Workout,") }).isEqualTo(1)
                    System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { directory ->
                        val output = File(directory, "android-v6-dense-workout-$metadata/${item.relativePath}")
                        val parent = checkNotNull(output.parentFile); check(parent.mkdirs() || parent.isDirectory); output.writeBytes(item.content)
                    }
                } else assertThat(text).doesNotContain("synthetic-route-1999")
            }
        }
    }

    @Test
    fun nativeWorkoutCompositionKeepsSelectedAuthorityAndRejectsInvalidSource() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T01:00:00.123456789Z")
        val end = start.plusSeconds(3600)
        fun exact(value: Instant) = com.healthmd.domain.model.ExactSourceTimestamp.from(value, ZoneOffset.UTC)
        val workout = com.healthmd.domain.model.WorkoutData(com.healthmd.domain.model.WorkoutType.RUNNING,
            start.atZone(context.zoneId).toLocalDateTime(), end.atZone(context.zoneId).toLocalDateTime(),
            duration = 30.minutes, exactStartTime = exact(start), exactEndTime = exact(end))
        suspend fun plan(candidate: com.healthmd.domain.model.WorkoutData, enabled: Set<String>, disabled: List<String> = emptyList()): ExportArtifactPlan {
            val selection = MetricSelectionState(enabledMetrics = enabled)
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
                metricSelection = selection, executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
                formatCustomization = FormatCustomization(frontmatterConfig = com.healthmd.domain.model.FrontmatterConfiguration(
                    fields = disabled.map { com.healthmd.domain.model.CustomFrontmatterField(it, isEnabled = false) })))
            val data = HealthData(LocalDate.of(2026, 11, 1), workouts = listOf(candidate), activity = ActivityData(steps = 42)).filtered(selection, context)
            val request = FrozenDailyAggregateExportRequest.capture(data, settings, AndroidExportProfile.android_sleep_v6,
                ExportEngineMode.rust, DailyAggregateExportIds("workout-boundary", "workout-boundary-session"))
            return HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request).plan
        }
        val registry = HealthMdCoreService().getMetricRegistry(com.healthmd.core.CoreMetricRegistryProfile.ANDROID_SLEEP_V6, 2u)
        val owners = registry.outputs.filter { it.key == "workouts" || it.key.startsWith("workout_") }.map { it.key }
        val hiddenPlan = plan(workout, setOf("workouts"), owners)
        assertThat(hiddenPlan.items).hasSize(4)
        val hiddenRecord = Json.parseToJsonElement(hiddenPlan.items.single { it.relativePath.endsWith(".json") }
            .content.decodeToString()).jsonObject.getValue("workouts").jsonArray.single().jsonObject
        assertThat(hiddenRecord.getValue("startTimeISO").jsonPrimitive.content).isEqualTo(start.toString())
        assertThat(hiddenRecord.getValue("duration").jsonPrimitive.content.toDouble()).isEqualTo(1800.0)
        for (item in hiddenPlan.items.filter { it.relativePath.endsWith(".md") }) for (key in owners) {
            assertThat(item.content.decodeToString()).doesNotContain("\n$key:")
        }
        val reversed = workout.copy(endTime = workout.startTime.minusSeconds(1), exactEndTime = exact(start.minusSeconds(1)))
        assertThat(runCatching { plan(reversed, setOf("workouts")) }.isFailure).isTrue()
        val nonfinite = workout.copy(heartRateSamples = listOf(com.healthmd.domain.model.TimestampedSample(
            workout.startTime, Double.NaN, exactTime = exact(start))))
        assertThat(runCatching { plan(nonfinite, setOf("workouts")) }.isFailure).isTrue()
        for (item in plan(reversed, setOf("steps")).items) {
            assertThat(item.content.decodeToString()).doesNotContain("native_workout_details")
            assertThat(item.content.decodeToString()).doesNotContain("startTimeISO")
        }
    }

    @Test
    fun denseWakeDateSleepRecordsRemainCompleteAcrossEveryFormat() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T02:00:00.123456789Z")
        val end = Instant.parse("2026-11-01T12:00:00.987654321Z")
        fun exact(value: Instant) = com.healthmd.domain.model.ExactSourceTimestamp.from(value, context.zoneId.rules.getOffset(value))
        val stages = (0 until 2_000).map { index ->
            val a = start.plusSeconds(index * 10L); val b = a.plusSeconds(10)
            com.healthmd.domain.model.SleepStageEntry(a.atZone(context.zoneId).toLocalDateTime(), b.atZone(context.zoneId).toLocalDateTime(),
                "light", exact(a), exact(b), com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-stage-$index"))
        }
        val parent = com.healthmd.domain.model.SleepSessionEntry(start.atZone(context.zoneId).toLocalDateTime(),
            end.atZone(context.zoneId).toLocalDateTime(), title = "Synthetic|sleep", notes = "source `clock`", source = "synthetic",
            metadata = mapOf("synthetic" to "source-parent"), exactStartTime = exact(start), exactEndTime = exact(end),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-parent"))
        val data = HealthData(LocalDate.of(2026, 11, 1), sleep = SleepData(stages = stages, sessions = listOf(parent),
            sessionStart = parent.startTime, sessionEnd = parent.endTime), heart = HeartData(samples = listOf(
                com.healthmd.domain.model.TimestampedSample(parent.startTime, Math.nextUp(72.125), exactTime = exact(start),
                    identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-sleep-heart")))))
        val selection = MetricSelectionState(enabledMetrics = setOf("sleep_total", "sleep_light", "sleep_bedtime", "sleep_wake", "avg_hr"))
        for (metadata in listOf(false, true)) {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
                includeMetadata = metadata, metricSelection = selection,
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data.filtered(selection, context), settings,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust, DailyAggregateExportIds("dense-sleep", "dense-sleep-session"))
            val result = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request)
            val native = Json.parseToJsonElement(com.healthmd.data.export.JsonExporter().export(
                request.data, request.customization, true, captureContext = context)).jsonObject.getValue("sleep").jsonObject
            assertThat(result.plan.items).hasSize(4)
            for (item in result.plan.items) {
                val text = item.content.decodeToString()
                if (item.relativePath.endsWith(".json")) {
                    val sleep = Json.parseToJsonElement(text).jsonObject.getValue("sleep").jsonObject
                    assertThat(sleep.getValue("sleepStages")).isEqualTo(native.getValue("sleepStages"))
                    assertThat(sleep.getValue("sleepSessions")).isEqualTo(native.getValue("sleepSessions"))
                    assertThat(sleep["totalDuration"]).isNull()
                    assertThat(sleep["lightSleep"]).isNull()
                    assertThat(sleep.getValue("bedtimeISO")).isEqualTo(native.getValue("bedtimeISO"))
                    assertThat(sleep.getValue("wakeTimeISO")).isEqualTo(native.getValue("wakeTimeISO"))
                } else if (item.relativePath.endsWith(".csv")) {
                    assertThat(text.lineSequence().count { it.contains(",Sleep Detail,Sleep Stage,") }).isEqualTo(2_000)
                    assertThat(text.lineSequence().count { it.contains(",Sleep Detail,Sleep Session,") }).isEqualTo(1)
                } else {
                    assertThat(text).contains("synthetic-stage-1999")
                    assertThat(text).contains("synthetic-parent")
                }
                System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { directory ->
                    val output = File(directory, "android-v6-dense-sleep-$metadata/${item.relativePath}")
                    val parentDirectory = checkNotNull(output.parentFile)
                    check(parentDirectory.mkdirs() || parentDirectory.isDirectory)
                    output.writeBytes(item.content)
                }
            }
        }
    }

    @Test
    fun composedSleepSourcesKeepOwnershipWhenSummaryFrontmatterIsHidden() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T01:00:00.123456789Z")
        val end = start.plusSeconds(3600)
        fun exact(value: Instant) = com.healthmd.domain.model.ExactSourceTimestamp.from(value, ZoneOffset.UTC)
        val stage = com.healthmd.domain.model.SleepStageEntry(start.atZone(context.zoneId).toLocalDateTime(),
            end.atZone(context.zoneId).toLocalDateTime(), "light", exact(start), exact(end))
        val session = com.healthmd.domain.model.SleepSessionEntry(stage.startTime, stage.endTime,
            exactStartTime = exact(start), exactEndTime = exact(end))
        val data = HealthData(LocalDate.of(2026, 11, 1), sleep = SleepData(stages = listOf(stage), sessions = listOf(session)))
        suspend fun plan(candidate: HealthData, enabled: Set<String>, disabled: List<String> = emptyList()): ExportArtifactPlan {
            val selection = MetricSelectionState(enabledMetrics = enabled)
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
                metricSelection = selection, executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
                formatCustomization = FormatCustomization(frontmatterConfig = com.healthmd.domain.model.FrontmatterConfiguration(
                    fields = disabled.map { com.healthmd.domain.model.CustomFrontmatterField(it, isEnabled = false) })))
            val request = FrozenDailyAggregateExportRequest.capture(candidate.filtered(selection, context), settings,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust, DailyAggregateExportIds("sleep-boundary", "sleep-boundary-session"))
            return HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request).plan
        }
        val owners = setOf("sleep_total", "sleep_light")
        for (disabled in listOf(listOf("sleep_light_hours"), listOf("sleep_total_hours", "sleep_in_bed_hours"))) {
            val result = plan(data, owners, disabled)
            assertThat(result.items).hasSize(4)
            val document = Json.parseToJsonElement(result.items.single { it.relativePath.endsWith(".json") }
                .content.decodeToString()).jsonObject
            assertThat(document.getValue("sleep").jsonObject.getValue("sleepStages").jsonArray).hasSize(1)
            assertThat(document.getValue("sleep").jsonObject.getValue("sleepSessions").jsonArray).hasSize(1)
            for (item in result.items.filter { it.relativePath.endsWith(".md") }) for (key in disabled) {
                assertThat(item.content.decodeToString()).doesNotContain("\n$key:")
            }
        }
        val reversed = data.copy(sleep = data.sleep.copy(stages = listOf(stage.copy(
            startTime = stage.endTime, endTime = stage.startTime, exactStartTime = exact(end), exactEndTime = exact(start)))))
        assertThat(runCatching { plan(reversed, owners) }.isFailure).isTrue()
        val zero = data.copy(sleep = data.sleep.copy(stages = listOf(stage.copy(endTime = stage.startTime, exactEndTime = exact(start)))))
        val zeroPlan = plan(zero, owners)
        val zeroSleep = Json.parseToJsonElement(zeroPlan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString())
            .jsonObject.getValue("sleep").jsonObject
        assertThat(zeroSleep.getValue("sleepStages").jsonArray.single().jsonObject.getValue("durationSeconds").jsonPrimitive.content.toDouble()).isEqualTo(0.0)

        assertThat(runCatching { plan(data.copy(date = data.date.minusDays(1)), owners) }.isFailure).isTrue()
        val steps = reversed.copy(activity = ActivityData(steps = 42))
        val onlySteps = plan(steps, setOf("steps"))
        assertThat(onlySteps.items).hasSize(4)
        for (item in onlySteps.items) {
            assertThat(item.content.decodeToString()).doesNotContain("sleepStages")
            assertThat(item.content.decodeToString()).doesNotContain("sleep_stage_details")
        }
    }

    @Test
    fun denseWakeDateQuantitySourcesRemainExportableAcrossEveryFormat() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val base = Instant.parse("2026-11-01T01:30:00.123456789Z")
        fun samples(value: Double, family: String) = (0 until 2_000).map { index ->
            val instant = base.plusSeconds(index.toLong())
            com.healthmd.domain.model.TimestampedSample(
                java.time.LocalDateTime.ofInstant(instant, context.zoneId), value,
                source = "synthetic", metadata = mapOf("synthetic" to "dense-quantity-$family-$index"),
                exactTime = com.healthmd.domain.model.ExactSourceTimestamp.from(instant, ZoneOffset.UTC),
                identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-quantity-$family-$index"))
        }
        val selection = MetricSelectionState(enabledMetrics = setOf("avg_hr", "hrv", "blood_oxygen", "blood_glucose", "respiratory_rate"))
        val data = HealthData(LocalDate.of(2026, 11, 1), heart = HeartData(samples = samples(Math.nextUp(72.125), "heart"), hrvSamples = samples(Math.nextUp(31.875), "hrv")),
            vitals = VitalsData(bloodOxygenSamples = samples(Math.nextUp(0.97125), "oxygen"), bloodGlucoseSamples = samples(Math.nextUp(101.875), "glucose"),
                respiratoryRateSamples = samples(Math.nextUp(16.125), "respiratory"))).filtered(selection, context)
        for (metadata in listOf(false, true)) {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
                includeMetadata = metadata, metricSelection = selection, executionSleepCaptureContext = context,
                executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data, settings,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust, DailyAggregateExportIds("dense-quantity", "dense-quantity-session"))
            val result = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request)
            val native = Json.parseToJsonElement(com.healthmd.data.export.JsonExporter().export(
                data, request.customization, true, captureContext = context)).jsonObject
            assertThat(result.plan.items).hasSize(4)
            for (item in result.plan.items) {
                val text = item.content.decodeToString()
                assertThat(text).contains("android-sleep-v6")
                val fixtureRoot = System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")
                if (!fixtureRoot.isNullOrBlank()) {
                    val output = File(fixtureRoot, "android-v6-dense-quantities-$metadata/${item.relativePath}")
                    val parent = checkNotNull(output.parentFile)
                    check(parent.mkdirs() || parent.isDirectory)
                    output.writeBytes(item.content)
                }
                if (item.relativePath.endsWith(".json")) {
                    val root = Json.parseToJsonElement(text).jsonObject
                    val source = root.getValue("heart").jsonObject.getValue("heartRateSamples").jsonArray
                    assertThat(source).isEqualTo(native.getValue("heart").jsonObject.getValue("heartRateSamples"))
                    assertThat(source).hasSize(2_000)
                    assertThat(source.last().jsonObject.getValue("value").jsonPrimitive.content.toDouble()).isEqualTo(Math.nextUp(72.125))
                    assertThat(source.last().jsonObject.getValue("metadata").jsonObject.getValue("synthetic").jsonPrimitive.content).isEqualTo("dense-quantity-heart-1999")
                    assertThat(root.getValue("heart").jsonObject["averageHeartRate"]).isNull()
                    for ((category, field, value) in listOf(Triple("heart", "hrvSamples", Math.nextUp(31.875)),
                        Triple("vitals", "bloodOxygenSamples", Math.nextUp(0.97125)), Triple("vitals", "bloodGlucoseSamples", Math.nextUp(101.875)),
                        Triple("vitals", "respiratoryRateSamples", Math.nextUp(16.125)))) {
                        val values = root.getValue(category).jsonObject.getValue(field).jsonArray
                        assertThat(values).isEqualTo(native.getValue(category).jsonObject.getValue(field))
                        assertThat(values).hasSize(2_000)
                        assertThat(values.last().jsonObject.getValue("value").jsonPrimitive.content.toDouble()).isEqualTo(value)
                    }
                } else if (item.relativePath.endsWith(".csv")) {
                    assertThat(text.lineSequence().count { it.contains(",Native Detail,Quantity Sample,") }).isEqualTo(10_000)
                } else if (item.relativePath.endsWith("-bases.md")) {
                    assertThat(text).contains("native_quantity_details:")
                    assertThat(text).contains("synthetic-quantity-heart-1999")
                } else {
                    assertThat(text.lineSequence().count { it.startsWith("| 2026-") }).isEqualTo(10_000)
                }
            }
        }
    }

    @Test
    fun nativeQuantityCompositionRejectsInvalidSourcesAndKeepsHiddenFrontmatterRecords() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val instant = Instant.parse("2026-11-01T01:30:00.123456789Z")
        fun sample(value: Double) = com.healthmd.domain.model.TimestampedSample(
            instant.atZone(context.zoneId).toLocalDateTime(), value,
            exactTime = com.healthmd.domain.model.ExactSourceTimestamp.from(instant, ZoneOffset.UTC))
        suspend fun plan(data: HealthData, selection: Set<String>, disabled: List<String> = emptyList()): ExportArtifactPlan {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
                metricSelection = MetricSelectionState(enabledMetrics = selection),
                formatCustomization = FormatCustomization(frontmatterConfig = com.healthmd.domain.model.FrontmatterConfiguration(
                    fields = disabled.map { com.healthmd.domain.model.CustomFrontmatterField(it, isEnabled = false) })),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data, settings, AndroidExportProfile.android_sleep_v6,
                ExportEngineMode.rust, DailyAggregateExportIds("quantity-boundary", "quantity-boundary-session"))
            return HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request).plan
        }
        val date = LocalDate.of(2026, 11, 1)
        for (value in listOf(Double.NaN, Double.POSITIVE_INFINITY, -0.01, 1.01)) {
            val data = HealthData(date, vitals = VitalsData(bloodOxygenSamples = listOf(sample(value))))
            assertThat(runCatching { plan(data, setOf("blood_oxygen")) }.isFailure).isTrue()
        }
        val heart = HealthData(date, heart = HeartData(samples = listOf(sample(72.125))))
        val hidden = listOf("average_heart_rate", "heart_rate_min", "heart_rate_max")
        val hiddenPlan = plan(heart, setOf("avg_hr"), hidden)
        assertThat(hiddenPlan.items).hasSize(4)
        val document = Json.parseToJsonElement(hiddenPlan.items.single { it.relativePath.endsWith(".json") }
            .content.decodeToString()).jsonObject
        assertThat(document.getValue("heart").jsonObject.getValue("heartRateSamples").jsonArray.single().jsonObject
            .getValue("value").jsonPrimitive.content.toDouble()).isEqualTo(72.125)
        for (item in hiddenPlan.items.filter { it.relativePath.endsWith(".md") }) for (key in hidden) {
            assertThat(item.content.decodeToString()).doesNotContain("\n$key:")
        }
        val unselected = heart.copy(activity = ActivityData(steps = 42),
            vitals = VitalsData(bloodOxygenSamples = listOf(sample(Double.NaN))))
        val selectedPlan = plan(unselected, setOf("steps"))
        assertThat(selectedPlan.items).hasSize(4)
        for (item in selectedPlan.items) {
            val text = item.content.decodeToString()
            assertThat(text).doesNotContain("heartRateSamples")
            assertThat(text).doesNotContain("bloodOxygenSamples")
            assertThat(text).doesNotContain("native_quantity_details")
        }
    }

    @Test
    fun nativeMindfulnessSessionsReachEverySuccessorFormatWithExactClocks() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = Instant.parse("2026-11-01T06:30:00.987654321Z")
        val metadata = mutableMapOf("synthetic" to "mind, source")
        val sessions = mutableListOf(com.healthmd.domain.model.MindfulnessSessionEntry(
            startTime = start.atZone(context.zoneId).toLocalDateTime(),
            endTime = end.atZone(context.zoneId).toLocalDateTime(),
            sessionType = "meditation", title = "Calm|alert", notes = "quoted \"note\" <test>",
            source = "synthetic-mindfulness",
            exactStartTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start, ZoneOffset.of("-04:00")),
            exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end, ZoneOffset.of("-05:00")),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-mindfulness-session"),
            metadata = metadata))
        val data = HealthData(date = LocalDate.of(2026, 11, 1),
            mindfulness = com.healthmd.domain.model.MindfulnessData(sessions = sessions))
        for (includeMetadata in listOf(false, true)) {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
                includeMetadata = includeMetadata, metricSelection = MetricSelectionState(enabledMetrics = setOf("mindful_minutes")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data, settings,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust, DailyAggregateExportIds("mindful-request", "mindful-session"))
            if (includeMetadata) { metadata["synthetic"] = "mutated"; sessions.clear() }
            val result = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request)
            assertThat(result.plan.items).hasSize(4)
            for (item in result.plan.items) {
                val text = item.content.decodeToString()
                assertThat(text).contains("2026-11-01T05:30:00.123456789Z")
                assertThat(text).contains("2026-11-01T06:30:00.987654321Z")
                assertThat(text).contains("synthetic-mindfulness-session")
                assertThat(text).contains("mind, source")
                assertThat(text).doesNotContain("mutated")
                if (item.relativePath.endsWith(".csv")) assertThat(text).contains(",Native Detail,Mindfulness Record,")
                if (item.relativePath.endsWith("-bases.md")) assertThat(text).contains("native_mindfulness_details:")
                else if (item.relativePath.endsWith(".md")) {
                    assertThat(text).contains("Mindfulness Session Details")
                    val row = text.lineSequence().single { it.startsWith("| `{") }
                    assertThat(row).endsWith("}` |")
                    val record = kotlinx.serialization.json.Json.parseToJsonElement(row.removePrefix("| `").removeSuffix("` |")).jsonObject
                    val sample = record.getValue("sample").jsonObject
                    assertThat(sample.getValue("notes").jsonPrimitive.content).isEqualTo(request.data.mindfulness.sessions.single().notes)
                }
                System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { directory ->
                    val output = File(directory, "android-v6-mindfulness-$includeMetadata/${item.relativePath}")
                    val parent = checkNotNull(output.parentFile)
                    check(parent.mkdirs() || parent.isDirectory)
                    output.writeBytes(item.content)
                }
            }
            if (includeMetadata) { metadata["synthetic"] = "mind, source"; sessions.add(request.data.mindfulness.sessions.single()) }
        }
    }

    @Test
    fun freshWakeDateScheduleCapturesProductionPinAndRendersAfterPreferenceChange() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("Asia/Kathmandu"), SleepDayAttribution.MORNING_ENDS)
        val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(),
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
            metricSelection = MetricSelectionState(enabledMetrics = setOf("steps")))
        val pinPlanner = ExportEnginePinPlanner()
        val pin = requireNotNull(pinPlanner.forScheduledExport(settings,
            com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER, context.zoneId))
        assertThat(pin.profile).isEqualTo(AndroidExportProfile.android_sleep_v6)
        assertThat(pin.engine).isEqualTo(ExportEngineMode.rust)
        val snapshot = AndroidExportSettingsSnapshot.capture(settings, pin, context.zoneId)
        val encoded = AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot)
        val current = ExportSettings(executionSleepCaptureContext = AndroidCaptureContext(
            ZoneId.of("Europe/Berlin"), SleepDayAttribution.NIGHT_BEGINS))
        val restored = requireNotNull(com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory(
            pinPlanner, mockk()).restoreForRun(com.healthmd.domain.model.ExportProfile(
                id = "production-wake-schedule", name = "Synthetic schedule", settingsSnapshotJson = encoded,
                target = com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER,
                createdAtEpochMillis = 0L, updatedAtEpochMillis = 0L), current, 2))
        assertThat(pinPlanner.persistedPinAppliesToScheduledExport(restored,
            com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER, pin)).isTrue()
        assertThat(pinPlanner.persistedPinAppliesToScheduledExport(current,
            com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER, pin)).isFalse()
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { error("No historical rendering") },
            policyResolver = LocalExportEnginePolicyResolver { error("No mutable policy during resume") })
        val result = planner.plan(HealthData(date = LocalDate.of(2026, 11, 1),
            activity = ActivityData(steps = 17)), restored)
        assertThat(result).isInstanceOf(LocalDailyAggregatePlanningResult.Planned::class.java)
        val plan = (result as LocalDailyAggregatePlanningResult.Planned).plan
        assertThat(plan.items).hasSize(4)
        for (item in plan.items) {
            val text = item.content.decodeToString()
            assertThat(text).contains("morning_ends")
            assertThat(text).contains("Asia/Kathmandu")
            assertThat(text).contains("android-sleep-v6")
            assertThat(text).doesNotContain("Europe/Berlin")
        }
        assertThat(pinPlanner.forScheduledExport(settings.copy(executionSleepCaptureContext =
            context.copy(exportProfileID = null)), com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER,
            context.zoneId)).isNull()
        assertThat(pinPlanner.forDirectGeneratedFiles(settings, ZoneId.of("Europe/Berlin"))).isNull()
        val directPin = pinPlanner.forDirectGeneratedFiles(settings, context.zoneId)
        assertThat(directPin).isEqualTo(pin)
        com.healthmd.direct.requireDirectGeneratedFilesAuthority(context, directPin)
        for (invalid in listOf(null, directPin!!.copy(ianaTimeZone = "Europe/Berlin"),
            directPin.copy(renderInputVersion = 1u))) {
            assertThat(runCatching { com.healthmd.direct.requireDirectGeneratedFilesAuthority(context, invalid) }
                .exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
        }
    }

    @Test
    fun productionGatewayFreezesCaptureBeforeCallbacksAndKeepsBothPreferenceDirections() = runTest {
        val first = LocalDate.of(2026, 11, 1)
        for (initial in SleepDayAttribution.entries) {
            var stored = initial
            var resolutions = 0
            var accepted: AndroidCaptureContext? = null
            val enabled = mutableSetOf("sleep_total")
            val observed = mutableListOf<SleepDayAttribution>()
            val repository = mockk<com.healthmd.domain.repository.HealthRepository>()
            io.mockk.every { repository.isBeforeFirstUnlock() } returns false
            coEvery { repository.resolveCaptureContext(any(), any()) } coAnswers {
                resolutions++
                AndroidCaptureContext(arg<ZoneId>(0), stored).also { accepted = it }
            }
            coEvery { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } coAnswers {
                val context = checkNotNull(accepted)
                assertThat(arg<ZoneId>(3)).isEqualTo(context.zoneId)
                val policy = arg<com.healthmd.domain.model.SleepDayAttributionOverride>(5)
                assertThat(policy).isEqualTo(context.explicitSleepDayAttributionOverride)
                observed += context.sleepDayAttribution
                val date = arg<List<LocalDate>>(0).single()
                val start = date.atTime(1, 0, 0, 123456789).atZone(context.zoneId).toInstant()
                val end = start.plusSeconds(3600)
                fun exact(value: Instant) = com.healthmd.domain.model.ExactSourceTimestamp.from(value, context.zoneId.rules.getOffset(value))
                val stage = com.healthmd.domain.model.SleepStageEntry(start.atZone(context.zoneId).toLocalDateTime(),
                    end.atZone(context.zoneId).toLocalDateTime(), "sleeping", exact(start), exact(end),
                    com.healthmd.domain.model.ExactSourceIdentity(nativeId = "gateway-stage-$date"))
                val parent = com.healthmd.domain.model.SleepSessionEntry(stage.startTime, stage.endTime,
                    exactStartTime = exact(start), exactEndTime = exact(end))
                listOf(HealthData(date, sleep = SleepData(totalDuration = 60.minutes, stages = listOf(stage), sessions = listOf(parent),
                    sessionStart = stage.startTime, sessionEnd = stage.endTime)))
            }
            val client = mockk<com.healthmd.data.export.AgentDataGatewayUploadClient>()
            val runner = com.healthmd.data.export.AgentDataGatewayExportRunner(repository, client, com.healthmd.data.export.JsonExporter(),
                com.healthmd.data.export.MarkdownExporter(), com.healthmd.data.export.CsvExporter(), com.healthmd.data.export.ObsidianBasesExporter())
            val settings = ExportSettings(exportTarget = com.healthmd.domain.model.ExportTarget.AGENT_DATA_GATEWAY,
                exportFormats = setOf(ExportFormat.JSON), includeGranularData = true,
                metricSelection = MetricSelectionState(enabledMetrics = enabled))
            val preview = runner.previewDates(listOf(first, first.plusDays(1)), settings, onProgress = { _, _, _ ->
                stored = if (initial == SleepDayAttribution.MORNING_ENDS) SleepDayAttribution.NIGHT_BEGINS else SleepDayAttribution.MORNING_ENDS
                enabled.clear()
            })
            assertThat(resolutions).isEqualTo(1)
            assertThat(observed).containsExactly(initial, initial)
            assertThat(preview.previewedDateCount).isEqualTo(2)
            for (day in preview.days) {
                val text = day.files.single().content
                if (initial == SleepDayAttribution.MORNING_ENDS) {
                    assertThat(text).contains("android-sleep-v6")
                    assertThat(text).contains("gateway-stage-${day.date}")
                    assertThat(text).contains(checkNotNull(accepted).zoneId.id)
                } else {
                    assertThat(text).doesNotContain("morning_ends")
                    assertThat(text).doesNotContain("gateway-stage-")
                }
            }
            if (initial == SleepDayAttribution.MORNING_ENDS) {
                val target = com.healthmd.domain.model.ExportTarget.AGENT_DATA_GATEWAY
                val pinnedSettings = settings.copy(executionSleepCaptureContext = accepted, executionSleepCaptureAuthorityIsFrozen = true,
                    scheduledExportTarget = target, agentDataGatewayUrl = "https://gateway.example.invalid",
                    metricSelection = MetricSelectionState(enabledMetrics = setOf("sleep_total")))
                val planner = ExportEnginePinPlanner()
                val pin = checkNotNull(planner.forScheduledExport(pinnedSettings, target, checkNotNull(accepted).zoneId))
                val snapshot = AndroidExportSettingsSnapshot.capture(pinnedSettings, pin, checkNotNull(accepted).zoneId)
                val recovered = AndroidExportSettingsSnapshotCodec.decode(AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot))
                    .restoreOnto(pinnedSettings.copy(executionSleepCaptureContext = AndroidCaptureContext(ZoneId.of("Europe/Berlin"), SleepDayAttribution.NIGHT_BEGINS)))
                assertThat(recovered.executionSleepCaptureContext).isEqualTo(accepted)
                assertThat(planner.persistedPinAppliesToScheduledExport(recovered, target, pin)).isTrue()
            }
            io.mockk.coVerify(exactly = 0) { repository.fetchHealthData(any()) }
            io.mockk.coVerify(exactly = 0) { client.upload(any(), any(), any()) }
        }
    }

    @Test
    fun productionGatewayDoesNotRecaptureEmptyRangesOrAdmitMissingFrozenAuthority() = runTest {
        val date = LocalDate.of(2026, 11, 1)
        val repository = mockk<com.healthmd.domain.repository.HealthRepository>()
        io.mockk.every { repository.isBeforeFirstUnlock() } returns false
        coEvery { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } returns emptyList()
        val client = mockk<com.healthmd.data.export.AgentDataGatewayUploadClient>()
        val runner = com.healthmd.data.export.AgentDataGatewayExportRunner(repository, client, com.healthmd.data.export.JsonExporter(),
            com.healthmd.data.export.MarkdownExporter(), com.healthmd.data.export.CsvExporter(), com.healthmd.data.export.ObsidianBasesExporter())
        val settings = ExportSettings(exportTarget = com.healthmd.domain.model.ExportTarget.AGENT_DATA_GATEWAY,
            exportFormats = setOf(ExportFormat.JSON), executionSleepCaptureContext = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS),
            executionSleepCaptureAuthorityIsFrozen = true)
        val preview = runner.previewDates(listOf(date), settings)
        assertThat(preview.previewedDateCount).isEqualTo(0)
        assertThat(preview.days).isEmpty()
        val missing = runner.previewDates(listOf(date), settings.copy(executionSleepCaptureContext = null))
        assertThat(missing.days.single().failureReason).isEqualTo(com.healthmd.domain.model.ExportFailureReason.UNKNOWN)
        val draft = runner.previewDates(listOf(date), settings.copy(executionSleepCaptureContext = settings.executionSleepCaptureContext!!.copy(exportProfileID = null)))
        assertThat(draft.days.single().failureReason).isEqualTo(com.healthmd.domain.model.ExportFailureReason.UNKNOWN)
        io.mockk.coVerify(exactly = 1) { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) }
        io.mockk.coVerify(exactly = 0) { repository.resolveCaptureContext(any(), any()) }
        io.mockk.coVerify(exactly = 0) { repository.fetchHealthData(any()) }
        io.mockk.coVerify(exactly = 0) { client.upload(any(), any(), any()) }
    }

    @Test
    fun productionGatewayKeepsConcurrentCapturedContextsSeparateAndRejectsWithoutDowngrading() = runTest {
        val date = LocalDate.of(2026, 11, 1)
        val morning = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val night = AndroidCaptureContext(ZoneId.of("Europe/Berlin"), SleepDayAttribution.NIGHT_BEGINS)
        val contexts = mapOf(date to morning, date.plusDays(1) to night)
        val repository = mockk<com.healthmd.domain.repository.HealthRepository>()
        io.mockk.every { repository.isBeforeFirstUnlock() } returns false
        var arrivals = 0
        val barrier = kotlinx.coroutines.CompletableDeferred<Unit>()
        coEvery { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } coAnswers {
            val owner = arg<List<LocalDate>>(0).single()
            val expected = contexts.getValue(owner)
            assertThat(arg<ZoneId>(3)).isEqualTo(expected.zoneId)
            assertThat(arg<com.healthmd.domain.model.SleepDayAttributionOverride>(5)).isEqualTo(expected.explicitSleepDayAttributionOverride)
            arrivals++
            if (arrivals == 2) barrier.complete(Unit)
            barrier.await()
            listOf(HealthData(owner, activity = ActivityData(steps = 42)))
        }
        val client = mockk<com.healthmd.data.export.AgentDataGatewayUploadClient>()
        val runner = com.healthmd.data.export.AgentDataGatewayExportRunner(repository, client, com.healthmd.data.export.JsonExporter(),
            com.healthmd.data.export.MarkdownExporter(), com.healthmd.data.export.CsvExporter(), com.healthmd.data.export.ObsidianBasesExporter())
        fun settings(context: AndroidCaptureContext) = ExportSettings(exportTarget = com.healthmd.domain.model.ExportTarget.AGENT_DATA_GATEWAY,
            exportFormats = setOf(ExportFormat.JSON), agentDataGatewayUrl = "https://gateway.example.invalid",
            metricSelection = MetricSelectionState(enabledMetrics = setOf("steps")),
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
        val a = async { runner.previewDates(listOf(date), settings(morning)) }
        val b = async { runner.previewDates(listOf(date.plusDays(1)), settings(night)) }
        val previews = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.Default) {
            kotlinx.coroutines.withTimeout(10_000) { listOf(a.await(), b.await()) }
        }
        assertThat(previews.map { it.previewedDateCount }).containsExactly(1, 1)
        val expected = previews.first().days.single().files.single().content.encodeToByteArray()
        coEvery { client.upload(any(), any(), any()) } coAnswers {
            val bytes = arg<ByteArray>(2)
            val manifest = arg<com.healthmd.data.export.AgentDataIngestManifest>(1)
            assertThat(bytes).isEqualTo(expected)
            assertThat(manifest.artifactSchemaVersion).isEqualTo(6)
            assertThat(manifest.byteCount).isEqualTo(bytes.size.toLong())
            assertThat(manifest.sha256).isEqualTo(sha256Hex(bytes))
            System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { directory ->
                val output = File(directory, "android-v6-gateway")
                check(output.mkdirs() || output.isDirectory)
                File(output, "artifact.json").writeBytes(bytes)
                File(output, "manifest.json").writeText(manifest.encodeJsonLine())
            }
            com.healthmd.data.export.AgentDataUploadReceipt.Rejected(com.healthmd.domain.model.AgentDataRejectionCodes.MANIFEST_INCOMPLETE, 200)
        }
        val result = runner.exportDates(listOf(date), settings(morning))
        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.agentDataOutcomes.single().rejectionCode).isEqualTo(com.healthmd.domain.model.AgentDataRejectionCodes.MANIFEST_INCOMPLETE)
        io.mockk.coVerify(exactly = 1) { client.upload(any(), any(), any()) }
        io.mockk.coVerify(exactly = 0) { repository.resolveCaptureContext(any(), any()) }
        io.mockk.coVerify(exactly = 0) { repository.fetchHealthData(any()) }
        io.mockk.every { repository.isBeforeFirstUnlock() } returns true
        val locked = runner.previewDates(listOf(date), settings(morning).copy(executionSleepCaptureContext = null))
        assertThat(locked.days.single().failureReason).isEqualTo(com.healthmd.domain.model.ExportFailureReason.DEVICE_LOCKED)
        io.mockk.coVerify(exactly = 3) { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) }
    }

    @Test
    fun successorApiAndDirectPreserveSelectedSleepingStageThroughProductionPlanners() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 11, 1)
        val start = Instant.parse("2026-11-01T05:30:00.123456789Z"); val end = Instant.parse("2026-11-01T06:30:00.987654321Z")
        fun exact(value: Instant) = com.healthmd.domain.model.ExactSourceTimestamp.from(value, context.zoneId.rules.getOffset(value))
        val stage = com.healthmd.domain.model.SleepStageEntry(start.atZone(context.zoneId).toLocalDateTime(), end.atZone(context.zoneId).toLocalDateTime(),
            "sleeping", exact(start), exact(end), com.healthmd.domain.model.ExactSourceIdentity(nativeId = "api-sleeping-stage"))
        val stages = mutableListOf(stage)
        val parent = com.healthmd.domain.model.SleepSessionEntry(stage.startTime, stage.endTime, exactStartTime = exact(start), exactEndTime = exact(end),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "api-sleeping-parent"))
        val selection = MetricSelectionState(enabledMetrics = setOf("sleep_total"))
        val data = HealthData(date, sleep = SleepData(totalDuration = 60.minutes, stages = stages, sessions = listOf(parent),
            sessionStart = stage.startTime, sessionEnd = stage.endTime))
        val settings = ExportSettings(includeGranularData = true, metricSelection = selection,
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
        val request = FrozenAPIExportRequest.capture(listOf(date), listOf(data), emptyList(), settings,
            ExportEngineMode.rust, APIExportIds("sleeping-api", "sleeping-api-session"), context.zoneId.id, end.plusSeconds(1))
        assertThat(request.records.single().sleep.stages).containsExactly(stage)
        stages.clear()
        val result = HealthMdRustAPIExportPlanner().plan(request)
        validateAPIPlan(result.plan, request)
        val native = Json.parseToJsonElement(com.healthmd.data.export.JsonExporter().export(request.records.single(),
            request.settings.formatCustomization, true, captureContext = context)).jsonObject.getValue("sleep").jsonObject
        val record = Json.parseToJsonElement(result.plan.items.single().content.decodeToString()).jsonObject.getValue("records").jsonArray.single().jsonObject
        val sleep = record.getValue("sleep").jsonObject
        assertThat(sleep.getValue("sleepStages")).isEqualTo(native.getValue("sleepStages"))
        assertThat(sleep.getValue("sleepSessions")).isEqualTo(native.getValue("sleepSessions"))
        assertThat(sleep.getValue("bedtimeISO")).isEqualTo(native.getValue("bedtimeISO"))
        assertThat(sleep.getValue("wakeTimeISO")).isEqualTo(native.getValue("wakeTimeISO"))
        assertThat(record.getValue("summary").jsonObject.getValue("sleep").jsonObject["sleep_light_hours"]).isNull()
        val repository = mockk<com.healthmd.domain.repository.HealthRepository>()
        coEvery { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } coAnswers {
            assertThat(arg<ZoneId>(3)).isEqualTo(context.zoneId)
            assertThat(arg<com.healthmd.domain.model.SleepDayAttributionOverride>(5)).isEqualTo(context.explicitSleepDayAttributionOverride)
            request.records
        }
        val producer = com.healthmd.direct.DirectGeneratedFilesProducer(repository,
            com.healthmd.data.export.MarkdownExporter(), com.healthmd.data.export.JsonExporter(),
            com.healthmd.data.export.CsvExporter(), com.healthmd.data.export.ObsidianBasesExporter())
        val directory = java.nio.file.Files.createTempDirectory("morning-sleeping-direct-").toFile()
        try {
            val directSettings = settings.copy(exportFormats = ExportFormat.entries.toSet(),
                executionEnginePin = result.pin, executionEngineAuthorityIsFrozen = true)
            val files = producer.produce(directory, listOf(date), directSettings, context)
            assertThat(files).hasSize(4)
            for (file in files) assertThat(file.file.readText()).contains("api-sleeping-stage")
            val directSleep = Json.parseToJsonElement(files.single { it.format == com.healthmd.direct.protocol.ArtifactFormat.JSON }.file.readText())
                .jsonObject.getValue("sleep").jsonObject
            assertThat(directSleep.getValue("sleepStages")).isEqualTo(native.getValue("sleepStages"))
            assertThat(directSleep.getValue("sleepSessions")).isEqualTo(native.getValue("sleepSessions"))
        } finally { directory.deleteRecursively() }
    }

    @Test
    fun successorApiUsesProductionNativeRecordsAndKeepsFailedBatchAuthority() = runTest {
        val zone = ZoneId.of("America/New_York")
        val context = AndroidCaptureContext(zone, SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 11, 1)
        val start = Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = Instant.parse("2026-11-01T06:30:00.123456789Z")
        val metadata = mutableMapOf("synthetic" to "original source")
        val sessions = mutableListOf(com.healthmd.domain.model.SleepSessionEntry(
            startTime = start.atZone(zone).toLocalDateTime(), endTime = end.atZone(zone).toLocalDateTime(),
            exactStartTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start, ZoneOffset.of("-04:00")),
            exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end, ZoneOffset.of("-05:00")),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "api-sleep-source"), metadata = metadata))
        val workout = com.healthmd.domain.model.WorkoutData(
            workoutType = com.healthmd.domain.model.WorkoutType.RUNNING, id = "api-workout-source",
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "api-workout-source"),
            startTime = start.atZone(zone).toLocalDateTime(), endTime = end.atZone(zone).toLocalDateTime(),
            duration = 60.minutes, metadata = metadata,
            exactStartTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start, ZoneOffset.of("-04:00")),
            exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end, ZoneOffset.of("-05:00")))
        val data = HealthData(date, activity = ActivityData(steps = 17), workouts = listOf(workout),
            sleep = SleepData(totalDuration = 60.minutes, sessions = sessions))
        val settings = ExportSettings(includeGranularData = true,
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
            formatCustomization = FormatCustomization.analyticalDefault().copy(unitPreference = UnitPreference.IMPERIAL),
            metricSelection = MetricSelectionState(enabledMetrics = setOf("sleep_total", "steps", "workouts")))
        val request = FrozenAPIExportRequest.capture(listOf(date, date.plusDays(1)), listOf(data),
            listOf(com.healthmd.domain.model.FailedDateDetail(date.plusDays(1), com.healthmd.domain.model.ExportFailureReason.NO_HEALTH_DATA)),
            settings, ExportEngineMode.rust, APIExportIds("successor-api-request", "successor-api-session"), zone.id,
            Instant.parse("2026-11-03T12:00:00Z"), maxDaysPerBatch = 1)
        sessions.clear(); metadata["synthetic"] = "changed after acceptance"
        val result = HealthMdRustAPIExportPlanner().plan(request)
        validateAPIPlan(result.plan, request)
        assertThat(result.pin.profile).isEqualTo(AndroidExportProfile.android_sleep_v6)
        assertThat(result.pin.registryVersion).isEqualTo(2u)
        assertThat(result.plan.items).hasSize(2)
        for (item in result.plan.items) {
            val root = Json.parseToJsonElement(item.content.decodeToString()).jsonObject
            assertThat(root.getValue("schema_version").jsonPrimitive.content).isEqualTo("2")
            assertThat(root.getValue("daily_record_schema_version").jsonPrimitive.content).isEqualTo("6")
            assertThat(root.getValue("daily_record_schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
            assertThat(root.getValue("daily_record_time_context").jsonObject.getValue("calendar_timezone").jsonPrimitive.content).isEqualTo(zone.id)
            assertThat(item.content.decodeToString()).doesNotContain("changed after acceptance")
        }
        val record = Json.parseToJsonElement(result.plan.items.first().content.decodeToString())
            .jsonObject.getValue("records").jsonArray.single().jsonObject
        assertThat(record.getValue("summary").jsonObject.getValue("sleep").jsonObject.getValue("sleep_total_hours").jsonPrimitive.content).isEqualTo("1.0")
        assertThat(record.getValue("workouts").jsonArray.single().jsonObject.getValue("identity").jsonObject.getValue("nativeId").jsonPrimitive.content).isEqualTo("api-workout-source")
        assertThat(record.getValue("summary").jsonObject.getValue("workouts").jsonObject).isNotEmpty()
        assertThat(record.getValue("units").jsonObject.getValue("workout_count").jsonPrimitive.content).isEqualTo("count")
        assertThat(record.getValue("units").jsonObject.getValue("workout_minutes").jsonPrimitive.content).isEqualTo("minute")
        assertThat(record.getValue("sleep").jsonObject.getValue("totalDuration").jsonPrimitive.content.toDouble()).isEqualTo(3600.0)
        assertThat(result.plan.items.first().content.decodeToString()).contains("api-sleep-source")
        assertThat(result.plan.items.first().content.decodeToString()).contains(start.toString())
        assertThat(result.plan.items.last().content.decodeToString()).doesNotContain("api-sleep-source")
        val sparse = FrozenAPIExportRequest.capture(listOf(date, date.plusDays(3)), request.records,
            listOf(request.failedDateDetails.single().copy(date = date.plusDays(3))), settings,
            ExportEngineMode.rust, APIExportIds("sparse-api", "sparse-session"), zone.id, request.exportedAt)
        val sparseResult = HealthMdRustAPIExportPlanner().plan(sparse)
        validateAPIPlan(sparseResult.plan, sparse)
        assertThat(sparseResult.plan.items.map { it.relativePath }).containsExactly(
            "api/sparse-api-0000.json", "api/sparse-api-0001.json").inOrder()
        val scopes = sparseResult.plan.items.map { Json.parseToJsonElement(it.content.decodeToString())
            .jsonObject.getValue("date_range").jsonObject }
        assertThat(scopes.first().getValue("start").jsonPrimitive.content).isEqualTo(date.toString())
        assertThat(scopes.first().getValue("end").jsonPrimitive.content).isEqualTo(date.toString())
        assertThat(scopes.last().getValue("start").jsonPrimitive.content).isEqualTo(date.plusDays(3).toString())
        assertThat(scopes.last().getValue("end").jsonPrimitive.content).isEqualTo(date.plusDays(3).toString())
        val failedOnly = FrozenAPIExportRequest.capture(listOf(date.plusDays(1)), emptyList(),
            request.failedDateDetails, settings, ExportEngineMode.rust, APIExportIds("failure-api", "failure-session"),
            zone.id, request.exportedAt)
        val failedResult = HealthMdRustAPIExportPlanner().plan(failedOnly)
        validateAPIPlan(failedResult.plan, failedOnly)
        val failedEnvelope = Json.parseToJsonElement(failedResult.plan.items.single().content.decodeToString()).jsonObject
        assertThat(failedEnvelope.getValue("records").jsonArray).isEmpty()
        assertThat(failedEnvelope.getValue("daily_record_schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
        assertThat(failedEnvelope.getValue("daily_record_time_context").jsonObject.getValue("sleep_day_attribution").jsonPrimitive.content).isEqualTo("morning_ends")
    }

    @Before
    fun useExplicitTaskOwnedHostCore() {
        val library = System.getenv("HEALTHMD_HOST_CORE_LIBRARY")
        assumeTrue("Host-core QA requires an explicit freshly built library", !library.isNullOrBlank())
        require(File(checkNotNull(library)).isFile) { "Host core library is unavailable" }
        System.setProperty("uniffi.component.healthmd_core_uniffi.libraryOverride", library)
    }

    @Test
    fun acceptedWorkoutSourcesRemainFixedWhenCallerCollectionsChange() = runTest {
        val zone = ZoneId.of("America/New_York")
        val context = AndroidCaptureContext(zone, SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = Instant.parse("2026-11-01T06:30:00.987654321Z")
        val localStart = start.atZone(zone).toLocalDateTime()
        val localEnd = end.atZone(zone).toLocalDateTime()
        val exactStart = com.healthmd.domain.model.ExactSourceTimestamp.from(start, ZoneOffset.of("-04:00"))
        val exactEnd = com.healthmd.domain.model.ExactSourceTimestamp.from(end, ZoneOffset.of("-05:00"))
        val mutations = listOf("control", "workouts", "metadata", "laps", "segments", "splits", "route",
            "series", "sample-metadata", "sample-context", "correlation-map", "correlation-ids")
        val changed = mutableListOf<String>()
        for (granular in listOf(false, true)) for (mutation in mutations) {
            val metadata = mutableMapOf("synthetic" to "accepted workout")
            val sampleMetadata = mutableMapOf("synthetic" to "accepted sample")
            val sampleContext = mutableMapOf("measurement" to "accepted context")
            val series = mutableListOf(com.healthmd.domain.model.TimestampedSample(localStart, 160.125,
                metadata = sampleMetadata, context = sampleContext, exactTime = exactStart))
            val laps = mutableListOf(com.healthmd.domain.model.WorkoutLapData(localStart, localEnd,
                length = 1000.125, exactStartTime = exactStart, exactEndTime = exactEnd))
            val segments = mutableListOf(com.healthmd.domain.model.WorkoutSegmentData(localStart, localEnd,
                type = "running", exactStartTime = exactStart, exactEndTime = exactEnd))
            val splits = mutableListOf(com.healthmd.domain.model.WorkoutSplitData(1, localStart, localEnd,
                duration = kotlin.time.Duration.parse("3600.864197532s"), distance = 1000.125,
                exactStartTime = exactStart, exactEndTime = exactEnd))
            val route = mutableListOf(com.healthmd.domain.model.WorkoutRoutePointData(localStart, 0.0, 0.0,
                exactTime = exactStart))
            val correlatedIds = mutableListOf("accepted-correlated-source")
            val correlations = mutableMapOf<String, List<String>>("heart_rate" to correlatedIds)
            val workouts = mutableListOf(com.healthmd.domain.model.WorkoutData(
                workoutType = com.healthmd.domain.model.WorkoutType.RUNNING, startTime = localStart, endTime = localEnd,
                duration = kotlin.time.Duration.parse("1800.5s"), averageHeartRate = 160.125,
                metadata = metadata, laps = laps, segments = segments, splits = splits, route = route,
                routeAccess = com.healthmd.domain.model.WorkoutRouteAccess.DATA,
                heartRateSamples = series, speedSamples = series, cyclingCadenceSamples = series,
                stepsCadenceSamples = series, powerSamples = series, elevationSamples = series,
                exactStartTime = exactStart, exactEndTime = exactEnd, correlatedSourceIds = correlations))
            val data = HealthData(LocalDate.of(2026, 11, 1), workouts = workouts, heart = HeartData(samples = series))
            val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(
                exportFormats = ExportFormat.entries.toSet(), includeGranularData = granular,
                metricSelection = MetricSelectionState(enabledMetrics = setOf("workouts", "avg_hr")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true),
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("accepted-workout-$granular-$mutation", "accepted-workout-session-$granular-$mutation"))
            val planner = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("no ambient clock") })
            val expectedData = Json.encodeToJsonElement(HealthData.serializer(), request.data)
            val expected = planner.plan(request).plan.items.associate { it.relativePath to it.content.decodeToString() }
            when (mutation) {
                "workouts" -> workouts.clear()
                "metadata" -> metadata["synthetic"] = "changed after acceptance"
                "laps" -> laps.clear()
                "segments" -> segments.clear()
                "splits" -> splits.clear()
                "route" -> route.clear()
                "series" -> series.clear()
                "sample-metadata" -> sampleMetadata.clear()
                "sample-context" -> sampleContext.clear()
                "correlation-map" -> correlations.clear()
                "correlation-ids" -> correlatedIds.clear()
            }
            if (Json.encodeToJsonElement(HealthData.serializer(), request.data) != expectedData) {
                changed += "$granular/$mutation: accepted source changed"
            }
            val actual = planner.plan(request).plan.items.associate { it.relativePath to it.content.decodeToString() }
            if (actual != expected) changed += "$granular/$mutation: exported bytes changed"
        }
        assertWithMessage("An accepted operation must retain its source facts and all four artifact bytes")
            .that(changed).isEmpty()
    }

    @Test
    fun nativeWorkoutsReachEverySuccessorFormatWithExactQuantitiesAndClocks() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = Instant.parse("2026-11-01T06:30:00.987654321Z")
        val workout = com.healthmd.domain.model.WorkoutData(
            workoutType = com.healthmd.domain.model.WorkoutType.RUNNING,
            startTime = start.atZone(context.zoneId).toLocalDateTime(),
            endTime = end.atZone(context.zoneId).toLocalDateTime(),
            duration = kotlin.time.Duration.parse("1800.5s"), calories = 320.125, distance = 5000.875,
            averageHeartRate = 160.125, heartRateMax = 179.875, heartRateMin = 91.125,
            stepsCadenceAvg = 178.625, powerAvg = 240.125, powerMax = 312.875,
            exactStartTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start, ZoneOffset.of("-04:00")),
            exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end, ZoneOffset.of("-05:00")),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-workout"),
            metadata = mapOf("synthetic" to "workout, source"))
        val data = HealthData(date = LocalDate.of(2026, 11, 1), workouts = listOf(workout))
        for (preference in listOf(UnitPreference.METRIC, UnitPreference.IMPERIAL)) {
            for (granular in listOf(false, true)) {
                val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(),
                    includeGranularData = granular,
                    formatCustomization = FormatCustomization(unitPreference = preference),
                    metricSelection = MetricSelectionState(enabledMetrics = setOf("workouts")),
                    executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
                val request = FrozenDailyAggregateExportRequest.capture(data, settings,
                    AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                    DailyAggregateExportIds("workouts-${preference.name}-$granular", "workouts-session-${preference.name}-$granular"))
                val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("no ambient clock") }).plan(request).plan
                assertThat(plan.items).hasSize(4)
                val native = Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()).jsonObject
                assertThat(native.getValue("schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
                val record = native.getValue("workouts").jsonArray.single().jsonObject
                assertThat(record.getValue("startTimeISO").jsonPrimitive.content).isEqualTo(start.toString())
                assertThat(record.getValue("endTimeISO").jsonPrimitive.content).isEqualTo(end.toString())
                assertThat(record.getValue("duration").jsonPrimitive.content.toDouble()).isEqualTo(1800.5)
                assertThat(record.getValue("elapsedDuration").jsonPrimitive.content.toDouble()).isEqualTo(3600.864197532)
                assertThat(record.getValue("avgHeartRate").jsonPrimitive.content.toDouble()).isEqualTo(160.125)
                assertThat(record.getValue("avgRunningCadence").jsonPrimitive.content.toDouble()).isEqualTo(178.625)
                assertThat(record.getValue("avgPower").jsonPrimitive.content.toDouble()).isEqualTo(240.125)
                val csv = plan.items.single { it.relativePath.endsWith(".csv") }.content.decodeToString()
                val minutesRow = csv.lineSequence().first { it.contains(",Workouts,Workout Minutes,") }
                assertThat(minutesRow.split(',')[3].toDouble()).isEqualTo(1800.5 / 60)
                val distanceRow = csv.lineSequence().first { it.contains(",Workouts,Workout Distance Km,") }
                assertThat(distanceRow.split(',')[3].toDouble()).isEqualTo(5000.875 / 1000)
                assertThat(csv).contains(",Native Detail,Workout,")
                assertThat(csv).contains("synthetic-workout")
                assertThat(csv).contains("160.125")
                val markdown = plan.items.single { it.relativePath.endsWith(".md") && !it.relativePath.contains("-bases") }.content.decodeToString()
                assertThat(markdown).contains("Workout Details")
                assertThat(markdown).contains("178.625")
                val bases = plan.items.single { it.relativePath.contains("-bases") }.content.decodeToString()
                assertThat(bases).contains("native_workout_details:")
                assertThat(bases).contains("240.125")
                System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { directory ->
                    for (item in plan.items) {
                        val output = File(File(directory, "android-v6-workouts-${preference.name}-$granular"), item.relativePath)
                        check(output.parentFile.mkdirs() || output.parentFile.isDirectory)
                        output.writeBytes(item.content)
                    }
                }
            }
        }
    }

    @Test
    fun anySelectedWorkoutOutputOwnsDetailsWithoutRequiringVisibleCountOrDuration() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 11, 1)
        val start = Instant.parse("2026-11-01T01:30:00Z")
        val end = start.plusSeconds(1800)
        val workout = com.healthmd.domain.model.WorkoutData(
            workoutType = com.healthmd.domain.model.WorkoutType.RUNNING,
            startTime = start.atZone(context.zoneId).toLocalDateTime(),
            endTime = end.atZone(context.zoneId).toLocalDateTime(), duration = 30.minutes,
            averageHeartRate = 160.125, heartRateMax = 179.875, heartRateMin = 91.125,
            exactStartTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start, ZoneOffset.UTC),
            exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end, ZoneOffset.UTC),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-selected-workout"))
        val data = HealthData(date = date, workouts = listOf(workout))
        val registry = HealthMdCoreService().getMetricRegistry(com.healthmd.core.CoreMetricRegistryProfile.ANDROID_SLEEP_V6, 2u)
        val keys = registry.outputs.filter { it.key == "workouts" || it.key.startsWith("workout_") }.map { it.key }
        // Android has twelve native outputs; Apple-only gait metrics and its mile alias stay absent.
        assertThat(keys).hasSize(12)
        for (key in keys) {
            val fields = keys.map { com.healthmd.domain.model.CustomFrontmatterField(it, isEnabled = it == key) }
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(),
                formatCustomization = FormatCustomization(frontmatterConfig = com.healthmd.domain.model.FrontmatterConfiguration(fields = fields)),
                metricSelection = MetricSelectionState(enabledMetrics = setOf("workouts")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data, settings,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("selected-$key", "selected-session-$key"))
            val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("no ambient clock") }).plan(request).plan
            assertThat(plan.items).hasSize(4)
            val csv = plan.items.single { it.relativePath.endsWith(".csv") }.content.decodeToString()
            assertThat(csv).contains(",Native Detail,Workout,")
            assertThat(csv).contains("synthetic-selected-workout")
            val document = Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()).jsonObject
            assertThat(document.getValue("workouts").jsonArray.single().jsonObject.getValue("identity").jsonObject.getValue("nativeId").jsonPrimitive.content)
                .isEqualTo("synthetic-selected-workout")
            assertThat(plan.items.single { it.relativePath.endsWith("-bases.md") }.content.decodeToString()).contains("native_workout_details:")
            assertThat(plan.items.single { it.relativePath.endsWith(".md") && !it.relativePath.endsWith("-bases.md") }.content.decodeToString()).contains("Workout Details")
        }
    }

    @Test
    fun capturedWorkoutIntervalsAndNestedSourcesKeepExactDstElapsedTime() = runTest {
        val zone = ZoneId.of("America/New_York")
        val date = LocalDate.of(2026, 11, 1)
        val start = Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = Instant.parse("2026-11-01T06:30:00.987654321Z")
        val source = Metadata.manualEntry(clientRecordId = "synthetic-workout-captured")
        for (longRoute in listOf(false, true)) {
            val route = androidx.health.connect.client.records.ExerciseRoute(listOf(
                androidx.health.connect.client.records.ExerciseRoute.Location(start, 0.0, 0.0, null, null, null),
                androidx.health.connect.client.records.ExerciseRoute.Location(end.minusNanos(1), if (longRoute) 0.03 else 0.0001, 0.0, null, null, null)))
            val session = androidx.health.connect.client.records.ExerciseSessionRecord(startTime = start,
                startZoneOffset = ZoneOffset.of("-04:00"), endTime = end, endZoneOffset = ZoneOffset.of("-05:00"),
                exerciseType = androidx.health.connect.client.records.ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
                title = "Synthetic workout", notes = "SDK | source", metadata = source, exerciseRoute = route,
                laps = listOf(androidx.health.connect.client.records.ExerciseLap(start.plusSeconds(900), end.minusSeconds(900),
                    androidx.health.connect.client.units.Length.meters(1000.125))),
                segments = listOf(androidx.health.connect.client.records.ExerciseSegment(start.plusSeconds(900), end.minusSeconds(900),
                    androidx.health.connect.client.records.ExerciseSegment.EXERCISE_SEGMENT_TYPE_RUNNING, 2)))
            val heart = androidx.health.connect.client.records.HeartRateRecord(startTime = start, startZoneOffset = null,
                endTime = end, endZoneOffset = null, metadata = Metadata.manualEntry(clientRecordId = "workout-heart"),
                samples = listOf(androidx.health.connect.client.records.HeartRateRecord.Sample(start.plusSeconds(1000), 160),
                    androidx.health.connect.client.records.HeartRateRecord.Sample(end.minusSeconds(1000), 161)))
            val power = androidx.health.connect.client.records.PowerRecord(startTime = start, startZoneOffset = null,
                endTime = end, endZoneOffset = null, metadata = Metadata.manualEntry(clientRecordId = "workout-power"),
                samples = listOf(androidx.health.connect.client.records.PowerRecord.Sample(start.plusSeconds(1000),
                    androidx.health.connect.client.units.Power.watts(240.125))))
            val client = mockk<HealthConnectClient>()
            val features = mockk<androidx.health.connect.client.HealthConnectFeatures>()
            io.mockk.every { client.features } returns features
            io.mockk.every { features.getFeatureStatus(any()) } returns androidx.health.connect.client.HealthConnectFeatures.FEATURE_STATUS_UNAVAILABLE
            val aggregate = mockk<androidx.health.connect.client.aggregate.AggregationResult>()
            io.mockk.every { aggregate[androidx.health.connect.client.records.StepsRecord.COUNT_TOTAL] } returns null
            coEvery { client.aggregate(any<androidx.health.connect.client.request.AggregateRequest>()) } returns aggregate
            coEvery { client.readRecords(any<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()) } answers {
                val type = firstArg<ReadRecordsRequest<*>>().recordType
                val records: List<androidx.health.connect.client.records.Record> = when (type) {
                    androidx.health.connect.client.records.ExerciseSessionRecord::class -> listOf(session)
                    androidx.health.connect.client.records.HeartRateRecord::class -> listOf(heart)
                    androidx.health.connect.client.records.PowerRecord::class -> listOf(power)
                    else -> emptyList()
                }
                ReadRecordsResponse(records, null)
            }
            val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
            for (mode in listOf(SleepDayAttribution.NIGHT_BEGINS, SleepDayAttribution.MORNING_ENDS)) {
                val captured = manager.fetchHealthDataRange(listOf(date), DataTypeSelection().deselectAll().copy(workouts = true),
                    true, zone, pinnedCalendarDays = true, sleepDayAttribution = mode).single()
                val workout = captured.workouts.single()
                val expected = if (mode == SleepDayAttribution.MORNING_ENDS) 3600.864197532 else 3600.864
                assertThat(workout.duration.toDouble(kotlin.time.DurationUnit.SECONDS)).isEqualTo(expected)
                assertThat(workout.averageHeartRate).isEqualTo(160.5)
                assertThat(workout.powerAvg).isEqualTo(240.125)
                assertThat(workout.exactStartTime?.instant()).isEqualTo(start)
                assertThat(workout.exactEndTime?.instant()).isEqualTo(end)
                if (mode == SleepDayAttribution.NIGHT_BEGINS) continue
                assertThat(workout.splits).isNotEmpty()
                if (!longRoute) {
                    assertThat(workout.splits.single().duration.toDouble(kotlin.time.DurationUnit.SECONDS)).isEqualTo(1800.864197532)
                    assertThat(workout.splits.single().averageHeartRate).isEqualTo(160.5)
                }
                val context = AndroidCaptureContext(zone, mode)
                val request = FrozenDailyAggregateExportRequest.capture(captured, ExportSettings(exportFormats = ExportFormat.entries.toSet(),
                    includeMetadata = false, includeGranularData = true, metricSelection = MetricSelectionState(enabledMetrics = setOf("workouts")),
                    executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true),
                    AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                    DailyAggregateExportIds("workout-captured-$longRoute", "workout-captured-session-$longRoute"))
                val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("no ambient clock") }).plan(request).plan
                val native = Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()).jsonObject
                val item = native.getValue("workouts").jsonArray.single().jsonObject
                assertThat(item.getValue("duration").jsonPrimitive.content.toDouble()).isEqualTo(3600.864197532)
                assertThat(item.getValue("elapsedDuration").jsonPrimitive.content.toDouble()).isEqualTo(3600.864197532)
                assertThat(item.getValue("avgHeartRate").jsonPrimitive.content.toDouble()).isEqualTo(160.5)
                assertThat(item.getValue("avgPower").jsonPrimitive.content.toDouble()).isEqualTo(240.125)
                assertThat(item.getValue("splits").jsonArray).isNotEmpty()
                System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf(String::isNotBlank)?.let { directory ->
                    for (artifact in plan.items) {
                        val output = File(File(directory, "android-v6-workouts-sdk-$longRoute"), artifact.relativePath)
                        check(output.parentFile.mkdirs() || output.parentFile.isDirectory)
                        output.writeBytes(artifact.content)
                    }
                }
            }
        }
    }

    @Test
    fun capturedActivityIntervalsKeepExactElapsedTimeAcrossDstFold() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 11, 1)
        val start = Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = Instant.parse("2026-11-01T06:30:00.987654321Z")
        val steps = androidx.health.connect.client.records.StepsRecord(startTime = start,
            startZoneOffset = ZoneOffset.of("-04:00"), endTime = end, endZoneOffset = ZoneOffset.of("-05:00"),
            count = 123, metadata = Metadata.manualEntry(clientRecordId = "captured-steps"))
        val intensity = androidx.health.connect.client.records.ActivityIntensityRecord(startTime = start,
            startZoneOffset = ZoneOffset.of("-04:00"), endTime = end, endZoneOffset = ZoneOffset.of("-05:00"),
            activityIntensityType = androidx.health.connect.client.records.ActivityIntensityRecord.ACTIVITY_INTENSITY_TYPE_MODERATE,
            metadata = Metadata.manualEntry(clientRecordId = "captured-intensity"))
        for (available in listOf(true, false)) {
            val client = mockk<HealthConnectClient>()
            val features = mockk<androidx.health.connect.client.HealthConnectFeatures>()
            io.mockk.every { client.features } returns features
            io.mockk.every { features.getFeatureStatus(any()) } answers {
                if (available && firstArg<Int>() == androidx.health.connect.client.HealthConnectFeatures.FEATURE_ACTIVITY_INTENSITY)
                    androidx.health.connect.client.HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
                else androidx.health.connect.client.HealthConnectFeatures.FEATURE_STATUS_UNAVAILABLE
            }
            val aggregate = mockk<androidx.health.connect.client.aggregate.AggregationResult>()
            io.mockk.every { aggregate[androidx.health.connect.client.records.StepsRecord.COUNT_TOTAL] } returns null
            coEvery { client.aggregate(any<androidx.health.connect.client.request.AggregateRequest>()) } returns aggregate
            coEvery { client.readRecords(any<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()) } answers {
                val request = firstArg<ReadRecordsRequest<*>>()
                val records: List<androidx.health.connect.client.records.Record> = when (request.recordType) {
                    androidx.health.connect.client.records.StepsRecord::class -> listOf(steps)
                    androidx.health.connect.client.records.ActivityIntensityRecord::class -> listOf(intensity)
                    else -> emptyList()
                }
                ReadRecordsResponse(records, null)
            }
            val captured = HealthConnectManager(mockk<Context>(relaxed = true), client).fetchHealthDataRange(
                listOf(date), DataTypeSelection().deselectAll().copy(activity = true), true, context.zoneId,
                pinnedCalendarDays = true, sleepDayAttribution = SleepDayAttribution.MORNING_ENDS).single()
            assertThat(captured.activity.steps).isNull()
            assertThat(captured.activity.stepSamples.single().exactTime?.instant()).isEqualTo(start)
            assertThat(captured.activity.stepSamples.single().exactEndTime?.instant()).isEqualTo(end)
            assertThat(captured.activity.activityIntensityEntries.size).isEqualTo(if (available) 1 else 0)
            val selection = MetricSelectionState(enabledMetrics = setOf("steps", "activity_intensity_minutes"))
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
                metricSelection = selection, executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(captured.filtered(selection, context), settings,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("sdk-activity-$available", "sdk-activity-session-$available"))
            val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("ambient clock is forbidden") }).plan(request).plan
            val native = Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()).jsonObject
            val activity = native.getValue("activity").jsonObject
            if (available) {
                val record = activity.getValue("activityIntensity").jsonArray.single().jsonObject
                assertThat(record.getValue("duration").jsonPrimitive.content).isEqualTo("3600.864197532")
            } else assertThat(activity["activityIntensity"]).isNull()
            for (artifact in plan.items) {
                val text = artifact.content.decodeToString()
                assertThat(text).contains(start.toString())
                assertThat(text).contains(end.atOffset(ZoneOffset.of("-05:00")).toString())
                assertThat(text).contains("captured-steps")
                assertThat(text.contains("captured-intensity")).isEqualTo(available)
            }
            io.mockk.coVerify(exactly = if (available) 1 else 0) {
                client.readRecords(match<ReadRecordsRequest<androidx.health.connect.client.records.Record>> {
                    it.recordType == androidx.health.connect.client.records.ActivityIntensityRecord::class
                })
            }
            System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf { it.isNotBlank() }?.let { directory ->
                plan.items.forEach { artifact ->
                    val output = File(directory, "android-v6-activity-captured-$available/${artifact.relativePath}")
                    requireNotNull(output.parentFile).mkdirs()
                    output.writeBytes(artifact.content)
                }
            }
        }
    }

    @Test
    fun nativeActivityIntervalsReachConcretePlannerWithoutInventedSummaries() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val start = Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = Instant.parse("2026-11-01T06:30:00.987654321Z")
        val metadata = mutableMapOf("synthetic" to "activity-source|`<br>&nbsp;")
        val activity = ActivityData(
            stepSamples = listOf(com.healthmd.domain.model.TimestampedSample(
                java.time.LocalDateTime.ofInstant(start, context.zoneId), 2_147_483_648.0, source = "example.synthetic.activity",
                metadata = metadata, exactTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start),
                exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end),
                identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-steps"))),
            activityIntensityEntries = listOf(com.healthmd.domain.model.ActivityIntensityEntry(
                java.time.LocalDateTime.ofInstant(start, context.zoneId), java.time.LocalDateTime.ofInstant(end, context.zoneId),
                60.minutes, "moderate", source = "example.synthetic.activity", metadata = metadata,
                exactStartTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start),
                exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end),
                identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-intensity"))))
        val data = HealthData(LocalDate.of(2026, 11, 1), activity = activity)
        val selection = MetricSelectionState(enabledMetrics = setOf("steps", "activity_intensity_minutes"))
        val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
            metricSelection = selection, executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
        val request = FrozenDailyAggregateExportRequest.capture(data.filtered(selection, context), settings,
            AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("concrete-activity", "concrete-activity-session"))
        metadata["synthetic"] = "mutated-after-freeze"
        val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("ambient clock is forbidden") }).plan(request).plan
        assertThat(plan.items).hasSize(4)
        for (artifact in plan.items) {
            val text = artifact.content.decodeToString()
            assertThat(text).contains(start.toString())
            assertThat(text).contains(end.toString())
            assertThat(text).contains("synthetic-steps")
            assertThat(text).contains("synthetic-intensity")
            assertThat(text).contains("example.synthetic.activity")
            assertThat(text).doesNotContain("mutated-after-freeze")
            assertThat(text).doesNotContain("steps:")
            assertThat(text).doesNotContain("activity_intensity_minutes:")
            if (artifact.relativePath.endsWith(".json")) {
                val activityJson = Json.parseToJsonElement(text).jsonObject.getValue("activity").jsonObject
                assertThat(activityJson.getValue("stepSamples").jsonArray.single().jsonObject.getValue("value").jsonPrimitive.content)
                    .isEqualTo("2147483648")
                assertThat(activityJson["steps"]).isNull()
                assertThat(activityJson["activityIntensityMinutes"]).isNull()
            }
        }
        System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf { it.isNotBlank() }?.let { directory ->
            plan.items.forEach { artifact ->
                val output = File(directory, "android-v6-activity/${artifact.relativePath}")
                requireNotNull(output.parentFile).mkdirs()
                output.writeBytes(artifact.content)
            }
        }
        for (count in listOf(-1.0, 1.5, Double.NaN, 9_007_199_254_740_992.0)) {
            val incompatible = data.copy(activity = activity.copy(stepSamples = activity.stepSamples.map { it.copy(value = count) }))
            try {
                com.healthmd.data.export.JsonExporter().export(incompatible, request.customization, true, captureContext = context)
                error("An incompatible source count must reject rather than truncate")
            } catch (error: IllegalArgumentException) {
                assertThat(error.message).isEqualTo("wake-date native JSON is incompatible")
                assertThat(error.cause).isNull()
            }
        }
        val invalid = data.copy(activity = activity.copy(stepSamples = activity.stepSamples.map {
            it.copy(exactEndTime = null)
        }))
        val invalidRequest = FrozenDailyAggregateExportRequest.capture(invalid.filtered(selection, context), settings,
            AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("invalid-activity", "invalid-activity-session"))
        try {
            HealthMdRustDailyAggregatePlanner().plan(invalidRequest)
            error("An interval without its exact end must reject")
        } catch (_: com.healthmd.domain.render.HealthMdRenderInputAdapter.AdapterException) { }
    }

    @Test
    fun pairedBloodPressureWithoutSummariesReachesConcretePlannerAcrossEveryFormat() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val instant = Instant.parse("2026-11-01T01:30:00.123456789Z")
        val sourceMetadata = mutableMapOf("synthetic" to "paired-pressure")
        val sample = com.healthmd.domain.model.BloodPressureSample(java.time.LocalDateTime.ofInstant(instant, context.zoneId),
            120.125, 80.875, measurementLocation = "left-arm", bodyPosition = "sitting", source = "example.synthetic.bp",
            metadata = sourceMetadata,
            exactTime = com.healthmd.domain.model.ExactSourceTimestamp(instant.epochSecond, instant.nano, "Z"),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-bp-correlation"))
        val samples = mutableListOf(sample)
        val captured = HealthData(LocalDate.of(2026, 11, 1), activity = ActivityData(steps = 0), vitals = VitalsData(bloodPressureSamples = samples))
        for (enabled in listOf(setOf("bp_systolic", "bp_diastolic"), setOf("bp_systolic", "steps"))) {
            val selection = MetricSelectionState(enabledMetrics = enabled)
            val data = captured.filtered(selection, context)
            val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(exportFormats = ExportFormat.entries.toSet(),
                includeGranularData = true, metricSelection = selection, executionSleepCaptureContext = context,
                executionSleepCaptureAuthorityIsFrozen = true), AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("concrete-bp-${enabled.size}", "concrete-bp-session-${enabled.size}"))
            if ("bp_diastolic" in enabled) { samples.clear(); sourceMetadata["synthetic"] = "mutated-after-capture" }
            val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("ambient timezone is forbidden") }).plan(request).plan
            assertThat(plan.items).hasSize(4)
            for (artifact in plan.items) {
                val text = artifact.content.decodeToString()
                assertThat(text.contains("120.125")).isEqualTo("bp_diastolic" in enabled)
                assertThat(text.contains("80.875")).isEqualTo("bp_diastolic" in enabled)
                assertThat(text).doesNotContain("blood_pressure_systolic:")
                assertThat(text).doesNotContain("mutated-after-capture")
                if ("bp_diastolic" in enabled && !text.contains("| Timestamp (UTC) | End (UTC) | Systolic |")) {
                    assertThat(text).contains("synthetic-bp-correlation")
                    assertThat(text).contains("example.synthetic.bp")
                }
            }
            if ("bp_diastolic" in enabled) System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf { it.isNotBlank() }?.let { directory ->
                plan.items.forEach { artifact ->
                    val output = File(directory, "android-v6-blood-pressure/${artifact.relativePath}")
                    requireNotNull(output.parentFile).mkdirs()
                    output.writeBytes(artifact.content)
                }
            }
        }
    }

    @Test
    fun quantityOnlyNativeRecordsReachConcretePlannerAcrossEveryFormat() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val instant = Instant.parse("2026-11-01T01:30:00.123456789Z")
        fun sample(value: Double) = com.healthmd.domain.model.TimestampedSample(
            java.time.LocalDateTime.ofInstant(instant, context.zoneId), value,
            metadata = mapOf("synthetic" to "quantity-source"),
            exactTime = com.healthmd.domain.model.ExactSourceTimestamp(instant.epochSecond, instant.nano, "Z"),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-quantity"))
        val captured = HealthData(LocalDate.of(2026, 11, 1),
            heart = HeartData(samples = listOf(sample(72.125)), hrvSamples = listOf(sample(31.875))),
            vitals = VitalsData(bloodOxygenSamples = listOf(sample(0.97125)), bloodGlucoseSamples = listOf(sample(101.875)),
                respiratoryRateSamples = listOf(sample(16.125))))
        for (enabled in listOf(setOf("avg_hr", "hrv", "blood_oxygen", "blood_glucose", "respiratory_rate"), setOf("avg_hr"))) {
            val selection = MetricSelectionState(enabledMetrics = enabled)
            val data = captured.filtered(selection, context)
            val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(
                exportFormats = ExportFormat.entries.toSet(), includeGranularData = true, metricSelection = selection,
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true),
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("concrete-quantity-${enabled.size}", "concrete-quantity-session-${enabled.size}"))
            val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("ambient timezone is forbidden") }).plan(request).plan
            val texts = plan.items.map { it.content.decodeToString() }
            assertThat(texts).hasSize(4)
            val csv = texts.single { it.contains(",Native Detail,Quantity Sample,") }
            assertThat(csv.lines().count { it.contains(",Native Detail,Quantity Sample,") }).isEqualTo(enabled.size)
            assertThat(csv).contains(instant.toString())
            assertThat(csv).contains("synthetic-quantity")
            val markdown = texts.single { it.contains("Heart Rate Sample Details") && !it.contains("native_quantity_details:") }
            assertThat(markdown).contains("| 72.125 | bpm |")
            assertThat(markdown).doesNotContain("average_heart_rate:")
            val bases = texts.single { it.contains("native_quantity_details:") }
            assertThat(bases.contains("hrv_rmssd")).isEqualTo("hrv" in enabled)
            assertThat(bases).doesNotContain("hrv_sdnn")
            val native = Json.parseToJsonElement(texts.single { it.trimStart().startsWith("{") }).jsonObject
            assertThat(native.getValue("heart").jsonObject.containsKey("averageHeartRate")).isFalse()
            System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf { it.isNotBlank() }?.let { directory ->
                for (item in plan.items) {
                    val output = File(directory, (if (enabled.size == 5) "android-v6-quantities/" else "android-v6-heart-only/") + item.relativePath)
                    requireNotNull(output.parentFile).mkdirs()
                    output.writeBytes(item.content)
                }
            }
        }
    }

    @Test
    fun nativeWakeDateStagesReachEveryFormatWithExactSourceClocks() {
        val core = HealthMdCoreService()
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val registry = core.getMetricRegistry(com.healthmd.core.CoreMetricRegistryProfile.ANDROID_SLEEP_V6, 2u)
        val start = Instant.parse("2026-07-24T23:00:00.123456789Z")
        val end = Instant.parse("2026-07-25T00:00:00.987654321Z")
        val stage = com.healthmd.domain.model.SleepStageEntry(
            java.time.LocalDateTime.ofInstant(start, context.zoneId), java.time.LocalDateTime.ofInstant(end, context.zoneId),
            "light", com.healthmd.domain.model.ExactSourceTimestamp(start.epochSecond, start.nano, "Z"),
            com.healthmd.domain.model.ExactSourceTimestamp(end.epochSecond, end.nano, "Z"),
            com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-stage-source"))
        val data = HealthData(date = LocalDate.of(2026, 7, 25), sleep = SleepData(
            totalDuration = 60.minutes, lightSleep = 60.minutes, stages = listOf(stage)))
        val adapter = com.healthmd.domain.semantic.HealthMdSemanticInputAdapter
        val config = adapter.sessionConfiguration("android-stage-detail", com.healthmd.domain.semantic.HealthMdSemanticInputAdapter.Profile.SLEEP_V6,
            MetricSelectionState(enabledMetrics = setOf("sleep_total", "sleep_light")), registry, context.zoneId.id,
            captureContext = context)
        val batch = adapter.batch("android-stage-detail", com.healthmd.domain.semantic.HealthMdSemanticInputAdapter.Profile.SLEEP_V6, 0u, true, listOf(data), registry,
            com.healthmd.domain.model.UnitConverter(UnitPreference.METRIC), context.zoneId.id, captureContext = context)
        val semantic = core.createSemanticSession(config).use { it.processBatch(batch.bytes) }
        val customization = FormatCustomization()
        val encoded = com.healthmd.domain.render.HealthMdRenderInputAdapter.encode(semantic, registry, context.zoneId.id,
            com.healthmd.domain.render.HealthMdRenderInputAdapter.Options("android-stage-detail",
                listOf("json", "csv", "markdown", "obsidian_bases"), includeGranularData = true),
            presentationByOwnerDate = mapOf("2026-07-25" to data), presentationCustomization = customization,
            captureContext = context)
        val plan = core.createRenderSession(encoded.configuration, semantic).use { session ->
            encoded.batches.forEach { session.processBatch(it) }; session.finish()
        }
        val texts = plan.items.map { it.content.decodeToString() }
        val csv = texts.single { it.contains(",Sleep Detail,Sleep Stage,") }
        assertThat(csv).contains(start.toString())
        assertThat(csv).contains(end.toString())
        assertThat(csv).contains("3600.864197532")
        assertThat(csv).contains("synthetic-stage-source")
        val markdown = texts.single { it.contains("Sleep Stage Details") }
        assertThat(markdown).contains("| light |")
        assertThat(texts.single { it.contains("sleep_stage_details") }).contains(start.toString())
        val native = com.healthmd.data.export.JsonExporter().export(data, customization, true, captureContext = context)
        assertThat(Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()))
            .isEqualTo(Json.parseToJsonElement(native))
        for (invalid in listOf(
            data.copy(sleep = data.sleep.copy(stages = listOf(stage.copy(stage = "deep")))),
            data.copy(sleep = data.sleep.copy(stages = List(1500) { stage })),
            data.copy(activity = ActivityData(steps = 1, stepSamples = listOf(com.healthmd.domain.model.TimestampedSample(
                stage.startTime, 1.0, exactTime = stage.exactStartTime)))),
        )) {
            org.junit.Assert.assertThrows(com.healthmd.domain.render.HealthMdRenderInputAdapter.AdapterException::class.java) {
                com.healthmd.domain.render.HealthMdRenderInputAdapter.encode(semantic, registry, context.zoneId.id,
                    com.healthmd.domain.render.HealthMdRenderInputAdapter.Options("android-stage-detail",
                        listOf("json", "csv", "markdown", "obsidian_bases"), includeGranularData = true),
                    presentationByOwnerDate = mapOf("2026-07-25" to invalid), presentationCustomization = customization,
                    captureContext = context)
            }
        }
        val sleeping = data.copy(sleep = data.sleep.copy(stages = listOf(stage.copy(stage = "sleeping"))))
        val sleepingInput = com.healthmd.domain.render.HealthMdRenderInputAdapter.encode(semantic, registry, context.zoneId.id,
            com.healthmd.domain.render.HealthMdRenderInputAdapter.Options("android-stage-detail", listOf("csv"), includeGranularData = true),
            presentationByOwnerDate = mapOf("2026-07-25" to sleeping), presentationCustomization = customization, captureContext = context)
        val sleepingDetails = Json.parseToJsonElement(sleepingInput.batches.single().decodeToString()).jsonObject
            .getValue("days").jsonArray.single().jsonObject.getValue("native_details").jsonObject
        assertThat(sleepingDetails.getValue("output_keys").toString()).isEqualTo("[\"sleep_total_hours\"]")
    }

    @Test
    fun concreteWakeDatePlannerRetainsCapturedSleepingStagesAndParents() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 11, 1)
        val start = Instant.parse("2026-11-01T02:00:00.123456789Z")
        val end = Instant.parse("2026-11-01T12:00:00.987654321Z")
        val client = mockk<HealthConnectClient>()
        coEvery { client.readRecords(any<ReadRecordsRequest<SleepSessionRecord>>()) } returns ReadRecordsResponse(listOf(
            SleepSessionRecord(startTime = start, startZoneOffset = ZoneOffset.of("-04:00"),
                endTime = end, endZoneOffset = ZoneOffset.of("-05:00"),
                metadata = Metadata.manualEntry(clientRecordId = "synthetic-sleeping-parent"),
                stages = listOf(SleepSessionRecord.Stage(start, end, SleepSessionRecord.STAGE_TYPE_SLEEPING))),
        ), null)
        val captured = HealthConnectManager(mockk<Context>(relaxed = true), client).fetchHealthDataRange(
            listOf(date), DataTypeSelection().deselectAll().copy(sleep = true), true, context.zoneId,
            sleepDayAttribution = SleepDayAttribution.MORNING_ENDS).single()
        val selection = MetricSelectionState(enabledMetrics = setOf("sleep_total", "sleep_light", "sleep_in_bed"))
        val data = captured.filtered(selection, context)
        val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(
            exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
            metricSelection = selection, executionSleepCaptureContext = context,
            executionSleepCaptureAuthorityIsFrozen = true,
        ), AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("concrete-sleep-detail", "concrete-sleep-detail-session"))
        val totalOnly = MetricSelectionState(enabledMetrics = setOf("sleep_total"))
        val lightOnly = MetricSelectionState(enabledMetrics = setOf("sleep_light"))
        assertThat(captured.filtered(totalOnly, context).sleep.stages).hasSize(1)
        assertThat(captured.filtered(lightOnly, context).sleep.stages).isEmpty()
        assertThat(captured.filtered(totalOnly).sleep.stages).isEmpty()
        assertThat(captured.filtered(lightOnly).sleep.stages).hasSize(1)
        val historicalContext = AndroidCaptureContext(context.zoneId, SleepDayAttribution.NIGHT_BEGINS)
        assertThat(captured.filtered(lightOnly, historicalContext)).isEqualTo(captured.filtered(lightOnly))
        org.junit.Assert.assertThrows(IllegalArgumentException::class.java) {
            captured.filtered(totalOnly, context.copy(exportProfileID = null))
        }
        val totalData = captured.filtered(totalOnly, context).filtered(totalOnly, context)
        assertThat(totalData.sleep.stages.single().exactStartTime).isEqualTo(captured.sleep.stages.single().exactStartTime)
        val planner = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("ambient timezone is forbidden") })
        val plan = planner.plan(request).plan
        assertThat(plan.items).hasSize(4)
        val mutableStages = data.sleep.stages.toMutableList()
        val mutableMetadata = data.sleep.sessions.single().metadata.toMutableMap()
        val mutableSessions = mutableListOf(data.sleep.sessions.single().copy(metadata = mutableMetadata))
        val mutableData = data.copy(sleep = data.sleep.copy(stages = mutableStages, sessions = mutableSessions))
        val frozen = FrozenDailyAggregateExportRequest.capture(mutableData, ExportSettings(
            exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
            metricSelection = selection, executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
        ), AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust, request.ids)
        mutableStages.clear()
        mutableSessions.clear()
        mutableMetadata["client_record_id"] = "changed-after-capture"
        assertThat(frozen.data.sleep.stages).hasSize(1)
        assertThat(frozen.data.sleep.sessions).hasSize(1)
        assertThat(frozen.data.sleep.sessions.single().metadata).isEqualTo(data.sleep.sessions.single().metadata)
        val frozenPlan = planner.plan(frozen).plan
        for (item in plan.items) {
            assertThat(frozenPlan.items.single { it.relativePath == item.relativePath }.content).isEqualTo(item.content)
        }
        val texts = plan.items.map { it.content.decodeToString() }
        assertThat(texts.single { it.contains(",Sleep Detail,Sleep Stage,") }).contains("sleeping")
        assertThat(texts.single { it.contains("sleep_stage_details") }).contains("synthetic-sleeping-parent")
        assertThat(texts.single { it.contains("Sleep Session Details") }).contains(start.toString())
        val totalRequest = FrozenDailyAggregateExportRequest.capture(totalData, ExportSettings(
            exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
            metricSelection = totalOnly, executionSleepCaptureContext = context,
            executionSleepCaptureAuthorityIsFrozen = true,
        ), AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("concrete-total-detail", "concrete-total-detail-session"))
        val totalPlan = planner.plan(totalRequest).plan
        assertThat(totalPlan.items.single { it.relativePath.endsWith(".csv") }.content.decodeToString())
            .contains(",Sleep Detail,Sleep Stage,")
        assertThat(totalPlan.items.single { it.relativePath.endsWith(".csv") }.content.decodeToString()).contains("sleeping")
        val totalNative = com.healthmd.data.export.JsonExporter().export(totalData, totalRequest.customization,
            true, captureContext = context)
        assertThat(Json.parseToJsonElement(totalPlan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()))
            .isEqualTo(Json.parseToJsonElement(totalNative))
        System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf { it.isNotBlank() }?.let { directory ->
            for (item in totalPlan.items) {
                val output = File(File(directory, "android-sleep-v6-concrete-sleeping"), item.relativePath)
                val parent = requireNotNull(output.parentFile)
                check(parent.mkdirs() || parent.isDirectory)
                output.writeBytes(item.content)
            }
        }
        val unavailableSummary = totalData.copy(sleep = totalData.sleep.copy(totalDuration = kotlin.time.Duration.ZERO,
            deepSleep = kotlin.time.Duration.ZERO, remSleep = kotlin.time.Duration.ZERO,
            lightSleep = kotlin.time.Duration.ZERO, awakeTime = kotlin.time.Duration.ZERO, inBedTime = kotlin.time.Duration.ZERO))
        val detailOnly = FrozenDailyAggregateExportRequest.capture(unavailableSummary, ExportSettings(
            exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
            metricSelection = totalOnly, executionSleepCaptureContext = context,
            executionSleepCaptureAuthorityIsFrozen = true,
        ), AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("concrete-detail-without-summary", "concrete-detail-without-summary-session"))
        val detailOnlyPlan = planner.plan(detailOnly).plan
        assertThat(detailOnlyPlan.items).hasSize(4)
        val detailOnlyJson = Json.parseToJsonElement(detailOnlyPlan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()).jsonObject
        val detailOnlySleep = detailOnlyJson.getValue("sleep").jsonObject
        assertThat(detailOnlySleep.containsKey("totalDuration")).isFalse()
        assertThat(detailOnlySleep.getValue("sleepStages").jsonArray).hasSize(1)
        assertThat(detailOnlySleep.getValue("sleepSessions").jsonArray).hasSize(1)
        for (item in detailOnlyPlan.items.filterNot { it.relativePath.endsWith(".json") }) {
            val text = item.content.decodeToString()
            assertThat(text).doesNotContain("sleep_total_hours:")
            assertThat(text).doesNotContain(",Total Sleep,")
            assertThat(text).contains(if (item.relativePath.endsWith(".csv")) ",Sleep Detail,Sleep Stage," else "sleep")
        }
        val nonSleep = data.copy(activity = ActivityData(steps = 1,
            stepSamples = listOf(com.healthmd.domain.model.TimestampedSample(data.sleep.stages.single().startTime, 1.0,
                exactTime = data.sleep.stages.single().exactStartTime))))
        val unqualified = FrozenDailyAggregateExportRequest.capture(nonSleep, ExportSettings(
            exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
            metricSelection = selection, executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
        ), AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("concrete-non-sleep-detail", "concrete-non-sleep-detail-session"))
        try {
            planner.plan(unqualified)
            error("An unselected activity interval must reject")
        } catch (error: com.healthmd.domain.render.HealthMdRenderInputAdapter.AdapterException) {
            assertThat(error.message).contains("native activity interval")
        }
        val native = com.healthmd.data.export.JsonExporter().export(data, request.customization, true, captureContext = context)
        assertThat(Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()))
            .isEqualTo(Json.parseToJsonElement(native))
    }

    @Test
    fun capturedWakeDateParentsAndStagesKeepSeparateSourceRecordsAcrossEveryFormat() = runTest {
        val core = HealthMdCoreService()
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 11, 1)
        val start = Instant.parse("2026-11-01T02:00:00.123456789Z")
        val end = Instant.parse("2026-11-01T18:30:00.987654321Z")
        val client = mockk<HealthConnectClient>()
        coEvery { client.readRecords(any<ReadRecordsRequest<SleepSessionRecord>>()) } returns ReadRecordsResponse(listOf(
            SleepSessionRecord(startTime = start, startZoneOffset = ZoneOffset.of("-04:00"),
                endTime = end, endZoneOffset = ZoneOffset.of("-05:00"),
                title = "Synthetic overnight, \"quoted\" | ` <source> &", notes = "first line\nsecond line",
                metadata = Metadata.manualEntry(clientRecordId = "synthetic-parent-overnight"),
                stages = listOf(SleepSessionRecord.Stage(start, end, SleepSessionRecord.STAGE_TYPE_LIGHT))),
            SleepSessionRecord(startTime = Instant.parse("2026-11-01T20:00:00.333333333Z"), startZoneOffset = null,
                endTime = Instant.parse("2026-11-01T20:30:00.444444444Z"), endZoneOffset = null,
                title = "Synthetic nap", metadata = Metadata.manualEntry(clientRecordId = "synthetic-parent-nap")),
        ), null)
        val data = HealthConnectManager(mockk<Context>(relaxed = true), client).fetchHealthDataRange(
            listOf(date), DataTypeSelection().deselectAll().copy(sleep = true), true, context.zoneId,
            sleepDayAttribution = SleepDayAttribution.MORNING_ENDS).single()
        assertThat(data.sleep.sessions).hasSize(2)
        val registry = core.getMetricRegistry(com.healthmd.core.CoreMetricRegistryProfile.ANDROID_SLEEP_V6, 2u)
        val adapter = com.healthmd.domain.semantic.HealthMdSemanticInputAdapter
        val profile = com.healthmd.domain.semantic.HealthMdSemanticInputAdapter.Profile.SLEEP_V6
        val config = adapter.sessionConfiguration("android-parent-detail", profile,
            MetricSelectionState(enabledMetrics = setOf("sleep_total", "sleep_light", "sleep_in_bed")), registry, context.zoneId.id,
            captureContext = context)
        val batch = adapter.batch("android-parent-detail", profile, 0u, true, listOf(data), registry,
            com.healthmd.domain.model.UnitConverter(UnitPreference.METRIC), context.zoneId.id, captureContext = context)
        val semantic = core.createSemanticSession(config).use { it.processBatch(batch.bytes) }
        val customization = FormatCustomization()
        fun encode(candidate: HealthData, includeMetadata: Boolean = true) = com.healthmd.domain.render.HealthMdRenderInputAdapter.encode(semantic,
            registry, context.zoneId.id, com.healthmd.domain.render.HealthMdRenderInputAdapter.Options(
                "android-parent-detail", listOf("json", "csv", "markdown", "obsidian_bases"), includeGranularData = true, includeMetadata = includeMetadata),
            presentationByOwnerDate = mapOf(date.toString() to candidate), presentationCustomization = customization,
            captureContext = context)
        val encoded = encode(data)
        val plan = core.createRenderSession(encoded.configuration, semantic).use { session ->
            encoded.batches.forEach { session.processBatch(it) }; session.finish()
        }
        System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf { it.isNotBlank() }?.let { directory ->
            for (item in plan.items) {
                val output = File(File(directory, "android-sleep-v6-parents"), item.relativePath)
                val parent = requireNotNull(output.parentFile)
                check(parent.mkdirs() || parent.isDirectory)
                output.writeBytes(item.content)
            }
        }
        val csv = plan.items.single { it.relativePath.endsWith(".csv") }.content.decodeToString()
        assertThat(csv.lines().count { it.startsWith("2026-11-01,Sleep Detail,Sleep Session,") }).isEqualTo(2)
        for (token in listOf(start.toString(), end.toString(), "synthetic-parent-overnight", "synthetic-parent-nap",
            "Synthetic overnight", "first line", "second line", "-04:00", "-05:00")) assertThat(csv).contains(token)
        val texts = plan.items.map { it.content.decodeToString() }
        val markdown = texts.single { it.contains("Sleep Session Details") }
        assertThat(markdown).contains("Sleep Stage Details")
        assertThat(markdown).contains(start.toString())
        assertThat(markdown).contains("2026-11-01T20:30:00.444444444Z")
        val bases = texts.single { it.contains("sleep_session_details") }
        assertThat(bases).contains("sleep_stage_details")
        assertThat(bases).contains("synthetic-parent-overnight")
        val native = com.healthmd.data.export.JsonExporter().export(data, customization, true, captureContext = context)
        assertThat(Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()))
            .isEqualTo(Json.parseToJsonElement(native))
        for (includeMetadata in listOf(false, true)) {
            val input = encode(data, includeMetadata)
            val emitted = core.createRenderSession(input.configuration, semantic).use { session ->
                input.batches.forEach { session.processBatch(it) }; session.finish()
            }
            val json = Json.parseToJsonElement(emitted.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()).jsonObject
            val source = json.getValue("sleep").jsonObject
            val md = emitted.items.single { it.relativePath.endsWith(".md") && !it.relativePath.endsWith("-bases.md") }.content.decodeToString()
            val records = md.lineSequence().filter { it.contains("| `{") }.map { row ->
                val cell = row.split('|').dropLast(1).last().trim()
                check(cell.startsWith("`{") && cell.endsWith("}`"))
                Json.parseToJsonElement(cell.removeSurrounding("`")).jsonObject
            }.toList()
            assertThat(records.filter { "stage" in it }).containsExactlyElementsIn(source.getValue("sleepStages").jsonArray)
            assertThat(records.filter { "startTimeISO" in it }).containsExactlyElementsIn(source.getValue("sleepSessions").jsonArray)
            System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf { it.isNotBlank() }?.let { directory ->
                for (item in emitted.items) {
                    val output = File(directory, "android-v6-sleep-source-$includeMetadata/${item.relativePath}")
                    check(output.parentFile!!.mkdirs() || output.parentFile!!.isDirectory)
                    output.writeBytes(item.content)
                }
            }
        }
        val parentOnly = data.copy(sleep = data.sleep.copy(stages = emptyList()))
        val parentEncoded = encode(parentOnly)
        val parentPlan = core.createRenderSession(parentEncoded.configuration, semantic).use { session ->
            parentEncoded.batches.forEach { session.processBatch(it) }; session.finish()
        }
        val parentTexts = parentPlan.items.map { it.content.decodeToString() }
        assertThat(parentTexts.single { it.contains("Sleep Session Details") }).doesNotContain("Sleep Stage Details")
        assertThat(parentTexts.single { it.contains("sleep_session_details") }).doesNotContain("sleep_stage_details")
        assertThat(parentTexts.single { it.contains(",Sleep Detail,Sleep Session,") }
            .lines().count { it.startsWith("2026-11-01,Sleep Detail,Sleep Session,") }).isEqualTo(2)
        for (invalid in listOf(
            data.copy(sleep = data.sleep.copy(sessions = data.sleep.sessions.map { it.copy(exactEndTime = null) })),
            data.copy(date = date.plusDays(1)),
            data.copy(sleep = data.sleep.copy(sessions = List(1500) { data.sleep.sessions[0] })),
        )) org.junit.Assert.assertThrows(IllegalArgumentException::class.java) { encode(invalid) }
    }

    @Test
    fun concreteWakeDatePlannerUsesFrozenClockAndReturnsAllFourSuccessorArtifacts() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("Asia/Kathmandu"), SleepDayAttribution.MORNING_ENDS)
        val data = HealthData(
            date = LocalDate.of(2026, 7, 25),
            sleep = SleepData(totalDuration = 495.minutes, lightSleep = 255.minutes),
            activity = ActivityData(steps = 1234),
        )
        val settings = ExportSettings(
            exportFormats = ExportFormat.entries.toSet(),
            includeMetadata = false,
            metricSelection = MetricSelectionState(enabledMetrics = setOf("sleep_total", "sleep_light", "steps")),
            executionSleepCaptureContext = context,
            executionSleepCaptureAuthorityIsFrozen = true,
        )
        val request = FrozenDailyAggregateExportRequest.capture(
            data, settings, AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("host-wake-date", "host-wake-date-session"),
        )
        val result = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { ZoneId.of("UTC") }).plan(request)

        assertThat(result.pin.ianaTimeZone).isEqualTo("Asia/Kathmandu")
        assertThat(result.pin.profile).isEqualTo(AndroidExportProfile.android_sleep_v6)
        assertThat(result.plan.artifactPlanVersion).isEqualTo(2u)
        assertThat(result.plan.items.map { it.relativePath }).containsExactly(
            "health/2026-07-25.md", "health/2026-07-25-bases.md", "health/2026-07-25.json", "health/2026-07-25.csv",
        ).inOrder()
        for (item in result.plan.items) {
            val text = item.content.decodeToString()
            assertThat(text).contains("morning_ends")
            assertThat(text).contains("Asia/Kathmandu")
            assertThat(text).doesNotContain("sleep_core_hours")
            assertThat(text).doesNotContain("android-analytical-v5")
            assertThat(item.writeMode).isEqualTo(ExportArtifactWriteMode.overwrite)
            if (item.relativePath.endsWith(".json")) {
                val root = Json.parseToJsonElement(text).jsonObject
                assertThat(root.getValue("schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
                assertThat(root.getValue("units").jsonObject.mapValues { it.value.jsonPrimitive.content }).containsExactly(
                    "sleep_total_hours", "hours", "sleep_light_hours", "hours", "steps", "steps",
                )
                assertThat(root.getValue("schema_version").jsonPrimitive.content).isEqualTo("6")
                assertThat(root.getValue("type").jsonPrimitive.content).isEqualTo("health-data")
                assertThat(root.getValue("sleep").jsonObject.getValue("totalDuration").jsonPrimitive.content.toDouble()).isEqualTo(29700.0)
                assertThat(root.getValue("sleep").jsonObject.getValue("lightSleep").jsonPrimitive.content.toDouble()).isEqualTo(15300.0)
                assertThat(root.getValue("activity").jsonObject.getValue("steps").jsonPrimitive.content).isEqualTo("1234")
            } else if (item.relativePath.endsWith(".md") && !item.relativePath.endsWith("-bases.md")) {
                assertThat(text.startsWith("---")).isFalse()
            }
        }
    }

    @Test
    fun successorCanonicalQuantityKeepsSourcePrecisionRatherThanAFormattedDisplayString() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val data = HealthData(LocalDate.of(2026, 11, 1), body = BodyData(weight = 72.125))
        val settings = ExportSettings(
            // Canonical semantic projection remains independently exercised by machine frontmatter.
            // Native JSON now retains SDK field names rather than the bare canonical prototype.
            exportFormats = setOf(ExportFormat.OBSIDIAN_BASES),
            metricSelection = MetricSelectionState(enabledMetrics = setOf("weight")),
            executionSleepCaptureContext = context,
            executionSleepCaptureAuthorityIsFrozen = true,
        )
        val request = FrozenDailyAggregateExportRequest.capture(data, settings,
            AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("host-exact-quantity", "host-exact-quantity-session"))
        val result = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("cannot read ambient clock") }).plan(request)
        val text = result.plan.items.single().content.decodeToString()
        assertThat(text).contains("weight_kg: 72.125\n")
        assertThat(text).contains("schema_profile: android-sleep-v6\n")
    }

    @Test
    fun requestedDisplayUnitsNeverRelabelCanonicalMachineQuantities() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val data = HealthData(LocalDate.of(2026, 11, 1), body = BodyData(weight = 72.125, height = 1.75125),
            activity = ActivityData(walkingRunningDistance = 1_234.125))
        val jsonDocuments = mutableListOf<String>()
        for (preference in UnitPreference.entries) {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(),
                formatCustomization = FormatCustomization(unitPreference = preference),
                metricSelection = MetricSelectionState(enabledMetrics = setOf("weight", "height", "distance")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(data, settings,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("host-display-units", "host-display-units-session"))
            val result = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("cannot read ambient clock") }).plan(request)
            val markdown = result.plan.items.single { it.relativePath.endsWith(".md") && !it.relativePath.endsWith("-bases.md") }.content.decodeToString()
            val bases = result.plan.items.single { it.relativePath.endsWith("-bases.md") }.content.decodeToString()
            for (document in listOf(markdown, bases)) {
                assertThat(document).contains("weight_kg: 72.125\n")
                assertThat(document).contains("height_m: 1.75125\n")
                assertThat(document).contains("walking_running_km: 1.234125\n")
            }
            val csv = result.plan.items.single { it.relativePath.endsWith(".csv") }.content.decodeToString()
            assertThat(csv).contains(",Weight,72.125,kg,")
            assertThat(csv).contains(",Height,1.75125,m,")
            assertThat(csv).contains(",unit_system,metric,")
            if (preference == UnitPreference.IMPERIAL) {
                assertThat(markdown).contains("159.0 lbs")
                assertThat(markdown).contains("5'8\"")
                assertThat(markdown).contains("0.77 mi")
            } else {
                assertThat(markdown).contains("72.1 kg")
                assertThat(markdown).contains("175.1 cm")
                assertThat(markdown).contains("1.23 km")
            }
            val json = result.plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()
            val root = Json.parseToJsonElement(json).jsonObject
            assertThat(root.getValue("body").jsonObject.getValue("weight").jsonPrimitive.content.toDouble()).isEqualTo(72.125)
            assertThat(root.getValue("body").jsonObject.getValue("height").jsonPrimitive.content.toDouble()).isEqualTo(1.75125)
            assertThat(root.getValue("units").jsonObject.mapValues { it.value.jsonPrimitive.content })
                .containsExactly("weight_kg", "kg", "height_m", "m", "walking_running_km", "km")
            jsonDocuments.add(json)
        }
        assertThat(jsonDocuments.distinct()).hasSize(1)
    }

    @Test
    fun humanTemperatureDifferencesScaleWithoutAnAbsoluteOffsetAndWaterKeepsMachineLiters() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val data = HealthData(LocalDate.of(2026, 11, 1),
            vitals = VitalsData(bodyTemperatureAvg = 36.8125, skinTemperatureDelta = -0.5),
            nutrition = NutritionData(water = 1.375))
        val jsonDocuments = mutableListOf<String>()
        for (preference in UnitPreference.entries) {
            val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(
                exportFormats = ExportFormat.entries.toSet(),
                formatCustomization = FormatCustomization(unitPreference = preference),
                metricSelection = MetricSelectionState(enabledMetrics = setOf("body_temp", "skin_temperature", "water")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true),
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("host-human-temperature", "host-human-temperature-session"))
            val result = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("cannot read ambient clock") }).plan(request)
            val markdown = result.plan.items.single { it.relativePath.endsWith(".md") && !it.relativePath.endsWith("-bases.md") }.content.decodeToString()
            for (expected in if (preference == UnitPreference.IMPERIAL)
                listOf("98.3°F", "-0.90°F", "46.5 oz") else listOf("36.8°C", "-0.50°C", "1.38 L")) {
                assertThat(markdown).contains(expected)
            }
            for (item in result.plan.items.filter { it.relativePath.endsWith(".md") }) {
                assertThat(item.content.decodeToString()).contains("skin_temperature_delta: -0.5\n")
                assertThat(item.content.decodeToString()).contains("water_l: 1.375\n")
            }
            val json = result.plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()
            val root = Json.parseToJsonElement(json).jsonObject
            assertThat(root.getValue("vitals").jsonObject.getValue("bodyTemperatureAvg").jsonPrimitive.content.toDouble()).isEqualTo(36.8125)
            assertThat(root.getValue("vitals").jsonObject.getValue("skinTemperatureDelta").jsonPrimitive.content.toDouble()).isEqualTo(-0.5)
            assertThat(root.getValue("unit_system").jsonPrimitive.content).isEqualTo("metric")
            jsonDocuments.add(json)
        }
        assertThat(jsonDocuments.distinct()).hasSize(1)
    }

    @Test
    fun canonicalSdkFactsKeepFractionalDurationsAndNativeStatisticsAcrossCategories() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val data = HealthData(
            LocalDate.of(2026, 11, 1),
            sleep = SleepData(totalDuration = 7.5.minutes, lightSleep = 3.75.minutes),
            activity = ActivityData(activeCalories = 123.875, walkingRunningDistance = 1234.125, exerciseMinutes = 7.625),
            heart = HeartData(averageHeartRate = 67.875, hrv = 42.125),
            vitals = VitalsData(bodyTemperatureAvg = 36.8125, bloodGlucoseAvg = 101.875, respiratoryRateAvg = 14.3125),
            body = BodyData(weight = 72.125, height = 1.75125, leanBodyMass = 51.875, bodyWaterMass = 40.625, boneMass = 3.125),
            nutrition = NutritionData(dietaryEnergy = 1700.25, protein = 12.375, sodium = 101.875, water = 1.375),
        )
        val selected = HealthMdCoreService().getMetricRegistry(AndroidExportProfile.android_sleep_v6.coreProfile, 2u)
            .metrics.map { it.selectionId }.toSet()
        val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(
            exportFormats = setOf(ExportFormat.OBSIDIAN_BASES), metricSelection = MetricSelectionState(enabledMetrics = selected),
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
        ), AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("host-fractional-facts", "host-fractional-facts-session"))
        val result = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("cannot read ambient clock") }).plan(request)
        val fields = result.plan.items.single().content.decodeToString().lineSequence().mapNotNull { line ->
            val pair = line.split(": ", limit = 2)
            if (pair.size == 2) pair[1].toDoubleOrNull()?.let { pair[0] to it } else null
        }.toMap()
        val expected = mapOf(
            "sleep_total_hours" to 0.125, "sleep_light_hours" to 0.0625,
            "active_calories" to 123.875, "walking_running_km" to 1.234125, "exercise_minutes" to 7.625,
            "average_heart_rate" to 67.875, "hrv_ms" to 42.125,
            "body_temperature" to 36.8125, "blood_glucose" to 101.875, "respiratory_rate" to 14.3125,
            "weight_kg" to 72.125, "height_m" to 1.75125, "bmi" to (72.125 / (1.75125 * 1.75125)), "lean_body_mass_kg" to 51.875,
            "body_water_mass_kg" to 40.625, "bone_mass_kg" to 3.125,
            "dietary_calories" to 1700.25, "protein_g" to 12.375, "sodium_mg" to 101.875, "water_l" to 1.375,
        )
        for ((key, value) in expected) {
            assertWithMessage(key).that(fields.getValue(key)).isEqualTo(value)
        }
    }

    @Test
    fun nativeSleepCaptureReachesEverySuccessorFormatWithoutShiftingSourceTimestamps() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val date = LocalDate.of(2026, 11, 1)
        val client = mockk<HealthConnectClient>()
        coEvery { client.readRecords(any<ReadRecordsRequest<SleepSessionRecord>>()) } returns ReadRecordsResponse(listOf(
            SleepSessionRecord(
                startTime = Instant.parse("2026-11-01T02:00:00.123456789Z"), startZoneOffset = ZoneOffset.of("-04:00"),
                endTime = Instant.parse("2026-11-01T12:00:00.987654321Z"), endZoneOffset = ZoneOffset.of("-05:00"),
                metadata = Metadata.manualEntry(clientRecordId = "synthetic-native-sleep"),
                stages = listOf(SleepSessionRecord.Stage(
                    Instant.parse("2026-11-01T02:00:00.123456789Z"),
                    Instant.parse("2026-11-01T12:00:00.987654321Z"),
                    SleepSessionRecord.STAGE_TYPE_LIGHT,
                )),
            ),
        ), null)
        val data = HealthConnectManager(mockk<Context>(relaxed = true), client).fetchHealthDataRange(
            listOf(date), DataTypeSelection().deselectAll().copy(sleep = true), false, context.zoneId,
            sleepDayAttribution = SleepDayAttribution.MORNING_ENDS,
        ).single()
        val planner = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("cannot read ambient clock") })
        for (formats in listOf(ExportFormat.entries.toSet(), setOf(ExportFormat.MARKDOWN, ExportFormat.CSV, ExportFormat.OBSIDIAN_BASES))) {
            val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(
                exportFormats = formats,
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
            ), AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("host-native-sleep", "host-native-sleep-session"))
            val result = planner.plan(request)
            assertThat(result.plan.artifactPlanVersion).isEqualTo(2u)
            assertThat(result.plan.items).hasSize(formats.size)
            // Explicit test-only capture of synthetic SDK facts through the real native/core writer.
            // Consumers use these bytes directly; this does not read a user's health store.
            if (ExportFormat.JSON in formats) {
                System.getenv("HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR")?.takeIf { it.isNotBlank() }?.let { directory ->
                    val destination = File(directory, "android-sleep-v6-dst")
                    for (item in result.plan.items) {
                        val output = File(destination, item.relativePath)
                        val parent = requireNotNull(output.parentFile)
                        check(parent.mkdirs() || parent.isDirectory)
                        output.writeBytes(item.content)
                    }
                }
            }
            for (item in result.plan.items) {
                val text = item.content.decodeToString()
                assertThat(text).contains("morning_ends")
                assertThat(text).doesNotContain("sleep_core_hours")
                assertThat(text).doesNotContain("Core Sleep")
                assertThat(text).contains(when {
                    item.relativePath.endsWith(".json") -> "lightSleep"
                    item.relativePath.endsWith("-bases.md") -> "sleep_light_hours"
                    else -> "Light Sleep"
                })
                if (item.relativePath.endsWith(".md")) {
                    assertThat(text).contains("sleep_bedtime: 22:00")
                    assertThat(text).contains("sleep_wake: 07:00")
                }
                if (item.relativePath.endsWith(".csv")) {
                    assertThat(text).contains(",Sleep,Bedtime,22:00,time,")
                    assertThat(text).contains(",Sleep,Wake Time,07:00,time,")
                    assertThat(text).contains(",22:00,time,2026-11-01T02:00:00.123456789Z\n")
                    assertThat(text).contains(",07:00,time,2026-11-01T12:00:00.987654321Z\n")
                }
            }
            if (ExportFormat.JSON in formats) {
                val root = Json.parseToJsonElement(result.plan.items.single {
                    it.relativePath.endsWith(".json")
                }.content.decodeToString()).jsonObject
                assertThat(root.getValue("schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
                val sleep = root.getValue("sleep").jsonObject
                assertThat(sleep.getValue("bedtimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T02:00:00.123456789Z")
                assertThat(sleep.getValue("wakeTimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T12:00:00.987654321Z")
                assertThat(sleep.getValue("totalDuration").jsonPrimitive.content.toDouble()).isEqualTo(36000.864197532)
            }
        }
        val settings = ExportSettings(
            exportFormats = setOf(ExportFormat.MARKDOWN, ExportFormat.CSV), includeMetadata = false,
            formatCustomization = FormatCustomization(timeFormat = TimeFormatPreference.HOUR_12),
            executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
        )
        val request = FrozenDailyAggregateExportRequest.capture(data, settings,
            AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
            DailyAggregateExportIds("host-native-human-clock", "host-native-human-clock-session"))
        val humanPlan = planner.plan(request).plan
        val markdown = humanPlan.items.single { it.relativePath.endsWith(".md") }.content.decodeToString()
        assertThat(markdown.startsWith("---")).isFalse()
        assertThat(markdown).contains("10:00 PM")
        assertThat(markdown).contains("7:00 AM")
        assertThat(markdown).contains("morning_ends")
        val csv = humanPlan.items.single { it.relativePath.endsWith(".csv") }.content.decodeToString()
        assertThat(csv).contains(",10:00 PM,time,2026-11-01T02:00:00.123456789Z\n")
        for (invalid in listOf(
            data.copy(date = date.plusDays(1)),
            data.copy(sleep = data.sleep.copy(sessionEnd = data.sleep.sessionEnd!!.plusHours(1))),
            data.copy(sleep = data.sleep.copy(sessions = data.sleep.sessions.map { it.copy(exactEndTime = null) })),
        )) {
            val candidate = FrozenDailyAggregateExportRequest.capture(invalid, settings,
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("host-invalid-clock", "host-invalid-clock-session"))
            assertThat(runCatching { planner.plan(candidate) }.isFailure).isTrue()
        }
    }


    @Test
    fun emptyAndPopulatedSleepDaysShareOneNativeJsonGrammar() = runTest {
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val dates = listOf(LocalDate.of(2026, 10, 31), LocalDate.of(2026, 11, 1))
        val client = mockk<HealthConnectClient>()
        coEvery { client.readRecords(any<ReadRecordsRequest<SleepSessionRecord>>()) } returns ReadRecordsResponse(listOf(
            SleepSessionRecord(
                startTime = Instant.parse("2026-11-01T02:00:00.123456789Z"), startZoneOffset = ZoneOffset.of("-04:00"),
                endTime = Instant.parse("2026-11-01T12:00:00.123456789Z"), endZoneOffset = ZoneOffset.of("-05:00"),
                metadata = Metadata.manualEntry(clientRecordId = "synthetic-uniform-grammar"),
            ),
        ), null)
        val days = HealthConnectManager(mockk<Context>(relaxed = true), client).fetchHealthDataRange(
            dates, DataTypeSelection().deselectAll().copy(sleep = true), false, context.zoneId,
            sleepDayAttribution = SleepDayAttribution.MORNING_ENDS,
        )
        val planner = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("cannot read ambient clock") })
        for ((index, captured) in days.withIndex()) {
            val data = captured.copy(activity = ActivityData(steps = 1234, activeCalories = 123.875))
            val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(
                exportFormats = setOf(ExportFormat.JSON), includeMetadata = false,
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true,
            ), AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("host-uniform-$index", "host-uniform-session-$index"))
            val root = Json.parseToJsonElement(planner.plan(request).plan.items.single().content.decodeToString()).jsonObject
            assertThat(root.getValue("type").jsonPrimitive.content).isEqualTo("health-data")
            assertThat(root.getValue("schema_version").jsonPrimitive.content).isEqualTo("6")
            assertThat(root.getValue("activity").jsonObject.getValue("activeCalories").jsonPrimitive.content.toDouble()).isEqualTo(123.875)
            assertThat(root.getValue("activity").jsonObject).doesNotContainKey("active_calories")
            if (captured.date == dates.first()) assertThat(root["sleep"]).isNull()
            else {
                val sleep = root.getValue("sleep").jsonObject
                assertThat(sleep.getValue("totalDuration").jsonPrimitive.content.toDouble()).isEqualTo(36000.0)
                assertThat(sleep.getValue("wakeTimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T12:00:00.123456789Z")
                assertThat(sleep).doesNotContainKey("sleep_total_hours")
            }
        }
    }

    @Test
    fun realPinnedWakeDateRouterDoesNotReadPolicyOrAmbientClockAndKeepsEmptySleepAuthority() = runTest {
        val service = HealthMdCoreService()
        val capturedStoragePin = requireNotNull(ExportEnginePinCodec.decodeOrNull(
            requireNotNull(javaClass.classLoader!!.getResource("direct/android-sleep-v6-storage-pin.json")).readText().trim(),
        ))
        assertThat(ExportEnginePinValidator().validate(capturedStoragePin, service).isCompatible).isTrue()
        val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
        val pin = ExportEnginePin.create(
            engine = ExportEngineMode.rust,
            profile = AndroidExportProfile.android_sleep_v6,
            ianaTimeZone = context.zoneId.id,
            readiness = service.checkReadiness(),
            registry = service.getMetricRegistry(AndroidExportProfile.android_sleep_v6.coreProfile, 2u),
        )
        val planner = AndroidDailyAggregateExportPlanner(
            nativePlanner = DailyAggregateNativePlanBuilder { error("cannot call historical native writers") },
            policyResolver = LocalExportEnginePolicyResolver { error("cannot consult live policy") },
            rustPlanner = HealthMdRustDailyAggregatePlanner(
                coreService = service,
                zoneIdProvider = { error("cannot consult the reader's clock") },
            ),
            idSource = DailyAggregateExportIdSource { DailyAggregateExportIds("host-router", "host-router-session") },
        )
        val result = planner.plan(
            HealthData(LocalDate.of(2026, 11, 1), activity = ActivityData(steps = 1234)),
            ExportSettings(
                exportFormats = setOf(ExportFormat.JSON),
                executionEnginePin = pin,
                executionEngineAuthorityIsFrozen = true,
                executionSleepCaptureContext = context,
                executionSleepCaptureAuthorityIsFrozen = true,
            ),
        )
        assertThat(result).isInstanceOf(LocalDailyAggregatePlanningResult.Planned::class.java)
        val item = (result as LocalDailyAggregatePlanningResult.Planned).plan.items.single()
        val root = Json.parseToJsonElement(item.content.decodeToString()).jsonObject
        assertThat(root.getValue("schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
        val time = root.getValue("time_context").jsonObject
        assertThat(time.getValue("calendar_timezone").jsonPrimitive.content).isEqualTo(context.zoneId.id)
        assertThat(time.getValue("sleep_day_attribution").jsonPrimitive.content).isEqualTo("morning_ends")
        assertThat(time.getValue("sleep_owner_day_rule").jsonPrimitive.content).isEqualTo("session_end_date")
        assertThat(time.getValue("sleep_interval_clipping").jsonPrimitive.content).isEqualTo("none")
        assertThat(root["sleep"]).isNull()
    }
}
