package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.LocalDate

class ExportOrchestratorReliabilityTest {

    private val startDate: LocalDate = LocalDate.of(2026, 1, 1)
    private val settings = ExportSettings()

    @Test
    fun exportDates_fullSuccessOverMultiDayRange_exportsEveryDay() = runTest {
        val dates = dates(5)
        val healthRepository = FakeHealthRepository().withDataFor(dates)
        val exportRepository = FakeExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val progress = mutableListOf<Triple<Int, Int, String>>()
        val result = orchestrator.exportDates(dates, settings) { current, total, dateString ->
            progress.add(Triple(current, total, dateString))
        }

        assertThat(result.isFullSuccess).isTrue()
        assertThat(result.successCount).isEqualTo(5)
        assertThat(result.totalCount).isEqualTo(5)
        assertThat(result.failedDateDetails).isEmpty()
        assertThat(healthRepository.fetchedDates).containsExactlyElementsIn(dates).inOrder()
        assertThat(exportRepository.exportedDates).containsExactlyElementsIn(dates).inOrder()
        assertThat(progress.map { it.first }).containsExactly(1, 2, 3, 4, 5).inOrder()
        assertThat(progress.last().third).isEqualTo(dates.last().toString())
    }

    @Test
    fun exportDates_partialNoDataDays_reportsFailuresWithoutWritingEmptyDays() = runTest {
        val dates = dates(3)
        val healthRepository = FakeHealthRepository().apply {
            putData(healthData(dates[0]))
            putData(HealthData(dates[1]))
            putData(healthData(dates[2]))
        }
        val exportRepository = FakeExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, settings)

        assertThat(result.isPartialSuccess).isTrue()
        assertThat(result.successCount).isEqualTo(2)
        assertThat(result.totalCount).isEqualTo(3)
        assertThat(result.failedDateDetails).containsExactly(
            com.healthmd.domain.model.FailedDateDetail(dates[1], ExportFailureReason.NO_HEALTH_DATA),
        )
        assertThat(exportRepository.exportedDates).containsExactly(dates[0], dates[2]).inOrder()
    }

    @Test
    fun exportDates_allNoData_isFailureAndRecordsEachNoDataDay() = runTest {
        val dates = dates(2)
        val healthRepository = FakeHealthRepository()
        val exportRepository = FakeExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, settings)

        assertThat(result.isFailure).isTrue()
        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.map { it.reason })
            .containsExactly(ExportFailureReason.NO_HEALTH_DATA, ExportFailureReason.NO_HEALTH_DATA)
            .inOrder()
        assertThat(exportRepository.exportedDates).isEmpty()
    }

    @Test
    fun exportDates_fileWriteFailure_marksDateAsFileWriteError() = runTest {
        val dates = dates(3)
        val healthRepository = FakeHealthRepository().withDataFor(dates)
        val exportRepository = FakeExportRepository().apply {
            resultsByDate[dates[1]] = false
        }
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, settings)

        assertThat(result.isPartialSuccess).isTrue()
        assertThat(result.successCount).isEqualTo(2)
        assertThat(result.failedDateDetails).containsExactly(
            com.healthmd.domain.model.FailedDateDetail(dates[1], ExportFailureReason.FILE_WRITE_ERROR),
        )
        assertThat(exportRepository.exportedDates).containsExactlyElementsIn(dates).inOrder()
    }

    @Test
    fun exportDates_healthConnectFailure_isClassifiedSeparatelyFromUnknown() = runTest {
        val dates = dates(1)
        val healthRepository = FakeHealthRepository().apply {
            fetchBehavior = {
                throw IllegalStateException("Health Connect provider unavailable")
            }
        }
        val exportRepository = FakeExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, settings)

        assertThat(result.isFailure).isTrue()
        assertThat(result.primaryFailureReason).isEqualTo(ExportFailureReason.HEALTH_CONNECT_ERROR)
        assertThat(result.failedDateDetails.single().errorDetails)
            .contains("Health Connect provider unavailable")
        assertThat(exportRepository.exportedDates).isEmpty()
    }

    @Test
    fun exportDates_securityPermissionFailure_isAccessDenied() = runTest {
        val dates = dates(1)
        val healthRepository = FakeHealthRepository().apply {
            fetchBehavior = {
                throw SecurityException("Permission denied for historical Health Connect data")
            }
        }
        val exportRepository = FakeExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, settings)

        assertThat(result.isFailure).isTrue()
        assertThat(result.primaryFailureReason).isEqualTo(ExportFailureReason.ACCESS_DENIED)
        assertThat(exportRepository.exportedDates).isEmpty()
    }

    @Test
    fun exportDates_rateLimitStopsAndMarksRemainingDates() = runTest {
        val dates = dates(5)
        val healthRepository = FakeHealthRepository().withDataFor(dates).apply {
            fetchBehavior = { date ->
                if (date == dates[2]) {
                    throw IllegalStateException("Health Connect rate limit exceeded")
                }
                healthData(date)
            }
        }
        val exportRepository = FakeExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, settings)

        assertThat(result.isFailure).isTrue()
        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.failedDateDetails.map { it.date })
            .containsExactlyElementsIn(dates)
            .inOrder()
        assertThat(result.failedDateDetails.map { it.reason }.distinct())
            .containsExactly(ExportFailureReason.RATE_LIMITED)
        assertThat(healthRepository.fetchedDates).containsExactly(dates[0], dates[1], dates[2]).inOrder()
        assertThat(exportRepository.exportedDates).isEmpty()
    }

    @Test
    fun exportDates_cancellationReturnsPartialCancelledResult() = runTest {
        val dates = dates(3)
        val healthRepository = FakeHealthRepository().withDataFor(dates).apply {
            fetchBehavior = { date ->
                if (date == dates[1]) {
                    throw CancellationException("cancelled by user")
                }
                healthData(date)
            }
        }
        val exportRepository = FakeExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, settings)

        assertThat(result.wasCancelled).isTrue()
        assertThat(result.isFullSuccess).isFalse()
        assertThat(result.isPartialSuccess).isFalse()
        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.totalCount).isEqualTo(3)
        assertThat(result.failedDateDetails).isEmpty()
        assertThat(exportRepository.exportedDates).isEmpty()
    }

    @Test
    fun exportDates_elevenOfNinetyRegression_isPartialAndNotFullSuccess() = runTest {
        val dates = dates(90)
        val healthRepository = FakeHealthRepository().apply {
            dates.take(11).forEach { putData(healthData(it)) }
        }
        val exportRepository = FakeExportRepository()
        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)

        val result = orchestrator.exportDates(dates, settings)

        assertThat(result.successCount).isEqualTo(11)
        assertThat(result.totalCount).isEqualTo(90)
        assertThat(result.isPartialSuccess).isTrue()
        assertThat(result.isFullSuccess).isFalse()
        assertThat(result.failedDateDetails).hasSize(79)
        assertThat(result.failedDateDetails.all { it.reason == ExportFailureReason.NO_HEALTH_DATA }).isTrue()
    }

    private fun dates(count: Int): List<LocalDate> =
        (0 until count).map { startDate.plusDays(it.toLong()) }

    private fun healthData(date: LocalDate): HealthData =
        ExportFixtures.partialDay.copy(date = date)

    private fun FakeHealthRepository.withDataFor(dates: List<LocalDate>): FakeHealthRepository = apply {
        dates.forEach { putData(healthData(it)) }
    }
}
