package com.healthmd.data.health

import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import java.time.LocalDate

class HealthConnectDataProvider(
    private val healthConnectManager: HealthConnectManager,
) : HealthDataProvider {
    override val providerId: String = "health_connect"

    override suspend fun fetchHealthData(date: LocalDate): HealthData =
        healthConnectManager.fetchHealthData(date)

    override suspend fun fetchHealthDataRange(
        dates: List<LocalDate>,
        dataTypes: DataTypeSelection,
        includeGranularData: Boolean,
    ): List<HealthData> =
        healthConnectManager.fetchHealthDataRange(dates, dataTypes, includeGranularData)

    override suspend fun isAvailable(): Boolean =
        healthConnectManager.isAvailable()

    override suspend fun hasPermissions(): Boolean =
        healthConnectManager.hasAllPermissions()

    override suspend fun hasHistoricalReadPermission(): Boolean =
        healthConnectManager.hasHistoricalReadPermission()

    override suspend fun hasBackgroundReadPermission(): Boolean =
        healthConnectManager.hasBackgroundReadPermission()

    override suspend fun getEarliestDataDate(): LocalDate? =
        healthConnectManager.getEarliestDataDate()

    override fun isBeforeFirstUnlock(): Boolean =
        healthConnectManager.isBeforeFirstUnlock()
}
