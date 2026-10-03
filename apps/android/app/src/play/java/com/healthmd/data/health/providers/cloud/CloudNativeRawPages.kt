package com.healthmd.data.health.providers.cloud

import com.healthmd.rawexport.RawProviderTypeDefinition
import com.healthmd.rawexport.RawSnapshotRequest

/**
 * Streaming boundary for exact provider-native API pages. Implementations call the existing
 * [CloudHealthApiClient] through [CloudRawResponseObserver]; normalized HealthData never crosses it.
 */
interface CloudNativeRawPageProvider {
    val rawProviderId: String
    val rawFidelityDeclaration: CloudProviderFidelityDeclaration
    val rawEndpointDefinitions: List<RawProviderTypeDefinition>

    suspend fun streamNativePages(
        request: RawSnapshotRequest,
        selectedEndpointKeys: Set<String>,
        observerFor: (endpointKey: String) -> CloudRawResponseObserver,
        onEndpointResult: suspend (CloudNativeEndpointResult) -> Unit,
    )
}

data class CloudNativeEndpointResult(
    val endpointKey: String,
    val successfulPageCount: Long,
    val failure: CloudNativeEndpointFailure? = null,
)

data class CloudNativeEndpointFailure(
    val code: String,
    val message: String,
    val retryable: Boolean = true,
)

internal const val MAX_NATIVE_PAGES_PER_ENDPOINT = 100
