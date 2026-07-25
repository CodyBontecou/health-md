package com.healthmd.data.health

import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import java.time.LocalDate

/**
 * Normalized read contract for every health data source Health.md can export.
 *
 * The export pipeline stays provider-agnostic by consuming the existing [HealthData]
 * domain model. Provider-specific SDKs/OAuth clients should map into this contract
 * instead of reaching into exporters directly.
 */
interface HealthDataProvider {
    val providerId: String

    suspend fun fetchHealthData(date: LocalDate): HealthData

    suspend fun fetchHealthDataRange(
        dates: List<LocalDate>,
        dataTypes: DataTypeSelection = DataTypeSelection(),
        includeGranularData: Boolean = false,
    ): List<HealthData> = dates.map { date ->
        fetchHealthData(date).filtered(dataTypes)
    }

    suspend fun isAvailable(): Boolean
    suspend fun hasPermissions(): Boolean
    suspend fun hasHistoricalReadPermission(): Boolean
    suspend fun hasBackgroundReadPermission(): Boolean
    suspend fun getEarliestDataDate(): LocalDate?
    fun isBeforeFirstUnlock(): Boolean
}
