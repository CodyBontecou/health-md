package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.HealthData
import com.healthmd.presentation.export.ExportViewModel
import io.mockk.mockk
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test
import java.time.LocalDate

@OptIn(ExperimentalCoroutinesApi::class)
class ExportViewModelReliabilityTest {

    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val startDate: LocalDate = LocalDate.of(2026, 1, 1)

    @Test
    fun startExport_fullSuccess_updatesProgressRecordsHistoryAndConsumesOneFreeExport() = runTest(
        mainDispatcherRule.testDispatcher,
    ) {
        val dates = dates(3)
        val dependencies = Dependencies().withDataFor(dates)
        val viewModel = dependencies.viewModel()

        runCurrent()
        viewModel.setStartDate(dates.first())
        viewModel.setEndDate(dates.last())
        viewModel.startExport()
        runCurrent()

        val state = viewModel.uiState.value
        assertThat(state.isExporting).isFalse()
        assertThat(state.exportProgress).isEqualTo(3)
        assertThat(state.exportTotal).isEqualTo(3)
        assertThat(state.exportProgressDate).isEqualTo(dates.last().toString())
        assertThat(state.exportedFolderUri).isEqualTo("content://exports")
        assertThat(state.lastResult?.isFullSuccess).isTrue()

        assertThat(dependencies.historyRepository.entries).hasSize(1)
        val history = dependencies.historyRepository.entries.single()
        assertThat(history.source).isEqualTo(ExportSource.MANUAL)
        assertThat(history.dateRangeStart).isEqualTo(dates.first())
        assertThat(history.dateRangeEnd).isEqualTo(dates.last())
        assertThat(history.successCount).isEqualTo(3)
        assertThat(history.totalCount).isEqualTo(3)
        assertThat(history.failureReason).isNull()

        assertThat(dependencies.settingsRepository.decrementFreeExportsCalls).isEqualTo(1)
        assertThat(dependencies.settingsRepository.getFreeExportsRemaining()).isEqualTo(2)
        assertThat(dependencies.settingsRepository.successfulExportCount).isEqualTo(1)
    }

    @Test
    fun startExport_elevenOfNinetyPartial_recordsHistoryButDoesNotConsumeFreeExport() = runTest(
        mainDispatcherRule.testDispatcher,
    ) {
        val dates = dates(90)
        val dependencies = Dependencies().apply {
            dates.take(11).forEach { healthRepository.putData(healthData(it)) }
        }
        val viewModel = dependencies.viewModel()

        runCurrent()
        viewModel.setStartDate(dates.first())
        viewModel.setEndDate(dates.last())
        viewModel.startExport()
        runCurrent()

        val result = viewModel.uiState.value.lastResult
        assertThat(result?.successCount).isEqualTo(11)
        assertThat(result?.totalCount).isEqualTo(90)
        assertThat(result?.isPartialSuccess).isTrue()
        assertThat(result?.isFullSuccess).isFalse()

        val history = dependencies.historyRepository.entries.single()
        assertThat(history.successCount).isEqualTo(11)
        assertThat(history.totalCount).isEqualTo(90)
        assertThat(history.failureReason).isEqualTo(ExportFailureReason.NO_HEALTH_DATA)
        assertThat(history.failedDateDetails).hasSize(79)

        assertThat(dependencies.settingsRepository.decrementFreeExportsCalls).isEqualTo(0)
        assertThat(dependencies.settingsRepository.getFreeExportsRemaining()).isEqualTo(3)
        assertThat(dependencies.settingsRepository.successfulExportCount).isEqualTo(0)
    }

    @Test
    fun startExport_fileWriteFailure_recordsFailureAndDoesNotConsumeFreeExport() = runTest(
        mainDispatcherRule.testDispatcher,
    ) {
        val dates = dates(2)
        val dependencies = Dependencies().withDataFor(dates).apply {
            exportRepository.defaultResult = false
        }
        val viewModel = dependencies.viewModel()

        runCurrent()
        viewModel.setStartDate(dates.first())
        viewModel.setEndDate(dates.last())
        viewModel.startExport()
        runCurrent()

        val result = viewModel.uiState.value.lastResult
        assertThat(result?.isFailure).isTrue()
        assertThat(result?.primaryFailureReason).isEqualTo(ExportFailureReason.FILE_WRITE_ERROR)

        val history = dependencies.historyRepository.entries.single()
        assertThat(history.successCount).isEqualTo(0)
        assertThat(history.totalCount).isEqualTo(2)
        assertThat(history.failureReason).isEqualTo(ExportFailureReason.FILE_WRITE_ERROR)
        assertThat(history.failedDateDetails).hasSize(2)

        assertThat(dependencies.settingsRepository.decrementFreeExportsCalls).isEqualTo(0)
        assertThat(dependencies.settingsRepository.getFreeExportsRemaining()).isEqualTo(3)
        assertThat(dependencies.settingsRepository.successfulExportCount).isEqualTo(0)
    }

    @Test
    fun startExport_cancelledPartialDoesNotConsumeFreeExportOrCountAsSuccessfulExport() = runTest(
        mainDispatcherRule.testDispatcher,
    ) {
        val dates = dates(3)
        val dependencies = Dependencies().withDataFor(dates).apply {
            healthRepository.fetchBehavior = { date ->
                if (date == dates[1]) {
                    throw CancellationException("cancelled")
                }
                healthData(date)
            }
        }
        val viewModel = dependencies.viewModel()

        runCurrent()
        viewModel.setStartDate(dates.first())
        viewModel.setEndDate(dates.last())
        viewModel.startExport()
        runCurrent()

        val result = viewModel.uiState.value.lastResult
        assertThat(result?.wasCancelled).isTrue()
        assertThat(result?.successCount).isEqualTo(1)
        assertThat(result?.totalCount).isEqualTo(3)

        val history = dependencies.historyRepository.entries.single()
        assertThat(history.successCount).isEqualTo(1)
        assertThat(history.totalCount).isEqualTo(3)

        assertThat(dependencies.settingsRepository.decrementFreeExportsCalls).isEqualTo(0)
        assertThat(dependencies.settingsRepository.getFreeExportsRemaining()).isEqualTo(3)
        assertThat(dependencies.settingsRepository.successfulExportCount).isEqualTo(0)
    }

    private fun dates(count: Int): List<LocalDate> =
        (0 until count).map { startDate.plusDays(it.toLong()) }

    private fun healthData(date: LocalDate): HealthData =
        ExportFixtures.partialDay.copy(date = date)

    private inner class Dependencies {
        val healthRepository = FakeHealthRepository()
        val exportRepository = FakeExportRepository()
        val settingsRepository = FakeSettingsRepository()
        val billingRepository = FakeBillingRepository()
        val historyRepository = FakeExportHistoryRepository()
        val fileExportManager: FileExportManager = mockk(relaxed = true)

        fun withDataFor(dates: List<LocalDate>): Dependencies = apply {
            dates.forEach { healthRepository.putData(healthData(it)) }
        }

        fun viewModel(): ExportViewModel = ExportViewModel(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
            billingRepository = billingRepository,
            exportHistoryRepository = historyRepository,
            fileExportManager = fileExportManager,
        )
    }
}
