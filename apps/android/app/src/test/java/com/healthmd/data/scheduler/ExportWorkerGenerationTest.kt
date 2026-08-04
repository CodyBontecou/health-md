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
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import java.time.LocalDate
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

    private fun worker(
        occurrence: ScheduledExportOccurrence,
        stateStore: ScheduledExportStateStore,
        apiRunner: APIEndpointExportRunner,
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
                healthRepository = mockk<HealthRepository>(relaxed = true),
                exportRepository = mockk<ExportRepository>(relaxed = true),
                settingsRepository = mockk<SettingsRepository>(relaxed = true),
                exportHistoryRepository = mockk<ExportHistoryRepository>(relaxed = true),
                apiEndpointExportRunner = apiRunner,
                rawSnapshotExportRunner = mockk<RawSnapshotService>(relaxed = true),
                apiCredentialStore = mockk<APIExportCredentialStore>(relaxed = true),
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

    private companion object {
        const val API_FINGERPRINT = "test-api-destination-fingerprint"
    }
}
