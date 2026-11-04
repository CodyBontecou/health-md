package com.healthmd.presentation.archive

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.FailedDateDetail
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.YearMonth

class ArchiveCoverageTest {
    private val today = LocalDate.of(2026, 10, 31)
    private val daily = ArchiveProfile("Daily")
    private val weekly = ArchiveProfile("Weekly CSV")

    private fun entry(
        start: LocalDate,
        end: LocalDate = start,
        success: Int = 1,
        total: Int = 1,
        failed: List<FailedDateDetail> = emptyList(),
        profile: String? = "Daily",
        timestamp: Long = start.toEpochDay(),
    ) = ExportHistoryEntry(
        timestamp = timestamp,
        source = ExportSource.SCHEDULED,
        dateRangeStart = start,
        dateRangeEnd = end,
        successCount = success,
        totalCount = total,
        failedDateDetails = failed,
        profileName = profile,
    )

    @Test
    fun `written dates are complete and uncovered past dates are not due`() {
        val entries = listOf(entry(LocalDate.of(2026, 10, 10)))
        assertEquals(CoverageStatus.COMPLETE, ArchiveCoverage.status(entries, daily, LocalDate.of(2026, 10, 10), today))
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.status(entries, daily, LocalDate.of(2026, 10, 11), today))
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.status(entries, weekly, LocalDate.of(2026, 10, 10), today))
    }

    @Test
    fun `today is in progress and future dates are not due`() {
        val entries = listOf(entry(today))
        assertEquals(CoverageStatus.IN_PROGRESS, ArchiveCoverage.status(entries, daily, today, today))
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.status(entries, daily, today.plusDays(1), today))
    }

    @Test
    fun `failed dates are missing until a later run writes them`() {
        val gap = LocalDate.of(2026, 10, 19)
        val failedRun = entry(
            start = gap.minusDays(1),
            end = gap,
            success = 1,
            total = 2,
            failed = listOf(FailedDateDetail(gap, ExportFailureReason.RATE_LIMITED)),
        )
        assertEquals(CoverageStatus.MISSING, ArchiveCoverage.status(listOf(failedRun), daily, gap, today))
        assertEquals(CoverageStatus.COMPLETE, ArchiveCoverage.status(listOf(failedRun), daily, gap.minusDays(1), today))

        val backfill = entry(gap, timestamp = failedRun.timestamp + 10)
        assertEquals(CoverageStatus.COMPLETE, ArchiveCoverage.status(listOf(failedRun, backfill), daily, gap, today))
    }

    @Test
    fun `a later failure never hides a date that was already written`() {
        val date = LocalDate.of(2026, 10, 5)
        val written = entry(date, timestamp = 1)
        val laterFailure = entry(date, success = 0, total = 1, timestamp = 2)
        assertEquals(CoverageStatus.COMPLETE, ArchiveCoverage.status(listOf(written, laterFailure), daily, date, today))
    }

    @Test
    fun `no health data and undetailed partial runs are partial`() {
        val date = LocalDate.of(2026, 10, 12)
        val noData = entry(date, success = 0, total = 1, failed = listOf(FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA)))
        assertEquals(CoverageStatus.PARTIAL, ArchiveCoverage.status(listOf(noData), daily, date, today))

        val undetailed = entry(date.minusDays(1), date, success = 1, total = 2)
        assertEquals(CoverageStatus.PARTIAL, ArchiveCoverage.status(listOf(undetailed), daily, date, today))
    }

    @Test
    fun `All aggregates due profiles with missing over partial over complete`() {
        assertEquals(
            CoverageStatus.MISSING,
            ArchiveCoverage.aggregate(listOf(CoverageStatus.COMPLETE, CoverageStatus.MISSING, CoverageStatus.PARTIAL), isToday = false),
        )
        assertEquals(
            CoverageStatus.PARTIAL,
            ArchiveCoverage.aggregate(listOf(CoverageStatus.COMPLETE, CoverageStatus.PARTIAL, CoverageStatus.NOT_DUE), isToday = false),
        )
        assertEquals(CoverageStatus.COMPLETE, ArchiveCoverage.aggregate(listOf(CoverageStatus.COMPLETE, CoverageStatus.NOT_DUE), isToday = false))
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.aggregate(listOf(CoverageStatus.NOT_DUE), isToday = false))
        assertEquals(CoverageStatus.IN_PROGRESS, ArchiveCoverage.aggregate(listOf(CoverageStatus.MISSING), isToday = true))
    }

    @Test
    fun `streak runs back from yesterday, skips not due dates and stops at the first gap`() {
        val days = listOf(
            LocalDate.of(2026, 10, 25) to CoverageStatus.COMPLETE,
            LocalDate.of(2026, 10, 26) to CoverageStatus.MISSING,
            LocalDate.of(2026, 10, 27) to CoverageStatus.COMPLETE,
            LocalDate.of(2026, 10, 28) to CoverageStatus.NOT_DUE,
            LocalDate.of(2026, 10, 29) to CoverageStatus.PARTIAL,
            LocalDate.of(2026, 10, 30) to CoverageStatus.COMPLETE,
            today to CoverageStatus.IN_PROGRESS,
        )
        val stats = ArchiveCoverage.stats(days, today)
        assertEquals(4, stats.archivedCount)
        assertEquals(1, stats.gapCount)
        assertEquals(3, stats.streak)
        assertEquals(LocalDate.of(2026, 10, 26), stats.earliestGap)
    }

    @Test
    fun `the month card carries the current streak across the month boundary`() {
        val today = LocalDate.of(2026, 11, 3)
        val gap = LocalDate.of(2026, 10, 5)
        val entries = listOf(
            entry(
                start = LocalDate.of(2026, 10, 1),
                end = LocalDate.of(2026, 11, 2),
                success = 32,
                total = 33,
                failed = listOf(FailedDateDetail(gap, ExportFailureReason.UNKNOWN)),
            ),
        )
        val november = ArchiveCoverage.month(entries, YearMonth.of(2026, 11), today, filter = null)
        assertEquals(2, november.stats.archivedCount)
        // Oct 6 through Nov 2, not just Nov 1 and 2; the widget reads the same number.
        assertEquals(28, november.stats.streak)
        assertEquals(28, ArchiveCoverage.currentStreak(entries, today))
    }

    @Test
    fun `month aggregates profiles with issue dots and a filter shows one profile`() {
        val gap = LocalDate.of(2026, 10, 19)
        val entries = listOf(
            entry(LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 30), success = 29, total = 30,
                failed = listOf(FailedDateDetail(gap, ExportFailureReason.FILE_WRITE_ERROR)), timestamp = 2),
            entry(LocalDate.of(2026, 10, 13), LocalDate.of(2026, 10, 19), success = 7, total = 7, profile = "Weekly CSV", timestamp = 1),
        )
        val month = ArchiveCoverage.month(entries, YearMonth.of(2026, 10), today, filter = null)
        assertEquals(listOf(daily, weekly), month.profiles)
        assertEquals(31, month.days.size)

        val gapDay = month.days.first { it.date == gap }
        assertEquals(CoverageStatus.MISSING, gapDay.status)
        assertEquals(listOf(ArchiveIssueDot(daily, isFilled = false)), gapDay.issueDots)
        assertEquals(CoverageStatus.IN_PROGRESS, month.days.last().status)
        assertEquals(1, month.stats.gapCount)
        assertEquals(gap, month.stats.earliestGap)

        val weeklyOnly = ArchiveCoverage.month(entries, YearMonth.of(2026, 10), today, filter = weekly)
        assertEquals(CoverageStatus.COMPLETE, weeklyOnly.days.first { it.date == gap }.status)
        assertTrue(weeklyOnly.days.all { it.issueDots.isEmpty() })
        assertEquals(0, weeklyOnly.stats.gapCount)
    }

    @Test
    fun `selected day rows report on track counts and the latest covering entry`() {
        val date = LocalDate.of(2026, 10, 20)
        val older = entry(date, timestamp = 1)
        val newer = entry(date, timestamp = 5)
        val rows = ArchiveCoverage.profileDays(listOf(older, newer), listOf(daily, weekly), date, today)
        assertEquals(newer, rows.first().latestEntry)
        assertNull(rows.last().latestEntry)
        assertEquals(1 to 1, ArchiveCoverage.onTrack(rows))
    }

    @Test
    fun `entries without a profile name form the current settings lane`() {
        val date = LocalDate.of(2026, 10, 3)
        val entries = listOf(entry(date, profile = null))
        assertEquals(listOf(ArchiveProfile(null)), ArchiveCoverage.profiles(entries))
        assertEquals(CoverageStatus.COMPLETE, ArchiveCoverage.status(entries, ArchiveProfile(null), date, today))
    }
}
