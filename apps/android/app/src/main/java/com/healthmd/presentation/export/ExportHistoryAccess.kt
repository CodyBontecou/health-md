package com.healthmd.presentation.export

import java.time.LocalDate

object ExportHistoryAccess {
    const val DEFAULT_ACCESSIBLE_HISTORY_DAYS = 30L

    fun requiresHistoricalReadPermission(
        startDate: LocalDate,
        endDate: LocalDate,
        today: LocalDate = LocalDate.now(),
        firstPermissionGrantDate: LocalDate? = null,
    ): Boolean {
        val oldestSelectedDate = minOf(startDate, endDate)
        val referenceDate = firstPermissionGrantDate ?: today
        val oldestDefaultAccessibleDate = referenceDate.minusDays(DEFAULT_ACCESSIBLE_HISTORY_DAYS)

        // Health Connect's default read window is based on when the app was first granted any
        // Health Connect permission, not on the current date. If we know that grant date, treat the
        // boundary day as requiring history access because daily reads start at midnight while the
        // permission may have been granted later in the day.
        return if (firstPermissionGrantDate != null) {
            !oldestSelectedDate.isAfter(oldestDefaultAccessibleDate)
        } else {
            oldestSelectedDate.isBefore(oldestDefaultAccessibleDate)
        }
    }
}
