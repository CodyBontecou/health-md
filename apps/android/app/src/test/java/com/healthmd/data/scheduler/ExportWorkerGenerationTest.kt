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
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
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
        val worker = worker(apiGenerationA, stateStore, apiRunner)

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
        coEvery {
            apiRunner.exportDates(
                dates = any(),
                settings = capture(exportedSettings),
                onProgress = null,
                expectedDestinationFingerprint = API_FINGERPRINT,
                durableOperationId = any(),
                durableSettingsSnapshotJson = any(),
            )
        } returns ExportResult(1, 1, target = ExportTarget.API_ENDPOINT)
        val worker = worker(
            occurrence = admitted,
            stateStore = stateStore,
            apiRunner = apiRunner,
            settingsRepository = settingsRepository,
            healthRepository = healthRepository,
            apiCredentialStore = credentialStore,
        )

        val result = worker.doWork()

        assertThat(result).isEqualTo(ListenableWorker.Result.success())
        assertThat(exportedSettings.captured.filenameFormat).isEqualTo("frozen-a-{date}")
        assertThat(exportedSettings.captured.scheduledExportTarget)
            .isEqualTo(ExportTarget.API_ENDPOINT)
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
    ): ExportWorker {
        val context = ApplicationProvider.getApplicationContext<Context>()
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
                runCoordinator = ScheduledExportRunCoordinator(),
                timeCalculator = ScheduledExportTimeCalculator(),
                stateStore = stateStore,
            )
        }
        return TestListenableWorkerBuilder<ExportWorker>(context)
            .setWorkerFactory(factory)
            .setInputData(occurrence.toWorkData())
            .build()
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
