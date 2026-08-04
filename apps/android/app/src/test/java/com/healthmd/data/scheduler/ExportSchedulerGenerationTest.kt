package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.Operation
import androidx.work.WorkManager
import com.google.common.truth.Truth.assertThat
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.SettableFuture
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.ScheduleCadenceUnit
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import java.time.LocalDate
import java.time.ZoneId
import java.util.TimeZone
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ExportSchedulerGenerationTest {
    private lateinit var context: Context
    private lateinit var stateStore: ScheduledExportStateStore
    private lateinit var originalTimeZone: TimeZone

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
        stateStore = ScheduledExportStateStore(context)
        originalTimeZone = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
    }

    @After
    fun tearDown() {
        TimeZone.setDefault(originalTimeZone)
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun destinationReplacementAwaitsOccurrenceAndFallbackCancellationBeforeArming() = runTest {
        val apiSettings = settings(ExportTarget.API_ENDPOINT)
        val folderSettings = settings(ExportTarget.DEVICE_FOLDER)
        stateStore.markGenerationMigrationComplete()
        stateStore.save(occurrence(apiSettings, "generation-api-a"))

        val occurrenceCancellation = SettableFuture.create<Operation.State.SUCCESS>()
        val fallbackCancellation = SettableFuture.create<Operation.State.SUCCESS>()
        val enqueued = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(
            enqueued = enqueued,
            occurrenceCancellation = pendingOperation(occurrenceCancellation),
            fallbackCancellation = pendingOperation(fallbackCancellation),
        )
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { folderSettings },
            generations = listOf("generation-folder-b"),
        )

        val replacement = async { scheduler.reconcile() }
        runCurrent()

        assertThat(replacement.isCompleted).isFalse()
        assertThat(enqueued).isEmpty()
        assertThat(stateStore.load()).isNull()
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
        verify(exactly = 0) {
            workManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }

        occurrenceCancellation.set(Operation.SUCCESS)
        runCurrent()

        assertThat(replacement.isCompleted).isFalse()
        assertThat(enqueued).isEmpty()
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }

        fallbackCancellation.set(Operation.SUCCESS)
        replacement.await()

        assertThat(enqueued).hasSize(1)
        assertThat(stateStore.load()?.generation).isEqualTo("generation-folder-b")
    }

    @Test
    fun legacyOccurrenceAndWorkAreCancelledOnceAndReplacedFromCurrentSettings() = runTest {
        val legacySettings = settings(ExportTarget.DEVICE_FOLDER).copy(scheduleLookbackDays = 9)
        val currentSettings = settings(ExportTarget.DEVICE_FOLDER).copy(scheduleLookbackDays = 2)
        val legacyOccurrence = occurrence(legacySettings, generation = null)
        stateStore.save(legacyOccurrence)
        val enqueued = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(enqueued)
        val generationFactory = generationFactory(listOf("generation-migrated"))
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { currentSettings },
            generationFactory = generationFactory,
        )

        scheduler.reconcile()
        scheduler.reconcile()

        val migrated = requireNotNull(stateStore.load())
        assertThat(stateStore.isGenerationMigrationComplete()).isTrue()
        assertThat(migrated.generation).isEqualTo("generation-migrated")
        assertThat(migrated.configuration.lookbackDays).isEqualTo(2)
        assertThat(migrated.configuration.signature)
            .isNotEqualTo(legacyOccurrence.configuration.signature)
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }
        verify(exactly = 1) { generationFactory.create() }
    }

    @Test
    fun rebootReconciliationKeepsThePersistedGeneration() = runTest {
        val settings = settings(ExportTarget.DEVICE_FOLDER)
        val persisted = occurrence(settings, "generation-before-reboot")
        stateStore.markGenerationMigrationComplete()
        stateStore.save(persisted)
        val requests = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(requests)
        val generationFactory = generationFactory(listOf("generation-unexpected"))

        // A new scheduler and state-store instance model process recreation after BOOT_COMPLETED.
        val rebootedScheduler = scheduler(
            workManager = workManager,
            currentSettings = { settings },
            generationFactory = generationFactory,
            stateStore = ScheduledExportStateStore(context),
        )
        rebootedScheduler.reconcile()

        val reloaded = ScheduledExportStateStore(context).load()
        assertThat(reloaded?.generation).isEqualTo("generation-before-reboot")
        assertThat(requests).hasSize(1)
        assertThat(
            requests.single().workSpec.input.getString(ScheduledExportOccurrence.KEY_GENERATION),
        ).isEqualTo("generation-before-reboot")
        verify(exactly = 0) { generationFactory.create() }
    }

    @Test
    fun rapidApiFolderSameApiReconfigurationLeavesOnlyFinalGenerationActive() = runTest {
        var currentSettings = settings(ExportTarget.API_ENDPOINT)
        stateStore.markGenerationMigrationComplete()
        val requests = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(requests)
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { currentSettings },
            generations = listOf(
                "generation-api-a",
                "generation-folder-b",
                "generation-api-c",
            ),
        )

        scheduler.reconcile()
        currentSettings = settings(ExportTarget.DEVICE_FOLDER)
        scheduler.reconcile()
        currentSettings = settings(ExportTarget.API_ENDPOINT)
        scheduler.reconcile()

        val active = requireNotNull(stateStore.load())
        assertThat(active.generation).isEqualTo("generation-api-c")
        assertThat(active.configuration.target).isEqualTo(ExportTarget.API_ENDPOINT)
        assertThat(requests.mapNotNull { request ->
            request.workSpec.input.getString(ScheduledExportOccurrence.KEY_GENERATION)
        }).containsExactly(
            "generation-api-a",
            "generation-folder-b",
            "generation-api-c",
        ).inOrder()
        assertThat(requests.last().tags)
            .contains(ExportScheduler.GENERATION_TAG_PREFIX + "generation-api-c")
        verify(exactly = 3) {
            workManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
        verify(exactly = 3) {
            workManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }
        verify(exactly = 0) { workManager.cancelAllWork() }
    }

    @Test
    fun frozenOutputSettingsReplacementMintsANewGeneration() = runTest {
        var currentSettings = settings(ExportTarget.DEVICE_FOLDER)
        stateStore.markGenerationMigrationComplete()
        val workManager = workManager()
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { currentSettings },
            generations = listOf("generation-output-a", "generation-output-b"),
        )

        scheduler.reconcile()
        currentSettings = currentSettings.copy(filenameFormat = "changed-{date}")
        scheduler.reconcile()

        assertThat(stateStore.load()?.generation).isEqualTo("generation-output-b")
        verify(exactly = 2) {
            workManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
    }

    private fun scheduler(
        workManager: WorkManager,
        currentSettings: () -> ExportSettings,
        generations: List<String> = emptyList(),
        generationFactory: ScheduledExportGeneration = generationFactory(generations),
        stateStore: ScheduledExportStateStore = this.stateStore,
    ): ExportScheduler {
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getExportSettings() } answers { currentSettings() }
        val credentialStore = mockk<APIExportCredentialStore>(relaxed = true)
        coEvery { credentialStore.destinationFingerprint(any()) } returns API_FINGERPRINT
        val enginePinPlanner = mockk<ExportEnginePinPlanner>()
        every { enginePinPlanner.forScheduledExport(any(), any(), any()) } returns null
        every {
            enginePinPlanner.persistedPinAppliesToScheduledExport(any(), any(), any())
        } returns true
        return ExportScheduler(
            context = context,
            workManager = workManager,
            settingsRepository = settingsRepository,
            apiCredentialStore = credentialStore,
            stateStore = stateStore,
            timeCalculator = ScheduledExportTimeCalculator(),
            enginePinPlanner = enginePinPlanner,
            generationFactory = generationFactory,
            runCoordinator = ScheduledExportRunCoordinator(),
        )
    }

    private fun occurrence(
        settings: ExportSettings,
        generation: String?,
    ): ScheduledExportOccurrence = ScheduledExportOccurrence(
        configuration = configuration(settings),
        triggerAtMillis = 1_900_000_000_000L,
        intendedLocalDate = LocalDate.parse("2030-03-17"),
        generation = generation,
    )

    private fun configuration(settings: ExportSettings): ScheduledExportConfiguration {
        val zone = ZoneId.of("UTC")
        val snapshot = AndroidExportSettingsSnapshot.capture(settings, pin = null, zone = zone)
        return ScheduledExportConfiguration.from(
            settings = settings,
            destinationFingerprint = API_FINGERPRINT.takeIf {
                settings.scheduledExportTarget == ExportTarget.API_ENDPOINT
            },
            zoneId = zone,
            enginePin = null,
            settingsSnapshot = snapshot,
        )
    }

    private fun settings(target: ExportTarget): ExportSettings = ExportSettings(
        exportTarget = target,
        scheduledExportTarget = target,
        apiEndpointUrl = "https://example.test/health",
        scheduleEnabled = true,
        scheduleCadenceValue = 15,
        scheduleCadenceUnit = ScheduleCadenceUnit.MINUTES,
        scheduleLookbackDays = 1,
    )

    private fun generationFactory(generations: List<String>): ScheduledExportGeneration =
        mockk<ScheduledExportGeneration>().also { factory ->
            if (generations.isNotEmpty()) {
                every { factory.create() } returnsMany generations
            }
        }

    private fun workManager(
        enqueued: MutableList<OneTimeWorkRequest> = mutableListOf(),
        occurrenceCancellation: Operation = successfulOperation(),
        fallbackCancellation: Operation = successfulOperation(),
    ): WorkManager = mockk(relaxed = true) {
        every {
            enqueueUniqueWork(
                any<String>(),
                any<ExistingWorkPolicy>(),
                any<OneTimeWorkRequest>(),
            )
        } answers {
            enqueued += thirdArg<OneTimeWorkRequest>()
            successfulOperation()
        }
        every { cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG) } returns
            occurrenceCancellation
        every { cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG) } returns
            fallbackCancellation
        every { cancelUniqueWork(any<String>()) } returns successfulOperation()
    }

    private fun successfulOperation(): Operation = mockk(relaxed = true) {
        every { result } returns Futures.immediateFuture(Operation.SUCCESS)
    }

    private fun pendingOperation(
        resultFuture: SettableFuture<Operation.State.SUCCESS>,
    ): Operation = mockk(relaxed = true) {
        every { result } returns resultFuture
    }

    private companion object {
        const val PREFERENCES_NAME = "health_md_scheduled_export_state"
        const val API_FINGERPRINT = "test-api-destination-fingerprint"
    }
}
