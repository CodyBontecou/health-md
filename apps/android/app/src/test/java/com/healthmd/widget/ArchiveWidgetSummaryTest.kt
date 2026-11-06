package com.healthmd.widget

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.presentation.archive.ArchiveProfile
import com.healthmd.presentation.archive.CoverageStatus
import com.healthmd.widget.glance.ArchiveWidgetSummary
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.YearMonth

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
        val summary = ArchiveWidgetSummary.from(entries, today, dueToday = setOf(ArchiveProfile(null)))
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

    @Test
    fun `month count holds archived days of the current month and the strip keeps dates`() {
        val october31 = LocalDate.of(2026, 10, 31)
        val entries = listOf(
            ExportHistoryEntry(
                timestamp = 1,
                source = ExportSource.SCHEDULED,
                dateRangeStart = LocalDate.of(2026, 9, 25),
                dateRangeEnd = october31.minusDays(1),
                successCount = 32,
                totalCount = 36,
                failedDateDetails = listOf(
                    FailedDateDetail(LocalDate.of(2026, 10, 19), ExportFailureReason.FILE_WRITE_ERROR),
                    FailedDateDetail(LocalDate.of(2026, 10, 20), ExportFailureReason.FILE_WRITE_ERROR),
                    FailedDateDetail(LocalDate.of(2026, 10, 23), ExportFailureReason.NO_HEALTH_DATA),
                    FailedDateDetail(LocalDate.of(2026, 10, 26), ExportFailureReason.NO_HEALTH_DATA),
                ),
            ),
        )

        val summary = ArchiveWidgetSummary.from(entries, october31, dueToday = setOf(ArchiveProfile(null)))

        assertEquals(YearMonth.of(2026, 10), summary.month)
        // October 1–30 minus the two gaps; September days and today never count.
        assertEquals(28, summary.monthArchivedCount)
        assertEquals(10, summary.streak)
        assertEquals(2, summary.gapCount)
        assertEquals(LocalDate.of(2026, 10, 18), summary.recentDays.first().date)
        assertEquals(october31, summary.recentDays.last().date)
        assertEquals(CoverageStatus.MISSING, summary.recentDays[1].status)
        assertEquals(CoverageStatus.PARTIAL, summary.recentDays[5].status)
        assertEquals(CoverageStatus.IN_PROGRESS, summary.recentDays.last().status)
    }

    @Test
    fun `next run is the earliest future occurrence across enabled schedules`() {
        val now = Instant.parse("2026-10-31T06:00:00Z")
        val daily = ScheduledProfileEntry(
            profileId = "daily",
            isEnabled = true,
            anchorEpochDay = LocalDate.of(2026, 10, 1).toEpochDay(),
            hour = 7,
            minute = 30,
            zoneId = "UTC",
        )
        val disabledEarlier = daily.copy(profileId = "off", isEnabled = false, hour = 6, minute = 15)
        val expected = Instant.parse("2026-10-31T07:30:00Z").toEpochMilli()

        assertEquals(
            expected,
            ArchiveWidgetSummary.nextRunAtMillis(
                appScheduleAtMillis = null,
                profileEntries = listOf(disabledEarlier, daily),
                nowMillis = now.toEpochMilli(),
            ),
        )
        val appSchedule = now.plusSeconds(600).toEpochMilli()
        assertEquals(
            appSchedule,
            ArchiveWidgetSummary.nextRunAtMillis(appSchedule, listOf(daily), now.toEpochMilli()),
        )
        // A stale app-wide trigger in the past is not shown as the next run.
        assertNull(
            ArchiveWidgetSummary.nextRunAtMillis(
                appScheduleAtMillis = now.minusSeconds(60).toEpochMilli(),
                profileEntries = emptyList(),
                nowMillis = now.toEpochMilli(),
            ),
        )
    }
}
