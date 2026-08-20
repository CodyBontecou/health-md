package com.healthmd.data.health

import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import java.time.LocalDate
import java.time.ZoneId

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
        zoneId: ZoneId,
        pinnedCalendarDays: Boolean,
        sleepDayAttribution: SleepDayAttribution,
    ): List<HealthData> =
        healthConnectManager.fetchHealthDataRange(
            dates,
            dataTypes,
            includeGranularData,
            zoneId,
            pinnedCalendarDays,
            sleepDayAttribution,
        )

    suspend fun fetchWidgetHealthDataRange(
        dates: List<LocalDate>,
        selection: HealthConnectWidgetReadSelection,
        zoneId: ZoneId = ZoneId.systemDefault(),
        sleepDayAttribution: SleepDayAttribution = SleepDayAttribution.DEFAULT,
    ): List<HealthData> = healthConnectManager.fetchWidgetHealthDataRange(
        dates = dates,
        selection = selection,
        zoneId = zoneId,
        sleepDayAttribution = sleepDayAttribution,
    )

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
