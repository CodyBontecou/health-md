package com.healthmd.widget.data

import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.widget.model.HealthWidgetSnapshot
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

interface WidgetHealthDataSource {
    suspend fun readRecentDays(
        today: LocalDate,
        selection: HealthConnectWidgetReadSelection,
        dayCount: Int = HealthWidgetSnapshot.SNAPSHOT_DAY_COUNT,
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): List<HealthData>

    suspend fun isAvailable(): Boolean
    fun isBeforeFirstUnlock(): Boolean
}

/** Phone widgets intentionally use the local Health Connect source, matching iOS's HealthKit source. */
class HealthConnectWidgetDataSource @Inject constructor(
    private val provider: HealthConnectDataProvider,
    private val settingsRepository: SettingsRepository,
) : WidgetHealthDataSource {
    override suspend fun readRecentDays(
        today: LocalDate,
        selection: HealthConnectWidgetReadSelection,
        dayCount: Int,
        zoneId: ZoneId,
    ): List<HealthData> {
        require(selection.hasAny) { "At least one widget health record family is required." }
        val boundedDayCount = dayCount.coerceIn(1, HealthWidgetSnapshot.SNAPSHOT_DAY_COUNT)
        val dates = (boundedDayCount - 1 downTo 0).map { offset ->
            today.minusDays(offset.toLong())
        }
        // Snapshot the caller's zone before the settings read can suspend.
        val captureContext = AndroidCaptureContext(
            zoneId = zoneId,
            sleepDayAttribution = settingsRepository.getSleepDayAttribution(),
        )
        val fetchedByDate = provider.fetchWidgetHealthDataRange(
            dates = dates,
            selection = selection,
            zoneId = captureContext.zoneId,
            sleepDayAttribution = captureContext.sleepDayAttribution,
        ).associateBy(HealthData::date)

        // Preserve missing dates so chart positions continue to represent calendar days.
        return dates.map { date -> fetchedByDate[date] ?: HealthData(date = date) }
    }

    override suspend fun isAvailable(): Boolean = provider.isAvailable()

    override fun isBeforeFirstUnlock(): Boolean = provider.isBeforeFirstUnlock()
}
