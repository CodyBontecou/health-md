package com.healthmd.data.scheduler

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.PendingScheduledExportRequest
import com.healthmd.export.FakeExportHistoryRepository
import com.healthmd.export.FakeExportRepository
import com.healthmd.export.FakeHealthRepository
import com.healthmd.export.FakeSettingsRepository
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.LocalDate

class ScheduledExportRecoveryManagerTest {

    @Test
    fun inspectPendingRecovery_returnsReadyWhenAppOpenPrerequisitesAreMet() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val manager = manager(
            settingsRepository = FakeSettingsRepository(
                initialSettings = settingsWithPending(pendingDate),
                initialFolderUri = "content://exports",
                initialPurchased = true,
            ),
            healthRepository = FakeHealthRepository().apply {
                permissionsGranted = true
                beforeFirstUnlock = false
            },
        )

        val status = manager.inspectPendingRecovery()

        assertThat(status.canRecover).isTrue()
        assertThat(status.pendingDates).containsExactly(pendingDate)
        assertThat(status.blocker).isNull()
    }

    @Test
    fun inspectPendingRecovery_blocksWithoutExportFolder() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val manager = manager(
            settingsRepository = FakeSettingsRepository(
                initialSettings = settingsWithPending(pendingDate),
                initialFolderUri = null,
                initialPurchased = true,
            ),
        )

        val status = manager.inspectPendingRecovery()

        assertThat(status.canRecover).isFalse()
        assertThat(status.blocker).isEqualTo(ScheduledExportRecoveryBlocker.NO_EXPORT_FOLDER)
    }

    @Test
    fun recoverPendingDates_suppressesDuplicateRuns() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val healthRepository = FakeHealthRepository().apply {
            putData(HealthData(date = pendingDate, activity = ActivityData(steps = 42)))
        }
        val exportStarted = CompletableDeferred<Unit>()
        val releaseExport = CompletableDeferred<Unit>()
        val exportRepository = FakeExportRepository().apply {
            exportBehavior = { _, _ ->
                exportStarted.complete(Unit)
                releaseExport.await()
                true
            }
        }
        val manager = manager(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = FakeSettingsRepository(
                initialSettings = settingsWithPending(pendingDate),
                initialFolderUri = "content://exports",
                initialPurchased = true,
            ),
        )

        val firstRun = async { manager.recoverPendingDates() }
        exportStarted.await()

        val duplicateRun = manager.recoverPendingDates()

        assertThat(duplicateRun.status).isEqualTo(ScheduledExportRecoveryRunStatus.ALREADY_RUNNING)
        releaseExport.complete(Unit)
        assertThat(firstRun.await().status).isEqualTo(ScheduledExportRecoveryRunStatus.COMPLETED)
    }

    @Test
    fun recoverPendingDates_clearsOnlySuccessfullyExportedPendingDates() = runTest {
        val successDate = LocalDate.now().minusDays(2)
        val failedDate = LocalDate.now().minusDays(1)
        val healthRepository = FakeHealthRepository().apply {
            putData(HealthData(date = successDate, activity = ActivityData(steps = 10)))
            putData(HealthData(date = failedDate, activity = ActivityData(steps = 20)))
        }
        val exportRepository = FakeExportRepository().apply {
            resultsByDate[successDate] = true
            resultsByDate[failedDate] = false
        }
        val settingsRepository = FakeSettingsRepository(
            initialSettings = ExportSettings(
                pendingScheduledExportRequests = listOf(
                    PendingScheduledExportRequest(date = successDate, firstFailedAtMillis = 100L, attemptCount = 1),
                    PendingScheduledExportRequest(date = failedDate, firstFailedAtMillis = 100L, attemptCount = 1),
                ),
            ),
            initialFolderUri = "content://exports",
            initialPurchased = true,
        )
        val historyRepository = FakeExportHistoryRepository()
        val manager = manager(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
            historyRepository = historyRepository,
        )

        val result = manager.recoverPendingDates()

        assertThat(result.status).isEqualTo(ScheduledExportRecoveryRunStatus.COMPLETED)
        assertThat(result.exportResult?.successCount).isEqualTo(1)
        assertThat(ScheduledExportPendingRequests.pendingDates(settingsRepository.getExportSettings()))
            .containsExactly(failedDate)
        assertThat(historyRepository.entries).hasSize(1)
        assertThat(historyRepository.entries.single().source.name).isEqualTo("SCHEDULED")
    }

    private fun settingsWithPending(date: LocalDate): ExportSettings = ExportSettings(
        pendingScheduledExportRequests = listOf(
            PendingScheduledExportRequest(date = date, firstFailedAtMillis = 100L, attemptCount = 1)
        ),
    )

    private fun manager(
        healthRepository: FakeHealthRepository = FakeHealthRepository(),
        exportRepository: FakeExportRepository = FakeExportRepository(),
        settingsRepository: FakeSettingsRepository = FakeSettingsRepository(initialPurchased = true),
        historyRepository: FakeExportHistoryRepository = FakeExportHistoryRepository(),
    ): ScheduledExportRecoveryManager = ScheduledExportRecoveryManager(
        healthRepository = healthRepository,
        exportRepository = exportRepository,
        settingsRepository = settingsRepository,
        exportHistoryRepository = historyRepository,
    )
}
