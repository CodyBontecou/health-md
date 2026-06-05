package com.healthmd.data.scheduler

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.PendingScheduledExportRequest
import org.junit.Test
import java.time.LocalDate

class ScheduledExportPendingRequestsTest {

    @Test
    fun pendingRequests_mergesLegacyDatesWithExplicitRequests() {
        val explicitDate = LocalDate.parse("2026-06-02")
        val settings = ExportSettings(
            pendingScheduledRetryDates = listOf("2026-06-01", "not-a-date", "2026-06-02"),
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = explicitDate,
                    firstFailedAtMillis = 100L,
                    lastAttemptAtMillis = 200L,
                    lastFailureReason = ExportFailureReason.DEVICE_LOCKED,
                    attemptCount = 2,
                )
            ),
        )

        val requests = ScheduledExportPendingRequests.pendingRequests(settings)

        assertThat(requests.map { it.date }).containsExactly(
            LocalDate.parse("2026-06-01"),
            explicitDate,
        ).inOrder()
        assertThat(requests.first { it.date == explicitDate }.lastFailureReason)
            .isEqualTo(ExportFailureReason.DEVICE_LOCKED)
        assertThat(requests.first { it.date == explicitDate }.attemptCount).isEqualTo(2)
    }

    @Test
    fun applyAttemptResult_clearsSuccessfulDatesAndKeepsFailedAndUnattemptedDates() {
        val date1 = LocalDate.parse("2026-06-01")
        val date2 = LocalDate.parse("2026-06-02")
        val date3 = LocalDate.parse("2026-06-03")
        val settings = ExportSettings(
            pendingScheduledExportRequests = listOf(date1, date2, date3).map {
                PendingScheduledExportRequest(date = it, firstFailedAtMillis = 100L, attemptCount = 1)
            },
        )

        val updated = ScheduledExportPendingRequests.applyAttemptResult(
            settings = settings,
            attemptedDates = listOf(date1, date2),
            failedDateDetails = listOf(FailedDateDetail(date2, ExportFailureReason.FILE_WRITE_ERROR)),
            nowMillis = 500L,
        )

        val requests = ScheduledExportPendingRequests.pendingRequests(updated)
        assertThat(requests.map { it.date }).containsExactly(date2, date3).inOrder()
        assertThat(requests.first { it.date == date2 }.lastFailureReason)
            .isEqualTo(ExportFailureReason.FILE_WRITE_ERROR)
        assertThat(requests.first { it.date == date2 }.lastAttemptAtMillis).isEqualTo(500L)
        assertThat(updated.pendingScheduledRetryDates).containsExactly("2026-06-02", "2026-06-03").inOrder()
    }
}
