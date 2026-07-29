package com.healthmd.domain.semantic

import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.core.HealthMdCoreService
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.MobilityData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.TimeFormatPreference
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.UnitConverter
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.VitalsData
import com.healthmd.domain.registry.HealthMdCoreRegistryAdapter
import java.time.LocalDate
import java.time.LocalDateTime
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class HealthMdSemanticInputAdapterInstrumentationTest {
    @Test
    fun capturedModelEncodesOnceAndProcessesThroughPackagedRustCore() {
        val service = HealthMdCoreService()
        val registry = HealthMdCoreRegistryAdapter.snapshot(
            CoreMetricRegistryProfile.ANDROID_FROZEN_V4,
            service,
        )
        val selection = MetricSelectionState(
            setOf("blood_oxygen", "body_fat", "sleep_total", "steps", "vo2_max"),
        )
        val configuration = HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionId = "android-adapter-instrumentation",
            profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
            selection = selection,
            registry = registry,
            calendarTimeZone = "Asia/Kathmandu",
            retainPlatformExtensions = true,
        )
        val batch = HealthMdSemanticInputAdapter.batch(
            sessionId = "android-adapter-instrumentation",
            profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
            batchIndex = 0u,
            finalBatch = true,
            healthData = listOf(
                HealthData(
                    date = LocalDate.of(2026, 3, 8),
                    sleep = SleepData(
                        sessionStart = LocalDateTime.of(2026, 3, 8, 21, 30),
                    ),
                    activity = ActivityData(
                        steps = 1,
                        stepSamples = listOf(
                            TimestampedSample(
                                time = LocalDateTime.of(2026, 3, 8, 12, 0),
                                value = 1.0,
                                identity = ExactSourceIdentity(nativeId = "instrumentation-step"),
                            ),
                        ),
                    ),
                    vitals = VitalsData(bloodOxygenAvg = 0.975),
                    body = BodyData(bodyFatPercentage = 0.2),
                    mobility = MobilityData(vo2Max = 42.5),
                ),
            ),
            registry = registry,
            converter = UnitConverter(UnitPreference.METRIC),
            calendarTimeZone = "Asia/Kathmandu",
            timeFormat = TimeFormatPreference.HOUR_12_SECONDS,
        )

        val parsedBatch = Json.parseToJsonElement(batch.bytes.decodeToString()).jsonObject
        parsedBatch.getValue("records").jsonArray.forEach { record ->
            val singleBatch = HealthMdSemanticInputAdapter.canonicalBytes(
                buildJsonObject {
                    put("schema", "healthmd.semantic_input")
                    put("semantic_input_version", 1)
                    put("session_id", "android-adapter-instrumentation")
                    put("batch_index", 0)
                    put("final_batch", true)
                    put("owner_dates", JsonArray(listOf(JsonPrimitive("2026-03-08"))))
                    put("records", JsonArray(listOf(record)))
                },
            )
            service.createSemanticSession(configuration).use { singleSession ->
                try {
                    singleSession.processBatch(singleBatch)
                } catch (error: Exception) {
                    throw AssertionError(
                        "adapter record rejected: ${record.jsonObject["output_key"]}",
                        error,
                    )
                }
            }
        }

        val session = service.createSemanticSession(configuration)
        try {
            val result = session.processBatch(batch.bytes).decodeToString()
            assertTrue(result.contains("\"state\":\"completed\""))
            assertTrue(result.contains("\"percent_0_100\""))
            assertFalse(result.contains("ratio_0_1"))
            assertTrue(result.contains("time_of_day_minute"))
            assertTrue(result.contains("milliliter_per_kilogram_minute"))
            assertTrue(result.contains("android.health_connect_step"))
            assertFalse(result.contains("total_calories"))
        } finally {
            session.close()
        }

        val disabledConfiguration = HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionId = "android-adapter-instrumentation",
            profile = HealthMdSemanticInputAdapter.Profile.FROZEN_V4,
            selection = selection,
            registry = registry,
            calendarTimeZone = "Asia/Kathmandu",
            disabledOutputKeys = setOf("body_fat_percent"),
            retainPlatformExtensions = false,
        )
        service.createSemanticSession(disabledConfiguration).use { disabledSession ->
            val result = disabledSession.processBatch(batch.bytes).decodeToString()
            assertFalse(result.contains("body_fat_percent"))
            assertFalse(result.contains("android.health_connect_step"))
        }
    }
}
