package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Test

class ExportEnginePinTest {
    private val json = Json

    @Test
    fun compatiblePinRoundTripsWithExactStringEngineAndVersions() {
        val pin = testPin(
            mode = ExportEngineMode.rust,
            profile = AndroidExportProfile.android_analytical_v5,
        )

        val encoded = json.encodeToString(pin)
        val decoded = json.decodeFromString<ExportEnginePin>(encoded)

        assertThat(encoded).contains("\"engine\":\"rust\"")
        assertThat(encoded).contains("\"profile\":\"android_analytical_v5\"")
        assertThat(decoded).isEqualTo(pin)
        assertThat(
            ExportEnginePinValidator().validate(
                decoded,
                testReadiness(),
                testRegistry(AndroidExportProfile.android_analytical_v5),
            ).isCompatible,
        ).isTrue()
    }

    @Test
    fun successorPinSelectsIndependentV2ContractsWithoutRepinningHistoricalDefaults() {
        val registry = testRegistry(AndroidExportProfile.android_sleep_v6).copy(
            registryVersion = 2u,
            registrySha256 = "709df0ae9f583e82627bc5439c4385905a5d85000e4322a0384cfe96b35a8f78",
        )
        val readiness = testReadiness()
        val pin = ExportEnginePin.create(
            engine = ExportEngineMode.rust,
            profile = AndroidExportProfile.android_sleep_v6,
            ianaTimeZone = "America/Los_Angeles",
            readiness = readiness,
            registry = registry,
        )

        assertThat(pin.publicSchemaVersion).isEqualTo(6u)
        assertThat(pin.semanticInputVersion).isEqualTo(2u)
        assertThat(pin.canonicalModelVersion).isEqualTo(2u)
        assertThat(pin.renderInputVersion).isEqualTo(2u)
        assertThat(pin.artifactPlanVersion).isEqualTo(2u)
        assertThat(pin.registryVersion).isEqualTo(2u)
        assertThat(pin.registrySha256).isEqualTo(registry.registrySha256)
        assertThat(ExportEnginePinCodec.decodeOrNull(ExportEnginePinCodec.encodeCanonical(pin)))
            .isEqualTo(pin)
        assertThat(ExportEnginePinValidator().validate(pin, readiness, registry).isCompatible).isTrue()
        assertThat(readiness.buildInfo.registryVersion).isEqualTo(1u)
        assertThat(readiness.buildInfo.semanticInputVersion).isEqualTo(1u)
        assertThat(testPin().artifactPlanVersion).isEqualTo(1u)
    }

    @Test
    fun successorPinsRejectEveryLegacyHandoffAndCannotBorrowHistoricalRegistryAuthority() {
        val readiness = testReadiness()
        val registry = testRegistry(AndroidExportProfile.android_sleep_v6).copy(
            registryVersion = 2u,
            registrySha256 = "709df0ae9f583e82627bc5439c4385905a5d85000e4322a0384cfe96b35a8f78",
        )
        val pin = ExportEnginePin.create(
            engine = ExportEngineMode.rust,
            profile = AndroidExportProfile.android_sleep_v6,
            ianaTimeZone = "UTC",
            readiness = readiness,
            registry = registry,
        )
        val invalid = listOf(
            pin.copy(semanticInputVersion = 1u) to ExportEnginePinIssue.SEMANTIC_INPUT_VERSION,
            pin.copy(canonicalModelVersion = 1u) to ExportEnginePinIssue.CANONICAL_MODEL_VERSION,
            pin.copy(renderInputVersion = 1u) to ExportEnginePinIssue.RENDER_INPUT_VERSION,
            pin.copy(artifactPlanVersion = 1u) to ExportEnginePinIssue.ARTIFACT_PLAN_VERSION,
            pin.copy(registryVersion = 1u) to ExportEnginePinIssue.REGISTRY_VERSION,
        )
        for ((draft, issue) in invalid) {
            assertThat(ExportEnginePinValidator().validate(draft, readiness, registry).issues)
                .contains(issue)
            val encoded = json.encodeToString(draft)
            assertThat(ExportEnginePinCodec.decodeOrNull(encoded)).isNull()
        }
        for (engine in listOf(ExportEngineMode.legacy, ExportEngineMode.shadow)) {
            val fallback = pin.copy(engine = engine)
            assertThat(ExportEnginePinValidator().validate(fallback, readiness, registry).issues)
                .contains(ExportEnginePinIssue.ENGINE)
            assertThat(ExportEnginePinCodec.decodeOrNull(json.encodeToString(fallback))).isNull()
        }
        val historicalHash = pin.copy(registrySha256 = readiness.buildInfo.registrySha256)
        assertThat(ExportEnginePinValidator().validate(historicalHash, readiness, registry).issues)
            .contains(ExportEnginePinIssue.REGISTRY_SHA256)
        assertThat(ExportEnginePinValidator().validate(pin, readiness, testRegistry()).issues)
            .containsAtLeast(ExportEnginePinIssue.PROFILE, ExportEnginePinIssue.REGISTRY_VERSION)
    }

    @Test
    fun missingAndUnknownOldEngineValuesDecodeAsLegacy() {
        val pin = testPin(mode = ExportEngineMode.shadow)
        val encoded = json.parseToJsonElement(json.encodeToString(pin)).jsonObject

        val missing = JsonObject(encoded.toMutableMap().apply { remove("engine") })
        val unknown = JsonObject(encoded.toMutableMap().apply {
            put("engine", JsonPrimitive("future-engine"))
        })

        assertThat(json.decodeFromJsonElement(ExportEnginePin.serializer(), missing).engine)
            .isEqualTo(ExportEngineMode.legacy)
        assertThat(json.decodeFromJsonElement(ExportEnginePin.serializer(), unknown).engine)
            .isEqualTo(ExportEngineMode.legacy)

        val legacyEncoded = json.encodeToString(pin.copy(engine = ExportEngineMode.legacy))
        assertThat(legacyEncoded).contains("\"engine\":\"legacy\"")
    }

    @Test
    fun pinValidationRejectsReadinessRegistryVersionAndTimezoneDrift() {
        val readiness = testReadiness()
        val registry = testRegistry()
        val pin = testPin().copy(
            coreApiVersion = readiness.buildInfo.coreApiVersion + 1u,
            registrySha256 = "c".repeat(64),
            ianaTimeZone = "+05:30",
        )

        val result = ExportEnginePinValidator().validate(pin, readiness, registry)

        assertThat(result.isCompatible).isFalse()
        assertThat(result.issues).containsAtLeast(
            ExportEnginePinIssue.CORE_API_VERSION,
            ExportEnginePinIssue.REGISTRY_SHA256,
            ExportEnginePinIssue.IANA_TIME_ZONE,
        )

        val notReady = ExportEnginePinValidator().validate(
            testPin(),
            testReadiness(isReady = false),
            registry,
        )
        assertThat(notReady.issues).contains(ExportEnginePinIssue.CORE_NOT_READY)
    }

    @Test
    fun pinCreationRejectsMismatchedRegistryProfile() {
        val exception = org.junit.Assert.assertThrows(
            ExportEnginePinCompatibilityException::class.java,
        ) {
            ExportEnginePin.create(
                engine = ExportEngineMode.shadow,
                profile = AndroidExportProfile.android_frozen_v4,
                ianaTimeZone = "UTC",
                readiness = testReadiness(),
                registry = testRegistry(AndroidExportProfile.android_analytical_v5),
            )
        }

        assertThat(exception.compatibility.issues)
            .contains(ExportEnginePinIssue.PROFILE)
    }
}
