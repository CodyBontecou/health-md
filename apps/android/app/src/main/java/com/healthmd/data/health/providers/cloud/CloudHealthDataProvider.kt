package com.healthmd.data.health.providers.cloud

import com.healthmd.data.health.HealthDataProvider
import com.healthmd.domain.model.HealthData
import java.time.LocalDate

abstract class CloudHealthDataProvider(
    final override val providerId: String,
    protected val apiClient: CloudHealthApiClient,
) : HealthDataProvider {
    /** Truthful source-fidelity label for additive raw-manifest integrations. */
    open val fidelityDeclaration: CloudProviderFidelityDeclaration = CloudProviderFidelityDeclaration(
        providerId = providerId,
        fidelity = CloudProviderFidelity.NATIVE_API_PAYLOAD,
    )

    override suspend fun isAvailable(): Boolean = apiClient.isConfigured(providerId)

    override suspend fun hasPermissions(): Boolean = apiClient.token(providerId) != null

    override suspend fun hasHistoricalReadPermission(): Boolean = hasPermissions()

    override suspend fun hasBackgroundReadPermission(): Boolean = hasPermissions()

    override suspend fun getEarliestDataDate(): LocalDate? = null

    override fun isBeforeFirstUnlock(): Boolean = false

    protected suspend fun getJson(
        url: String,
        query: Map<String, String> = emptyMap(),
    ) = apiClient.getJson(providerId, url, query)

    protected suspend fun getNativePage(
        url: String,
        query: Map<String, String> = emptyMap(),
        pageOrdinal: Int,
        observer: CloudRawResponseObserver,
    ): CloudHealthRawResponse {
        val response = apiClient.getRawJsonResponse(
            providerId = providerId,
            url = url,
            query = query,
            pageOrdinal = pageOrdinal,
            observer = observer,
        )
        if (!response.jsonValid) throw CloudHealthPayloadException(providerId)
        return response
    }

    protected fun empty(date: LocalDate): HealthData = HealthData(date)
}
