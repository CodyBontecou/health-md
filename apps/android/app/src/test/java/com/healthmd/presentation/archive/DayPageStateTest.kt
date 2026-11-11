package com.healthmd.presentation.archive

import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.ExportFailureReason
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class DayPageStateTest {
    private val today = LocalDate.of(2026, 11, 5)
    private val date = LocalDate.of(2026, 11, 2)
    private val settings = ExportSettings(subfolder = "Health", exportFormats = setOf(ExportFormat.MARKDOWN))
    private val sources = ArchiveLaneSources(settings = settings, appFolderUri = "content://tree/vault")

    private fun entry(profile: String?, success: Int = 1, timestamp: Long = 1, target: ExportTarget = ExportTarget.DEVICE_FOLDER) =
        ExportHistoryEntry(
            timestamp = timestamp,
            source = ExportSource.SCHEDULED,
            dateRangeStart = date,
            dateRangeEnd = date,
            successCount = success,
            totalCount = 1,
            failedDateDetails = if (success == 0) listOf(FailedDateDetail(date, ExportFailureReason.FILE_WRITE_ERROR)) else emptyList(),
            target = target,
            profileName = profile,
        )

    @Test
    fun `lanes round-trip through the route, the current settings lane included`() {
        for (lane in listOf(ArchiveProfile(null), ArchiveProfile("Daily"), ArchiveProfile("n:odd / name"))) {
            assertEquals(lane, DayPageViewModel.decodeLane(DayPageViewModel.encodeLane(lane)))
        }
        assertNull(DayPageViewModel.decodeLane(null))
        assertNull(DayPageViewModel.decodeLane("garbage"))
    }

    @Test
    fun `the route's lane opens its tab, else the lead lane`() {
        val entries = listOf(entry(null, timestamp = 2), entry("Weekly", success = 0, timestamp = 1))
        val asked = DayPageViewModel.state(entries, sources, ArchiveProfile("Weekly"), date, today)
        assertEquals(2, asked.lanes.size)
        assertEquals(ArchiveProfile("Weekly"), asked.lane?.row?.day?.profile)
        val lead = DayPageViewModel.state(entries, sources, null, date, today)
        assertEquals(ArchiveProfile(null), lead.lane?.row?.day?.profile)
        // A lane that no longer exists falls back to the lead.
        assertEquals(ArchiveProfile(null), DayPageViewModel.state(entries, sources, ArchiveProfile("Gone"), date, today).selected)
    }

    @Test
    fun `a written day reads its own file and offers re-export`() {
        val state = DayPageViewModel.state(listOf(entry(null)), sources, null, date, today)
        val key = state.fileKey!!
        assertEquals(ArchiveFileRef("content://tree/vault", "Health/2026-11-02.md"), key.ref)
        assertEquals(CoverageStatus.COMPLETE, key.status)
        assertEquals(ArchiveDayAction.REEXPORT, state.secondaryAction)
        assertTrue(state.lane!!.row.writesFilesOnDevice)
    }

    @Test
    fun `a gap reads nothing and offers backfill for its automation`() {
        val profile = com.healthmd.domain.model.ExportProfile(
            id = "weekly-id",
            name = "Weekly",
            settingsSnapshotJson = "{}",
            target = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://api.example.com/in",
            createdAtEpochMillis = 0,
            updatedAtEpochMillis = 0,
        )
        val withProfile = sources.copy(
            profiles = listOf(profile),
            schedules = listOf(ScheduledProfileEntry(profileId = "weekly-id", anchorEpochDay = 0)),
        )
        val state = DayPageViewModel.state(listOf(entry("Weekly", success = 0)), withProfile, null, date, today)
        val lane = state.lane!!
        assertEquals(CoverageStatus.MISSING, lane.row.day.status)
        assertNull(state.fileKey)
        assertEquals(ArchiveDayAction.BACKFILL, state.secondaryAction)
        assertEquals("weekly-id", lane.row.automationId)
        assertFalse(lane.row.writesFilesOnDevice)
        // Its schedule is off, so the lane reads as paused.
        assertTrue(lane.isPaused)
    }

    @Test
    fun `without a chosen folder there is a path but nothing to read`() {
        val state = DayPageViewModel.state(listOf(entry(null)), sources.copy(appFolderUri = null), null, date, today)
        assertEquals("Health/2026-11-02.md", state.lane?.row?.path)
        assertNull(state.fileKey)
    }
}
