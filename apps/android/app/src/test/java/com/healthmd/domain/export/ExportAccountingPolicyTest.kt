package com.healthmd.domain.export

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.FailedDateDetail
import org.junit.Test
import java.time.LocalDate

class ExportAccountingPolicyTest {

    @Test
    fun fullSuccessConsumesFreeExportForFreeUser() {
        val result = ExportResult(successCount = 3, totalCount = 3)

        assertThat(ExportAccountingPolicy.shouldConsumeFreeExport(result, isPurchased = false))
            .isTrue()
    }

    @Test
    fun fullSuccessDoesNotConsumeFreeExportForPurchasedUser() {
        val result = ExportResult(successCount = 3, totalCount = 3)

        assertThat(ExportAccountingPolicy.shouldConsumeFreeExport(result, isPurchased = true))
            .isFalse()
    }

    @Test
    fun elevenOfNinetyPartialExportDoesNotConsumeFreeExport() {
        val result = ExportResult(
            successCount = 11,
            totalCount = 90,
            failedDateDetails = failedDates(
                count = 79,
                reason = ExportFailureReason.FILE_WRITE_ERROR,
            ),
        )

        assertThat(result.isPartialSuccess).isTrue()
        assertThat(ExportAccountingPolicy.shouldConsumeFreeExport(result, isPurchased = false))
            .isFalse()
    }

    @Test
    fun fullFailureDoesNotConsumeFreeExport() {
        val result = ExportResult(
            successCount = 0,
            totalCount = 3,
            failedDateDetails = failedDates(
                count = 3,
                reason = ExportFailureReason.NO_HEALTH_DATA,
            ),
        )

        assertThat(result.isFailure).isTrue()
        assertThat(ExportAccountingPolicy.shouldConsumeFreeExport(result, isPurchased = false))
            .isFalse()
    }

    @Test
    fun failedExportsDoNotConsumeFreeExportForAnyFailureReason() {
        ExportFailureReason.values().forEach { reason ->
            val result = ExportResult(
                successCount = 0,
                totalCount = 1,
                failedDateDetails = failedDates(
                    count = 1,
                    reason = reason,
                ),
            )

            assertWithMessage(reason.name)
                .that(ExportAccountingPolicy.shouldConsumeFreeExport(result, isPurchased = false))
                .isFalse()
        }
    }

    @Test
    fun cancelledExportDoesNotConsumeFreeExportEvenWhenSomeDaysExported() {
        val result = ExportResult(
            successCount = 2,
            totalCount = 3,
            wasCancelled = true,
        )

        assertThat(ExportAccountingPolicy.shouldConsumeFreeExport(result, isPurchased = false))
            .isFalse()
    }

    @Test
    fun cancelledExportDoesNotConsumeFreeExportEvenWhenAllDaysExported() {
        val result = ExportResult(
            successCount = 3,
            totalCount = 3,
            wasCancelled = true,
        )

        assertThat(ExportAccountingPolicy.shouldConsumeFreeExport(result, isPurchased = false))
            .isFalse()
    }

    @Test
    fun reviewPromptCounterUsesFullSuccessRuleSeparatelyFromQuota() {
        val fullSuccess = ExportResult(successCount = 3, totalCount = 3)
        val partialSuccess = ExportResult(successCount = 11, totalCount = 90)

        assertThat(ExportAccountingPolicy.shouldCountForReviewPrompt(fullSuccess)).isTrue()
        assertThat(ExportAccountingPolicy.shouldCountForReviewPrompt(partialSuccess)).isFalse()
    }

    private fun failedDates(count: Int, reason: ExportFailureReason): List<FailedDateDetail> =
        List(count) { offset ->
            FailedDateDetail(
                date = LocalDate.of(2026, 1, 1).plusDays(offset.toLong()),
                reason = reason,
            )
        }
}
