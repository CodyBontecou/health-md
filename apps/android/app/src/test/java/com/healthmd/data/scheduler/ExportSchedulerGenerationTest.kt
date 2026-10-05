package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequest
import androidx.work.Operation
import androidx.work.WorkManager
import com.google.common.truth.Truth.assertThat
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.SettableFuture
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.drive.GoogleDriveDestination
import com.healthmd.data.drive.GoogleDriveDestinationStore
import com.healthmd.data.drive.GoogleDriveFolderCapabilities
import com.healthmd.data.drive.GoogleDriveSelectionStore
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.MarkdownTemplateConfig
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
    fun destinationReplacementPersistsNewStateBeforeAwaitingGenerationCancellation() = runTest {
        val apiSettings = settings(ExportTarget.API_ENDPOINT)
        val folderSettings = settings(ExportTarget.DEVICE_FOLDER)
        stateStore.markGenerationMigrationComplete()
        stateStore.save(occurrence(apiSettings, "generation-api-a"))

        val cancellation = SettableFuture.create<Operation.State.SUCCESS>()
        val enqueued = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(enqueued)
        every {
            workManager.cancelAllWorkByTag(
                ExportScheduler.GENERATION_TAG_PREFIX + "generation-api-a",
            )
        } returns pendingOperation(cancellation)
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { folderSettings },
            generations = listOf("generation-folder-b"),
        )

        val replacement = async { scheduler.reconcile() }
        runCurrent()

        assertThat(replacement.isCompleted).isFalse()
        assertThat(enqueued).isEmpty()
        assertThat(stateStore.load()?.generation).isEqualTo("generation-folder-b")
        assertThat(stateStore.loadTransition()?.phase)
            .isEqualTo(ScheduledExportTransitionPhase.PREPARED)
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(
                ExportScheduler.GENERATION_TAG_PREFIX + "generation-api-a",
            )
        }
        verify(exactly = 0) {
            workManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
        verify(exactly = 0) {
            workManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }

        cancellation.set(Operation.SUCCESS)
        replacement.await()

        assertThat(enqueued).hasSize(1)
        assertThat(stateStore.load()?.generation).isEqualTo("generation-folder-b")
        assertThat(stateStore.loadTransition()).isNull()
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
    fun dueLegacyOccurrenceUsesCurrentFrozenSettingsDuringMigration() = runTest {
        val legacySettings = settings(ExportTarget.DEVICE_FOLDER).copy(
            filenameFormat = "legacy-{date}",
        )
        val currentSettings = legacySettings.copy(filenameFormat = "current-{date}")
        val dueAtMillis = System.currentTimeMillis() - 60_000L
        val legacyOccurrence = occurrence(legacySettings, generation = null).copy(
            triggerAtMillis = dueAtMillis,
            intendedLocalDate = LocalDate.now(ZoneId.of("UTC")),
        )
        stateStore.save(legacyOccurrence)
        val requests = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(requests)
        val generationFactory = generationFactory(listOf("generation-migrated"))
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { currentSettings },
            generationFactory = generationFactory,
        )

        scheduler.reconcile()

        val exportRequests = requests.filter { request ->
            ExportScheduler.EXPORT_OCCURRENCE_TAG in request.tags
        }
        assertThat(exportRequests).hasSize(1)
        val admitted = requireNotNull(
            ScheduledExportOccurrence.fromWorkData(exportRequests.single().workSpec.input),
        )
        assertThat(admitted.generation).isEqualTo("generation-migrated")
        assertThat(admitted.triggerAtMillis).isEqualTo(dueAtMillis)
        assertThat(admitted.intendedLocalDate).isEqualTo(legacyOccurrence.intendedLocalDate)
        assertThat(admitted.settingsSnapshot?.filenameFormat).isEqualTo("current-{date}")

        val next = requireNotNull(stateStore.load())
        assertThat(stateStore.isGenerationMigrationComplete()).isTrue()
        assertThat(next.generation).isEqualTo("generation-migrated")
        assertThat(next.triggerAtMillis).isGreaterThan(dueAtMillis)
        assertThat(next.settingsSnapshot?.filenameFormat).isEqualTo("current-{date}")
        assertThat(stateStore.loadTransition()).isNull()
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }
        verify(exactly = 1) { generationFactory.create() }
    }

    @Test
    fun dueLegacyFallbackMigratesAndAdmitsWithoutCancellingItself() = runTest {
        val legacySettings = settings(ExportTarget.DEVICE_FOLDER).copy(
            filenameFormat = "legacy-{date}",
        )
        val currentSettings = legacySettings.copy(filenameFormat = "current-{date}")
        val dueAtMillis = System.currentTimeMillis() - 60_000L
        val legacyOccurrence = occurrence(legacySettings, generation = null).copy(
            triggerAtMillis = dueAtMillis,
            intendedLocalDate = LocalDate.now(ZoneId.of("UTC")),
        )
        stateStore.save(legacyOccurrence)
        val requests = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(requests)
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { currentSettings },
            generations = listOf("generation-migrated"),
        )

        val accepted = scheduler.handleOccurrence(
            occurrence = legacyOccurrence,
            expedited = true,
            isFallbackDelivery = true,
        )

        assertThat(accepted).isTrue()
        val exportRequests = requests.filter { request ->
            ExportScheduler.EXPORT_OCCURRENCE_TAG in request.tags
        }
        assertThat(exportRequests).hasSize(1)
        val admitted = requireNotNull(
            ScheduledExportOccurrence.fromWorkData(exportRequests.single().workSpec.input),
        )
        assertThat(admitted.generation).isEqualTo("generation-migrated")
        assertThat(admitted.triggerAtMillis).isEqualTo(dueAtMillis)
        assertThat(admitted.settingsSnapshot?.filenameFormat).isEqualTo("current-{date}")
        assertThat(stateStore.load()?.triggerAtMillis).isGreaterThan(dueAtMillis)
        verify(exactly = 0) {
            workManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }
        verify(exactly = 0) {
            workManager.cancelUniqueWork("scheduled_export_trigger_${legacyOccurrence.id}")
        }
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
        verify(exactly = 0) {
            workManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
        verify(exactly = 0) {
            workManager.cancelAllWorkByTag(ExportScheduler.FALLBACK_TRIGGER_TAG)
        }
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(
                ExportScheduler.GENERATION_TAG_PREFIX + "generation-api-a",
            )
        }
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(
                ExportScheduler.GENERATION_TAG_PREFIX + "generation-folder-b",
            )
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
        verify(exactly = 0) {
            workManager.cancelAllWorkByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG)
        }
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(
                ExportScheduler.GENERATION_TAG_PREFIX + "generation-output-a",
            )
        }
    }

    @Test
    fun dueOccurrenceUsesNewFrozenOutputSettingsDuringReconcile() = runTest {
        val oldSettings = settings(ExportTarget.DEVICE_FOLDER).copy(
            filenameFormat = "frozen-a-{date}",
        )
        val currentSettings = oldSettings.copy(filenameFormat = "material-b-{date}")
        val dueAtMillis = System.currentTimeMillis() - 60_000L
        val dueOccurrence = occurrence(oldSettings, "generation-output-a").copy(
            triggerAtMillis = dueAtMillis,
            intendedLocalDate = LocalDate.now(ZoneId.of("UTC")),
        )
        stateStore.markGenerationMigrationComplete()
        stateStore.save(dueOccurrence)
        val requests = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(requests)
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { currentSettings },
            generations = listOf("generation-output-b"),
        )

        scheduler.reconcile()

        val exportRequests = requests.filter { request ->
            ExportScheduler.EXPORT_OCCURRENCE_TAG in request.tags
        }
        assertThat(exportRequests).hasSize(1)
        val admitted = requireNotNull(
            ScheduledExportOccurrence.fromWorkData(exportRequests.single().workSpec.input),
        )
        assertThat(admitted.generation).isEqualTo("generation-output-b")
        assertThat(admitted.triggerAtMillis).isEqualTo(dueAtMillis)
        assertThat(admitted.intendedLocalDate).isEqualTo(dueOccurrence.intendedLocalDate)
        assertThat(admitted.settingsSnapshot?.filenameFormat).isEqualTo("material-b-{date}")

        val next = requireNotNull(stateStore.load())
        assertThat(next.generation).isEqualTo("generation-output-b")
        assertThat(next.triggerAtMillis).isGreaterThan(dueAtMillis)
        assertThat(next.settingsSnapshot?.filenameFormat).isEqualTo("material-b-{date}")
        assertThat(stateStore.loadTransition()).isNull()
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(
                ExportScheduler.GENERATION_TAG_PREFIX + "generation-output-a",
            )
        }
    }

    @Test
    fun dueOccurrenceUsesNewFrozenOutputSettingsBeforeContinuingReplacementGeneration() = runTest {
        val oldSettings = settings(ExportTarget.DEVICE_FOLDER).copy(
            filenameFormat = "frozen-a-{date}",
        )
        val currentSettings = oldSettings.copy(filenameFormat = "material-b-{date}")
        val dueAtMillis = System.currentTimeMillis() - 60_000L
        val dueOccurrence = occurrence(oldSettings, "generation-output-a").copy(
            triggerAtMillis = dueAtMillis,
            intendedLocalDate = LocalDate.now(ZoneId.of("UTC")),
        )
        stateStore.markGenerationMigrationComplete()
        stateStore.save(dueOccurrence)
        val requests = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(requests)
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { currentSettings },
            generations = listOf("generation-output-b"),
        )

        val accepted = scheduler.handleOccurrence(dueOccurrence, expedited = true)

        assertThat(accepted).isTrue()
        val exportRequests = requests.filter { request ->
            ExportScheduler.EXPORT_OCCURRENCE_TAG in request.tags
        }
        assertThat(exportRequests).hasSize(1)
        val admitted = requireNotNull(
            ScheduledExportOccurrence.fromWorkData(exportRequests.single().workSpec.input),
        )
        assertThat(admitted.generation).isEqualTo("generation-output-b")
        assertThat(admitted.triggerAtMillis).isEqualTo(dueAtMillis)
        assertThat(admitted.intendedLocalDate).isEqualTo(dueOccurrence.intendedLocalDate)
        assertThat(admitted.settingsSnapshot?.filenameFormat).isEqualTo("material-b-{date}")
        assertThat(exportRequests.single().tags).contains(
            ExportScheduler.EXPORT_GENERATION_TAG_PREFIX + "generation-output-b",
        )

        val next = requireNotNull(stateStore.load())
        assertThat(next.generation).isEqualTo("generation-output-b")
        assertThat(next.triggerAtMillis).isGreaterThan(dueAtMillis)
        assertThat(next.settingsSnapshot?.filenameFormat).isEqualTo("material-b-{date}")
        assertThat(stateStore.loadTransition()).isNull()
        verify(exactly = 1) {
            workManager.cancelAllWorkByTag(
                ExportScheduler.GENERATION_TAG_PREFIX + "generation-output-a",
            )
        }
    }

    @Test
    fun dueEndpointChangeFailsClosedAndOnlyArmsAFutureReplacement() = runTest {
        val oldSettings = settings(ExportTarget.API_ENDPOINT)
        val currentSettings = oldSettings.copy(apiEndpointUrl = "https://new.example.test/health")
        val dueAtMillis = System.currentTimeMillis() - 60_000L
        val dueOccurrence = occurrence(oldSettings, "generation-api-a").copy(
            triggerAtMillis = dueAtMillis,
            intendedLocalDate = LocalDate.now(ZoneId.of("UTC")),
        )
        stateStore.markGenerationMigrationComplete()
        stateStore.save(dueOccurrence)
        val requests = mutableListOf<OneTimeWorkRequest>()
        val scheduler = scheduler(
            workManager = workManager(requests),
            currentSettings = { currentSettings },
            generations = listOf("generation-api-b"),
            fingerprintForEndpoint = { endpoint ->
                if (endpoint == oldSettings.apiEndpointUrl) API_FINGERPRINT else NEW_API_FINGERPRINT
            },
        )

        val accepted = scheduler.handleOccurrence(dueOccurrence, expedited = true)

        assertThat(accepted).isFalse()
        assertThat(requests.none { ExportScheduler.EXPORT_OCCURRENCE_TAG in it.tags }).isTrue()
        val replacement = requireNotNull(stateStore.load())
        assertThat(replacement.generation).isEqualTo("generation-api-b")
        assertThat(replacement.configuration.destinationFingerprint)
            .isEqualTo(NEW_API_FINGERPRINT)
        assertThat(replacement.triggerAtMillis).isGreaterThan(dueAtMillis)
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun settingsAreCapturedAfterWaitingForRunningWorkerCoordinator() = runTest {
        val oldSettings = settings(ExportTarget.DEVICE_FOLDER).copy(
            filenameFormat = "frozen-a-{date}",
        )
        var currentSettings = oldSettings.copy(filenameFormat = "material-b-{date}")
        val due = occurrence(oldSettings, "generation-output-a").copy(
            triggerAtMillis = System.currentTimeMillis() - 60_000L,
            intendedLocalDate = LocalDate.now(ZoneId.of("UTC")),
        )
        stateStore.markGenerationMigrationComplete()
        stateStore.save(due)
        val requests = mutableListOf<OneTimeWorkRequest>()
        val coordinator = ScheduledExportRunCoordinator()
        val scheduler = scheduler(
            workManager = workManager(requests),
            currentSettings = { currentSettings },
            generations = listOf("generation-output-c"),
            runCoordinator = coordinator,
        )
        coordinator.mutex.lock()

        val handling = async { scheduler.handleOccurrence(due, expedited = true) }
        runCurrent()
        currentSettings = oldSettings.copy(filenameFormat = "material-c-{date}")
        coordinator.mutex.unlock()

        assertThat(handling.await()).isTrue()
        val export = requests.single { ExportScheduler.EXPORT_OCCURRENCE_TAG in it.tags }
        val admitted = requireNotNull(ScheduledExportOccurrence.fromWorkData(export.workSpec.input))
        assertThat(admitted.settingsSnapshot?.filenameFormat).isEqualTo("material-c-{date}")
        assertThat(admitted.generation).isEqualTo("generation-output-c")
    }

    @Test
    fun oversizedWorkDataIsRejectedBeforeReplacingTheActiveGeneration() = runTest {
        val oldSettings = settings(ExportTarget.DEVICE_FOLDER)
        val oversizedSettings = oldSettings.copy(
            formatCustomization = oldSettings.formatCustomization.copy(
                markdownTemplate = MarkdownTemplateConfig(customTemplate = "x".repeat(12_000)),
            ),
        )
        val active = occurrence(oldSettings, "generation-small")
        stateStore.markGenerationMigrationComplete()
        stateStore.save(active)
        val requests = mutableListOf<OneTimeWorkRequest>()
        val workManager = workManager(requests)
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { oversizedSettings },
            generations = listOf("generation-oversized"),
        )

        val error = runCatching { scheduler.reconcile() }.exceptionOrNull()

        assertThat(error).isInstanceOf(ScheduledExportWorkDataTooLargeException::class.java)
        assertThat(stateStore.load()).isEqualTo(active)
        assertThat(stateStore.loadTransition()).isNull()
        assertThat(stateStore.loadAdmission()).isNull()
        assertThat(requests).isEmpty()
        verify(exactly = 0) {
            workManager.cancelAllWorkByTag(
                ExportScheduler.GENERATION_TAG_PREFIX + "generation-small",
            )
        }
    }

    @Test
    fun googleDriveOccurrenceRequiresConnectedNetwork() = runTest {
        val currentSettings = settings(ExportTarget.GOOGLE_DRIVE)
        val due = occurrence(currentSettings, "generation-drive").copy(
            triggerAtMillis = System.currentTimeMillis() - 60_000L,
            intendedLocalDate = LocalDate.now(ZoneId.of("UTC")),
        )
        stateStore.markGenerationMigrationComplete()
        stateStore.save(due)
        val requests = mutableListOf<OneTimeWorkRequest>()
        val scheduler = scheduler(
            workManager = workManager(requests),
            currentSettings = { currentSettings },
        )

        assertThat(scheduler.handleOccurrence(due, expedited = true)).isTrue()

        val export = requests.single { ExportScheduler.EXPORT_OCCURRENCE_TAG in it.tags }
        assertThat(export.workSpec.constraints.requiredNetworkType).isEqualTo(NetworkType.CONNECTED)
    }

    @Test
    fun interruptedArmRecoversTheSameAdmissionWithoutReadmittingCompletedOccurrence() = runTest {
        val currentSettings = settings(ExportTarget.DEVICE_FOLDER)
        val due = occurrence(currentSettings, "generation-active").copy(
            triggerAtMillis = System.currentTimeMillis() - 60_000L,
            intendedLocalDate = LocalDate.now(ZoneId.of("UTC")),
        )
        stateStore.markGenerationMigrationComplete()
        stateStore.save(due)
        val requests = mutableListOf<OneTimeWorkRequest>()
        var failFallbackArm = true
        val workManager = workManager()
        every {
            workManager.enqueueUniqueWork(
                any<String>(),
                any<ExistingWorkPolicy>(),
                any<OneTimeWorkRequest>(),
            )
        } answers {
            val request = thirdArg<OneTimeWorkRequest>()
            requests += request
            if (failFallbackArm && ExportScheduler.FALLBACK_TRIGGER_TAG in request.tags) {
                failedOperation(IllegalStateException("simulated arm failure"))
            } else {
                successfulOperation()
            }
        }
        val scheduler = scheduler(
            workManager = workManager,
            currentSettings = { currentSettings },
        )

        assertThat(runCatching { scheduler.handleOccurrence(due, expedited = true) }.isFailure)
            .isTrue()
        val admission = requireNotNull(stateStore.loadAdmission())
        val next = requireNotNull(stateStore.load())
        assertThat(admission.occurrence).isEqualTo(due)
        assertThat(next.triggerAtMillis).isGreaterThan(due.triggerAtMillis)
        assertThat(stateStore.pendingArmOccurrence()).isEqualTo(next)

        failFallbackArm = false
        assertThat(
            scheduler.handleOccurrence(
                occurrence = due,
                expedited = true,
                isFallbackDelivery = true,
            ),
        ).isFalse()

        val exportRequests = requests.filter { ExportScheduler.EXPORT_OCCURRENCE_TAG in it.tags }
        assertThat(exportRequests).hasSize(2)
        assertThat(exportRequests.map { it.id }.distinct()).containsExactly(admission.workRequestId)
        assertThat(stateStore.pendingArmOccurrence()).isNull()
        assertThat(
            stateStore.completeAdmission(
                due,
                admission.operationId,
                admission.workRequestId,
            ),
        ).isTrue()

        assertThat(scheduler.handleOccurrence(due, expedited = true)).isFalse()
        assertThat(requests.count { ExportScheduler.EXPORT_OCCURRENCE_TAG in it.tags }).isEqualTo(2)
    }

    @Test
    fun busyExactDeliveryDoesNotRearmThePastOccurrence() = runTest {
        val currentSettings = settings(ExportTarget.DEVICE_FOLDER)
        val admittedOccurrence = occurrence(currentSettings, "generation-active").copy(
            triggerAtMillis = System.currentTimeMillis() - 120_000L,
            intendedLocalDate = LocalDate.now(ZoneId.of("UTC")),
        )
        val nextDue = admittedOccurrence.copy(
            triggerAtMillis = System.currentTimeMillis() - 60_000L,
        )
        val admission = ScheduledExportAdmission.create(
            occurrence = admittedOccurrence,
            catchUpThroughMillis = admittedOccurrence.triggerAtMillis,
            expedited = true,
        )
        stateStore.markGenerationMigrationComplete()
        stateStore.save(admittedOccurrence)
        assertThat(stateStore.prepareAdmission(admission, nextDue)).isTrue()
        assertThat(stateStore.completePendingArm(nextDue.id)).isTrue()
        val requests = mutableListOf<OneTimeWorkRequest>()
        val scheduler = scheduler(
            workManager = workManager(requests),
            currentSettings = { currentSettings },
        )

        val result = scheduler.handleOccurrenceDelivery(nextDue, expedited = true)

        assertThat(result).isEqualTo(ScheduledExportDeliveryResult.BUSY)
        assertThat(requests.count { ExportScheduler.EXPORT_OCCURRENCE_TAG in it.tags })
            .isEqualTo(1)
        assertThat(requests.none { ExportScheduler.FALLBACK_TRIGGER_TAG in it.tags }).isTrue()
        assertThat(stateStore.load()).isEqualTo(nextDue)
        assertThat(stateStore.loadAdmission()).isEqualTo(admission)
    }

    private fun scheduler(
        workManager: WorkManager,
        currentSettings: () -> ExportSettings,
        generations: List<String> = emptyList(),
        generationFactory: ScheduledExportGeneration = generationFactory(generations),
        stateStore: ScheduledExportStateStore = this.stateStore,
        fingerprintForEndpoint: (String) -> String? = { API_FINGERPRINT },
        runCoordinator: ScheduledExportRunCoordinator = ScheduledExportRunCoordinator(),
    ): ExportScheduler {
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        coEvery { settingsRepository.getExportSettings() } answers { currentSettings() }
        val credentialStore = mockk<APIExportCredentialStore>(relaxed = true)
        coEvery { credentialStore.destinationFingerprint(any()) } answers {
            fingerprintForEndpoint(firstArg())
        }
        val enginePinPlanner = mockk<ExportEnginePinPlanner>()
        every { enginePinPlanner.forScheduledExport(any(), any(), any()) } returns null
        every {
            enginePinPlanner.persistedPinAppliesToScheduledExport(any(), any(), any())
        } returns true
        val driveSelectionStore = mockk<GoogleDriveSelectionStore>(relaxed = true)
        val driveDestinationStore = mockk<GoogleDriveDestinationStore>(relaxed = true)
        val driveDestination = GoogleDriveDestination(
            id = "drive-destination",
            accountReferenceId = "drive-account",
            permissionId = "drive-permission",
            folderId = "drive-folder",
            accountLabel = "Google account",
            folderLabel = "Exports",
            capabilities = GoogleDriveFolderCapabilities(canAddChildren = true),
            lastValidatedAtEpochMillis = 1,
        )
        coEvery { driveSelectionStore.get() } returns driveDestination.id
        coEvery { driveDestinationStore.find(driveDestination.id) } returns driveDestination
        return ExportScheduler(
            context = context,
            workManager = workManager,
            settingsRepository = settingsRepository,
            apiCredentialStore = credentialStore,
            stateStore = stateStore,
            timeCalculator = ScheduledExportTimeCalculator(),
            enginePinPlanner = enginePinPlanner,
            generationFactory = generationFactory,
            runCoordinator = runCoordinator,
            transitionObserver = ScheduledExportTransitionObserver(),
            googleDriveSelectionStore = driveSelectionStore,
            googleDriveDestinationStore = driveDestinationStore,
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
            destinationFingerprint = when (settings.scheduledExportTarget) {
                ExportTarget.DEVICE_FOLDER -> null
                ExportTarget.API_ENDPOINT -> API_FINGERPRINT
                ExportTarget.GOOGLE_DRIVE -> driveDestination().fingerprint
            },
            zoneId = zone,
            enginePin = null,
            settingsSnapshot = snapshot,
        )
    }

    private fun driveDestination() = GoogleDriveDestination(
        id = "drive-destination",
        accountReferenceId = "drive-account",
        permissionId = "drive-permission",
        folderId = "drive-folder",
        accountLabel = "Google account",
        folderLabel = "Exports",
        capabilities = GoogleDriveFolderCapabilities(canAddChildren = true),
        lastValidatedAtEpochMillis = 1,
    )

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

    private fun pendingOperation(
        resultFuture: SettableFuture<Operation.State.SUCCESS>,
    ): Operation = mockk(relaxed = true) {
        every { result } returns resultFuture
    }

    private fun failedOperation(error: Throwable): Operation = mockk(relaxed = true) {
        every { result } returns Futures.immediateFailedFuture(error)
    }

    private companion object {
        const val PREFERENCES_NAME = "health_md_scheduled_export_state"
        const val API_FINGERPRINT = "test-api-destination-fingerprint"
        const val NEW_API_FINGERPRINT = "new-test-api-destination-fingerprint"
    }
}
