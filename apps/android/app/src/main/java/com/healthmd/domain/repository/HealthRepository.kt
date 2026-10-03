package com.healthmd.domain.repository

import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import java.time.LocalDate
import java.time.ZoneId

interface HealthRepository {
    suspend fun fetchHealthData(date: LocalDate): HealthData
    suspend fun fetchHealthDataRange(
        dates: List<LocalDate>,
        dataTypes: DataTypeSelection = DataTypeSelection(),
        includeGranularData: Boolean = false,
        zoneId: ZoneId = ZoneId.systemDefault(),
        pinnedCalendarDays: Boolean = false,
    ): List<HealthData> = dates.map { date ->
        fetchHealthData(date).filtered(dataTypes)
    }

    /**
     * Selects and authorizes exercise-route consent candidates across a complete interactive run.
     * Non-Health Connect and noninteractive implementations intentionally do nothing.
     */
    suspend fun authorizeExerciseRouteConsent(
        dates: List<LocalDate>,
        dataTypes: DataTypeSelection = DataTypeSelection(),
        includeGranularData: Boolean = false,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ) = Unit

    suspend fun isAvailable(): Boolean
    suspend fun hasPermissions(): Boolean
    suspend fun hasHistoricalReadPermission(): Boolean
    suspend fun hasBackgroundReadPermission(): Boolean
    suspend fun getEarliestDataDate(): LocalDate?
    fun isBeforeFirstUnlock(): Boolean
}
