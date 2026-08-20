package com.healthmd.data.health

import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.ProviderFailureProvenance
import com.healthmd.domain.model.SleepDayAttributionOverride
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.util.runCatchingCancellable
import java.time.LocalDate
import java.time.ZoneId

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

    private suspend fun configuredProviderIds(): List<String> =
        settingsRepository.getConnectedHealthProviderIds().distinct().sorted()

    private fun configuredProviders(connectedProviderIds: List<String>): List<HealthDataProvider> {
        val connectedIds = connectedProviderIds.toSet()
        return providerRegistry.exportProviders
            .filter { it.providerId in connectedIds }
            .sortedBy { it.providerId }
    }

    private suspend fun connectedProviders(): List<HealthDataProvider> =
        configuredProviders(configuredProviderIds())
            .filter { provider ->
                runCatchingCancellable {
                    provider.isAvailable() && provider.hasPermissions()
                }.getOrDefault(false)
            }

    private suspend fun providerReadiness(
        attemptedIds: List<String>,
        providers: List<HealthDataProvider>,
    ): Pair<List<HealthDataProvider>, MutableList<ProviderFailureProvenance>> {
        val failures = mutableListOf<ProviderFailureProvenance>()
        val knownIds = providers.map { it.providerId }.toSet()
        (attemptedIds - knownIds).forEach { providerId ->
            failures += ProviderFailureProvenance(providerId, "discovery", "ProviderNotRegistered")
        }
        val ready = providers.filter { provider ->
            val available = runCatchingCancellable { provider.isAvailable() }
            if (available.isFailure) {
                failures += available.exceptionOrNull().toFailure(provider.providerId, "availability")
                return@filter false
            }
            if (available.getOrThrow().not()) {
                failures += ProviderFailureProvenance(provider.providerId, "availability", "ProviderUnavailable")
                return@filter false
            }
            val permitted = runCatchingCancellable { provider.hasPermissions() }
            if (permitted.isFailure) {
                failures += permitted.exceptionOrNull().toFailure(provider.providerId, "permissions")
                return@filter false
            }
            if (permitted.getOrThrow().not()) {
                failures += ProviderFailureProvenance(provider.providerId, "permissions", "PermissionDenied")
                return@filter false
            }
            true
        }
        return ready to failures
    }

    override suspend fun fetchHealthData(date: LocalDate): HealthData =
        fetchHealthDataRange(dates = listOf(date)).firstOrNull() ?: HealthData(date)

    override suspend fun fetchHealthDataRange(
        dates: List<LocalDate>,
        dataTypes: DataTypeSelection,
        includeGranularData: Boolean,
        zoneId: ZoneId,
        pinnedCalendarDays: Boolean,
        sleepDayAttributionOverride: SleepDayAttributionOverride,
    ): List<HealthData> {
        if (dates.isEmpty()) return emptyList()
        // Snapshot the operation's timezone argument and attribution together at
        // capture entry. Every provider query and projection receives these exact
        // values even if settings or the system timezone change while suspended.
        val captureZoneId = zoneId
        val attribution = when (sleepDayAttributionOverride) {
            SleepDayAttributionOverride.StoredPreference -> settingsRepository.getSleepDayAttribution()
            is SleepDayAttributionOverride.Value -> sleepDayAttributionOverride.attribution
        }
        if (!shouldUseAllConnected()) {
            return activeProvider().fetchHealthDataRange(
                dates,
                dataTypes,
                includeGranularData,
                captureZoneId,
                pinnedCalendarDays,
                attribution,
            )
        }
        val attemptedIds = configuredProviderIds()
        val (providers, readinessFailures) = providerReadiness(attemptedIds, configuredProviders(attemptedIds))
        val failuresByDate = dates.associateWith { readinessFailures.toMutableList() }.toMutableMap()
        val dataByDate = dates.associateWith { mutableListOf<HealthDataMerger.ProviderData>() }.toMutableMap()

        providers.forEach { provider ->
            runCatchingCancellable {
                provider.fetchHealthDataRange(
                    dates,
                    dataTypes,
                    includeGranularData,
                    captureZoneId,
                    pinnedCalendarDays,
                    attribution,
                )
            }
                .onSuccess { records ->
                    records.forEach { record ->
                        if (record.date in dataByDate) {
                            dataByDate.getValue(record.date) += HealthDataMerger.ProviderData(
                                provider.providerId,
                                record.filtered(dataTypes),
                            )
                        }
                    }
                }
                .onFailure { error ->
                    dates.forEach { date ->
                        failuresByDate.getValue(date) += error.toFailure(provider.providerId, "fetchHealthDataRange")
                    }
                }
        }
        return dates.map { date ->
            HealthDataMerger.mergeAllConnected(
                date = date,
                attemptedProviderIds = attemptedIds,
                successfulData = dataByDate.getValue(date),
                failures = failuresByDate.getValue(date),
            )
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

    override suspend fun getEarliestDataDate(): LocalDate? =
        if (shouldUseAllConnected()) {
            connectedProviders().mapNotNull {
                runCatchingCancellable { it.getEarliestDataDate() }.getOrNull()
            }.minOrNull()
        } else {
            activeProvider().getEarliestDataDate()
        }

    override fun isBeforeFirstUnlock(): Boolean =
        providerRegistry.primaryExportProvider().isBeforeFirstUnlock()

    private fun Throwable?.toFailure(providerId: String, operation: String): ProviderFailureProvenance {
        val error = this
        return ProviderFailureProvenance(
            providerId = providerId,
            operation = operation,
            errorType = error?.javaClass?.simpleName?.takeIf { it.isNotBlank() } ?: "UnknownFailure",
            message = error?.message?.takeIf { it.isNotBlank() },
        )
    }
}
