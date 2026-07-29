package com.healthmd.domain.render

import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.CoreRegistryMetric
import com.healthmd.core.CoreRegistryOutput
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.UnitPreference
import com.healthmd.export.ExportSignatureFixtures
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import org.junit.Assert.assertArrayEquals
import org.junit.Test

/**
 * Freezes adapter requests and independent production-renderer bytes for Rust parity replay.
 * The expected bytes come only from the shipped native exporters, never from Rust.
 */
class NativeRenderRequestFixtureTest {
    private val json = Json { explicitNulls = true }

    @Test
    fun androidRenderRequestsAndNativeBytesMatchFrozenFixture() {
        val root = repositoryRoot()
        val fixture = fixtureBytes(root)
        val path = root.resolve("packages/contracts/render-input/v1/fixtures/native-android-render-requests-v1.json")
        if (System.getenv("HEALTHMD_UPDATE_M5_ANDROID_FULL_REQUEST_FIXTURE") == "1") {
            Files.write(path, fixture)
            return
        }
        check(Files.exists(path)) { "Missing immutable Android full render-request fixture" }
        assertArrayEquals(
            "Android render request/native renderer fixture drifted; review adapter and public bytes",
            Files.readAllBytes(path),
            fixture,
        )
    }

    private fun fixtureBytes(root: Path): ByteArray {
        val registryRoot = json.parseToJsonElement(
            Files.readAllBytes(root.resolve("packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json")).decodeToString(),
        ).jsonObject
        val cases = listOf(
            RenderCase("frozen-default", FormatCustomization(), false),
            RenderCase(
                "frozen-legacy-native-granular",
                FormatCustomization(
                    includeLegacyAndroidAliases = true,
                    includeAndroidNativeFields = true,
                    compatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
                ),
                true,
            ),
            RenderCase("analytical-v5-granular", FormatCustomization.analyticalDefault(), true),
            RenderCase(
                "analytical-v5-imperial",
                FormatCustomization.analyticalDefault().copy(unitPreference = UnitPreference.IMPERIAL),
                false,
            ),
        )
        val encodedCases = cases.map { renderCase ->
            val profile = when (renderCase.customization.compatibilitySchemaProfile) {
                CompatibilitySchemaProfile.IOS_V4_FROZEN -> "android_frozen_v4"
                CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> "android_analytical_v5"
            }
            val registry = registry(registryRoot, profile)
            val semantic = semanticResult(registry, renderCase.customization)
            val requestId = "native-android-render-${renderCase.id}"
            val encoded = HealthMdRenderInputAdapter.encode(
                semanticResult = semantic,
                registry = registry,
                calendarTimeZone = "UTC",
                options = HealthMdRenderInputAdapter.Options(
                    requestId = requestId,
                    formats = listOf("markdown", "obsidian_bases", "json", "csv"),
                    includeGranularData = renderCase.granular,
                ),
                presentationByOwnerDate = mapOf("2026-03-15" to ExportSignatureFixtures.syntheticDay),
                presentationCustomization = renderCase.customization,
            )
            val data = ExportSignatureFixtures.syntheticDay
            val expected = listOf(
                ExpectedOutput(
                    "markdown",
                    "health/2026-03-15.md",
                    "text/markdown; charset=utf-8",
                    MarkdownExporter().export(data, true, true, renderCase.customization, renderCase.granular),
                ),
                ExpectedOutput(
                    "obsidian_bases",
                    "health/2026-03-15-bases.md",
                    "text/markdown; charset=utf-8",
                    ObsidianBasesExporter().export(data, renderCase.customization),
                ),
                ExpectedOutput(
                    "json",
                    "health/2026-03-15.json",
                    "application/json",
                    JsonExporter().export(data, renderCase.customization, renderCase.granular),
                ),
                ExpectedOutput(
                    "csv",
                    "health/2026-03-15.csv",
                    "text/csv; charset=utf-8",
                    CsvExporter().export(data, renderCase.customization, renderCase.granular),
                ),
            )
            buildJsonObject {
                put("id", renderCase.id)
                put("profile", profile)
                put("semantic_result", json.parseToJsonElement(semantic.decodeToString()))
                put("configuration", json.parseToJsonElement(encoded.configuration.decodeToString()))
                put("batches", JsonArray(encoded.batches.map { json.parseToJsonElement(it.decodeToString()) }))
                put("expected_outputs", buildJsonArray {
                    expected.forEach { output ->
                        val bytes = output.content.encodeToByteArray()
                        add(buildJsonObject {
                            put("format", output.format)
                            put("relative_path", output.relativePath)
                            put("media_type", output.mediaType)
                            put("bytes_base64", Base64.getEncoder().encodeToString(bytes))
                            put("byte_count", bytes.size)
                            put("sha256", sha256(bytes))
                        })
                    }
                })
            }
        }
        val fixture = buildJsonObject {
            put("schema", "healthmd.native_render_requests")
            put("schema_version", 1)
            put("render_input_version", 1)
            put("artifact_plan_version", 1)
            put("cases", JsonArray(encodedCases))
        }
        return (Json.encodeToString(JsonObject.serializer(), fixture) + "\n").encodeToByteArray()
    }

    private fun registry(root: JsonObject, profileId: String): CoreMetricRegistrySnapshot {
        val profile = root.getValue("profiles").jsonArray
            .map(JsonElement::jsonObject)
            .single { it.getValue("id").jsonPrimitive.content == profileId }
        val orderedSelections = profile.getValue("ordered_selection_ids").jsonArray
            .map { it.jsonPrimitive.content }
            .toSet()
        val metrics = root.getValue("metrics").jsonArray.mapNotNull { element ->
            val row = element.jsonObject
            val android = row["android"]?.jsonObject ?: return@mapNotNull null
            val selectionId = android["selection_id"]?.jsonPrimitive?.contentOrNull ?: return@mapNotNull null
            if (selectionId !in orderedSelections || android["status"]?.jsonPrimitive?.content != "backed") {
                return@mapNotNull null
            }
            CoreRegistryMetric(
                semanticId = row.getValue("semantic_id").jsonPrimitive.content,
                selectionId = selectionId,
                labelKey = android.getValue("label_key").jsonPrimitive.content,
                referenceName = row.getValue("reference_name").jsonPrimitive.content,
                categoryId = android.getValue("category_id").jsonPrimitive.content,
                unit = android.getValue("unit").jsonPrimitive.content,
                kind = "captured",
                sourceAggregation = android.getValue("source_aggregation").jsonPrimitive.content,
                defaultEnabled = android.getValue("default_enabled").jsonPrimitive.content.toBoolean(),
                archiveOnly = false,
                availabilityKey = android.getValue("availability_key").jsonPrimitive.content,
                authorizationKey = "health_connect",
                capabilityId = row.getValue("capability_id").jsonPrimitive.content,
                sourceSelector = selectionId,
                relatedSemanticIds = android["related_semantic_ids"]?.jsonArray?.map { it.jsonPrimitive.content }.orEmpty(),
                ordinal = android.getValue("ordinal").jsonPrimitive.content.toUInt(),
            )
        }
        val outputs = profile.getValue("outputs").jsonArray.mapIndexed { ordinal, element ->
            val output = element.jsonObject
            CoreRegistryOutput(
                selectionIds = output.getValue("selection_ids").jsonArray.map { it.jsonPrimitive.content },
                surface = output.getValue("surface").jsonPrimitive.content,
                key = output.getValue("key").jsonPrimitive.content,
                unit = output["unit"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                dailyAggregation = output["daily_aggregation"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                rollup = output["rollup"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                aliasKind = output.getValue("alias_kind").jsonPrimitive.content,
                platformNative = output.getValue("platform_native").jsonPrimitive.content.toBoolean(),
                condition = output.getValue("condition").jsonPrimitive.content,
                enabledByDefault = output.getValue("enabled_by_default").jsonPrimitive.content.toBoolean(),
                ordinal = ordinal.toUInt(),
            )
        }
        return CoreMetricRegistrySnapshot(
            registryVersion = root.getValue("registry_version").jsonPrimitive.content.toUInt(),
            registrySha256 = com.healthmd.domain.model.HEALTHMD_CORE_REGISTRY_SHA256,
            profileId = profileId,
            publicProfileId = profile.getValue("public_profile_id").jsonPrimitive.content,
            publicSchema = profile.getValue("public_schema").jsonPrimitive.content,
            publicSchemaVersion = profile.getValue("public_schema_version").jsonPrimitive.content.toUInt(),
            profileRevision = profile.getValue("profile_revision").jsonPrimitive.content.toUInt(),
            categories = emptyList(),
            metrics = metrics,
            unavailableMetrics = emptyList(),
            outputs = outputs,
        )
    }

    private fun semanticResult(
        registry: CoreMetricRegistrySnapshot,
        customization: FormatCustomization,
    ): ByteArray {
        val metricsBySelection = registry.metrics.associateBy { it.selectionId }
        val outputsByKey = registry.outputs.associateBy { it.key }
        val fields = HealthDataFields.extract(
            ExportSignatureFixtures.syntheticDay,
            customization.unitConverter,
            customization.timeFormat,
            customization.includeLegacyAndroidAliases,
            customization.includeAndroidNativeFields,
        ).filter { it.value != null && outputsByKey[it.key] != null }
        val values = fields.mapIndexed { ordinal, field ->
            val output = outputsByKey.getValue(field.key)
            val semanticId = output.selectionIds.firstNotNullOf(metricsBySelection::get).semanticId
            buildJsonObject {
                put("output_key", field.key)
                put("semantic_id", semanticId)
                put("aggregation", output.dailyAggregation.ifEmpty { "pass_through" })
                put("value", semanticValue(field.value!!, field.unit))
                put("source_record_ids", buildJsonArray { add(JsonPrimitive("native-$ordinal")) })
            }
        }
        val root = buildJsonObject {
            put("schema", "healthmd.semantic_result")
            put("semantic_input_version", 1)
            put("canonical_model_version", 1)
            put("core_api_version", 3)
            put("registry_sha256", registry.registrySha256)
            put("profile_revision", registry.profileRevision.toInt())
            put("session_id", "native-android-bases-${registry.profileId}")
            put("profile", registry.profileId)
            put("state", "completed")
            put("next_batch_index", 1)
            put("records_accepted", values.size)
            put("records_filtered", 0)
            put("days", buildJsonArray {
                add(buildJsonObject {
                    put("owner_date", "2026-03-15")
                    put("values", JsonArray(values))
                })
            })
            put("rollups", buildJsonArray {})
            put("retained_extensions", buildJsonArray {})
        }
        return json.encodeToString(JsonObject.serializer(), root).encodeToByteArray()
    }

    private fun semanticValue(value: Any, unit: String): JsonObject = when (value) {
        is Byte, is Short, is Int, is Long -> buildJsonObject {
            put("value_type", "number")
            put("number", buildJsonObject {
                put("representation", "signed_integer")
                put("decimal", value.toString())
            })
            put("unit", buildJsonObject { put("id", unit.ifEmpty { "unitless" }) })
        }
        is Float, is Double -> {
            val double = (value as Number).toDouble()
            buildJsonObject {
                put("value_type", "number")
                put("number", buildJsonObject {
                    put("representation", "binary64")
                    put("bits", java.lang.Long.toUnsignedString(double.toRawBits(), 16).padStart(16, '0'))
                })
                put("unit", buildJsonObject { put("id", unit.ifEmpty { "unitless" }) })
            }
        }
        is Boolean -> buildJsonObject { put("value_type", "boolean"); put("boolean", value) }
        else -> buildJsonObject { put("value_type", "text"); put("text", value.toString()) }
    }

    private fun sha256(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256")
        .digest(bytes)
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    private fun repositoryRoot(): Path {
        var candidate = Path.of(System.getProperty("user.dir")).toAbsolutePath()
        while (!Files.isDirectory(candidate.resolve("packages/contracts"))) {
            candidate = candidate.parent ?: error("repository root is unavailable")
        }
        return candidate
    }

    private data class RenderCase(
        val id: String,
        val customization: FormatCustomization,
        val granular: Boolean,
    )

    private data class ExpectedOutput(
        val format: String,
        val relativePath: String,
        val mediaType: String,
        val content: String,
    )
}
