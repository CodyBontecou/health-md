package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.TestListenableWorkerBuilder
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.Lazy
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.CapturingSlot
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ScheduledProfileExportWorkerCancellationTest {
    @Before
    fun setUp() {
        ScheduledExportCancellationCoordinator.resetForTests()
    }

    @After
    fun tearDown() {
        ScheduledExportCancellationCoordinator.resetForTests()
    }

    @Test
    fun `partial cancellation freezes only residual owner dates and is not failure history`() = runTest {
        val harness = harness(checkpointPersists = true)
        val foregroundInfo = harness.worker.getForegroundInfo()
        assertThat(foregroundInfo.notification.actions.single().title.toString())
            .isEqualTo("Cancel Export")

        val workerRun = async { harness.worker.doWork() }
        harness.exportStarted.await()
        assertThat(
            ScheduledExportCancellationCoordinator.requestCancellation(harness.worker.id),
        ).isTrue()
        val result = workerRun.await()

        assertThat(result).isEqualTo(ListenableWorker.Result.success())
        assertThat(harness.replacementGroups.captured).hasSize(1)
        val pending = harness.replacementGroups.captured.single()
        assertThat(pending.ownerDates).containsExactly(harness.exportedDates.captured.last())
        assertThat(pending.durableOperationId).isEqualTo("profile-api-residual")
        assertThat(pending.settingsSnapshotJson).isEqualTo(harness.profile.settingsSnapshotJson)
        assertThat(pending.apiEndpointUrl).isEqualTo(harness.profile.apiEndpointUrl)
        assertThat(harness.history.captured.successCount).isEqualTo(1)
        assertThat(harness.history.captured.failureReason).isNull()
        assertThat(harness.history.captured.failedDateDetails).isEmpty()
        coVerify(exactly = 0) { harness.entryStore.recordSuccess(any(), any(), any()) }
        coVerify(exactly = 1) { harness.scheduler.reconcile() }
    }

    @Test
    fun `failed cancellation checkpoint retries without history or success checkpoint`() = runTest {
        val harness = harness(checkpointPersists = false)

        val workerRun = async { harness.worker.doWork() }
        harness.exportStarted.await()
        assertThat(
            ScheduledExportCancellationCoordinator.requestCancellation(harness.worker.id),
        ).isTrue()
        val result = workerRun.await()

        assertThat(result).isEqualTo(ListenableWorker.Result.retry())
        coVerify(exactly = 0) { harness.historyRepository.insertEntry(any()) }
        coVerify(exactly = 0) { harness.entryStore.recordSuccess(any(), any(), any()) }
        coVerify(exactly = 1) { harness.scheduler.reconcile() }
    }

    private fun harness(checkpointPersists: Boolean): CancellationHarness {
        val profileId = "profile-cancel"
        val entry = ScheduledProfileEntry(
            profileId = profileId,
            isEnabled = true,
            anchorEpochDay = LocalDate.now(ZoneId.of("UTC")).toEpochDay(),
            hour = 0,
            minute = 0,
            lookbackDays = 2,
            zoneId = "UTC",
        )
        val profile = ExportProfile(
            id = profileId,
            name = "Morning API",
            settingsSnapshotJson = "frozen-profile-snapshot",
            target = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/health",
            createdAtEpochMillis = 1L,
            updatedAtEpochMillis = 1L,
        )
        val settings = ExportSettings(
            exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = requireNotNull(profile.apiEndpointUrl),
        )
        val profileRepository = mockk<ExportProfileRepository>(relaxed = true)
        coEvery { profileRepository.profileById(profileId) } returns profile
        val entryStore = mockk<ScheduledProfileEntryStore>(relaxed = true)
        coEvery { entryStore.entry(profileId) } returns entry
        val replacementGroups = slot<List<ScheduledProfilePendingExport>>()
        coEvery {
            entryStore.recordCancellation(
                profileId = profileId,
                fireAtMillis = any(),
                attemptedPendingID = null,
                replacements = capture(replacementGroups),
            )
        } returns checkpointPersists
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getExportSettings() } returns settings
        every { settingsRepository.isPurchased } returns flowOf(true)
        val healthRepository = mockk<HealthRepository>(relaxed = true)
        coEvery { healthRepository.hasBackgroundReadPermission() } returns true
        val snapshotFactory = mockk<ScheduledProfileSnapshotFactory>(relaxed = true)
        every { snapshotFactory.restoreForRun(profile, settings, 2) } returns settings
        val exportedDates = slot<List<LocalDate>>()
        val exportStarted = CompletableDeferred<Unit>()
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        coEvery {
            apiRunner.exportDates(
                dates = capture(exportedDates),
                settings = any(),
                onProgress = null,
                expectedDestinationFingerprint = null,
                durableOperationId = any(),
                durableSettingsSnapshotJson = profile.settingsSnapshotJson,
            )
        } coAnswers {
            val dates = exportedDates.captured
            exportStarted.complete(Unit)
            try {
                awaitCancellation()
            } catch (_: kotlinx.coroutines.CancellationException) {
                ExportResult(
                    successCount = 1,
                    totalCount = dates.size,
                    wasCancelled = true,
                    target = ExportTarget.API_ENDPOINT,
                    retryOperationIds = mapOf(dates.last() to "profile-api-residual"),
                    remainingDates = setOf(dates.last()),
                )
            }
        }
        val historyRepository = mockk<ExportHistoryRepository>(relaxed = true)
        val history = slot<ExportHistoryEntry>()
        coEvery { historyRepository.insertEntry(capture(history)) } returns Unit
        val scheduler = mockk<ScheduledProfileScheduler>(relaxed = true)
        val worker = worker(
            profileId = profileId,
            settingsRepository = settingsRepository,
            healthRepository = healthRepository,
            exportHistoryRepository = historyRepository,
            apiEndpointExportRunner = apiRunner,
            profileRepository = profileRepository,
            entryStore = entryStore,
            snapshotFactory = snapshotFactory,
            profileScheduler = scheduler,
        )
        return CancellationHarness(
            worker = worker,
            profile = profile,
            entryStore = entryStore,
            historyRepository = historyRepository,
            scheduler = scheduler,
            replacementGroups = replacementGroups,
            exportedDates = exportedDates,
            exportStarted = exportStarted,
            history = history,
        )
    }

    private fun worker(
        profileId: String,
        settingsRepository: SettingsRepository,
        healthRepository: HealthRepository,
        exportHistoryRepository: ExportHistoryRepository,
        apiEndpointExportRunner: APIEndpointExportRunner,
        profileRepository: ExportProfileRepository,
        entryStore: ScheduledProfileEntryStore,
        snapshotFactory: ScheduledProfileSnapshotFactory,
        profileScheduler: ScheduledProfileScheduler,
    ): ScheduledProfileExportWorker {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val factory = object : WorkerFactory() {
            override fun createWorker(
                appContext: Context,
                workerClassName: String,
                workerParameters: WorkerParameters,
            ): ListenableWorker = ScheduledProfileExportWorker(
                appContext = appContext,
                workerParams = workerParameters,
                settingsRepository = settingsRepository,
                healthRepository = healthRepository,
                exportRepository = mockk<ExportRepository>(relaxed = true),
                exportHistoryRepository = exportHistoryRepository,
                apiEndpointExportRunner = apiEndpointExportRunner,
                profileRepository = profileRepository,
                entryStore = entryStore,
                snapshotFactory = snapshotFactory,
                folderAdoption = mockk<ProfileFolderAdoptionScope>(relaxed = true),
                profileScheduler = Lazy { profileScheduler },
            )
        }
        return TestListenableWorkerBuilder<ScheduledProfileExportWorker>(context)
            .setWorkerFactory(factory)
            .setInputData(
                androidx.work.workDataOf(ScheduledProfileExportWorker.INPUT_PROFILE_ID to profileId),
            )
            .build()
    }

    private data class CancellationHarness(
        val worker: ScheduledProfileExportWorker,
        val profile: ExportProfile,
        val entryStore: ScheduledProfileEntryStore,
        val historyRepository: ExportHistoryRepository,
        val scheduler: ScheduledProfileScheduler,
        val replacementGroups: CapturingSlot<List<ScheduledProfilePendingExport>>,
        val exportedDates: CapturingSlot<List<LocalDate>>,
        val exportStarted: CompletableDeferred<Unit>,
        val history: CapturingSlot<ExportHistoryEntry>,
    )
}
