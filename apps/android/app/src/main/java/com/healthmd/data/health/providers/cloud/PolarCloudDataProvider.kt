package com.healthmd.data.health.providers.cloud

import com.healthmd.domain.model.HealthData
import java.time.LocalDate

/**
 * Polar AccessLink is transaction-based: apps must register the user, create
 * activity/training transactions, then pull available resources. The OAuth and
 * token plumbing is available here, while production history sync should add a
 * small transaction cache so exports do not consume the same AccessLink
 * transaction repeatedly.
 */
class PolarCloudDataProvider(
    apiClient: CloudHealthApiClient,
) : CloudHealthDataProvider("polar", apiClient) {
    override val fidelityDeclaration: CloudProviderFidelityDeclaration = CloudProviderFidelityDeclaration(
        providerId = providerId,
        fidelity = CloudProviderFidelity.UNSUPPORTED,
    )

    override suspend fun fetchHealthData(date: LocalDate): HealthData = empty(date)
}
