package com.healthmd.widget

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.presentation.archive.CoverageStatus
import com.healthmd.widget.glance.ArchiveWidgetSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class ArchiveWidgetSummaryTest {
    private val today = LocalDate.of(2026, 11, 2)

    @Test
    fun `streak crosses the month boundary and recent ends with today`() {
        val entries = listOf(
            ExportHistoryEntry(
                timestamp = 1,
                source = ExportSource.SCHEDULED,
                dateRangeStart = today.minusDays(10),
                dateRangeEnd = today.minusDays(1),
                successCount = 9,
                totalCount = 10,
                failedDateDetails = listOf(FailedDateDetail(today.minusDays(6), ExportFailureReason.FILE_WRITE_ERROR)),
            ),
        )
        val summary = ArchiveWidgetSummary.from(entries, today)
        assertTrue(summary.hasHistory)
        assertEquals(5, summary.streak)
        assertEquals(1, summary.gapCount)
        assertEquals(ArchiveWidgetSummary.RECENT_DAYS, summary.recent.size)
        assertEquals(CoverageStatus.IN_PROGRESS, summary.recent.last())
        assertEquals(CoverageStatus.MISSING, summary.recent[summary.recent.size - 7])
    }

    @Test
    fun `no history renders the empty state`() {
        val summary = ArchiveWidgetSummary.from(emptyList(), today)
        assertFalse(summary.hasHistory)
        assertEquals(0, summary.streak)
        assertTrue(summary.recent.dropLast(1).all { it == CoverageStatus.NOT_DUE })
    }
}
