package com.healthmd.domain.render

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.CoreRegistryMetric
import com.healthmd.core.CoreRegistryOutput
import com.healthmd.core.HEALTHMD_SLEEP_REGISTRY_SHA256
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.SleepDayAttribution
import java.time.ZoneId
import kotlinx.serialization.json.JsonArray
import com.healthmd.domain.model.HealthData
import java.time.LocalDate
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertThrows
import com.healthmd.domain.model.HEALTHMD_CORE_REGISTRY_SHA256
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class HealthMdRenderInputAdapterTest {
    @Test
    fun completedSemanticResultBecomesBoundedDeterministicRenderInput() {
        val first = HealthMdRenderInputAdapter.encode(
            semanticResult = semanticResult(),
            registry = registry(),
            calendarTimeZone = "UTC",
            options = HealthMdRenderInputAdapter.Options(
                requestId = "android-render-test",
                formats = listOf("markdown", "obsidian_bases", "json", "csv"),
                writeMode = "update",
            ),
        )
        val second = HealthMdRenderInputAdapter.encode(
            semanticResult = semanticResult(),
            registry = registry(),
            calendarTimeZone = "UTC",
            options = HealthMdRenderInputAdapter.Options(
                requestId = "android-render-test",
                formats = listOf("markdown", "obsidian_bases", "json", "csv"),
                writeMode = "update",
            ),
        )

        assertThat(first.configuration).isEqualTo(second.configuration)
        assertThat(first.batches.map(ByteArray::decodeToString)).containsExactlyElementsIn(second.batches.map(ByteArray::decodeToString)).inOrder()
        assertThat(first.batches).hasSize(1)
        assertThat(first.batches.single().size).isAtMost(2 * 1024 * 1024)

        val config = Json.parseToJsonElement(first.configuration.decodeToString()).jsonObject
        assertThat(config.getValue("profile").jsonPrimitive.content).isEqualTo("android_frozen_v4")
        assertThat(config.getValue("render_input_version").jsonPrimitive.content).isEqualTo("1")
        assertThat(config.getValue("artifact_plan_version").jsonPrimitive.content).isEqualTo("1")
        val batch = Json.parseToJsonElement(first.batches.single().decodeToString()).jsonObject
        assertThat(batch.getValue("final_batch").jsonPrimitive.content).isEqualTo("true")
        val metric = batch.getValue("days").jsonArray.single().jsonObject
            .getValue("metrics").jsonArray.single().jsonObject
        assertThat(metric.getValue("output_key").jsonPrimitive.content).isEqualTo("steps")
        assertThat(metric.getValue("public_value").jsonPrimitive.content).isEqualTo("1234")
    }

    @Test
    fun invalidTimezoneAndProfileMismatchFailClosed() {
        val options = HealthMdRenderInputAdapter.Options("android-render-test", listOf("json"))
        val invalidZone = runCatching {
            HealthMdRenderInputAdapter.encode(semanticResult(), registry(), "not/a-zone", options)
        }.exceptionOrNull()
        assertThat(invalidZone).isInstanceOf(HealthMdRenderInputAdapter.AdapterException::class.java)

        val analytical = registry().copy(profileId = "android_analytical_v5", publicProfileId = "android-analytical-v5", publicSchemaVersion = 5u)
        val mismatch = runCatching {
            HealthMdRenderInputAdapter.encode(semanticResult(), analytical, "UTC", options)
        }.exceptionOrNull()
        assertThat(mismatch).isInstanceOf(HealthMdRenderInputAdapter.AdapterException::class.java)
    }

    @Test
    fun wakeDateRenderHandoffUsesV2AndChecksCompletedCapturedClock() {
        val registry = registry().copy(
            registryVersion = 2u,
            registrySha256 = HEALTHMD_SLEEP_REGISTRY_SHA256,
            profileId = "android_sleep_v6",
            publicProfileId = "android-sleep-v6",
            publicSchemaVersion = 6u,
        )
        val result = successorResult()
        val options = HealthMdRenderInputAdapter.Options("native-successor", listOf("json", "csv", "markdown"))
        val encoded = HealthMdRenderInputAdapter.encode(result, registry, "UTC", options)
        val config = Json.parseToJsonElement(encoded.configuration.decodeToString()).jsonObject
        assertThat(config.getValue("render_input_version").jsonPrimitive.content).isEqualTo("2")
        assertThat(config.getValue("canonical_model_version").jsonPrimitive.content).isEqualTo("2")
        assertThat(config.getValue("artifact_plan_version").jsonPrimitive.content).isEqualTo("2")
        assertThat(Json.parseToJsonElement(encoded.batches.single().decodeToString()).jsonObject
            .getValue("render_input_version").jsonPrimitive.content).isEqualTo("2")

        assertThrows(HealthMdRenderInputAdapter.AdapterException::class.java) {
            HealthMdRenderInputAdapter.encode(result, registry, "Asia/Kathmandu", options)
        }
        val parsed = Json.parseToJsonElement(result.decodeToString()).jsonObject
        for ((key, value) in listOf(
            "semantic_input_version" to JsonPrimitive(1),
            "canonical_model_version" to JsonPrimitive(1),
            "sleep_capture_context" to kotlinx.serialization.json.JsonNull,
        )) {
            val draft = JsonObject(parsed.toMutableMap().apply { put(key, value) }).toString().encodeToByteArray()
            assertThrows(HealthMdRenderInputAdapter.AdapterException::class.java) {
                HealthMdRenderInputAdapter.encode(draft, registry, "UTC", options)
            }
        }
        // Native v4/v5 public exporters must never supply relabeled successor profile documents.
        assertThrows(HealthMdRenderInputAdapter.AdapterException::class.java) {
            HealthMdRenderInputAdapter.encode(
                result, registry, "UTC", options,
                presentationByOwnerDate = mapOf("2026-07-25" to HealthData(
                    date = LocalDate.of(2026, 7, 25), activity = ActivityData(steps = 1234),
                )),
            )
        }
    }

    @Test
    fun nativeJsonHandoffRequiresOneMatchingCapturedDayForEveryCompletedOwner() {
        val context = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS)
        val registry = registry().copy(
            registryVersion = 2u, registrySha256 = HEALTHMD_SLEEP_REGISTRY_SHA256,
            profileId = "android_sleep_v6", publicProfileId = "android-sleep-v6", publicSchemaVersion = 6u,
        )
        val parsed = Json.parseToJsonElement(successorResult().decodeToString()).jsonObject
        val first = parsed.getValue("days").jsonArray.single().jsonObject
        val second = JsonObject(first.toMutableMap().apply { put("owner_date", JsonPrimitive("2026-07-26")) })
        val result = JsonObject(parsed.toMutableMap().apply { put("days", JsonArray(listOf(first, second))) })
            .toString().encodeToByteArray()
        val day = HealthData(LocalDate.of(2026, 7, 25), activity = ActivityData(steps = 1234))
        val captured = mapOf("2026-07-25" to day, "2026-07-26" to day.copy(date = day.date.plusDays(1)))
        val options = HealthMdRenderInputAdapter.Options("native-complete-days", listOf("json"))
        fun encode(days: Map<String, HealthData>) = HealthMdRenderInputAdapter.encode(
            result, registry, "UTC", options, presentationByOwnerDate = days, captureContext = context,
        )
        val encoded = encode(captured)
        val outputDays = Json.parseToJsonElement(encoded.batches.single().decodeToString()).jsonObject
            .getValue("days").jsonArray
        assertThat(outputDays).hasSize(2)
        outputDays.forEach { value ->
            val rendered = value.jsonObject
            val document = rendered.getValue("profile_documents").jsonObject.getValue("json_root").jsonObject
            assertThat(document.getValue("value_type").jsonPrimitive.content).isEqualTo("object")
        }
        for (invalid in listOf(
            emptyMap(), captured - "2026-07-26",
            captured + ("2026-07-27" to day.copy(date = day.date.plusDays(2))),
            captured + ("2026-07-26" to day),
        )) {
            val failure = assertThrows(HealthMdRenderInputAdapter.AdapterException::class.java) { encode(invalid) }
            assertThat(failure.message).isEqualTo("wake-date native days are incompatible")
            assertThat(failure.cause).isNull()
        }
    }

    private fun successorResult(): ByteArray {
        val old = Json.parseToJsonElement(semanticResult().decodeToString()).jsonObject
        return JsonObject(old.toMutableMap().apply {
            put("semantic_input_version", JsonPrimitive(2))
            put("canonical_model_version", JsonPrimitive(2))
            put("core_api_version", JsonPrimitive(4))
            put("registry_sha256", JsonPrimitive(HEALTHMD_SLEEP_REGISTRY_SHA256))
            put("profile", JsonPrimitive("android_sleep_v6"))
            put("sleep_capture_context", Json.parseToJsonElement("""
                {"schema_profile":"android-sleep-v6","calendar_timezone":"UTC", "sleep_day_attribution":"morning_ends", "sleep_owner_day_rule":"session_end_date", "sleep_interval_clipping":"none"}
            """.trimIndent()))
        }).toString().encodeToByteArray()
    }

    private fun semanticResult(): ByteArray = """
        {"schema":"healthmd.semantic_result","semantic_input_version":1,"canonical_model_version":1,"core_api_version":3,"registry_sha256":"$HEALTHMD_CORE_REGISTRY_SHA256","profile_revision":1,"session_id":"android-render-session","profile":"android_frozen_v4","state":"completed","next_batch_index":1,"records_accepted":1,"records_filtered":0,"days":[{"owner_date":"2026-07-25","values":[{"output_key":"steps","semantic_id":"steps","aggregation":"sum","value":{"value_type":"number","number":{"representation":"unsigned_integer","decimal":"1234"},"unit":{"id":"count"}},"source_record_ids":["record-1"]}]}],"rollups":[],"retained_extensions":[]}
    """.trimIndent().encodeToByteArray()

    private fun registry(): CoreMetricRegistrySnapshot = CoreMetricRegistrySnapshot(
        registryVersion = 1u,
        registrySha256 = HEALTHMD_CORE_REGISTRY_SHA256,
        profileId = "android_frozen_v4",
        publicProfileId = "android-frozen-v4",
        publicSchema = "healthmd.health_data",
        publicSchemaVersion = 4u,
        profileRevision = 1u,
        categories = emptyList(),
        metrics = listOf(
            CoreRegistryMetric(
                semanticId = "steps", selectionId = "steps", labelKey = "steps", referenceName = "Steps",
                categoryId = "activity", unit = "count", kind = "quantity", sourceAggregation = "sum",
                defaultEnabled = true, archiveOnly = false, availabilityKey = "steps", authorizationKey = "steps",
                capabilityId = "export.metric-registry", sourceSelector = "steps", relatedSemanticIds = emptyList(), ordinal = 0u,
            ),
        ),
        unavailableMetrics = emptyList(),
        outputs = listOf(
            CoreRegistryOutput(
                selectionIds = listOf("steps"), surface = "flat", key = "steps", unit = "count",
                dailyAggregation = "sum", rollup = "sum", aliasKind = "none", platformNative = false,
                condition = "default", enabledByDefault = true, ordinal = 0u,
            ),
        ),
    )
}
