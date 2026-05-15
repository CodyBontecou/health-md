package com.healthmd.presentation.export

import java.time.LocalDate

object ExportHistoryAccess {
    const val DEFAULT_ACCESSIBLE_HISTORY_DAYS = 30L

    fun requiresHistoricalReadPermission(
        startDate: LocalDate,
        endDate: LocalDate,
        today: LocalDate = LocalDate.now(),
    ): Boolean {
        val oldestSelectedDate = minOf(startDate, endDate)
        val oldestDefaultAccessibleDate = today.minusDays(DEFAULT_ACCESSIBLE_HISTORY_DAYS)
        return oldestSelectedDate.isBefore(oldestDefaultAccessibleDate)
    }
}
