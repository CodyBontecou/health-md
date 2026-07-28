package com.healthmd.presentation.export

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.LocalDate

class ExportHistoryAccessTest {

    private val today = LocalDate.of(2026, 3, 15)

    @Test
    fun thirtyDayRangeDoesNotRequireHistoricalPermission() {
        val start = today.minusDays(29)

        assertThat(
            ExportHistoryAccess.requiresHistoricalReadPermission(
                startDate = start,
                endDate = today,
                today = today,
            )
        ).isFalse()
    }

    @Test
    fun oldestAccessibleBoundaryDoesNotRequireHistoricalPermission() {
        val start = today.minusDays(30)

        assertThat(
            ExportHistoryAccess.requiresHistoricalReadPermission(
                startDate = start,
                endDate = today,
                today = today,
            )
        ).isFalse()
    }

    @Test
    fun boundaryDateRequiresHistoricalPermissionWhenFirstGrantDateIsKnown() {
        val firstGrantDate = LocalDate.of(2026, 3, 15)
        val start = firstGrantDate.minusDays(30)

        assertThat(
            ExportHistoryAccess.requiresHistoricalReadPermission(
                startDate = start,
                endDate = firstGrantDate,
                today = firstGrantDate,
                firstPermissionGrantDate = firstGrantDate,
            )
        ).isTrue()
    }

    @Test
    fun dateRangeInsideThirtyDaysFromTodayCanRequireHistoryFromLaterPermissionGrant() {
        val today = LocalDate.of(2026, 3, 15)
        val firstGrantDate = LocalDate.of(2026, 3, 10)
        val start = LocalDate.of(2026, 2, 8)

        assertThat(
            ExportHistoryAccess.requiresHistoricalReadPermission(
                startDate = start,
                endDate = today,
                today = today,
                firstPermissionGrantDate = firstGrantDate,
            )
        ).isTrue()
    }

    @Test
    fun ninetyDayRangeRequiresHistoricalPermission() {
        val start = today.minusDays(89)

        assertThat(
            ExportHistoryAccess.requiresHistoricalReadPermission(
                startDate = start,
                endDate = today,
                today = today,
            )
        ).isTrue()
    }

    @Test
    fun reversedRangeStillUsesOldestDate() {
        val start = today
        val end = today.minusDays(89)

        assertThat(
            ExportHistoryAccess.requiresHistoricalReadPermission(
                startDate = start,
                endDate = end,
                today = today,
            )
        ).isTrue()
    }
}
