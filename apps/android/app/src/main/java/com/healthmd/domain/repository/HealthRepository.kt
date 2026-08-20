package com.healthmd.domain.repository

import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttributionOverride
import java.time.LocalDate
import java.time.ZoneId

interface HealthRepository {
    suspend fun fetchHealthData(date: LocalDate): HealthData

    /** Resolves all mutable device inputs once, before an operation's first health read. */
    suspend fun resolveCaptureContext(
        zoneId: ZoneId = ZoneId.systemDefault(),
        sleepDayAttributionOverride: SleepDayAttributionOverride = SleepDayAttributionOverride.StoredPreference,
    ): AndroidCaptureContext

    /**
     * [sleepDayAttributionOverride] selects whether capture reads the persisted
     * device preference or uses an explicit value. NIGHT_BEGINS is a real value,
     * never a sentinel for reading settings (issue #104).
     */
    suspend fun fetchHealthDataRange(
        dates: List<LocalDate>,
        dataTypes: DataTypeSelection = DataTypeSelection(),
        includeGranularData: Boolean = false,
        zoneId: ZoneId = ZoneId.systemDefault(),
        pinnedCalendarDays: Boolean = false,
        sleepDayAttributionOverride: SleepDayAttributionOverride = SleepDayAttributionOverride.StoredPreference,
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
