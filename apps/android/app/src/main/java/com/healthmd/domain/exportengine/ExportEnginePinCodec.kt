package com.healthmd.domain.exportengine

import com.healthmd.core.HealthMdCoreService
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.rawexport.ExportMode
import java.nio.charset.StandardCharsets
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** Bounded, deterministic JSON used only for durable native operation metadata. */
object ExportEnginePinCodec {
    const val MAX_CANONICAL_JSON_BYTES: Int = 4 * 1024

    private val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = false
        prettyPrint = false
    }

    fun encodeCanonical(pin: ExportEnginePin): String {
        require(isStructurallyValid(pin)) { "Export engine pin is not valid durable metadata." }
        val canonical = canonicalize(json.parseToJsonElement(json.encodeToString(pin))).toString()
        require(canonical.toByteArray(StandardCharsets.UTF_8).size <= MAX_CANONICAL_JSON_BYTES) {
            "Export engine pin metadata exceeds its durable size limit."
        }
        return canonical
    }

    /**
     * Strict durable decode. Unlike the compatibility enum serializer, an unknown stored engine is
     * rejected so a persisted shadow/Rust operation can never be reinterpreted as legacy.
     */
    fun decodeOrNull(raw: String?): ExportEnginePin? {
        if (raw.isNullOrEmpty() || raw.toByteArray(StandardCharsets.UTF_8).size > MAX_CANONICAL_JSON_BYTES) {
            return null
        }
        return runCatching {
            val objectValue = json.parseToJsonElement(raw).jsonObject
            val engineValue = objectValue["engine"]?.jsonPrimitive?.content
            require(engineValue in DURABLE_ENGINE_VALUES)
            val pin = json.decodeFromJsonElement(ExportEnginePin.serializer(), objectValue)
            require(isStructurallyValid(pin))
            pin
        }.getOrNull()
    }

    fun isStructurallyValid(pin: ExportEnginePin): Boolean =
        pin.publicSchema == ExportEnginePin.PUBLIC_SCHEMA &&
            pin.publicSchemaVersion == pin.profile.publicSchemaVersion &&
            pin.coreApiVersion > 0u &&
            pin.semanticInputVersion > 0u &&
            pin.canonicalModelVersion > 0u &&
            pin.renderInputVersion > 0u &&
            pin.artifactPlanVersion > 0u &&
            pin.registryVersion > 0u &&
            pin.registrySha256.isLowercaseSha256() &&
            pin.semanticProfileRevision > 0u &&
            pin.renderProfileRevision > 0u &&
            pin.coreSourceRevision.isNotBlank() &&
            pin.coreSourceRevision.length <= MAX_SOURCE_REVISION_CHARACTERS &&
            pin.ianaTimeZone.length <= MAX_TIME_ZONE_CHARACTERS &&
            pin.ianaTimeZone in ZoneId.getAvailableZoneIds()

    private fun canonicalize(element: JsonElement): JsonElement = when (element) {
        is JsonObject -> JsonObject(
            element.entries
                .sortedBy(Map.Entry<String, JsonElement>::key)
                .associate { (key, value) -> key to canonicalize(value) },
        )
        is JsonArray -> JsonArray(element.map(::canonicalize))
        else -> element
    }

    private val DURABLE_ENGINE_VALUES = ExportEngineMode.entries.mapTo(linkedSetOf()) { it.name }
    private const val MAX_SOURCE_REVISION_CHARACTERS = 256
    private const val MAX_TIME_ZONE_CHARACTERS = 128
}

/** Resolves policy exactly once while planning, before any provider values are captured. */
@Singleton
class ExportEnginePinPlanner @Inject constructor() {
    private val policyResolver by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        ExportEnginePolicyResolver()
    }
    private val coreService by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        HealthMdCoreService()
    }

    fun forScheduledExport(
        settings: ExportSettings,
        target: ExportTarget,
        zoneId: ZoneId,
    ): ExportEnginePin? {
        if (!supportsNewScheduledPin(settings, target)) return null
        val policy = if (target == ExportTarget.API_ENDPOINT) {
            // API v1 is permanently profile-frozen even when local files use analytical v5.
            policyResolver.resolveApiV1()
        } else {
            policyResolver.resolveLocal(settings.localExportProfile())
        }
        return pinBeforeCapture(policy, zoneId)
    }

    fun forDirectGeneratedFiles(settings: ExportSettings, zoneId: ZoneId): ExportEnginePin? {
        if (!supportsNewDirectGeneratedFilesPin(settings)) return null
        return pinBeforeCapture(policyResolver.resolveLocal(settings.localExportProfile()), zoneId)
    }

    fun forApiV1(zoneId: ZoneId): ExportEnginePin? =
        pinBeforeCapture(policyResolver.resolveApiV1(), zoneId)

    /** Pure metadata check for a persisted scheduled operation; this never resolves current policy. */
    fun persistedPinAppliesToScheduledExport(
        settings: ExportSettings,
        target: ExportTarget,
        pin: ExportEnginePin?,
    ): Boolean {
        if (pin == null) return true
        if (!supportsNewScheduledPin(settings, target)) return false
        val expectedProfile = if (target == ExportTarget.API_ENDPOINT) {
            AndroidExportProfile.android_frozen_v4
        } else {
            settings.localExportProfile()
        }
        return pin.profile == expectedProfile
    }

    private fun pinBeforeCapture(
        policy: ResolvedExportEnginePolicy,
        zoneId: ZoneId,
    ): ExportEnginePin? {
        if (policy.mode == ExportEngineMode.legacy) return null
        return try {
            val canonicalZone = ZoneId.of(zoneId.id).id
            val readiness = coreService.checkReadiness()
            if (!readiness.isReady) return null
            val registry = coreService.getMetricRegistry(policy.profile.coreProfile)
            ExportEnginePin.create(
                engine = policy.mode,
                profile = policy.profile,
                ianaTimeZone = canonicalZone,
                readiness = readiness,
                registry = registry,
            )
        } catch (error: Throwable) {
            if (error.isFatalExportEngineFailure()) throw error
            // Planning has not read provider values yet, so legacy is the only safe fallback point.
            null
        }
    }

    companion object {
        fun supportsNewScheduledPin(
            settings: ExportSettings,
            target: ExportTarget,
        ): Boolean = when (target) {
            ExportTarget.DEVICE_FOLDER ->
                AndroidDailyAggregateExportPlanner.supportsNonLegacy(settings)
            ExportTarget.API_ENDPOINT ->
                settings.exportMode == ExportMode.COMPATIBILITY &&
                    settings.selectedExportFormats.isNotEmpty()
            ExportTarget.GOOGLE_DRIVE ->
                AndroidDailyAggregateExportPlanner.supportsNonLegacy(
                    settings.copy(exportTarget = ExportTarget.DEVICE_FOLDER),
                )
        }

        fun supportsNewDirectGeneratedFilesPin(settings: ExportSettings): Boolean =
            AndroidDailyAggregateExportPlanner.supportsNonLegacy(settings)
    }

    private fun ExportSettings.localExportProfile(): AndroidExportProfile =
        when (formatCustomization.compatibilitySchemaProfile) {
            CompatibilitySchemaProfile.IOS_V4_FROZEN -> AndroidExportProfile.android_frozen_v4
            CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5 -> AndroidExportProfile.android_analytical_v5
        }
}
