package com.healthmd.domain.render

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.HEALTHMD_SLEEP_REGISTRY_SHA256
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepStageEntry
import java.time.LocalDateTime
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.UnitConverter
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.semantic.HealthMdSemanticInputAdapter
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZoneId
import kotlin.time.Duration.Companion.minutes
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * Independently produced Kotlin requests replayed by the real Rust semantic/render sessions.
 * These synthetic post-capture facts do not qualify Health Connect ownership or native public writers.
 */
class WakeDateNativeHandoffFixtureTest {
    private val context = AndroidCaptureContext(ZoneId.of("Asia/Kathmandu"), SleepDayAttribution.MORNING_ENDS)
    private val profile = HealthMdSemanticInputAdapter.Profile.SLEEP_V6

    @Test
    fun nativeWakeDateRequestsMatchSeparateFixtureAndRefuseDraftAuthority() {
        val root = repositoryRoot()
        val inventoryBytes = Files.readAllBytes(root.resolve(
            "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v2.json",
        ))
        assertThat(MessageDigest.getInstance("SHA-256").digest(inventoryBytes)
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }).isEqualTo(HEALTHMD_SLEEP_REGISTRY_SHA256)
        val registry = NativeRenderRequestFixtureTest().registry(
            Json.parseToJsonElement(inventoryBytes.decodeToString()).jsonObject,
            "android_sleep_v6",
            HEALTHMD_SLEEP_REGISTRY_SHA256,
        )
        val configuration = HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionId = "native-android-wake-date",
            profile = profile,
            selection = MetricSelectionState(enabledMetrics = setOf("sleep_total", "sleep_light", "steps")),
            registry = registry,
            calendarTimeZone = context.zoneId.id,
            captureContext = context,
        )
        val data = HealthData(
            date = LocalDate.of(2026, 7, 25),
            sleep = SleepData(totalDuration = 495.minutes, lightSleep = 255.minutes),
            activity = ActivityData(steps = 1234),
        )
        fun encode(capture: AndroidCaptureContext?, zone: String = context.zoneId.id, aliases: Boolean = false) =
            HealthMdSemanticInputAdapter.boundedBatches(
                sessionId = "native-android-wake-date", profile = profile, healthData = listOf(data),
                registry = registry, converter = UnitConverter(UnitPreference.METRIC),
                calendarTimeZone = zone, captureContext = capture, includeLegacyAndroidAliases = aliases,
            )
        val batches = encode(context)
        assertThat(batches).hasSize(1)
        val batch = Json.parseToJsonElement(batches.single().bytes.decodeToString()).jsonObject
        assertThat(batch.getValue("semantic_input_version").toString()).isEqualTo("2")
        assertThat(batch.toString()).contains("\"semantic_id\":\"sleep_light\"")
        assertThat(batch.toString()).doesNotContain("sleep_core")
        for (invalid in listOf(null, context.copy(exportProfileID = null),
            AndroidCaptureContext(context.zoneId, SleepDayAttribution.NIGHT_BEGINS))) {
            assertThrows(HealthMdSemanticInputAdapter.AdapterException::class.java) { encode(invalid) }
            assertThrows(HealthMdSemanticInputAdapter.AdapterException::class.java) {
                HealthMdSemanticInputAdapter.sessionConfiguration(
                    "native-invalid-authority", profile, MetricSelectionState(), registry,
                    context.zoneId.id, captureContext = invalid,
                )
            }
        }
        assertThrows(HealthMdSemanticInputAdapter.AdapterException::class.java) { encode(context, "UTC") }
        assertThrows(HealthMdSemanticInputAdapter.AdapterException::class.java) { encode(context, aliases = true) }
        assertThrows(HealthMdSemanticInputAdapter.AdapterException::class.java) {
            HealthMdSemanticInputAdapter.batch(
                sessionId = "native-invalid-core-stage", profile = profile, batchIndex = 0u, finalBatch = true,
                healthData = listOf(data.copy(sleep = data.sleep.copy(stages = listOf(SleepStageEntry(
                    LocalDateTime.of(2026, 7, 25, 1, 0), LocalDateTime.of(2026, 7, 25, 2, 0), "core",
                ))))),
                registry = registry, converter = UnitConverter(UnitPreference.METRIC),
                calendarTimeZone = context.zoneId.id, captureContext = context,
            )
        }

        // Literal expected reductions from the synthetic SDK facts above, not shared-core output.
        val expected = Json.parseToJsonElement("""
            {"schema":"healthmd.semantic_result","semantic_input_version":2,"canonical_model_version":2,
             "core_api_version":4,"registry_sha256":"$HEALTHMD_SLEEP_REGISTRY_SHA256","profile_revision":1,
             "session_id":"native-android-wake-date","profile":"android_sleep_v6","state":"completed",
             "next_batch_index":1,"records_accepted":3,"records_filtered":0,
             "sleep_capture_context":{"schema_profile":"android-sleep-v6","calendar_timezone":"Asia/Kathmandu",
              "sleep_day_attribution":"morning_ends","sleep_owner_day_rule":"session_end_date","sleep_interval_clipping":"none"},
             "days":[{"owner_date":"2026-07-25","values":[
              {"output_key":"sleep_total_hours","semantic_id":"sleep_total","aggregation":"pass_through",
               "value":{"value_type":"number","number":{"representation":"binary64","bits":"4020800000000000"},"unit":{"id":"hour"}},
               "source_record_ids":["android-daily-2026-07-25-sleep_total_hours"]},
              {"output_key":"sleep_light_hours","semantic_id":"sleep_light","aggregation":"pass_through",
               "value":{"value_type":"number","number":{"representation":"binary64","bits":"4011000000000000"},"unit":{"id":"hour"}},
               "source_record_ids":["android-daily-2026-07-25-sleep_light_hours"]},
              {"output_key":"steps","semantic_id":"steps","aggregation":"pass_through",
               "value":{"value_type":"number","number":{"representation":"signed_integer","decimal":"1234"},"unit":{"id":"count"}},
               "source_record_ids":["android-daily-2026-07-25-steps"]}]}],"rollups":[],"retained_extensions":[]}
        """.trimIndent()).jsonObject
        val semanticResult = JsonObject(expected.toMutableMap().apply {
            put("records_filtered", JsonPrimitive(batch.getValue("records").jsonArray.size - 3))
        })
        val render = HealthMdRenderInputAdapter.encode(
            semanticResult.toString().encodeToByteArray(), registry, context.zoneId.id,
            HealthMdRenderInputAdapter.Options(
                "native-android-wake-date-render", listOf("markdown", "obsidian_bases", "json", "csv"),
                includeMetadata = false,
            ),
        )
        val fixture = buildJsonObject {
            put("schema", "healthmd.native_wake_date_handoff")
            put("schema_version", 1)
            put("semantic_configuration", Json.parseToJsonElement(configuration.decodeToString()))
            put("semantic_batches", JsonArray(batches.map { Json.parseToJsonElement(it.bytes.decodeToString()) }))
            put("expected_semantic_result", semanticResult)
            put("render_configuration", Json.parseToJsonElement(render.configuration.decodeToString()))
            put("render_batches", JsonArray(render.batches.map { Json.parseToJsonElement(it.decodeToString()) }))
        }
        val bytes = (fixture.toString() + "\n").encodeToByteArray()
        val path = root.resolve("packages/contracts/render-input/v2/fixtures/native-android-v6-handoff.json")
        if (System.getenv("HEALTHMD_UPDATE_WAKE_DATE_ANDROID_HANDOFF_FIXTURE") == "1") {
            Files.createDirectories(path.parent)
            Files.write(path, bytes)
        } else {
            assertArrayEquals("Native wake-date handoff drifted; review independently versioned authority",
                Files.readAllBytes(path), bytes)
        }
    }

    private fun repositoryRoot(): Path {
        var root = Path.of(System.getProperty("user.dir")).toAbsolutePath()
        while (!Files.isDirectory(root.resolve("packages/contracts"))) {
            root = root.parent ?: error("repository root is unavailable")
        }
        return root
    }
}
