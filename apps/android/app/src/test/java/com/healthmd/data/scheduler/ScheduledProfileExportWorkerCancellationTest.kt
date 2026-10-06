package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.TestListenableWorkerBuilder
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.FakeBillingRepository
import com.healthmd.rawexport.ExportMode
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
        assertThat(harness.history.captured.profileName).isEqualTo("Morning API")
        assertThat(harness.history.captured.targetLabel).isEqualTo("https://example.test/health")
        coVerify(exactly = 0) { harness.entryStore.recordSuccess(any(), any(), any(), any()) }
        coVerify(exactly = 1) { harness.scheduler.reconcile() }
    }

    @Test
    fun `history target labels use folder display names and redact API secrets`() {
        val folderProfile = ExportProfile(
            id = "folder-profile",
            name = "Research",
            settingsSnapshotJson = "snapshot",
            target = ExportTarget.DEVICE_FOLDER,
            folderUri = "content://provider/private/document/123",
            folderDisplayName = "  Research Exports  ",
            createdAtEpochMillis = 1L,
            updatedAtEpochMillis = 1L,
        )
        val apiProfile = ExportProfile(
            id = "api-profile",
            name = "API",
            settingsSnapshotJson = "snapshot",
            target = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/health?token=secret",
            createdAtEpochMillis = 1L,
            updatedAtEpochMillis = 1L,
        )

        assertThat(scheduledProfileHistoryTargetLabel(folderProfile))
            .isEqualTo("Research Exports")
        assertThat(scheduledProfileHistoryTargetLabel(folderProfile))
            .doesNotContain("content://")
        assertThat(scheduledProfileHistoryTargetLabel(apiProfile))
            .isEqualTo("https://example.test/health")
        assertThat(scheduledProfileHistoryTargetLabel(apiProfile))
            .doesNotContain("secret")
        assertThat(
            scheduledProfileHistoryTargetLabel(
                folderProfile.copy(folderDisplayName = " "),
            ),
        ).isEqualTo("Export folder")
    }

    @Test
    fun `fresh pending folder capture does not require a nonexistent journal`() {
        assertThat(
            shouldRequireExistingProfileFolderJournal(
                pendingOperationId = null,
                isPendingResidual = true,
                runAttemptCount = 1,
            ),
        ).isFalse()
        assertThat(
            shouldRequireExistingProfileFolderJournal(
                pendingOperationId = null,
                isPendingResidual = false,
                runAttemptCount = 1,
            ),
        ).isTrue()
        assertThat(
            shouldRequireExistingProfileFolderJournal(
                pendingOperationId = "folder-operation",
                isPendingResidual = true,
                runAttemptCount = 1,
            ),
        ).isTrue()
    }

    @Test
    fun `blocked imported profile disables its entry and fails before settings or health access`() = runTest {
        val profileId = "blocked-profile"
        val profile = ExportProfile(
            id = profileId,
            name = "Imported",
            settingsSnapshotJson = "must-not-decode",
            target = ExportTarget.DEVICE_FOLDER,
            createdAtEpochMillis = 1L,
            updatedAtEpochMillis = 1L,
        )
        val entry = ScheduledProfileEntry(
            profileId = profileId,
            isEnabled = true,
            anchorEpochDay = LocalDate.now(ZoneId.of("UTC")).toEpochDay(),
            hour = 0,
            zoneId = "UTC",
        )
        val profileRepository = mockk<ExportProfileRepository>(relaxed = true)
        coEvery { profileRepository.profileById(profileId) } returns profile
        coEvery { profileRepository.isSharedSetupV2Blocked(profileId) } returns true
        val entryStore = mockk<ScheduledProfileEntryStore>(relaxed = true)
        coEvery { entryStore.entry(profileId) } returns entry
        coEvery { entryStore.updateForGeneration(profileId, 0L, any()) } returns true
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        val healthRepository = mockk<HealthRepository>(relaxed = true)
        val worker = worker(
            profileId = profileId,
            settingsRepository = settingsRepository,
            healthRepository = healthRepository,
            exportHistoryRepository = mockk(relaxed = true),
            apiEndpointExportRunner = mockk(relaxed = true),
            profileRepository = profileRepository,
            entryStore = entryStore,
            snapshotFactory = mockk(relaxed = true),
            profileScheduler = mockk(relaxed = true),
        )

        val result = worker.doWork()

        assertThat(result.outputData.getString(ScheduledProfileExportWorker.OUTPUT_PROFILE_ERROR))
            .isEqualTo(ScheduledProfileExportWorker.PROFILE_REBIND_REQUIRED)
        coVerify(exactly = 1) {
            entryStore.updateForGeneration(profileId, 0L, any())
        }
        coVerify(exactly = 0) { settingsRepository.getExportSettings() }
        coVerify(exactly = 0) { healthRepository.hasBackgroundReadPermission() }
    }

    @Test
    fun `failed attempt freezes profile provenance before WorkManager backoff`() = runTest {
        val profileId = "profile-retry"
        val profile = ExportProfile(
            id = profileId,
            name = "Original API",
            settingsSnapshotJson = "original-snapshot",
            target = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://original.example.test/health",
            createdAtEpochMillis = 1L,
            updatedAtEpochMillis = 1L,
        )
        val entry = ScheduledProfileEntry(
            profileId = profileId,
            isEnabled = true,
            anchorEpochDay = LocalDate.now(ZoneId.of("UTC")).toEpochDay(),
            hour = 0,
            minute = 0,
            lookbackDays = 1,
            zoneId = "UTC",
            recoveryGeneration = 1L,
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
        val retryGroups = slot<List<ScheduledProfilePendingExport>>()
        coEvery {
            entryStore.recordRetry(
                profileId = profileId,
                fireAtMillis = any(),
                attemptedPendingID = null,
                replacements = capture(retryGroups),
                expectedRecoveryGeneration = 1L,
            )
        } returns true
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getExportSettings() } returns settings
        every { settingsRepository.isPurchased } returns flowOf(true)
        val healthRepository = mockk<HealthRepository>(relaxed = true)
        coEvery { healthRepository.hasBackgroundReadPermission() } returns true
        val snapshotFactory = mockk<ScheduledProfileSnapshotFactory>(relaxed = true)
        every { snapshotFactory.restoreForRun(profile, settings, 1) } returns settings
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        coEvery {
            apiRunner.exportDates(
                dates = any(),
                settings = any(),
                onProgress = null,
                expectedDestinationFingerprint = null,
                durableOperationId = any(),
                durableSettingsSnapshotJson = profile.settingsSnapshotJson,
            )
        } coAnswers {
            val dates = firstArg<List<LocalDate>>()
            ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = dates.map {
                    com.healthmd.domain.model.FailedDateDetail(
                        it,
                        com.healthmd.domain.model.ExportFailureReason.NETWORK_ERROR,
                    )
                },
                target = ExportTarget.API_ENDPOINT,
            )
        }
        val scheduler = mockk<ScheduledProfileScheduler>(relaxed = true)
        val worker = worker(
            profileId = profileId,
            settingsRepository = settingsRepository,
            healthRepository = healthRepository,
            exportHistoryRepository = mockk(relaxed = true),
            apiEndpointExportRunner = apiRunner,
            profileRepository = profileRepository,
            entryStore = entryStore,
            snapshotFactory = snapshotFactory,
            profileScheduler = scheduler,
            recoveryGeneration = 1L,
        )

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.retry())

        val frozen = retryGroups.captured.single()
        assertThat(frozen.profileName).isEqualTo("Original API")
        assertThat(frozen.settingsSnapshotJson).isEqualTo("original-snapshot")
        assertThat(frozen.target).isEqualTo(ExportTarget.API_ENDPOINT)
        assertThat(frozen.apiEndpointUrl).isEqualTo("https://original.example.test/health")
        assertThat(frozen.durableOperationId).startsWith("profile-api-")
        assertThat(frozen.durableOperationId).endsWith("-g1")
        coVerify(exactly = 1) { entryStore.recordRetry(any(), any(), null, any(), 1L) }
        coVerify(exactly = 0) { entryStore.recordSuccess(any(), any(), any(), any()) }
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
        coVerify(exactly = 0) { harness.entryStore.recordSuccess(any(), any(), any(), any()) }
        coVerify(exactly = 1) { harness.scheduler.reconcile() }
    }

    @Test
    fun `raw profiles use the raw range runner for both targets and keep history mode`() = runTest {
        for (target in ExportTarget.entries) {
            val harness = rawHarness(target = target) { ExportResult(1, 1, target = target, exportMode = ExportMode.RAW_SNAPSHOT) }

            assertThat(harness.worker.doWork()).isEqualTo(ListenableWorker.Result.success())

            assertThat(harness.rawStart.captured).isEqualTo(LocalDate.now(ZoneId.of("UTC")).minusDays(2))
            assertThat(harness.rawEnd.captured).isEqualTo(LocalDate.now(ZoneId.of("UTC")).minusDays(1))
            assertThat(harness.history.captured.exportMode).isEqualTo(ExportMode.RAW_SNAPSHOT)
            assertThat(harness.history.captured.target).isEqualTo(target)
            coVerify(exactly = 1) {
                harness.rawRunner.exportRange(any(), any(), harness.runSettings, target, null, false)
            }
            coVerify(exactly = 0) { harness.apiRunner.exportDates(any(), any(), any(), any(), any(), any()) }
            coVerify(exactly = 0) { harness.exportRepository.exportHealthData(any(), any()) }
            if (target == ExportTarget.DEVICE_FOLDER) {
                coVerify(exactly = 1) { harness.settingsRepository.saveExportFolderUri("content://synthetic/profile") }
                coVerify(exactly = 1) { harness.settingsRepository.saveExportFolderUri("content://synthetic/live") }
            }
        }
    }

    @Test
    fun `raw retry ignores a compatibility operation left by the old profile worker`() = runTest {
        val pending = ScheduledProfilePendingExport(
            id = "old-raw-retry",
            ownerEpochDays = listOf(LocalDate.now(ZoneId.of("UTC")).minusDays(10).toEpochDay()),
            fireAtMillis = 1_000L,
            settingsSnapshotJson = "frozen-raw-snapshot",
            target = ExportTarget.API_ENDPOINT,
            profileName = "Frozen raw profile",
            apiEndpointUrl = "https://example.test/raw",
            durableOperationId = "old-compatibility-operation",
        )
        val harness = rawHarness(pending = pending) {
            ExportResult(1, 1, target = ExportTarget.API_ENDPOINT, exportMode = ExportMode.RAW_SNAPSHOT)
        }

        assertThat(harness.worker.doWork()).isEqualTo(ListenableWorker.Result.success())

        assertThat(harness.rawStart.captured).isEqualTo(pending.ownerDates.single())
        assertThat(harness.rawEnd.captured).isEqualTo(pending.ownerDates.single())
        assertThat(harness.history.captured.profileName).isEqualTo("Frozen raw profile")
        coVerify(exactly = 1) { harness.entryStore.recordSuccess(any(), 1_000L, pending.id, 0L) }
        coVerify(exactly = 0) { harness.apiRunner.exportDates(any(), any(), any(), any(), any(), any()) }
    }

    @Test
    fun `partial raw providers retain every completed date and do not satisfy Today Refresh`() = runTest {
        // Provider successes outnumber the owner dates. Neither those counts nor a start-date
        // diagnostic prove that another provider captured any day of the range.
        val harness = rawHarness(todayRefresh = true) { dates ->
            ExportResult(
                successCount = 5, totalCount = 6,
                failedDateDetails = listOf(FailedDateDetail(dates.first(), ExportFailureReason.RAW_PARTIAL)),
                target = ExportTarget.API_ENDPOINT, exportMode = ExportMode.RAW_SNAPSHOT,
            )
        }

        assertThat(harness.worker.doWork()).isEqualTo(ListenableWorker.Result.retry())

        val residual = harness.replacements.captured.single()
        assertThat(residual.ownerDates).containsExactly(
            harness.rawStart.captured, harness.rawStart.captured.plusDays(1),
        ).inOrder()
        assertThat(residual.durableOperationId).isNull()
        coVerify(exactly = 0) { harness.entryStore.recordRefreshSuccess(any(), any(), any()) }
        coVerify(exactly = 0) { harness.entryStore.recordSuccess(any(), any(), any(), any()) }
    }

    @Test
    fun `raw cancellation retains the full range instead of interpreting artifact counts as dates`() = runTest {
        val harness = rawHarness { dates ->
            ExportResult(
                successCount = 2, totalCount = 3, wasCancelled = true,
                target = ExportTarget.API_ENDPOINT, exportMode = ExportMode.RAW_SNAPSHOT,
                remainingDates = setOf(dates.first()),
            )
        }

        assertThat(harness.worker.doWork()).isEqualTo(ListenableWorker.Result.success())

        assertThat(harness.replacements.captured.single().ownerDates)
            .containsExactly(harness.rawStart.captured, harness.rawEnd.captured).inOrder()
        assertThat(harness.replacements.captured.single().durableOperationId).isNull()
        coVerify(exactly = 1) { harness.entryStore.recordCancellation(any(), any(), null, any(), 0L) }
    }

    @Test
    fun `raw refresh-only failure leaves no historical residual or completed-day checkpoint`() = runTest {
        val harness = rawHarness(todayRefresh = true, refreshOnly = true) { dates ->
            ExportResult(
                successCount = 0, totalCount = 1,
                failedDateDetails = listOf(FailedDateDetail(dates.first(), ExportFailureReason.RAW_PARTIAL)),
                target = ExportTarget.API_ENDPOINT, exportMode = ExportMode.RAW_SNAPSHOT,
            )
        }

        assertThat(harness.worker.doWork()).isEqualTo(ListenableWorker.Result.retry())

        assertThat(harness.replacements.captured).isEmpty()
        coVerify(exactly = 1) { harness.entryStore.recordRetry(any(), null, null, emptyList(), 0L) }
        coVerify(exactly = 0) { harness.entryStore.recordRefreshSuccess(any(), any(), any()) }
    }

    @Test
    fun `discarded generation skips stale admitted work before health or export access`() = runTest {
        val harness = rawHarness { ExportResult(1, 1, exportMode = ExportMode.RAW_SNAPSHOT) }
        coEvery { harness.entryStore.entry(harness.entry.profileId) } returns
            harness.entry.copy(recoveryGeneration = 1L)

        assertThat(harness.worker.doWork()).isEqualTo(ListenableWorker.Result.success())

        coVerify(exactly = 0) { harness.healthRepository.hasBackgroundReadPermission() }
        coVerify(exactly = 0) { harness.rawRunner.exportRange(any(), any(), any(), any(), any(), any()) }
        coVerify(exactly = 0) { harness.apiRunner.exportDates(any(), any(), any(), any(), any(), any()) }
    }

    @Test
    fun `discard during an export prevents late residual and refresh checkpoints`() = runTest {
        val harness = rawHarness(todayRefresh = true) {
            ExportResult(0, 1, exportMode = ExportMode.RAW_SNAPSHOT)
        }
        coEvery { harness.rawRunner.exportRange(any(), any(), any(), any(), any(), any()) } coAnswers {
            coEvery { harness.entryStore.entry(harness.entry.profileId) } returns
                harness.entry.copy(recoveryGeneration = 1L)
            ExportResult(0, 1, exportMode = ExportMode.RAW_SNAPSHOT)
        }

        assertThat(harness.worker.doWork()).isEqualTo(ListenableWorker.Result.success())

        coVerify(exactly = 0) { harness.entryStore.recordRetry(any(), any(), any(), any(), any()) }
        coVerify(exactly = 0) { harness.entryStore.recordRefreshSuccess(any(), any(), any()) }
    }

    private fun rawHarness(
        target: ExportTarget = ExportTarget.API_ENDPOINT,
        pending: ScheduledProfilePendingExport? = null,
        todayRefresh: Boolean = false,
        refreshOnly: Boolean = false,
        result: (List<LocalDate>) -> ExportResult,
    ): RawHarness {
        val today = LocalDate.now(ZoneId.of("UTC"))
        val entry = ScheduledProfileEntry(
            profileId = "raw-profile", isEnabled = true, anchorEpochDay = today.toEpochDay(),
            hour = 0, minute = 0, lookbackDays = 2, zoneId = "UTC",
            todayRefreshEnabled = todayRefresh, todayRefreshIntervalHours = 3,
            lastSuccessEpochMillis = if (refreshOnly) today.atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli() else null,
            pendingExports = listOfNotNull(pending),
        )
        val profile = ExportProfile(
            id = entry.profileId, name = "Raw profile", settingsSnapshotJson = "raw-profile-snapshot",
            target = target, apiEndpointUrl = "https://example.test/raw",
            folderUri = "content://synthetic/profile", createdAtEpochMillis = 1L, updatedAtEpochMillis = 1L,
        )
        val settings = ExportSettings(
            exportTarget = target, scheduledExportTarget = target,
            apiEndpointUrl = requireNotNull(profile.apiEndpointUrl), exportMode = ExportMode.RAW_SNAPSHOT,
        )
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        // Frozen profile mode must win over the current interactive mode.
        coEvery { settingsRepository.getExportSettings() } returns settings.copy(exportMode = ExportMode.COMPATIBILITY)
        every { settingsRepository.isPurchased } returns flowOf(true)
        coEvery { settingsRepository.getExportFolderUri() } returns "content://synthetic/live"
        val profileRepository = mockk<ExportProfileRepository>(relaxed = true)
        coEvery { profileRepository.profileById(profile.id) } returns profile
        val entryStore = mockk<ScheduledProfileEntryStore>(relaxed = true)
        coEvery { entryStore.entry(entry.profileId) } returns entry
        val replacements = slot<List<ScheduledProfilePendingExport>>()
        coEvery { entryStore.recordRetry(any(), any(), any(), capture(replacements), 0L) } returns true
        coEvery { entryStore.recordCancellation(any(), any(), any(), capture(replacements), 0L) } returns true
        val healthRepository = mockk<HealthRepository>(relaxed = true)
        coEvery { healthRepository.hasBackgroundReadPermission() } returns true
        val snapshotFactory = mockk<ScheduledProfileSnapshotFactory>(relaxed = true)
        every { snapshotFactory.restoreForRun(any(), any(), any()) } returns settings
        val rawRunner = mockk<RawSnapshotService>(relaxed = true)
        val rawStart = slot<LocalDate>()
        val rawEnd = slot<LocalDate>()
        coEvery { rawRunner.exportRange(capture(rawStart), capture(rawEnd), settings, target, null, false) } coAnswers {
            result(rawStart.captured.datesUntil(rawEnd.captured.plusDays(1)).toList())
        }
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        val exportRepository = mockk<ExportRepository>(relaxed = true)
        val historyRepository = mockk<ExportHistoryRepository>(relaxed = true)
        val history = slot<ExportHistoryEntry>()
        coEvery { historyRepository.insertEntry(capture(history)) } returns Unit
        val worker = worker(
            profileId = profile.id, settingsRepository = settingsRepository, healthRepository = healthRepository,
            exportHistoryRepository = historyRepository, apiEndpointExportRunner = apiRunner,
            rawSnapshotExportRunner = rawRunner, profileRepository = profileRepository, entryStore = entryStore,
            snapshotFactory = snapshotFactory, profileScheduler = mockk(relaxed = true),
            exportRepository = exportRepository,
            folderAdoption = ProfileFolderAdoptionScope(settingsRepository, profileRepository),
        )
        return RawHarness(worker, entry, entryStore, settings, settingsRepository, healthRepository,
            rawRunner, apiRunner, exportRepository, rawStart, rawEnd, replacements, history)
    }

    private data class RawHarness(
        val worker: ScheduledProfileExportWorker,
        val entry: ScheduledProfileEntry,
        val entryStore: ScheduledProfileEntryStore,
        val runSettings: ExportSettings,
        val settingsRepository: SettingsRepository,
        val healthRepository: HealthRepository,
        val rawRunner: RawSnapshotService,
        val apiRunner: APIEndpointExportRunner,
        val exportRepository: ExportRepository,
        val rawStart: CapturingSlot<LocalDate>,
        val rawEnd: CapturingSlot<LocalDate>,
        val replacements: CapturingSlot<List<ScheduledProfilePendingExport>>,
        val history: CapturingSlot<ExportHistoryEntry>,
    )

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
                expectedRecoveryGeneration = 0L,
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
        rawSnapshotExportRunner: RawSnapshotService = mockk(relaxed = true),
        exportRepository: ExportRepository = mockk(relaxed = true),
        folderAdoption: ProfileFolderAdoptionScope = mockk(relaxed = true),
        recoveryGeneration: Long = 0L,
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
                exportRepository = exportRepository,
                exportHistoryRepository = exportHistoryRepository,
                apiEndpointExportRunner = apiEndpointExportRunner,
                rawSnapshotExportRunner = rawSnapshotExportRunner,
                profileRepository = profileRepository,
                entryStore = entryStore,
                snapshotFactory = snapshotFactory,
                folderAdoption = folderAdoption,
                profileScheduler = Lazy { profileScheduler },
                entitlementRepository = FakeBillingRepository(),
                distributionPolicy = DistributionPolicy.play(),
            )
        }
        return TestListenableWorkerBuilder<ScheduledProfileExportWorker>(context)
            .setWorkerFactory(factory)
            .setInputData(
                androidx.work.workDataOf(
                    ScheduledProfileExportWorker.INPUT_PROFILE_ID to profileId,
                    ScheduledProfileExportWorker.INPUT_RECOVERY_GENERATION to recoveryGeneration,
                ),
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
