package com.healthmd.presentation.archive

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportPreviewFile
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
}
