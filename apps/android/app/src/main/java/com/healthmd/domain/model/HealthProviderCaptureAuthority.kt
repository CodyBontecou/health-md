package com.healthmd.domain.model

import java.util.Collections
import java.util.UUID
import kotlinx.serialization.Serializable
import kotlinx.serialization.Required

/** Private job authority. Contains opaque grant identities, never OAuth tokens or health data. */
@Serializable
data class HealthProviderCaptureAuthority(
    @Required val version: Int = 1,
    val selectedProviderId: String,
    val providerIds: List<String>,
    /** A present null means unavailable at acceptance; it must never adopt a later login. */
    val connectionIds: Map<String, String?>,
) {
    fun validatedCopy(): HealthProviderCaptureAuthority {
        require(version == 1) { "Unsupported provider capture authority" }
        require(providerIds.size <= 32 && providerIds == providerIds.distinct().sorted())
        require(providerIds.all { it.matches(Regex("[a-z][a-z0-9_]{0,63}")) && it != "all_connected" })
        require(selectedProviderId == "all_connected" || providerIds == listOf(selectedProviderId))
        require(connectionIds.keys == providerIds.filterNot { it == "health_connect" }.toSet())
        require(connectionIds.values.all { id ->
            id == null || runCatching { UUID.fromString(id).toString() == id }.getOrDefault(false)
        }) { "Invalid provider connection identity" }
        return copy(
            providerIds = Collections.unmodifiableList(providerIds.toList()),
            connectionIds = Collections.unmodifiableMap(connectionIds.toSortedMap()),
        )
    }
}
