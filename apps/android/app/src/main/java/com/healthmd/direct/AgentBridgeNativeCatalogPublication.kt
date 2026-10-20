package com.healthmd.direct

import com.healthmd.direct.protocol.*
import com.healthmd.domain.model.HEALTHMD_CORE_REGISTRY_SHA256
import java.security.MessageDigest
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*

/** Private signed issuer metadata, not a wire capability, permission or consent token. */
@Serializable
internal data class AgentBridgeNativeCatalogPublication(val revision: Int, val sourceInstallationId: String, val factsSha256: String) {
    fun validate() {
        if (revision < 1 || !Regex("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}").matches(sourceInstallationId) ||
            !Regex("[0-9a-f]{64}").matches(factsSha256)) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
    }
}

/** SDK/controller facts only: no health/provider/credential/preview/output activity. */
internal fun AgentBridgeNativePlanningFacts.fingerprint(sourceInstallationId: String): String {
    val facts = buildJsonObject {
        // Advance this support revision when the installed planner dialect changes.
        put("planning_support_revision", 1); put("registry_sha256", HEALTHMD_CORE_REGISTRY_SHA256)
        put("platform", "android"); put("source_installation_id", sourceInstallationId)
        put("device_settings_object_id", deviceSettingsObjectId)
        put("available_native_metric_ids", JsonArray(availableNativeMetricIds.sorted().map(::JsonPrimitive)))
        put("source_calendar_timezone", sourceCalendarTimezone)
        put("configuration_protection", configurationProtection.name.lowercase(java.util.Locale.ROOT))
        put("native_grants", nativeGrants.name.lowercase(java.util.Locale.ROOT))
        put("entitlement", entitlement.name.lowercase(java.util.Locale.ROOT))
        put("execution_available", userStartedServiceActive); put("data_available", firstUnlockComplete)
    }
    val bytes = AgentBridgeCodec.canonicalize(facts.toString().toByteArray())
    return MessageDigest.getInstance("SHA-256").digest("HealthMd.NativePlanningFacts.v1\u0000".toByteArray() + bytes)
        .joinToString("") { "%02x".format(it) }
}
