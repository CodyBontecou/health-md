package com.healthmd.export

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.UnitPreference
import java.nio.file.Files
import java.nio.file.Path
import java.security.MessageDigest
import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertArrayEquals
import org.junit.Test

/** Exact native byte oracle captured before the M5 Rust renderer becomes authoritative. */
class NativeRendererGoldenFixtureTest {
    private val jsonExporter = JsonExporter()
    private val csvExporter = CsvExporter()
    private val markdownExporter = MarkdownExporter()
    private val basesExporter = ObsidianBasesExporter()

    @Test
    fun nativeAndroidRendererBytesMatchFrozenFixture() {
        val current = fixtureBytes()
        val path = repositoryRoot().resolve("packages/contracts/render-input/v1/fixtures/native-android-v4-v5.json")
        check(Files.exists(path)) { "Missing immutable Android v4/v5 renderer golden" }
        assertArrayEquals(
            "Android v4/v5 renderer bytes drifted; add a new public profile instead of rewriting this oracle",
            Files.readAllBytes(path),
            current,
        )
    }

    private fun fixtureBytes(): ByteArray {
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
        val root = buildJsonObject {
            put("schema", "healthmd.native_renderer_goldens")
            put("schema_version", 1)
            put("profiles", buildJsonArray {
                add(JsonPrimitive("android-frozen-v4"))
                add(JsonPrimitive("android-analytical-v5"))
            })
            put("public_schema", "healthmd.health_data")
            put("cases", buildJsonArray {
                for (renderCase in cases) add(renderCaseObject(renderCase))
            })
        }
        return (Json.encodeToString(JsonObject.serializer(), root) + "\n").encodeToByteArray()
    }

    private fun renderCaseObject(renderCase: RenderCase): JsonObject {
        val data = ExportSignatureFixtures.syntheticDay
        val customization = renderCase.customization
        val outputs = listOf(
            Output(
                "markdown",
                "text/markdown; charset=utf-8",
                markdownExporter.export(data, true, true, customization, renderCase.granular),
            ),
            Output("obsidian_bases", "text/markdown; charset=utf-8", basesExporter.export(data, customization)),
            Output("json", "application/json", jsonExporter.export(data, customization, renderCase.granular)),
            Output("csv", "text/csv; charset=utf-8", csvExporter.export(data, customization, renderCase.granular)),
        )
        return buildJsonObject {
            put("id", renderCase.id)
            put("profile", when (customization.compatibilitySchemaProfile) {
                CompatibilitySchemaProfile.IOS_V4_FROZEN -> "android-frozen-v4"
                CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> "android-analytical-v5"
            })
            put("granular", renderCase.granular)
            put("outputs", JsonArray(outputs.map(::outputObject)))
        }
    }

    private fun outputObject(output: Output): JsonObject {
        val bytes = output.content.encodeToByteArray()
        return buildJsonObject {
            put("format", output.format)
            put("media_type", output.mediaType)
            put("byte_count", bytes.size)
            put("sha256", MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 0xff) })
            put("bytes_base64", Base64.getEncoder().encodeToString(bytes))
        }
    }

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

    private data class Output(
        val format: String,
        val mediaType: String,
        val content: String,
    )
}
