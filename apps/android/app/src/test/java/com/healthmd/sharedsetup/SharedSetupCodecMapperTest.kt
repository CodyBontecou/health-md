package com.healthmd.sharedsetup

import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.MetricSelectionState
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class SharedSetupCodecMapperTest {
    private val json = Json { ignoreUnknownKeys = true; explicitNulls = true }
    private val registry = FixtureMetricRegistry()
    private val codec = SharedSetupCodec(registry)
    private val mapper = SharedSetupMapper(registry)

    @Test
    fun canonicalCrossLanguageFixtureDecodesAndMapsExactSupportedSettings() {
        val bytes = fixtureFile().readBytes()
        val decoded = codec.decode(bytes)
        assertTrue(decoded is SharedSetupDecodeResult.Valid)
        val document = (decoded as SharedSetupDecodeResult.Valid).document
        val current = ExportSettings.newInstallDefaults().copy(
            apiEndpointUrl = "https://existing.invalid/keep",
            metricSelection = MetricSelectionState(setOf("old_selection")),
        )

        val preview = mapper.preview(document, current)

        assertEquals(
            setOf("active_calories", "bp_systolic", "avg_hr", "sleep_light", "steps"),
            preview.candidate.metricSelection.enabledMetrics,
        )
        assertFalse(preview.candidate.scheduleEnabled)
        assertEquals("https://existing.invalid/keep", preview.candidate.apiEndpointUrl)
        assertEquals("https://setup.invalid:8443/synthetic/health", preview.pendingEndpoint)
        assertTrue(preview.review.items.none { it.status == SharedSetupCompatibilityStatus.INVALID })
        assertTrue(preview.review.items.any {
            it.title == "Metrics unavailable" && it.status == SharedSetupCompatibilityStatus.REQUIRES_ACTION
        })
        assertEquals(document.profile.presentation.markdown.customText, preview.candidate.formatCustomization.markdownTemplate.customTemplate)
    }

    @Test
    fun androidOriginFixturePreservesExplicitNativeDefaultsAndDistinctMetricIdentity() {
        val decoded = codec.decode(fixtureFile("android-shared-setup-v1.json").readBytes())
        assertTrue(decoded is SharedSetupDecodeResult.Valid)
        val document = (decoded as SharedSetupDecodeResult.Valid).document
        val preview = mapper.preview(document, ExportSettings.newInstallDefaults())

        assertEquals("android", document.createdBy.platform)
        assertTrue(preview.candidate.dailyNoteInjection.createIfMissing)
        assertEquals("{metric}-{date}-{time}", preview.candidate.individualTracking.filenameTemplate)
        assertEquals(6, preview.candidate.scheduleHour)
        assertEquals(setOf("hrv", "steps"), preview.candidate.metricSelection.enabledMetrics)

        val roundTrip = codec.decode(
            codec.encode(mapper.export(preview.candidate, document.platformExtensions.apple))
        ) as SharedSetupDecodeResult.Valid
        assertTrue(roundTrip.document.platformExtensions.android != null)
        assertEquals(document.platformExtensions.apple, roundTrip.document.platformExtensions.apple)
    }

    @Test
    fun codecToleratesBoundedUnknownFieldsButRejectsFutureVersionSensitiveDataAndUnsafePaths() {
        val root = fixtureObject()
        val withUnknown = JsonObject(root + ("future_optional" to JsonObject(mapOf("bounded" to JsonPrimitive(true)))))
        assertTrue(codec.decode(json.encodeToString(JsonObject.serializer(), withUnknown).encodeToByteArray()) is SharedSetupDecodeResult.Valid)

        val future = root.replacing(listOf("schema_version"), JsonPrimitive(2))
        assertTrue(codec.decode(future.encoded()) is SharedSetupDecodeResult.Invalid)

        val sensitive = JsonObject(root + ("future_optional" to JsonPrimitive("Bearer synthetic-secret")))
        assertTrue(codec.decode(sensitive.encoded()) is SharedSetupDecodeResult.Invalid)

        val metrics = root.path("profile", "metrics").jsonObject
        val categoryAuthority = root.replacing(
            listOf("profile", "metrics"),
            JsonObject(metrics + ("enabled_categories" to JsonArray(listOf(JsonPrimitive("activity"))))),
        )
        assertTrue(codec.decode(categoryAuthority.encoded()) is SharedSetupDecodeResult.Invalid)

        val traversal = root.replacing(
            listOf("profile", "export", "folder_template"),
            JsonPrimitive("../escape"),
        )
        assertTrue(codec.decode(traversal.encoded()) is SharedSetupDecodeResult.Invalid)
        assertTrue(codec.decode(ByteArray(SHARED_SETUP_MAX_BYTES + 1)) is SharedSetupDecodeResult.Invalid)
    }

    @Test
    fun duplicateAliasRowsAreRejectedWithoutCrashing() {
        val root = fixtureObject()
        val aliases = root.getValue("metric_aliases").jsonArray
        val duplicate = root.replacing(listOf("metric_aliases"), JsonArray(aliases + aliases.first()))

        assertTrue(codec.decode(duplicate.encoded()) is SharedSetupDecodeResult.Invalid)
    }

    @Test
    fun malformedOrUnsupportedTemplateIsReviewableAndDoesNotReplaceLocalTemplate() {
        val malformed = fixtureObject().replacing(
            listOf("profile", "presentation", "markdown", "custom_text"),
            JsonPrimitive("{{#sleep}}not closed"),
        )
        val decoded = codec.decode(malformed.encoded())
        assertTrue(decoded is SharedSetupDecodeResult.Valid)
        val current = ExportSettings.newInstallDefaults()
        val preview = mapper.preview((decoded as SharedSetupDecodeResult.Valid).document, current)

        assertEquals(current.formatCustomization.markdownTemplate, preview.candidate.formatCustomization.markdownTemplate)
        assertTrue(preview.review.items.any { it.title == "Template needs review" && it.status == SharedSetupCompatibilityStatus.REQUIRES_ACTION })
    }

    @Test
    fun unsupportedScheduleIsNeverApproximated() {
        val unsupported = fixtureObject()
            .replacing(listOf("profile", "schedule", "cadence", "value"), JsonPrimitive(2))
            .replacing(listOf("profile", "schedule", "cadence", "unit"), JsonPrimitive("months"))
            .replacing(listOf("platform_extensions", "apple", "schedule", "frequency"), JsonPrimitive("custom"))
            .replacing(listOf("platform_extensions", "apple", "schedule", "custom_unit"), JsonPrimitive("months"))
        val document = (codec.decode(unsupported.encoded()) as SharedSetupDecodeResult.Valid).document
        val current = ExportSettings.newInstallDefaults().copy(
            scheduleCadenceValue = 7,
            scheduleHour = 4,
            scheduleMinute = 45,
        )

        val preview = mapper.preview(document, current)

        assertFalse(preview.candidate.scheduleEnabled)
        assertEquals(7, preview.candidate.scheduleCadenceValue)
        assertEquals(4, preview.candidate.scheduleHour)
        assertEquals(45, preview.candidate.scheduleMinute)
        assertTrue(preview.review.items.any {
            it.title == "Schedule will remain off" && it.detail.contains("cannot be represented exactly")
        })
    }

    @Test
    fun subFifteenMinuteScheduleIsNeverApproximated() {
        val tooFrequent = fixtureObject("android-shared-setup-v1.json")
            .replacing(listOf("profile", "schedule", "cadence", "value"), JsonPrimitive(1))
            .replacing(listOf("profile", "schedule", "cadence", "unit"), JsonPrimitive("minutes"))
        val document = (codec.decode(tooFrequent.encoded()) as SharedSetupDecodeResult.Valid).document
        val current = ExportSettings.newInstallDefaults().copy(scheduleCadenceValue = 7, scheduleHour = 4)

        val preview = mapper.preview(document, current)

        assertEquals(7, preview.candidate.scheduleCadenceValue)
        assertEquals(4, preview.candidate.scheduleHour)
        assertTrue(preview.review.items.any { it.title == "Schedule will remain off" })
    }

    @Test
    fun unknownFutureMetricIsSkippedWhileSupportedExactSelectionsStillApply() {
        val root = fixtureObject()
            .replacing(listOf("metric_registry", "registry_sha256"), JsonPrimitive("0".repeat(64)))
        val ids = root.path("profile", "metrics", "enabled_ids").jsonArray + JsonPrimitive("future_metric")
        val futureAlias = JsonObject(
            mapOf(
                "semantic_id" to JsonPrimitive("future_metric"),
                "equivalence" to JsonPrimitive("platform_exact_or_unavailable"),
                "apple_selection_id" to kotlinx.serialization.json.JsonNull,
                "android_selection_id" to JsonPrimitive("future_metric"),
            )
        )
        val aliases = root.getValue("metric_aliases").jsonArray + futureAlias
        val candidateRoot = root
            .replacing(listOf("profile", "metrics", "enabled_ids"), JsonArray(ids.sortedBy { (it as JsonPrimitive).content }))
            .replacing(listOf("metric_aliases"), JsonArray(aliases.sortedBy { it.jsonObject.getValue("semantic_id").toString() }))
        val decoded = codec.decode(candidateRoot.encoded())
        assertTrue(decoded is SharedSetupDecodeResult.Valid)

        val preview = mapper.preview(
            (decoded as SharedSetupDecodeResult.Valid).document,
            ExportSettings.newInstallDefaults().copy(metricSelection = MetricSelectionState(setOf("old_selection"))),
        )

        assertEquals(
            setOf("active_calories", "bp_systolic", "avg_hr", "sleep_light", "steps"),
            preview.candidate.metricSelection.enabledMetrics,
        )
        assertTrue(preview.review.items.any { it.title == "Metrics unavailable" })
    }

    @Test
    fun registryDriftUsesCurrentLocalMappingButStillRejectsMalformedAliasIds() {
        val drifted = fixtureObject()
            .replacing(listOf("metric_registry", "registry_sha256"), JsonPrimitive("0".repeat(64)))
        val aliases = drifted.getValue("metric_aliases").jsonArray.map { element ->
            val alias = element.jsonObject
            if (alias.getValue("semantic_id").toString().contains("active_energy")) {
                JsonObject(alias + ("android_selection_id" to JsonPrimitive("historical_active_energy")))
            } else element
        }
        val document = (codec.decode(drifted.replacing(listOf("metric_aliases"), JsonArray(aliases)).encoded()) as SharedSetupDecodeResult.Valid).document

        val preview = mapper.preview(document, ExportSettings.newInstallDefaults())

        assertTrue("active_calories" in preview.candidate.metricSelection.enabledMetrics)

        val malformed = JsonObject(aliases.first().jsonObject + ("android_selection_id" to JsonPrimitive("not/a/valid/id")))
        val malformedAliases = listOf(malformed) + aliases.drop(1)
        assertTrue(
            codec.decode(drifted.replacing(listOf("metric_aliases"), JsonArray(malformedAliases)).encoded()) is SharedSetupDecodeResult.Invalid
        )
    }

    @Test
    fun androidWriterDoesNotFabricateAppleExtensionDefaults() {
        val document = mapper.export(ExportSettings.newInstallDefaults())

        assertEquals(null, document.platformExtensions.apple)
        assertTrue(document.platformExtensions.android != null)
        codec.encode(document)
    }

    @Test
    fun absentForeignAndroidExtensionPreservesCurrentAndroidOnlySettings() {
        val withoutAndroid = fixtureObject().replacing(
            listOf("platform_extensions", "android"),
            JsonNull,
        )
        val document = (codec.decode(withoutAndroid.encoded()) as SharedSetupDecodeResult.Valid).document
        val defaults = ExportSettings.newInstallDefaults()
        val current = defaults.copy(
            subfolder = "keep/android",
            folderOrganization = FolderOrganization.BY_YEAR,
            formatCustomization = defaults.formatCustomization.copy(includeLegacyAndroidAliases = true),
        )

        val candidate = mapper.preview(document, current).candidate

        assertEquals("keep/android", candidate.subfolder)
        assertEquals(FolderOrganization.BY_YEAR, candidate.folderOrganization)
        assertTrue(candidate.formatCustomization.includeLegacyAndroidAliases)
    }

    @Test
    fun writerRejectsSensitiveMaterialHiddenInCustomContent() {
        val defaults = ExportSettings.newInstallDefaults()
        val settings = defaults.copy(
            formatCustomization = defaults.formatCustomization.copy(
                frontmatterConfig = defaults.formatCustomization.frontmatterConfig.copy(
                    customFields = mapOf("family_note" to "Bearer synthetic-secret")
                )
            )
        )

        assertThrows(IllegalArgumentException::class.java) {
            codec.encode(mapper.export(settings))
        }
    }

    @Test
    fun androidWriterStripsEndpointQueryEmitsNoCredentialsAndPreservesAppleExtension() {
        val fixture = (codec.decode(fixtureFile().readBytes()) as SharedSetupDecodeResult.Valid).document
        val settings = ExportSettings.newInstallDefaults().copy(
            apiEndpointUrl = "https://synthetic-user:synthetic-pass@family.invalid:9443/health?tenant=private#fragment",
            metricSelection = MetricSelectionState(setOf("steps")),
        )

        val exported = mapper.export(settings, fixture.platformExtensions.apple)
        val encoded = codec.encode(exported)
        val decoded = (codec.decode(encoded) as SharedSetupDecodeResult.Valid).document

        assertEquals("family.invalid", decoded.profile.apiEndpoint?.host)
        assertEquals("/health", decoded.profile.apiEndpoint?.path)
        assertTrue(decoded.profile.apiEndpoint?.queryOmitted == true)
        assertEquals(fixture.platformExtensions.apple, decoded.platformExtensions.apple)
        val text = encoded.decodeToString()
        assertFalse(text.contains("tenant=private"))
        assertFalse(text.contains("synthetic-user"))
        assertFalse(text.contains("synthetic-pass"))
        assertFalse(text.contains("fragment"))
        assertFalse(text.contains("authorization", ignoreCase = true))
        assertArrayEquals(encoded, codec.encode(decoded))
    }

    private fun JsonObject.encoded(): ByteArray =
        json.encodeToString(JsonObject.serializer(), this).encodeToByteArray()

    private fun fixtureObject(name: String = "shared-setup-v1.json"): JsonObject =
        json.parseToJsonElement(fixtureFile(name).readText()).jsonObject

    private fun fixtureFile(name: String = "shared-setup-v1.json"): File {
        var directory = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (true) {
            val candidate = File(directory, "packages/contracts/shared-setup/v1/fixtures/$name")
            if (candidate.isFile) return candidate
            directory = directory.parentFile ?: error("Could not locate the shared-setup canonical fixture")
        }
    }

    private fun JsonObject.replacing(path: List<String>, value: JsonElement): JsonObject {
        require(path.isNotEmpty())
        val key = path.first()
        val replacement = if (path.size == 1) value else {
            getValue(key).jsonObject.replacing(path.drop(1), value)
        }
        return JsonObject(toMutableMap().apply { this[key] = replacement })
    }

    private fun JsonObject.path(vararg keys: String): JsonElement =
        keys.fold(this as JsonElement) { value, key -> value.jsonObject.getValue(key) }

    private class FixtureMetricRegistry : SharedSetupMetricRegistry {
        override val version: Int = 1
        override val sha256: String = "4597c2f197c25e6e6a0ec1976e3b5de930edffa2ca61fd4779d47b465075bae2"
        private val bindings = listOf(
            SharedSetupRegistryBinding("android.hrv_rmssd", null, "hrv", "platform_distinct"),
            SharedSetupRegistryBinding("active_energy", "active_energy", "active_calories", "mapped_alias"),
            SharedSetupRegistryBinding("blood_pressure_systolic", "blood_pressure_systolic", "bp_systolic", "mapped_alias"),
            SharedSetupRegistryBinding("heart_rate_avg", "heart_rate_avg", "avg_hr", "mapped_alias"),
            SharedSetupRegistryBinding("hrv", "hrv", null, "platform_exact_or_unavailable"),
            SharedSetupRegistryBinding("sleep_core", "sleep_core", "sleep_light", "mapped_alias"),
            SharedSetupRegistryBinding("steps", "steps", "steps", "platform_exact_or_unavailable"),
        )
        override val bySemanticId = bindings.associateBy { it.semanticId }
        override val byAndroidSelectionId = bindings.mapNotNull { binding ->
            binding.androidSelectionId?.let { it to binding }
        }.toMap()
    }
}
