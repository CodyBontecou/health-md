package com.healthmd.presentation.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.presentation.export.ExportResultDays.Row
import com.healthmd.rawexport.ExportMode
import java.time.LocalDate
import org.junit.Test

class ExportNowFlowTest {
    private val today = LocalDate.of(2026, 11, 7)
    private fun day(d: Int) = LocalDate.of(2026, 11, d)

    @Test
    fun presetsAreCompletedDaysEndingYesterday() {
        assertThat(ExportNowFlow.presetDates(DateRangeOption.Yesterday, today)).isEqualTo(day(6) to day(6))
        assertThat(ExportNowFlow.presetDates(DateRangeOption.Last7Days, today)).isEqualTo(LocalDate.of(2026, 10, 31) to day(6))
        assertThat(ExportNowFlow.presetDates(DateRangeOption.Last30Days, today)).isEqualTo(LocalDate.of(2026, 10, 8) to day(6))
        assertThat(ExportNowFlow.presetDates(DateRangeOption.Today, today)).isEqualTo(today to today)
        assertThat(ExportNowFlow.presetDates(DateRangeOption.Custom, today)).isNull()
        assertThat(ExportNowFlow.presetDates(DateRangeOption.AllTime, today)).isNull()
    }

    @Test
    fun thirtyDaysAreRecognisedAsThePreset() {
        val yesterday = LocalDate.now().minusDays(1)
        assertThat(DateRangeOption.fromDates(yesterday.minusDays(29), yesterday, allTimeSelected = false))
            .isEqualTo(DateRangeOption.Last30Days)
        assertThat(DateRangeOption.fromDates(yesterday.minusDays(28), yesterday, allTimeSelected = false))
            .isEqualTo(DateRangeOption.Custom)
    }

    @Test
    fun theLargeExportBannerStartsAtThirtyDaysAndSkipsRawSnapshots() {
        assertThat(ExportNowFlow.showsLargeExportBanner(29, ExportMode.COMPATIBILITY)).isFalse()
        assertThat(ExportNowFlow.showsLargeExportBanner(30, ExportMode.COMPATIBILITY)).isTrue()
        assertThat(ExportNowFlow.showsLargeExportBanner(365, ExportMode.RAW_SNAPSHOT)).isFalse()
    }

    @Test
    fun onlyRunsThatMissedDaysEndOnTheResultSheet() {
        assertThat(ExportNowFlow.showsResultSheet(ExportResult(successCount = 7, totalCount = 7))).isFalse()
        assertThat(ExportNowFlow.showsResultSheet(ExportResult(successCount = 5, totalCount = 7))).isTrue()
        assertThat(ExportNowFlow.showsResultSheet(ExportResult(successCount = 0, totalCount = 1))).isTrue()
        assertThat(ExportNowFlow.showsResultSheet(ExportResult(successCount = 7, totalCount = 7, wasCancelled = true))).isTrue()
        assertThat(
            ExportNowFlow.showsResultSheet(ExportResult(successCount = 0, totalCount = 1, exportMode = ExportMode.RAW_SNAPSHOT)),
        ).isFalse()
    }

    @Test
    fun resultRowsCollapseLongCompleteRunsNewestFirst() {
        val rows = ExportResultDays.rows(
            start = day(1),
            end = day(7),
            failed = mapOf(day(5) to ExportFailureReason.NO_HEALTH_DATA),
            notWritten = emptySet(),
            successCount = 6,
        )
        assertThat(rows).containsExactly(
            Row.Complete(day(7), day(7)),
            Row.Complete(day(6), day(6)),
            Row.Failed(day(5), ExportFailureReason.NO_HEALTH_DATA),
            Row.Complete(day(1), day(4)),
        ).inOrder()
    }

    @Test
    fun resultRowsNeverCallUncountedDaysComplete() {
        // Cancelled without knowing which days were written: list only what is known.
        val rows = ExportResultDays.rows(
            start = day(1),
            end = day(4),
            failed = mapOf(day(2) to ExportFailureReason.NETWORK_ERROR),
            notWritten = emptySet(),
            successCount = 1,
        )
        assertThat(rows).containsExactly(Row.Failed(day(2), ExportFailureReason.NETWORK_ERROR))

        val cancelled = ExportResultDays.rows(
            start = day(1),
            end = day(3),
            failed = emptyMap(),
            notWritten = setOf(day(3)),
            successCount = 2,
        )
        assertThat(cancelled).containsExactly(
            Row.NotWritten(day(3)),
            Row.Complete(day(2), day(2)),
            Row.Complete(day(1), day(1)),
        ).inOrder()
    }

    @Test
    fun retryCoversFailedAndUnwrittenDays() {
        val result = ExportResult(
            successCount = 3,
            totalCount = 6,
            failedDateDetails = listOf(FailedDateDetail(day(4), ExportFailureReason.NETWORK_ERROR)),
            remainingDates = setOf(day(5), day(6)),
            wasCancelled = true,
        )
        assertThat(ExportResultDays.retryRange(result)).isEqualTo(day(4) to day(6))
        assertThat(ExportResultDays.retryRange(ExportResult(successCount = 1, totalCount = 1))).isNull()
    }
}
