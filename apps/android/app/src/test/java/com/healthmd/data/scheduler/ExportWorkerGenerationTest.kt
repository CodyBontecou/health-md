package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.TestListenableWorkerBuilder
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIEndpointExportRunner
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.ScheduleDateWindow
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
import io.mockk.verify
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ExportWorkerGenerationTest {
    @Test
    fun queuedOfflineApiGenerationCannotReviveAfterFolderAndSameApiGenerations() = runTest {
        val apiGenerationA = occurrence(ExportTarget.API_ENDPOINT, "generation-api-a")
        val folderGenerationB = occurrence(ExportTarget.DEVICE_FOLDER, "generation-folder-b")
        val apiGenerationC = occurrence(ExportTarget.API_ENDPOINT, "generation-api-c")
        assertThat(apiGenerationA.configuration.signature)
            .isEqualTo(apiGenerationC.configuration.signature)
        assertThat(folderGenerationB.generation).isNotEqualTo(apiGenerationA.generation)

        val stateStore = mockk<ScheduledExportStateStore>()
        every { stateStore.isGenerationMigrationComplete() } returns true
        every { stateStore.load() } returns apiGenerationC
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        val worker = worker(
            apiGenerationA,
            stateStore,
            apiRunner,
            admissionMatches = false,
        )

        val result = worker.doWork()

        assertThat(result).isEqualTo(ListenableWorker.Result.success())
        coVerify(exactly = 0) { apiRunner.exportDates(any(), any()) }
    }

    @Test
    fun sameGenerationWorkerWithoutExactAdmissionIsStaleSuccess() = runTest {
        val captured = occurrence(ExportTarget.API_ENDPOINT, "generation-active")
        val next = captured.copy(triggerAtMillis = captured.triggerAtMillis + 900_000L)
        val stateStore = mockk<ScheduledExportStateStore>()
        every { stateStore.isGenerationMigrationComplete() } returns true
        every { stateStore.load() } returns next
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        val worker = worker(
            occurrence = captured,
            stateStore = stateStore,
            apiRunner = apiRunner,
            admissionMatches = false,
        )

        val result = worker.doWork()

        assertThat(result).isEqualTo(ListenableWorker.Result.success())
        coVerify(exactly = 0) { apiRunner.exportDates(any(), any()) }
    }

    @Test
    fun legacyWorkerWithoutGenerationIsStaleSuccessAfterMigration() = runTest {
        val active = occurrence(ExportTarget.API_ENDPOINT, "generation-active")
        val legacy = occurrence(ExportTarget.API_ENDPOINT, generation = null)
        val stateStore = mockk<ScheduledExportStateStore>()
        every { stateStore.isGenerationMigrationComplete() } returns true
        every { stateStore.load() } returns active
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        val worker = worker(legacy, stateStore, apiRunner)

        val result = worker.doWork()

        assertThat(result).isEqualTo(ListenableWorker.Result.success())
        coVerify(exactly = 0) { apiRunner.exportDates(any(), any()) }
    }

    @Test
    fun admittedSameTargetRunFinishesFrozenSnapshotAfterMutableSettingsChange() = runTest {
        val frozenSettings = ExportSettings(
            exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/health",
            filenameFormat = "frozen-a-{date}",
            scheduleEnabled = true,
            scheduleCadenceValue = 15,
            scheduleCadenceUnit = ScheduleCadenceUnit.MINUTES,
        )
        val persistedAfterAdmission = frozenSettings.copy(filenameFormat = "mutable-b-{date}")
        val admitted = frozenOccurrence(frozenSettings, "generation-admitted")
        val stateStore = mockk<ScheduledExportStateStore>()
        every { stateStore.isGenerationMigrationComplete() } returns true
        every { stateStore.load() } returns admitted
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getExportSettings() } returns persistedAfterAdmission
        every { settingsRepository.isPurchased } returns flowOf(true)
        val healthRepository = mockk<HealthRepository>(relaxed = true)
        coEvery { healthRepository.hasBackgroundReadPermission() } returns true
        val credentialStore = mockk<APIExportCredentialStore>(relaxed = true)
        coEvery { credentialStore.destinationFingerprint(any()) } returns API_FINGERPRINT
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        val exportedSettings = slot<ExportSettings>()
        val exportedOperationId = slot<String>()
        coEvery {
            apiRunner.exportDates(
                dates = any(),
                settings = capture(exportedSettings),
                onProgress = null,
                expectedDestinationFingerprint = API_FINGERPRINT,
                durableOperationId = capture(exportedOperationId),
                durableSettingsSnapshotJson = any(),
            )
        } returns ExportResult(1, 1, target = ExportTarget.API_ENDPOINT)
        val scheduler = mockk<ExportScheduler>(relaxed = true)
        val worker = worker(
            occurrence = admitted,
            stateStore = stateStore,
            apiRunner = apiRunner,
            settingsRepository = settingsRepository,
            healthRepository = healthRepository,
            apiCredentialStore = credentialStore,
            exportScheduler = scheduler,
        )

        val result = worker.doWork()

        assertThat(result).isEqualTo(ListenableWorker.Result.success())
        assertThat(exportedSettings.captured.filenameFormat).isEqualTo("frozen-a-{date}")
        assertThat(exportedOperationId.captured).isEqualTo(
            ScheduledExportAdmission.create(
                occurrence = admitted,
                catchUpThroughMillis = admitted.triggerAtMillis,
                expedited = false,
            ).operationId,
        )
        assertThat(exportedSettings.captured.scheduledExportTarget)
            .isEqualTo(ExportTarget.API_ENDPOINT)
        verify(exactly = 1) { stateStore.completeAdmission(any(), any(), any()) }
        coVerify(exactly = 1) { scheduler.reconcile() }
    }

    @Test
    fun admissionClearFailureRetriesFinalizationWithoutRepeatingExport() = runTest {
        val settings = ExportSettings(
            exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/health",
            scheduleEnabled = true,
            scheduleCadenceValue = 15,
            scheduleCadenceUnit = ScheduleCadenceUnit.MINUTES,
        )
        val admitted = frozenOccurrence(settings, "generation-admitted")
        val stateStore = mockk<ScheduledExportStateStore>()
        every { stateStore.isGenerationMigrationComplete() } returns true
        every { stateStore.load() } returns admitted
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getExportSettings() } returns settings
        every { settingsRepository.isPurchased } returns flowOf(true)
        val healthRepository = mockk<HealthRepository>(relaxed = true)
        coEvery { healthRepository.hasBackgroundReadPermission() } returns true
        val credentialStore = mockk<APIExportCredentialStore>(relaxed = true)
        coEvery { credentialStore.destinationFingerprint(any()) } returns API_FINGERPRINT
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        coEvery {
            apiRunner.exportDates(
                dates = any(),
                settings = any(),
                onProgress = null,
                expectedDestinationFingerprint = API_FINGERPRINT,
                durableOperationId = any(),
                durableSettingsSnapshotJson = any(),
            )
        } returns ExportResult(1, 1, target = ExportTarget.API_ENDPOINT)
        val scheduler = mockk<ExportScheduler>(relaxed = true)
        val worker = worker(
            occurrence = admitted,
            stateStore = stateStore,
            apiRunner = apiRunner,
            settingsRepository = settingsRepository,
            healthRepository = healthRepository,
            apiCredentialStore = credentialStore,
            exportScheduler = scheduler,
        )
        var executionCompleted = false
        var clearAttempts = 0
        every { stateStore.isAdmissionExecutionCompleted(any(), any(), any()) } answers {
            executionCompleted
        }
        every { stateStore.markAdmissionExecutionCompleted(any(), any(), any()) } answers {
            executionCompleted = true
            true
        }
        every { stateStore.completeAdmission(any(), any(), any()) } answers {
            clearAttempts += 1
            clearAttempts > 1
        }

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.retry())
        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.success())

        coVerify(exactly = 1) {
            apiRunner.exportDates(
                dates = any(),
                settings = any(),
                onProgress = null,
                expectedDestinationFingerprint = API_FINGERPRINT,
                durableOperationId = any(),
                durableSettingsSnapshotJson = any(),
            )
        }
        coVerify(exactly = 1) { scheduler.reconcile() }
    }

    @Test
    fun retryRetainsAdmissionAndDoesNotReconcileTheNextOccurrence() = runTest {
        val settings = ExportSettings(
            exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/health",
            scheduleEnabled = true,
            scheduleCadenceValue = 15,
            scheduleCadenceUnit = ScheduleCadenceUnit.MINUTES,
        )
        val admitted = frozenOccurrence(settings, "generation-admitted")
        val stateStore = mockk<ScheduledExportStateStore>()
        every { stateStore.isGenerationMigrationComplete() } returns true
        every { stateStore.load() } returns admitted
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getExportSettings() } returns settings
        every { settingsRepository.isPurchased } returns flowOf(true)
        val healthRepository = mockk<HealthRepository>(relaxed = true)
        coEvery { healthRepository.hasBackgroundReadPermission() } returns true
        val credentialStore = mockk<APIExportCredentialStore>(relaxed = true)
        coEvery { credentialStore.destinationFingerprint(any()) } returns API_FINGERPRINT
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        coEvery {
            apiRunner.exportDates(
                dates = any(),
                settings = any(),
                onProgress = null,
                expectedDestinationFingerprint = API_FINGERPRINT,
                durableOperationId = any(),
                durableSettingsSnapshotJson = any(),
            )
        } returns ExportResult(
            successCount = 0,
            totalCount = 1,
            failedDateDetails = listOf(
                FailedDateDetail(admitted.intendedLocalDate, ExportFailureReason.DEVICE_LOCKED),
            ),
            target = ExportTarget.API_ENDPOINT,
        )
        val scheduler = mockk<ExportScheduler>(relaxed = true)
        val worker = worker(
            occurrence = admitted,
            stateStore = stateStore,
            apiRunner = apiRunner,
            settingsRepository = settingsRepository,
            healthRepository = healthRepository,
            apiCredentialStore = credentialStore,
            exportScheduler = scheduler,
        )

        val result = worker.doWork()

        assertThat(result).isEqualTo(ListenableWorker.Result.retry())
        verify(exactly = 0) { stateStore.completeAdmission(any(), any(), any()) }
        coVerify(exactly = 0) { scheduler.reconcile() }
    }

    @Test
    fun finalOuterExceptionClearsAdmissionAndReconcilesInsteadOfFreezingSchedule() = runTest {
        val settings = ExportSettings(
            exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/health",
            scheduleEnabled = true,
            scheduleCadenceValue = 15,
            scheduleCadenceUnit = ScheduleCadenceUnit.MINUTES,
        )
        val admitted = frozenOccurrence(settings, "generation-admitted")
        val stateStore = mockk<ScheduledExportStateStore>()
        every { stateStore.isGenerationMigrationComplete() } returns true
        every { stateStore.load() } returns admitted
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getExportSettings() } throws
            IllegalStateException("simulated repository failure")
        val scheduler = mockk<ExportScheduler>(relaxed = true)
        val worker = worker(
            occurrence = admitted,
            stateStore = stateStore,
            apiRunner = mockk(relaxed = true),
            settingsRepository = settingsRepository,
            exportScheduler = scheduler,
            runAttemptCount = 3,
        )

        val result = worker.doWork()

        assertThat(result).isEqualTo(ListenableWorker.Result.failure())
        verify(exactly = 1) {
            stateStore.markAdmissionExecutionCompleted(any(), any(), any())
        }
        verify(exactly = 1) { stateStore.completeAdmission(any(), any(), any()) }
        coVerify(exactly = 1) { scheduler.reconcile() }
    }

    @Test
    fun admittedRunStillFailsClosedWhenEndpointIdentityChanges() = runTest {
        val frozenSettings = ExportSettings(
            exportTarget = ExportTarget.API_ENDPOINT,
            scheduledExportTarget = ExportTarget.API_ENDPOINT,
            apiEndpointUrl = "https://example.test/health",
            scheduleEnabled = true,
            scheduleCadenceValue = 15,
            scheduleCadenceUnit = ScheduleCadenceUnit.MINUTES,
        )
        val admitted = frozenOccurrence(frozenSettings, "generation-admitted")
        val stateStore = mockk<ScheduledExportStateStore>()
        every { stateStore.isGenerationMigrationComplete() } returns true
        every { stateStore.load() } returns admitted
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getExportSettings() } returns frozenSettings.copy(
            apiEndpointUrl = "https://different.example.test/health",
        )
        val credentialStore = mockk<APIExportCredentialStore>(relaxed = true)
        coEvery { credentialStore.destinationFingerprint(any()) } returns "different-fingerprint"
        val apiRunner = mockk<APIEndpointExportRunner>(relaxed = true)
        val worker = worker(
            occurrence = admitted,
            stateStore = stateStore,
            apiRunner = apiRunner,
            settingsRepository = settingsRepository,
            apiCredentialStore = credentialStore,
        )

        val result = worker.doWork()

        assertThat(result).isEqualTo(ListenableWorker.Result.success())
        coVerify(exactly = 0) { apiRunner.exportDates(any(), any()) }
    }

    private fun worker(
        occurrence: ScheduledExportOccurrence,
        stateStore: ScheduledExportStateStore,
        apiRunner: APIEndpointExportRunner,
        settingsRepository: SettingsRepository = mockk(relaxed = true),
        healthRepository: HealthRepository = mockk(relaxed = true),
        apiCredentialStore: APIExportCredentialStore = mockk(relaxed = true),
        admissionMatches: Boolean = true,
        runCoordinator: ScheduledExportRunCoordinator = ScheduledExportRunCoordinator(),
        exportScheduler: ExportScheduler = mockk(relaxed = true),
        runAttemptCount: Int = 0,
    ): ExportWorker {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val admission = occurrence.generation?.let {
            ScheduledExportAdmission.create(
                occurrence = occurrence,
                catchUpThroughMillis = occurrence.triggerAtMillis,
                expedited = false,
            )
        }
        every { stateStore.matchesAdmission(any(), any(), any()) } returns admissionMatches
        every { stateStore.isAdmissionExecutionCompleted(any(), any(), any()) } returns false
        every { stateStore.markAdmissionExecutionCompleted(any(), any(), any()) } returns admissionMatches
        every { stateStore.completeAdmission(any(), any(), any()) } returns admissionMatches
        every { stateStore.pendingArmOccurrence() } returns null
        val factory = object : WorkerFactory() {
            override fun createWorker(
                appContext: Context,
                workerClassName: String,
                workerParameters: WorkerParameters,
            ): ListenableWorker = ExportWorker(
                appContext = appContext,
                workerParams = workerParameters,
                healthRepository = healthRepository,
                exportRepository = mockk<ExportRepository>(relaxed = true),
                settingsRepository = settingsRepository,
                exportHistoryRepository = mockk<ExportHistoryRepository>(relaxed = true),
                apiEndpointExportRunner = apiRunner,
                rawSnapshotExportRunner = mockk<RawSnapshotService>(relaxed = true),
                apiCredentialStore = apiCredentialStore,
                runCoordinator = runCoordinator,
                timeCalculator = ScheduledExportTimeCalculator(),
                stateStore = stateStore,
                exportScheduler = Lazy { exportScheduler },
            )
        }
        val builder = TestListenableWorkerBuilder<ExportWorker>(context)
            .setWorkerFactory(factory)
            .setInputData(admission?.inputData ?: occurrence.toWorkData())
            .setRunAttemptCount(runAttemptCount)
        admission?.let { builder.setId(it.workRequestId) }
        return builder.build()
    }

    private fun occurrence(
        target: ExportTarget,
        generation: String?,
    ): ScheduledExportOccurrence = ScheduledExportOccurrence(
        configuration = ScheduledExportConfiguration(
            cadenceValue = 15,
            cadenceUnit = ScheduleCadenceUnit.MINUTES,
            hour = 6,
            minute = 0,
            lookbackDays = 1,
            dateWindow = ScheduleDateWindow.PAST_COMPLETE_DAYS,
            target = target,
            destinationFingerprint = API_FINGERPRINT.takeIf {
                target == ExportTarget.API_ENDPOINT
            },
            zoneId = "UTC",
        ),
        triggerAtMillis = 1_800_000_000_000L,
        intendedLocalDate = LocalDate.parse("2027-01-15"),
        generation = generation,
    )

    private fun frozenOccurrence(
        settings: ExportSettings,
        generation: String,
    ): ScheduledExportOccurrence {
        val zone = ZoneId.of("UTC")
        val snapshot = AndroidExportSettingsSnapshot.capture(settings, pin = null, zone = zone)
        return ScheduledExportOccurrence(
            configuration = ScheduledExportConfiguration.from(
                settings = settings,
                destinationFingerprint = API_FINGERPRINT,
                zoneId = zone,
                enginePin = null,
                settingsSnapshot = snapshot,
            ),
            triggerAtMillis = 1_800_000_000_000L,
            intendedLocalDate = LocalDate.parse("2027-01-15"),
            generation = generation,
        )
    }

    private companion object {
        const val API_FINGERPRINT = "test-api-destination-fingerprint"
    }
}
