package com.healthmd.domain.repository

import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import java.time.LocalDate

interface HealthRepository {
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
