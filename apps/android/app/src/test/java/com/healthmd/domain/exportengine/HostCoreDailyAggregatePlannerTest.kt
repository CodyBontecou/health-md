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
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

/**
 * Opt-in real host UniFFI/JNA qualification of the concrete Android planner.
 * SDK-boundary cases substitute only Health Connect IPC; no real provider, device library or destination is used.
 */
class HostCoreDailyAggregatePlannerTest {
    @Before
    fun useExplicitTaskOwnedHostCore() {
        val library = System.getenv("HEALTHMD_HOST_CORE_LIBRARY")
        assumeTrue("Host-core QA requires an explicit freshly built library", !library.isNullOrBlank())
        require(File(checkNotNull(library)).isFile) { "Host core library is unavailable" }
        System.setProperty("uniffi.component.healthmd_core_uniffi.libraryOverride", library)
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
        val data = HealthData(LocalDate.of(2026, 11, 1), body = BodyData(weight = 72.125, height = 1.75125))
        val jsonDocuments = mutableListOf<String>()
        for (preference in UnitPreference.entries) {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(),
                formatCustomization = FormatCustomization(unitPreference = preference),
                metricSelection = MetricSelectionState(enabledMetrics = setOf("weight", "height")),
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
            }
            val csv = result.plan.items.single { it.relativePath.endsWith(".csv") }.content.decodeToString()
            assertThat(csv).contains(",Weight,72.125,kg,")
            assertThat(csv).contains(",Height,1.75125,m,")
            assertThat(csv).contains(",unit_system,metric,")
            if (preference == UnitPreference.IMPERIAL) {
                assertThat(markdown).contains("159.0 lbs")
                assertThat(markdown).contains("5'8\"")
            } else {
                assertThat(markdown).contains("72.1 kg")
                assertThat(markdown).contains("175.1 cm")
            }
            val json = result.plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString()
            val root = Json.parseToJsonElement(json).jsonObject
            assertThat(root.getValue("body").jsonObject.getValue("weight").jsonPrimitive.content.toDouble()).isEqualTo(72.125)
            assertThat(root.getValue("body").jsonObject.getValue("height").jsonPrimitive.content.toDouble()).isEqualTo(1.75125)
            assertThat(root.getValue("units").jsonObject.mapValues { it.value.jsonPrimitive.content })
                .containsExactly("weight_kg", "kg", "height_m", "m")
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
                        check(output.parentFile.mkdirs() || output.parentFile.isDirectory)
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
                // Captured summary quantities keep milliseconds; source instants keep nanoseconds.
                assertThat(sleep.getValue("totalDuration").jsonPrimitive.content.toDouble()).isEqualTo(36000.864)
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
