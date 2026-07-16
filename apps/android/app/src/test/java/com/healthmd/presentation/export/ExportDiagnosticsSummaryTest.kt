package com.healthmd.presentation.export

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.FailedDateDetail
import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExportDiagnosticsSummaryTest {

    @Test
    fun partialRateLimitedExportShowsFailedDayCountAndRateLimitGuidance() {
        val failedDates = (11 until 90).map { offset ->
            FailedDateDetail(
                date = LocalDate.of(2026, 1, 1).plusDays(offset.toLong()),
                reason = ExportFailureReason.RATE_LIMITED,
            )
        }
        val result = ExportResult(
            successCount = 11,
            totalCount = 90,
            failedDateDetails = failedDates,
        )

        val summary = result.toDiagnosticsSummary()

        assertTrue(summary.isPartial)
        assertEquals(79, summary.failedDayCount)
        assertEquals(1, summary.failureGroups.size)
        assertEquals(ExportFailureReason.RATE_LIMITED, summary.failureGroups.single().reason)
        assertEquals(79, summary.failureGroups.single().count)
        assertEquals(ExportDiagnosticGuidance.RATE_LIMIT, summary.failureGroups.single().guidance)
        assertTrue(summary.failureGroups.single().sampleDates.contains(LocalDate.of(2026, 1, 12)))
        assertFalse(summary.shouldAutoDismiss)
    }

    @Test
    fun groupsFailuresByReasonInDescendingCountOrder() {
        val result = ExportResult(
            successCount = 3,
            totalCount = 8,
            failedDateDetails = listOf(
                FailedDateDetail(LocalDate.of(2026, 2, 1), ExportFailureReason.FILE_WRITE_ERROR),
                FailedDateDetail(LocalDate.of(2026, 2, 2), ExportFailureReason.NO_HEALTH_DATA),
                FailedDateDetail(LocalDate.of(2026, 2, 3), ExportFailureReason.FILE_WRITE_ERROR),
                FailedDateDetail(LocalDate.of(2026, 2, 4), ExportFailureReason.ACCESS_DENIED),
                FailedDateDetail(LocalDate.of(2026, 2, 5), ExportFailureReason.FILE_WRITE_ERROR),
            ),
        )

        val summary = result.toDiagnosticsSummary()

        assertEquals(
            listOf(
                ExportFailureReason.FILE_WRITE_ERROR,
                ExportFailureReason.NO_HEALTH_DATA,
                ExportFailureReason.ACCESS_DENIED,
            ),
            summary.failureGroups.map { it.reason },
        )
        assertEquals(ExportDiagnosticGuidance.FILE_WRITE, summary.failureGroups[0].guidance)
        assertEquals(ExportDiagnosticGuidance.NO_DATA, summary.failureGroups[1].guidance)
        assertEquals(ExportDiagnosticGuidance.HISTORICAL_PERMISSION, summary.failureGroups[2].guidance)
    }

    @Test
    fun rawPartialUsesProviderNeutralGuidance() {
        val result = ExportResult(
            successCount = 0,
            totalCount = 1,
            failedDateDetails = listOf(
                FailedDateDetail(LocalDate.of(2026, 3, 1), ExportFailureReason.RAW_PARTIAL),
            ),
        )

        val group = result.toDiagnosticsSummary().failureGroups.single()

        assertEquals(ExportDiagnosticGuidance.RAW_PROVIDER, group.guidance)
    }

    @Test
    fun rawCancellationDoesNotSuggestChangingTheSnapshotRange() {
        val result = ExportResult(
            successCount = 0,
            totalCount = 1,
            failedDateDetails = listOf(
                FailedDateDetail(LocalDate.of(2026, 3, 1), ExportFailureReason.RAW_CANCELLED),
            ),
        )

        assertEquals(
            ExportDiagnosticGuidance.RAW_CANCELLED,
            result.toDiagnosticsSummary().failureGroups.single().guidance,
        )
    }

    @Test
    fun fullSuccessCanAutoDismissButPartialAndFailureRemainInspectable() {
        val success = ExportResult(successCount = 7, totalCount = 7)
        val partial = ExportResult(
            successCount = 6,
            totalCount = 7,
            failedDateDetails = listOf(
                FailedDateDetail(LocalDate.of(2026, 3, 7), ExportFailureReason.NO_HEALTH_DATA),
            ),
        )
        val failure = ExportResult(
            successCount = 0,
            totalCount = 7,
            failedDateDetails = (1..7).map { day ->
                FailedDateDetail(LocalDate.of(2026, 3, day), ExportFailureReason.FILE_WRITE_ERROR)
            },
        )

        assertTrue(success.toDiagnosticsSummary().shouldAutoDismiss)
        assertFalse(partial.toDiagnosticsSummary().shouldAutoDismiss)
        assertFalse(failure.toDiagnosticsSummary().shouldAutoDismiss)
    }
}
