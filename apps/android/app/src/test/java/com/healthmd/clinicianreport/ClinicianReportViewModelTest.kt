package com.healthmd.clinicianreport

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.clinicianreport.ClinicianReportDataSource
import com.healthmd.data.clinicianreport.ClinicianReportFileStore
import com.healthmd.data.clinicianreport.ClinicianReportPdfRenderer
import com.healthmd.data.clinicianreport.ReportPageSize
import com.healthmd.domain.clinicianreport.*
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.FakeSettingsRepository
import com.healthmd.export.MainDispatcherRule
import com.healthmd.presentation.clinicianreport.ClinicianReportViewModel
import java.io.OutputStream
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.withContext
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

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
        assertThat(viewModel.uiState.value.isConfigurationReady).isTrue()
        assertThat(viewModel.uiState.value.configuration.dateRange.inclusiveDayCount).isEqualTo(30)
        viewModel.preview()
        waitFor { viewModel.uiState.value.report != null || viewModel.uiState.value.errorMessage != null }
        assertThat(viewModel.uiState.value.report).isNotNull()
        assertThat(viewModel.uiState.value.report!!.sections).hasSize(ReportMetric.entries.size)
        viewModel.generatePdf()
        waitFor { viewModel.uiState.value.pdfFile != null || viewModel.uiState.value.errorMessage != null }
        val generated = viewModel.uiState.value.pdfFile!!
        assertThat(generated.readText()).startsWith("%PDF-")
        assertThat(viewModel.uiState.value.isConfigurationEditable).isTrue()

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

    @Test fun busyPreparationRejectsEveryConfigurationMutationAndCompletesOriginalSnapshot() = runTest(dispatcherRule.testDispatcher) {
        val calls = AtomicInteger()
        val started = CompletableDeferred<Unit>()
        val release = CompletableDeferred<Unit>()
        val completedConfiguration = CompletableDeferred<ReportConfiguration>()
        val dataSource = ClinicianReportDataSource { configuration, zoneId ->
            calls.incrementAndGet()
            started.complete(Unit)
            withContext(NonCancellable) { release.await() }
            completedConfiguration.complete(configuration)
            ClinicianReportInput(
                configuration = configuration,
                zoneId = zoneId,
                generatedAt = Instant.parse("2026-08-08T12:00:00Z"),
                dailyValues = listOf(
                    DailyReportValue(ReportMetric.STEPS, configuration.dateRange.endDate, 1_234.0),
                ),
            )
        }
        val viewModel = viewModel(dataSource)
        advanceUntilIdle()
        val today = LocalDate.of(2026, 8, 8)
        viewModel.selectPreset(ReportDateRangePreset.DAYS_7, today)
        viewModel.setDisplayName("Original")
        val originalConfiguration = viewModel.uiState.value.configuration
        val originalPreset = viewModel.uiState.value.selectedPreset

        viewModel.preview()
        started.await()
        assertThat(viewModel.uiState.value.isBusy).isTrue()
        assertThat(viewModel.uiState.value.isConfigurationEditable).isFalse()

        viewModel.selectPreset(ReportDateRangePreset.DAYS_90, today)
        viewModel.selectPreset(ReportDateRangePreset.CUSTOM, today)
        viewModel.setCustomRange(today.minusDays(3), today.minusDays(2), today)
        viewModel.toggleMetric(ReportMetric.HEART_RATE)
        viewModel.setDetailLevel(ReportDetailLevel.SUMMARY_AND_READINGS)
        viewModel.setDisplayName("Queued mutation")
        viewModel.preview()
        viewModel.generatePdf()

        val busyState = viewModel.uiState.value
        assertThat(calls.get()).isEqualTo(1)
        assertThat(busyState.isLoading).isTrue()
        assertThat(busyState.isBusy).isTrue()
        assertThat(busyState.isConfigurationEditable).isFalse()
        assertThat(busyState.configuration).isEqualTo(originalConfiguration)
        assertThat(busyState.selectedPreset).isEqualTo(originalPreset)

        release.complete(Unit)
        waitFor { viewModel.uiState.value.report != null && !viewModel.uiState.value.isBusy }
        assertThat(completedConfiguration.await()).isEqualTo(originalConfiguration)
        assertThat(viewModel.uiState.value.configuration).isEqualTo(originalConfiguration)
        assertThat(viewModel.uiState.value.report!!.displayName).isEqualTo("Original")
        assertThat(viewModel.uiState.value.isConfigurationEditable).isTrue()
    }

    @Test fun configurationChangePreventsStaleReadFromRepublishing() = runTest(dispatcherRule.testDispatcher) {
        val calls = AtomicInteger()
        val firstStarted = CompletableDeferred<Unit>()
        val releaseFirst = CompletableDeferred<Unit>()
        val firstReturned = AtomicBoolean(false)
        val dataSource = ClinicianReportDataSource { configuration, zoneId ->
            if (calls.incrementAndGet() == 1) {
                firstStarted.complete(Unit)
                withContext(NonCancellable) { releaseFirst.await() }
                firstReturned.set(true)
            }
            ClinicianReportInput(configuration, zoneId, Instant.parse("2026-08-08T12:00:00Z"))
        }
        val viewModel = viewModel(dataSource)
        advanceUntilIdle()
        viewModel.preview()
        firstStarted.await()

        viewModel.cancel()
        assertThat(viewModel.uiState.value.isConfigurationEditable).isTrue()
        viewModel.toggleMetric(ReportMetric.HEART_RATE)
        viewModel.preview()
        waitFor { viewModel.uiState.value.report != null }
        assertThat(viewModel.uiState.value.report!!.sections.map { it.metric }).doesNotContain(ReportMetric.HEART_RATE)

        releaseFirst.complete(Unit)
        waitFor { firstReturned.get() }
        advanceUntilIdle()
        assertThat(calls.get()).isEqualTo(2)
        assertThat(viewModel.uiState.value.isLoading).isFalse()
        assertThat(viewModel.uiState.value.report!!.sections.map { it.metric }).doesNotContain(ReportMetric.HEART_RATE)
    }

    @Test fun duplicateGenerationAndConfigurationMutationsCannotSupersedeRendering() = runTest(dispatcherRule.testDispatcher) {
        val renderCalls = AtomicInteger()
        val renderStarted = CountDownLatch(1)
        val releaseRender = CountDownLatch(1)
        val renderer = object : ClinicianReportPdfRenderer {
            override fun render(
                report: ClinicianReportData,
                output: OutputStream,
                pageSize: ReportPageSize,
                shouldContinue: () -> Boolean,
            ): Int {
                renderCalls.incrementAndGet()
                renderStarted.countDown()
                check(releaseRender.await(5, TimeUnit.SECONDS)) { "Timed out waiting to release the renderer" }
                if (!shouldContinue()) throw java.util.concurrent.CancellationException("render cancelled")
                output.write("%PDF-blocking-test".toByteArray())
                return 1
            }
        }
        val viewModel = viewModel(
            dataSource = ClinicianReportDataSource { configuration, zoneId ->
                ClinicianReportInput(configuration, zoneId, Instant.parse("2026-08-08T12:00:00Z"))
            },
            renderer = renderer,
        )
        advanceUntilIdle()
        viewModel.setDisplayName("Original")
        viewModel.preview()
        waitFor { viewModel.uiState.value.report != null }
        val originalConfiguration = viewModel.uiState.value.configuration
        val originalReport = viewModel.uiState.value.report

        viewModel.generatePdf()
        runCurrent()
        assertThat(renderStarted.await(5, TimeUnit.SECONDS)).isTrue()
        assertThat(viewModel.uiState.value.isRendering).isTrue()
        assertThat(viewModel.uiState.value.isConfigurationEditable).isFalse()

        val today = LocalDate.now()
        viewModel.selectPreset(ReportDateRangePreset.DAYS_7, today)
        viewModel.selectPreset(ReportDateRangePreset.CUSTOM, today)
        viewModel.setCustomRange(today.minusDays(2), today, today)
        viewModel.toggleMetric(ReportMetric.HEART_RATE)
        viewModel.setDetailLevel(ReportDetailLevel.SUMMARY_AND_READINGS)
        viewModel.setDisplayName("Queued mutation")
        viewModel.preview()
        viewModel.generatePdf()

        val renderingState = viewModel.uiState.value
        assertThat(renderCalls.get()).isEqualTo(1)
        assertThat(renderingState.isRendering).isTrue()
        assertThat(renderingState.isBusy).isTrue()
        assertThat(renderingState.configuration).isEqualTo(originalConfiguration)
        assertThat(renderingState.report).isEqualTo(originalReport)

        releaseRender.countDown()
        waitFor { viewModel.uiState.value.pdfFile != null || viewModel.uiState.value.errorMessage != null }
        assertThat(renderCalls.get()).isEqualTo(1)
        assertThat(viewModel.uiState.value.pdfFile).isNotNull()
        assertThat(viewModel.uiState.value.isBusy).isFalse()
        assertThat(viewModel.uiState.value.isConfigurationEditable).isTrue()
        viewModel.uiState.value.pdfFile?.delete()
    }

    @Test fun previewAndConfigurationWaitForPersistedUnitPreference() = runTest(dispatcherRule.testDispatcher) {
        val settingsReadStarted = CompletableDeferred<Unit>()
        val releaseSettings = CompletableDeferred<Unit>()
        val storedSettings = ExportSettings(
            formatCustomization = FormatCustomization(unitPreference = UnitPreference.IMPERIAL),
        )
        val delegate = FakeSettingsRepository(initialSettings = storedSettings)
        val settingsRepository = object : SettingsRepository by delegate {
            override suspend fun getExportSettings(): ExportSettings {
                settingsReadStarted.complete(Unit)
                releaseSettings.await()
                return storedSettings
            }
        }
        val calls = AtomicInteger()
        var observedConfiguration: ReportConfiguration? = null
        val viewModel = viewModel(
            dataSource = ClinicianReportDataSource { configuration, zoneId ->
                calls.incrementAndGet()
                observedConfiguration = configuration
                ClinicianReportInput(configuration, zoneId, Instant.parse("2026-08-08T12:00:00Z"))
            },
            settingsRepository = settingsRepository,
        )

        runCurrent()
        settingsReadStarted.await()
        val initializing = viewModel.uiState.value
        assertThat(initializing.isConfigurationReady).isFalse()
        assertThat(initializing.isConfigurationEditable).isFalse()
        assertThat(initializing.canPreview).isFalse()
        viewModel.setDisplayName("Ignored")
        viewModel.selectPreset(ReportDateRangePreset.DAYS_7, LocalDate.of(2026, 8, 8))
        viewModel.preview()
        assertThat(calls.get()).isEqualTo(0)
        assertThat(viewModel.uiState.value.configuration.displayName).isEmpty()

        releaseSettings.complete(Unit)
        advanceUntilIdle()
        val ready = viewModel.uiState.value
        assertThat(ready.isConfigurationReady).isTrue()
        assertThat(ready.isConfigurationEditable).isTrue()
        assertThat(ready.configuration.unitPreference).isEqualTo(UnitPreference.IMPERIAL)

        viewModel.preview()
        waitFor { viewModel.uiState.value.report != null }
        assertThat(calls.get()).isEqualTo(1)
        assertThat(observedConfiguration!!.unitPreference).isEqualTo(UnitPreference.IMPERIAL)
    }

    @Test fun terminalFailureRestoresConfigurationEditability() = runTest(dispatcherRule.testDispatcher) {
        val viewModel = viewModel(ClinicianReportDataSource { _, _ ->
            error("synthetic preparation failure")
        })
        advanceUntilIdle()

        viewModel.preview()
        waitFor { viewModel.uiState.value.errorMessage != null }
        assertThat(viewModel.uiState.value.isBusy).isFalse()
        assertThat(viewModel.uiState.value.isConfigurationEditable).isTrue()
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
        assertThat(viewModel.uiState.value.isConfigurationEditable).isFalse()
        viewModel.cancel()
        advanceUntilIdle()
        assertThat(viewModel.uiState.value.isLoading).isFalse()
        assertThat(viewModel.uiState.value.isBusy).isFalse()
        assertThat(viewModel.uiState.value.isConfigurationEditable).isTrue()
        assertThat(cancelled.get()).isTrue()
    }

    private fun waitFor(condition: () -> Boolean) {
        repeat(400) {
            dispatcherRule.testDispatcher.scheduler.advanceUntilIdle()
            if (condition()) return
            Thread.sleep(5)
        }
        assertThat(condition()).isTrue()
    }

    private fun viewModel(
        dataSource: ClinicianReportDataSource,
        renderer: ClinicianReportPdfRenderer = successfulRenderer(),
        settingsRepository: SettingsRepository = FakeSettingsRepository(initialFreeExportsRemaining = 0),
    ): ClinicianReportViewModel {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        return ClinicianReportViewModel(
            dataSource,
            ClinicianReportFileStore(context, renderer),
            settingsRepository,
            reportVocabularyFactory(),
        )
    }

    private fun successfulRenderer(): ClinicianReportPdfRenderer = object : ClinicianReportPdfRenderer {
        override fun render(
            report: ClinicianReportData,
            output: OutputStream,
            pageSize: ReportPageSize,
            shouldContinue: () -> Boolean,
        ): Int {
            output.write("%PDF-test".toByteArray())
            return 1
        }
    }
}
