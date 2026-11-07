package com.healthmd.presentation.archive

import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate

class ArchiveAttentionTest {
    private val date = LocalDate.of(2026, 10, 30)

    private fun run(
        timestamp: Long,
        success: Int,
        target: ExportTarget = ExportTarget.API_ENDPOINT,
        profile: String? = "Feed",
        details: String? = null,
        reason: ExportFailureReason? = null,
    ) = ExportHistoryEntry(
        timestamp = timestamp,
        source = ExportSource.SCHEDULED,
        dateRangeStart = date,
        dateRangeEnd = date,
        successCount = success,
        totalCount = 1,
        failureReason = reason,
        failedDateDetails = if (success == 0) listOf(FailedDateDetail(date, reason ?: ExportFailureReason.API_REJECTED, details)) else emptyList(),
        target = target,
        profileName = profile,
    )

    private fun profile(id: String, name: String, target: ExportTarget, folderUri: String? = null, url: String? = null) = ExportProfile(
        id = id,
        name = name,
        settingsSnapshotJson = "{}",
        target = target,
        apiEndpointUrl = url,
        folderUri = folderUri,
        createdAtEpochMillis = 0,
        updatedAtEpochMillis = 0,
    )

    private fun inputs(
        entries: List<ExportHistoryEntry> = emptyList(),
        sources: ArchiveLaneSources = ArchiveLaneSources(),
        healthConnected: Boolean? = true,
        folderAccessible: Boolean = true,
        folderName: String? = null,
    ) = ArchiveAttentionInputs(entries, sources, healthConnected, folderAccessible, folderName)

    @Test
    fun `nothing needs attention when health, folder and endpoints are fine`() {
        assertTrue(ArchiveAttention.items(inputs()).isEmpty())
        // An unchecked Health Connect state is not reported as a problem.
        assertTrue(ArchiveAttention.items(inputs(healthConnected = null)).isEmpty())
    }

    @Test
    fun `missing Health Connect permission is listed first`() {
        val items = ArchiveAttention.items(inputs(healthConnected = false))
        assertEquals(listOf(ArchiveAttentionItem.HealthPermission), items)
    }

    @Test
    fun `an unavailable folder names the automations waiting on it`() {
        val sources = ArchiveLaneSources(
            profiles = listOf(
                profile("a", "Daily", ExportTarget.DEVICE_FOLDER),
                profile("b", "Elsewhere", ExportTarget.DEVICE_FOLDER, folderUri = "content://other"),
                profile("c", "Feed", ExportTarget.API_ENDPOINT),
            ),
            appFolderUri = "content://vault",
        )
        val items = ArchiveAttention.items(inputs(sources = sources, folderAccessible = false, folderName = "Vault"))
        assertEquals(listOf(ArchiveAttentionItem.FolderUnavailable("Vault", listOf("Daily"))), items)
        // No folder chosen yet is setup, not a lost folder.
        assertTrue(ArchiveAttention.items(inputs(sources = sources.copy(appFolderUri = null), folderAccessible = false)).isEmpty())
    }

    @Test
    fun `failing endpoint runs count the streak and its repeated status`() {
        val entries = listOf(
            run(1, success = 1),
            run(2, success = 0, details = "HTTP 503 Service Unavailable"),
            run(3, success = 0, details = "HTTP 503"),
            run(4, success = 0, details = "HTTP 503"),
            run(5, success = 1, target = ExportTarget.DEVICE_FOLDER),
        )
        val sources = ArchiveLaneSources(
            profiles = listOf(profile("feed", "Feed", ExportTarget.API_ENDPOINT, url = "https://api.example.com/health")),
            schedules = listOf(ScheduledProfileEntry(profileId = "feed", isEnabled = true, anchorEpochDay = 0, todayRefreshEnabled = true)),
        )
        val item = ArchiveAttention.items(inputs(entries, sources)).single() as ArchiveAttentionItem.EndpointFailing
        assertEquals(ExportTarget.API_ENDPOINT, item.target)
        assertEquals("api.example.com", item.host)
        assertEquals(3, item.failures)
        assertEquals(503, item.httpStatus)
        assertEquals("feed", item.profileId)
        assertEquals(ArchiveAttentionItem.Retry.NEXT_REFRESH, item.retry)
    }

    @Test
    fun `a recovered endpoint or mixed statuses read accordingly`() {
        assertTrue(ArchiveAttention.items(inputs(listOf(run(1, success = 0), run(2, success = 1)))).isEmpty())
        val mixed = listOf(
            run(1, success = 0, details = "HTTP 500"),
            run(2, success = 0, details = "HTTP 503", reason = ExportFailureReason.NETWORK_ERROR),
        )
        val item = ArchiveAttention.items(inputs(mixed, ArchiveLaneSources(settings = ExportSettings()))).single()
            as ArchiveAttentionItem.EndpointFailing
        assertEquals(2, item.failures)
        assertNull(item.httpStatus)
        assertEquals(ExportFailureReason.NETWORK_ERROR, item.reason)
        // No profile or URL: the host falls back to the destination's name in the UI.
        assertNull(item.host)
        assertNull(item.retry)
    }

    @Test
    fun `http statuses come from status-only descriptions`() {
        assertEquals(503, ArchiveAttention.httpStatus("HTTP 503"))
        assertEquals(429, ArchiveAttention.httpStatus("rejected: HTTP 429 Too Many Requests"))
        assertNull(ArchiveAttention.httpStatus("timeout"))
        assertNull(ArchiveAttention.httpStatus(null))
        assertEquals(503, ArchiveAttention.repeatedStatus(listOf("HTTP 503", "HTTP 503")))
        assertNull(ArchiveAttention.repeatedStatus(listOf("HTTP 503", null)))
        assertNull(ArchiveAttention.repeatedStatus(emptyList()))
    }
}
