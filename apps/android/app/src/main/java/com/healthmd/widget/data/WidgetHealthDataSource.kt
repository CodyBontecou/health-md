package com.healthmd.widget.data

import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.domain.model.HealthData
import com.healthmd.widget.model.HealthWidgetSnapshot
import java.time.LocalDate
import javax.inject.Inject

interface WidgetHealthDataSource {
    suspend fun readRecentDays(
        today: LocalDate,
        selection: HealthConnectWidgetReadSelection,
        dayCount: Int = HealthWidgetSnapshot.SNAPSHOT_DAY_COUNT,
    ): List<HealthData>

    suspend fun isAvailable(): Boolean
    fun isBeforeFirstUnlock(): Boolean
}

/** Phone widgets intentionally use the local Health Connect source, matching iOS's HealthKit source. */
class HealthConnectWidgetDataSource @Inject constructor(
    private val provider: HealthConnectDataProvider,
) : WidgetHealthDataSource {
    override suspend fun readRecentDays(
        today: LocalDate,
        selection: HealthConnectWidgetReadSelection,
        dayCount: Int,
    ): List<HealthData> {
        require(selection.hasAny) { "At least one widget health record family is required." }
        val boundedDayCount = dayCount.coerceIn(1, HealthWidgetSnapshot.SNAPSHOT_DAY_COUNT)
        val dates = (boundedDayCount - 1 downTo 0).map { offset ->
            today.minusDays(offset.toLong())
        }
        val fetchedByDate = provider.fetchWidgetHealthDataRange(
            dates = dates,
            selection = selection,
        ).associateBy(HealthData::date)

        // Preserve missing dates so chart positions continue to represent calendar days.
        return dates.map { date -> fetchedByDate[date] ?: HealthData(date = date) }
    }

    override suspend fun isAvailable(): Boolean = provider.isAvailable()

    override fun isBeforeFirstUnlock(): Boolean = provider.isBeforeFirstUnlock()
}
