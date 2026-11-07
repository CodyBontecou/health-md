package com.healthmd.presentation.archive

import com.healthmd.data.scheduler.ScheduledProfileCadenceUnit
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.rawexport.ExportMode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
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
    fun `today is in progress only when due and future dates are not due`() {
        val entries = listOf(entry(today))
        assertEquals(CoverageStatus.IN_PROGRESS, ArchiveCoverage.status(entries, daily, today, today, isDueToday = true))
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.status(entries, daily, today.plusDays(1), today, isDueToday = true))
        // On demand: today's written file shows, and nothing written is not due rather than a gap.
        assertEquals(CoverageStatus.COMPLETE, ArchiveCoverage.status(entries, daily, today, today))
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.status(emptyList(), daily, today, today))
        val failedToday = entry(today, success = 0, total = 1)
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.status(listOf(failedToday), daily, today, today))
    }

    @Test
    fun `an on-demand-only today is not due in All and on the day card`() {
        val entries = listOf(entry(today.minusDays(1)))
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.aggregateDay(entries, today, today))
        assertEquals(CoverageStatus.IN_PROGRESS, ArchiveCoverage.aggregateDay(entries, today, today, dueToday = setOf(daily)))

        val rows = ArchiveCoverage.profileDays(entries, listOf(daily), today, today)
        assertEquals(CoverageStatus.NOT_DUE, rows.single().status)
        assertEquals(0 to 0, ArchiveCoverage.onTrack(rows))
        val month = ArchiveCoverage.month(entries, YearMonth.from(today), today, filter = null)
        assertEquals(CoverageStatus.NOT_DUE, month.days.last().status)
    }

    @Test
    fun `daily schedules and Today Refresh make a lane due today`() {
        fun schedule(id: String, enabled: Boolean = true, unit: ScheduledProfileCadenceUnit = ScheduledProfileCadenceUnit.DAY,
            value: Int = 1, refresh: Boolean = false) = ScheduledProfileEntry(
            profileId = id, isEnabled = enabled, anchorEpochDay = today.toEpochDay(),
            cadenceUnit = unit, cadenceValue = value, todayRefreshEnabled = refresh,
        )
        assertTrue(ArchiveCoverage.isDueToday(schedule("a")))
        assertTrue(ArchiveCoverage.isDueToday(schedule("a", unit = ScheduledProfileCadenceUnit.WEEK, refresh = true)))
        assertFalse(ArchiveCoverage.isDueToday(schedule("a", unit = ScheduledProfileCadenceUnit.WEEK)))
        assertFalse(ArchiveCoverage.isDueToday(schedule("a", value = 2)))
        assertFalse(ArchiveCoverage.isDueToday(schedule("a", enabled = false)))
        assertFalse(ArchiveCoverage.isDueToday(null as ScheduledProfileEntry?))

        fun profile(id: String, name: String) = ExportProfile(
            id = id, name = name, settingsSnapshotJson = "{}", target = ExportTarget.DEVICE_FOLDER,
            createdAtEpochMillis = 0, updatedAtEpochMillis = 0,
        )
        val due = ArchiveCoverage.dueToday(
            lanes = listOf(daily, weekly, ArchiveProfile(null)),
            profiles = listOf(profile("d", "Daily"), profile("w", "Weekly CSV")),
            schedules = listOf(schedule("d"), schedule("w", unit = ScheduledProfileCadenceUnit.WEEK)),
            settings = ExportSettings(scheduleEnabled = false),
        )
        assertEquals(setOf(daily), due)
    }

    @Test
    fun `row actions follow the coverage status`() {
        assertEquals(ArchiveDayAction.OPEN, ArchiveCoverage.action(CoverageStatus.COMPLETE, hasTodayRefresh = false, canOpen = true))
        assertNull(ArchiveCoverage.action(CoverageStatus.COMPLETE, hasTodayRefresh = false, canOpen = false))
        assertEquals(ArchiveDayAction.REEXPORT, ArchiveCoverage.action(CoverageStatus.PARTIAL, hasTodayRefresh = false, canOpen = true))
        assertEquals(ArchiveDayAction.RETRY, ArchiveCoverage.action(CoverageStatus.PARTIAL, hasTodayRefresh = true, canOpen = true))
        assertEquals(ArchiveDayAction.BACKFILL, ArchiveCoverage.action(CoverageStatus.MISSING, hasTodayRefresh = false, canOpen = false))
        assertEquals(ArchiveDayAction.REFRESH, ArchiveCoverage.action(CoverageStatus.IN_PROGRESS, hasTodayRefresh = false, canOpen = false))
        assertNull(ArchiveCoverage.action(CoverageStatus.NOT_DUE, hasTodayRefresh = true, canOpen = true))
    }

    @Test
    fun `path lines name the dated file, the folder or the endpoint`() {
        val date = LocalDate.of(2026, 10, 19)
        val settings = ExportSettings(subfolder = "Health", exportFormats = setOf(ExportFormat.MARKDOWN))
        val folder = ArchiveOutput.DeviceFolder(folderName = "Vault", settings = settings)
        assertEquals("Vault/Health/2026-10-19.md", ArchiveCoverage.pathLine(folder, date, CoverageStatus.COMPLETE))
        assertEquals("Vault", ArchiveCoverage.pathLine(folder, date, CoverageStatus.NOT_DUE))
        assertEquals(
            "Health/2026-10-19.md",
            ArchiveCoverage.pathLine(folder.copy(folderName = null), date, CoverageStatus.MISSING),
        )
        val raw = folder.copy(settings = settings.copy(exportMode = ExportMode.RAW_SNAPSHOT))
        assertEquals("Vault", ArchiveCoverage.pathLine(raw, date, CoverageStatus.COMPLETE))
        assertNull(ArchiveCoverage.pathLine(null, date, CoverageStatus.COMPLETE))

        assertEquals("POST api.example.com/health", ArchiveCoverage.endpointLine("https://user:pw@api.example.com/health?key=secret"))
        assertEquals("POST api.example.com:8443", ArchiveCoverage.endpointLine("https://api.example.com:8443/"))
        assertNull(ArchiveCoverage.endpointLine(""))
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
        assertEquals(CoverageStatus.IN_PROGRESS, ArchiveCoverage.aggregate(listOf(CoverageStatus.IN_PROGRESS), isToday = true))
        assertEquals(
            CoverageStatus.IN_PROGRESS,
            ArchiveCoverage.aggregate(listOf(CoverageStatus.COMPLETE, CoverageStatus.NOT_DUE), isToday = true),
        )
        // Nothing due today reads as not due, never as updating (Apple parity).
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.aggregate(listOf(CoverageStatus.NOT_DUE), isToday = true))
        assertEquals(CoverageStatus.NOT_DUE, ArchiveCoverage.aggregate(emptyList(), isToday = true))
    }

    @Test
    fun `stats count archived days and gaps before today`() {
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
        assertEquals(LocalDate.of(2026, 10, 26), stats.earliestGap)
    }

    @Test
    fun `month aggregates profiles with issue dots and a filter shows one profile`() {
        val gap = LocalDate.of(2026, 10, 19)
        val entries = listOf(
            entry(LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 30), success = 29, total = 30,
                failed = listOf(FailedDateDetail(gap, ExportFailureReason.FILE_WRITE_ERROR)), timestamp = 2),
            entry(LocalDate.of(2026, 10, 13), LocalDate.of(2026, 10, 19), success = 7, total = 7, profile = "Weekly CSV", timestamp = 1),
        )
        val month = ArchiveCoverage.month(entries, YearMonth.of(2026, 10), today, filter = null, dueToday = setOf(daily))
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

    @Test
    fun `the gap button jumps to the earliest gap of the shown month`() {
        val first = LocalDate.of(2026, 10, 8)
        val second = LocalDate.of(2026, 10, 21)
        val entries = listOf(
            entry(LocalDate.of(2026, 9, 20), LocalDate.of(2026, 10, 30), success = 38, total = 41,
                failed = listOf(
                    FailedDateDetail(LocalDate.of(2026, 9, 25), ExportFailureReason.FILE_WRITE_ERROR),
                    FailedDateDetail(second, ExportFailureReason.FILE_WRITE_ERROR),
                    FailedDateDetail(first, ExportFailureReason.FILE_WRITE_ERROR),
                )),
        )
        val october = ArchiveCoverage.month(entries, YearMonth.of(2026, 10), today, filter = null)
        assertEquals(2, october.stats.gapCount)
        assertEquals(first, october.stats.earliestGap)

        val clean = ArchiveCoverage.month(listOf(entry(LocalDate.of(2026, 10, 1), LocalDate.of(2026, 10, 30))),
            YearMonth.of(2026, 10), today, filter = null)
        assertEquals(0, clean.stats.gapCount)
        assertNull(clean.stats.earliestGap)
    }
}
