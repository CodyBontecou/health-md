package com.healthmd.clinicianreport

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.clinicianreport.ClinicianReportDataSource
import com.healthmd.data.clinicianreport.ClinicianReportFileStore
import com.healthmd.data.clinicianreport.ClinicianReportPdfRenderer
import com.healthmd.data.clinicianreport.ReportPageSize
import com.healthmd.domain.clinicianreport.*
import com.healthmd.export.FakeSettingsRepository
import com.healthmd.export.MainDispatcherRule
import com.healthmd.presentation.clinicianreport.ClinicianReportViewModel
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.io.OutputStream
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

@OptIn(ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ClinicianReportViewModelTest {
    @get:Rule val dispatcherRule = MainDispatcherRule()

    @Test fun previewUsesNormalizedModelAndPdfGenerationIsIndependentOfExportQuota() = runTest(dispatcherRule.testDispatcher) {
        val dataSource = ClinicianReportDataSource { configuration, zoneId ->
            ClinicianReportInput(configuration, zoneId, Instant.parse("2026-08-08T12:00:00Z"))
        }
        val viewModel = viewModel(dataSource)
        advanceUntilIdle()
        assertThat(viewModel.uiState.value.configuration.dateRange.inclusiveDayCount).isEqualTo(30)
        viewModel.preview()
        waitFor { viewModel.uiState.value.report != null || viewModel.uiState.value.errorMessage != null }
        assertThat(viewModel.uiState.value.report).isNotNull()
        assertThat(viewModel.uiState.value.report!!.sections).hasSize(ReportMetric.entries.size)
        viewModel.generatePdf()
        waitFor { viewModel.uiState.value.pdfFile != null || viewModel.uiState.value.errorMessage != null }
        val generated = viewModel.uiState.value.pdfFile!!
        assertThat(generated.readText()).startsWith("%PDF-")

        // ACTION_SEND consumers can open the granted URI after this screen changes or
        // is destroyed, so a shared file remains until a later generation cleans it.
        // The dedicated file-store test covers FileProvider URI construction; inject a
        // harmless intent here so Robolectric does not cache another test's temp path.
        assertThat(viewModel.shareIntent { android.content.Intent() }).isNotNull()
        viewModel.toggleMetric(ReportMetric.HEART_RATE)
        assertThat(generated.exists()).isTrue()
        generated.delete()
    }

    @Test fun normalizedEffectiveRangeIsPublishedAndUsedForPdfFilename() = runTest(dispatcherRule.testDispatcher) {
        val effectiveRange = ReportDateRange(LocalDate.of(2026, 2, 2), LocalDate.of(2026, 2, 3))
        val dataSource = ClinicianReportDataSource { configuration, zoneId ->
            ClinicianReportInput(
                configuration.copy(dateRange = effectiveRange),
                zoneId,
                Instant.parse("2026-02-04T12:00:00Z"),
            )
        }
        val viewModel = viewModel(dataSource)
        advanceUntilIdle()

        viewModel.preview()
        waitFor { viewModel.uiState.value.report != null }
        assertThat(viewModel.uiState.value.configuration.dateRange).isEqualTo(effectiveRange)

        viewModel.generatePdf()
        waitFor { viewModel.uiState.value.pdfFile != null }
        val generated = viewModel.uiState.value.pdfFile!!
        assertThat(generated.name).contains("2026-02-02_2026-02-03")
        assertThat(generated.name).doesNotContain("_to_")
        generated.delete()
    }

    @Test fun configurationChangePreventsStaleReadFromRepublishing() = runTest(dispatcherRule.testDispatcher) {
        val calls = AtomicInteger()
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val dataSource = ClinicianReportDataSource { configuration, zoneId ->
            if (calls.incrementAndGet() == 1) {
                firstStarted.complete(Unit)
                withContext(NonCancellable) { releaseFirst.await() }
            }
            ClinicianReportInput(configuration, zoneId, Instant.parse("2026-08-08T12:00:00Z"))
        }
        val viewModel = viewModel(dataSource)
        advanceUntilIdle()
        viewModel.preview()
        firstStarted.await()
        viewModel.toggleMetric(ReportMetric.HEART_RATE)
        viewModel.preview()
        waitFor { viewModel.uiState.value.report != null }
        assertThat(viewModel.uiState.value.report!!.sections.map { it.metric }).doesNotContain(ReportMetric.HEART_RATE)
        releaseFirst.complete(Unit)
        waitFor { calls.get() == 2 && !viewModel.uiState.value.isLoading }
        assertThat(viewModel.uiState.value.report!!.sections.map { it.metric }).doesNotContain(ReportMetric.HEART_RATE)
    }

    @Test fun cancelStopsOngoingRead() = runTest(dispatcherRule.testDispatcher) {
        val started = CompletableDeferred<Unit>()
        val never = CompletableDeferred<ClinicianReportInput>()
        val cancelled = AtomicBoolean(false)
        val viewModel = viewModel(ClinicianReportDataSource { _, _ ->
            started.complete(Unit)
            try { never.await() } finally { cancelled.set(true) }
        })
        advanceUntilIdle()
        viewModel.preview()
        started.await()
        viewModel.cancel()
        advanceUntilIdle()
        assertThat(viewModel.uiState.value.isLoading).isFalse()
        assertThat(cancelled.get()).isTrue()
    }

    private fun waitFor(condition: () -> Boolean) {
        repeat(200) {
            dispatcherRule.testDispatcher.scheduler.advanceUntilIdle()
            if (condition()) return
            Thread.sleep(5)
        }
    }

    private fun viewModel(dataSource: ClinicianReportDataSource): ClinicianReportViewModel {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val renderer = object : ClinicianReportPdfRenderer {
            override fun render(report: ClinicianReportData, output: OutputStream, pageSize: ReportPageSize, shouldContinue: () -> Boolean): Int { output.write("%PDF-test".toByteArray()); return 1 }
        }
        return ClinicianReportViewModel(
            dataSource,
            ClinicianReportFileStore(context, renderer),
            FakeSettingsRepository(initialFreeExportsRemaining = 0),
            reportVocabularyFactory(),
        )
    }
}
