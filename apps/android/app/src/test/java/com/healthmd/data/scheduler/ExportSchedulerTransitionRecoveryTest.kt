package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.Operation
import androidx.work.WorkManager
import com.google.common.truth.Truth.assertThat
import com.google.common.util.concurrent.Futures
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
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ExportSchedulerTransitionRecoveryTest {
    private lateinit var context: Context
    private lateinit var originalTimeZone: TimeZone

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        clearPreferences()
        originalTimeZone = TimeZone.getDefault()
        TimeZone.setDefault(TimeZone.getTimeZone("UTC"))
    }

    @After
    fun tearDown() {
        TimeZone.setDefault(originalTimeZone)
        clearPreferences()
    }

    @Test
    fun ordinaryReconcileRecoversDeathAtEveryTransitionCheckpointWithoutMintingAgain() = runTest {
        ScheduledExportTransitionCheckpoint.entries.forEachIndexed { index, checkpoint ->
            clearPreferences()
            val oldSettings = settings(ExportTarget.API_ENDPOINT)
            val replacementSettings = settings(ExportTarget.DEVICE_FOLDER)
            val store = ScheduledExportStateStore(context)
            store.markGenerationMigrationComplete()
            store.save(occurrence(oldSettings, "generation-old-$index"))
            val crashedRequests = mutableListOf<OneTimeWorkRequest>()
            val crashObserver = mockk<ScheduledExportTransitionObserver>()
            every { crashObserver.onCheckpoint(any()) } answers {
                if (firstArg<ScheduledExportTransitionCheckpoint>() == checkpoint) {
                    throw SimulatedProcessDeath(checkpoint)
                }
            }
            val crashingScheduler = scheduler(
                workManager = workManager(crashedRequests),
                currentSettings = { replacementSettings },
                generationFactory = generationFactory("generation-new-$index"),
                stateStore = store,
                transitionObserver = crashObserver,
            )

            val failure = runCatching { crashingScheduler.reconcile() }.exceptionOrNull()
            assertThat(failure).isInstanceOf(SimulatedProcessDeath::class.java)

            val afterCrash = ScheduledExportStateStore(context)
            assertThat(afterCrash.load()?.generation).isEqualTo("generation-new-$index")
            if (checkpoint == ScheduledExportTransitionCheckpoint.FINALIZATION) {
                assertThat(afterCrash.loadTransition()).isNull()
            } else {
                assertThat(afterCrash.loadTransition()).isNotNull()
            }

            val recoveryRequests = mutableListOf<OneTimeWorkRequest>()
            val unexpectedFactory = generationFactory("generation-unexpected-$index")
            val recoveredScheduler = scheduler(
                workManager = workManager(recoveryRequests),
                currentSettings = { replacementSettings },
                generationFactory = unexpectedFactory,
                stateStore = ScheduledExportStateStore(context),
            )

            recoveredScheduler.reconcile()

            val recovered = ScheduledExportStateStore(context)
            assertThat(recovered.load()?.generation).isEqualTo("generation-new-$index")
            assertThat(recovered.loadTransition()).isNull()
            assertThat(recoveryRequests).isNotEmpty()
            assertThat(recoveryRequests.last().workSpec.input.getString(
                ScheduledExportOccurrence.KEY_GENERATION,
            )).isEqualTo("generation-new-$index")
            verify(exactly = 0) { unexpectedFactory.create() }
        }
    }

    @Test
    fun legacyMigrationRecoversArmBeforeFinalizeWithoutBroadlyCancellingNewWork() = runTest {
        val currentSettings = settings(ExportTarget.DEVICE_FOLDER)
        val store = ScheduledExportStateStore(context)
        store.save(occurrence(currentSettings.copy(scheduleLookbackDays = 9), generation = null))
        val crashingScheduler = scheduler(
            workManager = workManager(),
            currentSettings = { currentSettings },
            generationFactory = generationFactory("generation-migrated"),
            stateStore = store,
            transitionObserver = throwingObserver(
                ScheduledExportTransitionCheckpoint.NEW_OCCURRENCE_ARM,
            ),
        )
        runCatching { crashingScheduler.reconcile() }

        val afterCrash = ScheduledExportStateStore(context)
        assertThat(afterCrash.isGenerationMigrationComplete()).isFalse()
        assertThat(afterCrash.loadTransition()?.phase)
            .isEqualTo(ScheduledExportTransitionPhase.OLD_WORK_CANCELLED)
        val recoveryWorkManager = workManager()
        val unexpectedFactory = generationFactory("generation-unexpected")
        val recoveredScheduler = scheduler(
            workManager = recoveryWorkManager,
            currentSettings = { currentSettings },
            generationFactory = unexpectedFactory,
            stateStore = afterCrash,
        )

        recoveredScheduler.reconcile()

        val recovered = ScheduledExportStateStore(context)
        assertThat(recovered.isGenerationMigrationComplete()).isTrue()
        assertThat(recovered.load()?.generation).isEqualTo("generation-migrated")
        assertThat(recovered.load()?.configuration?.lookbackDays).isEqualTo(1)
        assertThat(recovered.loadTransition()).isNull()
        verify(exactly = 0) {
            recoveryWorkManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
        verify(exactly = 0) {
            recoveryWorkManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }
        verify(exactly = 0) { unexpectedFactory.create() }
    }

    @Test
    fun survivingOldFallbackFinishesTransitionButCannotExportItsStaleGeneration() = runTest {
        val oldSettings = settings(ExportTarget.API_ENDPOINT)
        val replacementSettings = settings(ExportTarget.DEVICE_FOLDER)
        val old = occurrence(oldSettings, "generation-old")
        val store = ScheduledExportStateStore(context)
        store.markGenerationMigrationComplete()
        store.save(old)
        val crashObserver = throwingObserver(ScheduledExportTransitionCheckpoint.DURABLE_TRANSITION)
        val crashingScheduler = scheduler(
            workManager = workManager(),
            currentSettings = { replacementSettings },
            generationFactory = generationFactory("generation-new"),
            stateStore = store,
            transitionObserver = crashObserver,
        )
        runCatching { crashingScheduler.reconcile() }

        val recoveryRequests = mutableListOf<OneTimeWorkRequest>()
        val recoveryWorkManager = workManager(recoveryRequests)
        val recoveredScheduler = scheduler(
            workManager = recoveryWorkManager,
            currentSettings = { replacementSettings },
            generationFactory = generationFactory("generation-unexpected"),
            stateStore = ScheduledExportStateStore(context),
        )

        val accepted = recoveredScheduler.handleOccurrence(
            occurrence = old,
            expedited = true,
            isFallbackDelivery = true,
        )

        assertThat(accepted).isFalse()
        assertThat(ScheduledExportStateStore(context).load()?.generation)
            .isEqualTo("generation-new")
        assertThat(ScheduledExportStateStore(context).loadTransition()).isNull()
        assertThat(recoveryRequests.none { ExportScheduler.EXPORT_OCCURRENCE_TAG in it.tags }).isTrue()
        verify(exactly = 1) {
            recoveryWorkManager.cancelAllWorkByTag(
                ExportScheduler.EXPORT_GENERATION_TAG_PREFIX + "generation-old",
            )
        }
        verify(exactly = 0) {
            recoveryWorkManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
        verify(exactly = 0) {
            recoveryWorkManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }
    }

    @Test
    fun survivingNewFallbackFinalizesArmAndAdvancesWithoutReplacingItself() = runTest {
        val oldSettings = settings(ExportTarget.API_ENDPOINT)
        val replacementSettings = settings(ExportTarget.DEVICE_FOLDER)
        val store = ScheduledExportStateStore(context)
        store.markGenerationMigrationComplete()
        store.save(occurrence(oldSettings, "generation-old"))
        val crashingScheduler = scheduler(
            workManager = workManager(),
            currentSettings = { replacementSettings },
            generationFactory = generationFactory("generation-new"),
            stateStore = store,
            transitionObserver = throwingObserver(
                ScheduledExportTransitionCheckpoint.NEW_OCCURRENCE_ARM,
            ),
        )
        runCatching { crashingScheduler.reconcile() }
        val armedReplacement = requireNotNull(ScheduledExportStateStore(context).loadTransition())
            .replacement
        assertThat(ScheduledExportStateStore(context).loadTransition()?.phase)
            .isEqualTo(ScheduledExportTransitionPhase.OLD_WORK_CANCELLED)

        val recoveryRequests = mutableListOf<OneTimeWorkRequest>()
        val recoveredScheduler = scheduler(
            workManager = workManager(recoveryRequests),
            currentSettings = { replacementSettings },
            generationFactory = generationFactory("generation-unexpected"),
            stateStore = ScheduledExportStateStore(context),
        )

        val accepted = recoveredScheduler.handleOccurrence(
            occurrence = armedReplacement,
            expedited = true,
            isFallbackDelivery = true,
        )

        assertThat(accepted).isTrue()
        assertThat(recoveryRequests.count { ExportScheduler.EXPORT_OCCURRENCE_TAG in it.tags })
            .isEqualTo(1)
        // Recovery did not REPLACE the fallback currently executing; only the next occurrence arms.
        assertThat(recoveryRequests.count { ExportScheduler.FALLBACK_TRIGGER_TAG in it.tags })
            .isEqualTo(1)
        val active = requireNotNull(ScheduledExportStateStore(context).load())
        assertThat(active.generation).isEqualTo("generation-new")
        assertThat(active.triggerAtMillis).isGreaterThan(armedReplacement.triggerAtMillis)
        assertThat(ScheduledExportStateStore(context).loadTransition()).isNull()
    }

    private fun scheduler(
        workManager: WorkManager,
        currentSettings: () -> ExportSettings,
        generationFactory: ScheduledExportGeneration,
        stateStore: ScheduledExportStateStore,
        transitionObserver: ScheduledExportTransitionObserver = ScheduledExportTransitionObserver(),
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
            transitionObserver = transitionObserver,
            googleDriveSelectionStore = mockk(relaxed = true),
            googleDriveDestinationStore = mockk(relaxed = true),
        )
    }

    private fun occurrence(
        settings: ExportSettings,
        generation: String?,
    ): ScheduledExportOccurrence {
        val zone = ZoneId.of("UTC")
        val snapshot = AndroidExportSettingsSnapshot.capture(settings, pin = null, zone = zone)
        return ScheduledExportOccurrence(
            configuration = ScheduledExportConfiguration.from(
                settings = settings,
                destinationFingerprint = API_FINGERPRINT.takeIf {
                    settings.scheduledExportTarget == ExportTarget.API_ENDPOINT
                },
                zoneId = zone,
                enginePin = null,
                settingsSnapshot = snapshot,
            ),
            triggerAtMillis = 1_900_000_000_000L,
            intendedLocalDate = LocalDate.parse("2030-03-17"),
            generation = generation,
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

    private fun generationFactory(generation: String): ScheduledExportGeneration =
        mockk<ScheduledExportGeneration>().also { factory ->
            every { factory.create() } returns generation
        }

    private fun throwingObserver(
        checkpoint: ScheduledExportTransitionCheckpoint,
    ): ScheduledExportTransitionObserver = mockk<ScheduledExportTransitionObserver>().also { observer ->
        every { observer.onCheckpoint(any()) } answers {
            if (firstArg<ScheduledExportTransitionCheckpoint>() == checkpoint) {
                throw SimulatedProcessDeath(checkpoint)
            }
        }
    }

    private fun workManager(
        enqueued: MutableList<OneTimeWorkRequest> = mutableListOf(),
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
        every { cancelAllWorkByTag(any<String>()) } returns successfulOperation()
        every { cancelUniqueWork(any<String>()) } returns successfulOperation()
    }

    private fun successfulOperation(): Operation = mockk(relaxed = true) {
        every { result } returns Futures.immediateFuture(Operation.SUCCESS)
    }

    private fun clearPreferences() {
        context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
            .edit()
            .clear()
            .commit()
    }

    private class SimulatedProcessDeath(
        checkpoint: ScheduledExportTransitionCheckpoint,
    ) : RuntimeException(checkpoint.name)

    private companion object {
        const val PREFERENCES_NAME = "health_md_scheduled_export_state"
        const val API_FINGERPRINT = "test-api-destination-fingerprint"
    }
}
