package com.healthmd.domain.repository

import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import java.time.LocalDate
import java.time.ZoneId

interface HealthRepository {
    suspend fun fetchHealthData(date: LocalDate): HealthData

    /**
     * [sleepDayAttribution] selects which daily note owns a midnight-spanning sleep
     * session (issue #104). [HealthRepositoryImpl] reads the persisted device
     * preference when the caller keeps the default.
     */
    suspend fun fetchHealthDataRange(
        dates: List<LocalDate>,
        dataTypes: DataTypeSelection = DataTypeSelection(),
        includeGranularData: Boolean = false,
        zoneId: ZoneId = ZoneId.systemDefault(),
        pinnedCalendarDays: Boolean = false,
        sleepDayAttribution: SleepDayAttribution = SleepDayAttribution.DEFAULT,
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
