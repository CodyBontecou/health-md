package com.healthmd.data.health.providers.cloud

import com.healthmd.data.health.HealthDataProvider
import com.healthmd.domain.model.HealthData
import java.time.LocalDate

abstract class CloudHealthDataProvider(
    final override val providerId: String,
    private val apiClient: CloudHealthApiClient,
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

    protected fun empty(date: LocalDate): HealthData = HealthData(date)
}
