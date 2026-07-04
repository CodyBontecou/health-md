package com.healthmd.data.health

import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import java.time.LocalDate

class HealthRepositoryImpl(
    private val providerRegistry: HealthProviderRegistry,
    private val settingsRepository: SettingsRepository,
) : HealthRepository {

    private suspend fun activeProvider(): HealthDataProvider {
        val selectedProviderId = settingsRepository.getSelectedHealthProviderId()
        return providerRegistry.providerFor(selectedProviderId)
    }

    private suspend fun shouldUseAllConnected(): Boolean =
        settingsRepository.getSelectedHealthProviderId() == HealthDataMerger.ALL_CONNECTED_PROVIDER_ID

    private suspend fun connectedProviders(): List<HealthDataProvider> {
        val connectedIds = settingsRepository.getConnectedHealthProviderIds()
        return providerRegistry.exportProviders
            .filter { provider -> provider.providerId in connectedIds }
            .filter { provider -> runCatching { provider.isAvailable() && provider.hasPermissions() }.getOrDefault(false) }
    }

    override suspend fun fetchHealthData(date: LocalDate): HealthData {
        if (!shouldUseAllConnected()) return activeProvider().fetchHealthData(date)
        val dataSets = connectedProviders().mapNotNull { provider ->
            runCatching { provider.fetchHealthData(date) }.getOrNull()
        }
        return HealthDataMerger.merge(date, dataSets)
    }

    override suspend fun fetchHealthDataRange(
        dates: List<LocalDate>,
        dataTypes: DataTypeSelection,
        includeGranularData: Boolean,
    ): List<HealthData> {
        if (!shouldUseAllConnected()) {
            return activeProvider().fetchHealthDataRange(dates, dataTypes, includeGranularData)
        }
        val providers = connectedProviders()
        return dates.map { date ->
            val dataSets = providers.mapNotNull { provider ->
                runCatching {
                    provider.fetchHealthData(date).filtered(dataTypes)
                }.getOrNull()
            }
            HealthDataMerger.merge(date, dataSets)
        }
    }

    override suspend fun isAvailable(): Boolean =
        if (shouldUseAllConnected()) connectedProviders().isNotEmpty() else activeProvider().isAvailable()

    override suspend fun hasPermissions(): Boolean =
        if (shouldUseAllConnected()) connectedProviders().isNotEmpty() else activeProvider().hasPermissions()

    override suspend fun hasHistoricalReadPermission(): Boolean =
        if (shouldUseAllConnected()) connectedProviders().all { it.hasHistoricalReadPermission() } else activeProvider().hasHistoricalReadPermission()

    override suspend fun hasBackgroundReadPermission(): Boolean =
        if (shouldUseAllConnected()) connectedProviders().all { it.hasBackgroundReadPermission() } else activeProvider().hasBackgroundReadPermission()

    override suspend fun getEarliestDataDate(): java.time.LocalDate? =
        if (shouldUseAllConnected()) {
            connectedProviders().mapNotNull { runCatching { it.getEarliestDataDate() }.getOrNull() }.minOrNull()
        } else {
            activeProvider().getEarliestDataDate()
        }

    override fun isBeforeFirstUnlock(): Boolean =
        providerRegistry.primaryExportProvider().isBeforeFirstUnlock()
}
