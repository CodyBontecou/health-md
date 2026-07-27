package com.healthmd.domain.exportengine

import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.HealthMdCoreReadiness
import com.healthmd.core.HealthMdCoreService
import java.time.ZoneId
import java.util.Collections
import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** Profile-scoped runtime authority. Wire values are deliberately lowercase and closed. */
@Serializable(with = ExportEngineModeSerializer::class)
enum class ExportEngineMode {
    legacy,
    shadow,
    rust;

    companion object {
        /** Unknown configuration and persisted values always fail closed. */
        fun fromWireValue(value: String?): ExportEngineMode = when (value) {
            "legacy" -> legacy
            "shadow" -> shadow
            "rust" -> rust
            else -> legacy
        }
    }
}

/** String serializer that keeps old journals readable after missing or unknown mode values. */
object ExportEngineModeSerializer : KSerializer<ExportEngineMode> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("com.healthmd.export_engine_mode", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: ExportEngineMode) {
        encoder.encodeString(value.name)
    }

    override fun deserialize(decoder: Decoder): ExportEngineMode =
        ExportEngineMode.fromWireValue(decoder.decodeString())
}

@Serializable
enum class AndroidExportProfile(
    internal val coreProfile: CoreMetricRegistryProfile,
    internal val publicProfileId: String,
    internal val publicSchemaVersion: UInt,
) {
    android_frozen_v4(
        CoreMetricRegistryProfile.ANDROID_FROZEN_V4,
        "android-frozen-v4",
        4u,
    ),
    android_analytical_v5(
        CoreMetricRegistryProfile.ANDROID_ANALYTICAL_V5,
        "android-analytical-v5",
        5u,
    ),
}

/**
 * Immutable, durable identity of every versioned input used by one export attempt.
 *
 * A decoded pin is data, not proof of compatibility. Call [ExportEnginePinValidator] before a
 * non-legacy engine is allowed to render it.
 */
@OptIn(ExperimentalSerializationApi::class)
@Serializable
data class ExportEnginePin(
    @EncodeDefault(EncodeDefault.Mode.ALWAYS)
    val engine: ExportEngineMode = ExportEngineMode.legacy,
    val profile: AndroidExportProfile,
    @SerialName("public_schema")
    val publicSchema: String,
    @SerialName("public_schema_version")
    val publicSchemaVersion: UInt,
    @SerialName("core_api_version")
    val coreApiVersion: UInt,
    @SerialName("semantic_input_version")
    val semanticInputVersion: UInt,
    @SerialName("canonical_model_version")
    val canonicalModelVersion: UInt,
    @SerialName("render_input_version")
    val renderInputVersion: UInt,
    @SerialName("artifact_plan_version")
    val artifactPlanVersion: UInt,
    @SerialName("registry_version")
    val registryVersion: UInt,
    @SerialName("registry_sha256")
    val registrySha256: String,
    @SerialName("semantic_profile_revision")
    val semanticProfileRevision: UInt,
    @SerialName("render_profile_revision")
    val renderProfileRevision: UInt,
    @SerialName("core_source_revision")
    val coreSourceRevision: String,
    /** Explicit IANA zone ID captured at planning time; never inferred during resume. */
    @SerialName("iana_time_zone")
    val ianaTimeZone: String,
) {
    companion object {
        const val PUBLIC_SCHEMA: String = "healthmd.health_data"
        const val EXPECTED_SEMANTIC_PROFILE_REVISION: UInt = 1u

        /** Creates a pin from already-fetched, compatible core evidence. */
        fun create(
            engine: ExportEngineMode,
            profile: AndroidExportProfile,
            ianaTimeZone: String,
            readiness: HealthMdCoreReadiness,
            registry: CoreMetricRegistrySnapshot,
        ): ExportEnginePin {
            val buildInfo = readiness.buildInfo
            val pin = ExportEnginePin(
                engine = engine,
                profile = profile,
                publicSchema = registry.publicSchema,
                publicSchemaVersion = registry.publicSchemaVersion,
                coreApiVersion = buildInfo.coreApiVersion,
                semanticInputVersion = buildInfo.semanticInputVersion,
                canonicalModelVersion = buildInfo.canonicalModelVersion,
                renderInputVersion = buildInfo.renderInputVersion,
                artifactPlanVersion = buildInfo.artifactPlanVersion,
                registryVersion = registry.registryVersion,
                registrySha256 = registry.registrySha256,
                semanticProfileRevision = registry.profileRevision,
                renderProfileRevision = buildInfo.renderProfileRevision,
                coreSourceRevision = buildInfo.coreSourceRevision,
                ianaTimeZone = ianaTimeZone,
            )
            val compatibility = ExportEnginePinValidator().validate(pin, readiness, registry)
            if (!compatibility.isCompatible) {
                throw ExportEnginePinCompatibilityException(compatibility)
            }
            return pin
        }
    }
}

enum class ExportEnginePinIssue {
    CORE_UNAVAILABLE,
    CORE_NOT_READY,
    PROFILE,
    PUBLIC_SCHEMA,
    PUBLIC_SCHEMA_VERSION,
    CORE_API_VERSION,
    SEMANTIC_INPUT_VERSION,
    CANONICAL_MODEL_VERSION,
    RENDER_INPUT_VERSION,
    ARTIFACT_PLAN_VERSION,
    REGISTRY_VERSION,
    REGISTRY_SHA256,
    SEMANTIC_PROFILE_REVISION,
    RENDER_PROFILE_REVISION,
    CORE_SOURCE_REVISION,
    IANA_TIME_ZONE,
}

class ExportEnginePinCompatibility internal constructor(issues: Collection<ExportEnginePinIssue>) {
    val issues: Set<ExportEnginePinIssue> =
        Collections.unmodifiableSet(LinkedHashSet(issues))
    val isCompatible: Boolean get() = issues.isEmpty()

    override fun toString(): String =
        "ExportEnginePinCompatibility(isCompatible=$isCompatible, issues=$issues)"
}

/** Contains only fixed compatibility dimensions; no captured values are included. */
class ExportEnginePinCompatibilityException(
    val compatibility: ExportEnginePinCompatibility,
) : IllegalStateException("export engine pin is incompatible")

/** Exact compatibility validation against both packaged build evidence and profile registry data. */
class ExportEnginePinValidator {
    fun validate(
        pin: ExportEnginePin,
        service: HealthMdCoreService,
    ): ExportEnginePinCompatibility = try {
        val readiness = service.checkReadiness()
        if (!readiness.isReady) {
            ExportEnginePinCompatibility(listOf(ExportEnginePinIssue.CORE_NOT_READY))
        } else {
            validate(pin, readiness, service.getMetricRegistry(pin.profile.coreProfile))
        }
    } catch (error: Throwable) {
        if (error.isFatalExportEngineFailure()) throw error
        ExportEnginePinCompatibility(listOf(ExportEnginePinIssue.CORE_UNAVAILABLE))
    }

    fun validate(
        pin: ExportEnginePin,
        readiness: HealthMdCoreReadiness,
        registry: CoreMetricRegistrySnapshot,
    ): ExportEnginePinCompatibility {
        val info = readiness.buildInfo
        val issues = linkedSetOf<ExportEnginePinIssue>()
        if (!readiness.isReady) issues += ExportEnginePinIssue.CORE_NOT_READY
        if (
            registry.profileId != pin.profile.name ||
            registry.publicProfileId != pin.profile.publicProfileId
        ) {
            issues += ExportEnginePinIssue.PROFILE
        }
        if (
            pin.publicSchema != ExportEnginePin.PUBLIC_SCHEMA ||
            registry.publicSchema != ExportEnginePin.PUBLIC_SCHEMA ||
            pin.publicSchema != registry.publicSchema
        ) {
            issues += ExportEnginePinIssue.PUBLIC_SCHEMA
        }
        if (
            pin.publicSchemaVersion != pin.profile.publicSchemaVersion ||
            registry.publicSchemaVersion != pin.profile.publicSchemaVersion ||
            pin.publicSchemaVersion != registry.publicSchemaVersion
        ) {
            issues += ExportEnginePinIssue.PUBLIC_SCHEMA_VERSION
        }
        if (pin.coreApiVersion != info.coreApiVersion) {
            issues += ExportEnginePinIssue.CORE_API_VERSION
        }
        if (pin.semanticInputVersion != info.semanticInputVersion) {
            issues += ExportEnginePinIssue.SEMANTIC_INPUT_VERSION
        }
        if (pin.canonicalModelVersion != info.canonicalModelVersion) {
            issues += ExportEnginePinIssue.CANONICAL_MODEL_VERSION
        }
        if (pin.renderInputVersion != info.renderInputVersion) {
            issues += ExportEnginePinIssue.RENDER_INPUT_VERSION
        }
        if (pin.artifactPlanVersion != info.artifactPlanVersion) {
            issues += ExportEnginePinIssue.ARTIFACT_PLAN_VERSION
        }
        if (
            pin.registryVersion != info.registryVersion ||
            pin.registryVersion != registry.registryVersion
        ) {
            issues += ExportEnginePinIssue.REGISTRY_VERSION
        }
        if (
            pin.registrySha256 != info.registrySha256 ||
            pin.registrySha256 != registry.registrySha256 ||
            !pin.registrySha256.isLowercaseSha256()
        ) {
            issues += ExportEnginePinIssue.REGISTRY_SHA256
        }
        if (
            pin.semanticProfileRevision != ExportEnginePin.EXPECTED_SEMANTIC_PROFILE_REVISION ||
            registry.profileRevision != ExportEnginePin.EXPECTED_SEMANTIC_PROFILE_REVISION ||
            pin.semanticProfileRevision != registry.profileRevision
        ) {
            issues += ExportEnginePinIssue.SEMANTIC_PROFILE_REVISION
        }
        if (pin.renderProfileRevision != info.renderProfileRevision) {
            issues += ExportEnginePinIssue.RENDER_PROFILE_REVISION
        }
        // Source revision is provenance, not an equality gate. Compatible rollback builds may
        // resume older pins; behavior changes must advance a version/profile pin above.
        if (
            pin.coreSourceRevision.isBlank() ||
            pin.coreSourceRevision.length > 256 ||
            info.coreSourceRevision.isBlank() ||
            info.coreSourceRevision.length > 256
        ) {
            issues += ExportEnginePinIssue.CORE_SOURCE_REVISION
        }
        if (!pin.ianaTimeZone.isExplicitIanaTimeZone()) {
            issues += ExportEnginePinIssue.IANA_TIME_ZONE
        }
        return ExportEnginePinCompatibility(issues)
    }
}

internal fun String.isLowercaseSha256(): Boolean =
    length == 64 && all { it in '0'..'9' || it in 'a'..'f' }

internal fun String.isExplicitIanaTimeZone(): Boolean =
    isNotBlank() && this in ZoneId.getAvailableZoneIds()

internal fun Throwable.isFatalExportEngineFailure(): Boolean =
    this is VirtualMachineError || this is ThreadDeath
