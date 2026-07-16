package com.healthmd.rawexport

import com.google.common.truth.Truth.assertThat
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Test

class HealthConnectHistoryAccessBoundaryTest {
    @Test
    fun longStandingGrantUsesGrantBoundaryRatherThanCurrentDateWindow() {
        val grantDate = LocalDate.of(2025, 1, 1)
        val request = request(LocalDate.of(2024, 12, 15))

        assertThat(requiresHistoricalReadPermission(request, grantDate)).isFalse()
    }

    @Test
    fun newGrantMarksRangeAtOrBeforeThirtyDayBoundaryAsRequiringHistory() {
        val grantDate = LocalDate.of(2026, 7, 1)

        assertThat(requiresHistoricalReadPermission(request(LocalDate.of(2026, 6, 2)), grantDate)).isFalse()
        assertThat(requiresHistoricalReadPermission(request(LocalDate.of(2026, 6, 1)), grantDate)).isTrue()
        assertThat(requiresHistoricalReadPermission(request(LocalDate.of(2026, 5, 31)), grantDate)).isTrue()
    }

    @Test
    fun unknownLegacyGrantBoundaryDoesNotClaimFullCoverage() {
        assertThat(requiresHistoricalReadPermission(request(LocalDate.of(2026, 7, 1)), null)).isTrue()
    }

    private fun request(start: LocalDate): RawSnapshotRequest {
        val zone = ZoneId.of("America/New_York")
        val startInstant = start.atStartOfDay(zone).toInstant()
        val endInstant = start.plusDays(1).atStartOfDay(zone).toInstant()
        return RawSnapshotRequest(
            format = RawExportFormat.NDJSON,
            scope = RawSnapshotScope.SELECTED_RECORD_TYPES,
            startTime = RawInstant(startInstant.epochSecond, startInstant.nano),
            endTime = RawInstant(endInstant.epochSecond, endInstant.nano),
            selectedMetricIds = setOf("steps"),
            calendarZoneId = zone.id,
        )
    }
}
