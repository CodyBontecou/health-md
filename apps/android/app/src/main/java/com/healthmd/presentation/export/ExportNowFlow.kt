package com.healthmd.presentation.export

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.rawexport.ExportMode
import java.time.LocalDate

/** Pure rules behind the Export now sheet, shared with iOS ExportNowSheet and ExportMomentView. */
internal object ExportNowFlow {
    /** From this many days the sheet warns that the export takes a while (iOS: 30). */
    const val LARGE_BANNER_DAYS = 30

    fun showsLargeExportBanner(days: Int, mode: ExportMode): Boolean =
        mode != ExportMode.RAW_SNAPSHOT && days >= LARGE_BANNER_DAYS

    /** The completed days a preset covers, ending yesterday; null for the custom options. */
    fun presetDates(option: DateRangeOption, today: LocalDate): Pair<LocalDate, LocalDate>? {
        val yesterday = today.minusDays(1)
        return when (option) {
            DateRangeOption.Yesterday -> yesterday to yesterday
            DateRangeOption.Last7Days -> yesterday.minusDays(6) to yesterday
            DateRangeOption.Last30Days -> yesterday.minusDays(29) to yesterday
            DateRangeOption.Today -> today to today
            DateRangeOption.AllTime, DateRangeOption.Custom -> null
        }
    }

    /**
     * A finished run goes to the result sheet when it did not write every day; full successes
     * end on the moment. Raw snapshots keep their own diagnostics, which explain one artifact.
     */
    fun showsResultSheet(result: ExportResult): Boolean =
        result.exportMode != ExportMode.RAW_SNAPSHOT && result.totalCount > 0 &&
            !result.toDiagnosticsSummary().shouldAutoDismiss
}

/** ExportResultG's day list: which days were written, failed, or left unwritten by Cancel. */
internal object ExportResultDays {
    sealed interface Row {
        data class Complete(val start: LocalDate, val end: LocalDate) : Row
        data class Failed(val date: LocalDate, val reason: ExportFailureReason) : Row
        data class NotWritten(val date: LocalDate) : Row
    }

    /**
     * Newest first. Runs of three or more complete days collapse into one range row; shorter
     * runs list each day. Days are only called complete when the counts agree with
     * [successCount]; otherwise only the failed and unwritten days are listed.
     */
    fun rows(
        start: LocalDate,
        end: LocalDate,
        failed: Map<LocalDate, ExportFailureReason>,
        notWritten: Set<LocalDate>,
        successCount: Int,
    ): List<Row> {
        val first = minOf(start, end)
        val last = maxOf(start, end)
        val days = generateSequence(last) { it.minusDays(1) }.takeWhile { !it.isBefore(first) }.toList()
        val completeCount = days.count { it !in failed && it !in notWritten }
        val showComplete = completeCount == successCount
        val rows = mutableListOf<Row>()
        val run = mutableListOf<LocalDate>()
        fun closeRun() {
            if (run.size >= 3) {
                rows += Row.Complete(start = run.last(), end = run.first())
            } else {
                run.forEach { rows += Row.Complete(it, it) }
            }
            run.clear()
        }
        days.forEach { day ->
            val reason = failed[day]
            when {
                reason != null -> { closeRun(); rows += Row.Failed(day, reason) }
                day in notWritten -> { closeRun(); rows += Row.NotWritten(day) }
                showComplete -> run += day
            }
        }
        closeRun()
        return rows
    }

    /** What Retry writes again: every failed or unwritten day, as one range. */
    fun retryRange(result: ExportResult): Pair<LocalDate, LocalDate>? {
        val dates = result.failedDateDetails.map { it.date } + result.remainingDates
        val first = dates.minOrNull() ?: return null
        return first to dates.max()
    }
}
