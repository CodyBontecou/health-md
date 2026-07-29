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
