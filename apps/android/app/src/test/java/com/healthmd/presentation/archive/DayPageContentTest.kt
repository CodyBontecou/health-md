package com.healthmd.presentation.archive

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.FailedDateDetail
import java.time.LocalDate
import org.junit.Test

class DayPageContentTest {
    private val file = ExportPreviewFile(
        format = ExportFormat.MARKDOWN,
        relativePath = "Health/2026-10-30.md",
        byteCount = 12,
        content = "---\nsteps: 1\n",
    )

    @Test
    fun filesWinOverAFailureOnAnotherFile() {
        assertThat(DayPageViewModel.dayPageContent(listOf(file), failed = true))
            .isEqualTo(DayPageContent.Files(listOf(file)))
    }

    @Test
    fun noFilesIsEitherEmptyOrFailed() {
        assertThat(DayPageViewModel.dayPageContent(emptyList(), failed = false)).isEqualTo(DayPageContent.Empty)
        assertThat(DayPageViewModel.dayPageContent(emptyList(), failed = true)).isEqualTo(DayPageContent.Failed)
    }

    @Test
    fun onlyWrittenDatesCountAsWrittenIncludingToday() {
        val start = LocalDate.of(2026, 11, 1)
        val gap = LocalDate.of(2026, 11, 2)
        val entries = listOf(
            ExportHistoryEntry(
                timestamp = 1,
                source = ExportSource.MANUAL,
                dateRangeStart = start,
                dateRangeEnd = LocalDate.of(2026, 11, 4),
                successCount = 3,
                totalCount = 4,
                failedDateDetails = listOf(FailedDateDetail(gap, ExportFailureReason.FILE_WRITE_ERROR)),
            ),
        )
        assertThat(DayPageViewModel.isWritten(entries, start)).isTrue()
        assertThat(DayPageViewModel.isWritten(entries, LocalDate.of(2026, 11, 4))).isTrue()
        assertThat(DayPageViewModel.isWritten(entries, gap)).isFalse()
        assertThat(DayPageViewModel.isWritten(entries, LocalDate.of(2026, 10, 31))).isFalse()
    }
}
