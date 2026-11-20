package com.healthmd.presentation.archive

import com.healthmd.presentation.schedule.ScheduleUiState
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The Archive's next-run card never promises a run that schedule access gates off. */
class ArchiveNextRunLineTest {
    private val run = ArchiveNextRun(profileName = "Default", atMillis = 1_800_000_000_000L)

    @Test
    fun scheduledRunShowsWithAccess() {
        assertEquals(ArchiveNextRunLine.Scheduled(run), ArchiveNextRunLine.of(run, hasScheduleAccess = true))
    }

    @Test
    fun lockedScheduleNeedsSubscriptionInsteadOfANextRun() {
        assertEquals(ArchiveNextRunLine.NeedsSubscription, ArchiveNextRunLine.of(run, hasScheduleAccess = false))
    }

    @Test
    fun nothingScheduledIsTheSameWithOrWithoutAccess() {
        assertEquals(ArchiveNextRunLine.NothingScheduled, ArchiveNextRunLine.of(null, hasScheduleAccess = true))
        assertEquals(ArchiveNextRunLine.NothingScheduled, ArchiveNextRunLine.of(null, hasScheduleAccess = false))
    }

    @Test
    fun scheduleAccessIsPurchaseOrClinicDestination() {
        assertFalse(ScheduleUiState().hasScheduleAccess)
        assertTrue(ScheduleUiState(isPurchased = true).hasScheduleAccess)
        assertTrue(ScheduleUiState(clinicDestinationAuthorized = true).hasScheduleAccess)
    }
}
