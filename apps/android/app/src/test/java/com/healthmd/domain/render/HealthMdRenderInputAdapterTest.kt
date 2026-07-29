package com.healthmd.domain.render

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.CoreRegistryMetric
import com.healthmd.core.CoreRegistryOutput
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
