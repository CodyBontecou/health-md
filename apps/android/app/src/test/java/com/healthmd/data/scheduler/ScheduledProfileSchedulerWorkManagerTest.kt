package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.Operation
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.google.common.truth.Truth.assertThat
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.SettableFuture
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import java.util.UUID
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** WorkManager cleanup boundaries that pure occurrence/naming tests cannot exercise. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ScheduledProfileSchedulerWorkManagerTest {

    @Test
    fun `explicit profile cancellation works after its entry row disappeared`() = runTest {
        val workManager = workManager()
        val scheduler = scheduler(
            workManager = workManager,
            entries = emptyList(),
            profiles = emptyList(),
        )

        scheduler.cancelProfileRuntime("deleted-profile")

        verify(exactly = 1) {
            workManager.cancelUniqueWork(
                ScheduledProfileScheduler.exportWorkName("deleted-profile"),
            )
        }
        verify(exactly = 1) {
            workManager.cancelUniqueWork(
                ScheduledProfileScheduler.fallbackName("deleted-profile"),
            )
        }
    }

    @Test
    fun `remove entry cancels runtime before deleting the persisted row`() = runTest {
        val workManager = workManager()
        val entryStore = mockk<ScheduledProfileEntryStore>()
        coEvery { entryStore.delete("removed-profile") } returns Unit
        val scheduler = scheduler(
            workManager = workManager,
            entries = emptyList(),
            profiles = emptyList(),
            entryStoreOverride = entryStore,
        )

        scheduler.removeEntry("removed-profile")

        verify {
            workManager.cancelUniqueWork(
                ScheduledProfileScheduler.exportWorkName("removed-profile"),
            )
            workManager.cancelUniqueWork(
                ScheduledProfileScheduler.fallbackName("removed-profile"),
            )
        }
        coVerify(exactly = 1) { entryStore.delete("removed-profile") }
    }

    @Test
    fun `reconcile cancels both unique work chains for a disabled entry`() = runTest {
        val workManager = workManager()
        val disabled = ScheduledProfileEntry(
            profileId = "disabled-profile",
            isEnabled = false,
            anchorEpochDay = 20_000,
            zoneId = "UTC",
        )
        val scheduler = scheduler(
            workManager = workManager,
            entries = listOf(disabled),
            profiles = listOf(profile("disabled-profile")),
        )

        scheduler.reconcile()

        verify(exactly = 1) {
            workManager.cancelUniqueWork(
                ScheduledProfileScheduler.exportWorkName("disabled-profile"),
            )
        }
        verify(exactly = 1) {
            workManager.cancelUniqueWork(
                ScheduledProfileScheduler.fallbackName("disabled-profile"),
            )
        }
        verify(exactly = 0) {
            workManager.enqueueUniqueWork(
                any<String>(),
                any<ExistingWorkPolicy>(),
                any<OneTimeWorkRequest>(),
            )
        }
    }

    @Test
    fun `failed migration write keeps the legacy schedule enabled`() = runTest {
        val workManager = workManager()
        val entryStore = mockk<ScheduledProfileEntryStore> {
            coEvery { pendingLegacyMigrationProfileId() } returns null
            coEvery { getEntries() } returns emptyList()
            coEvery { beginLegacyMigration(any()) } returns false
        }
        val defaultProfile = profile("default")
        val profileRepository = mockk<ExportProfileRepository> {
            coEvery { getProfiles() } returns listOf(defaultProfile)
            coEvery { getActiveProfile() } returns defaultProfile
        }
        val legacy = ExportSettings(scheduleEnabled = true, scheduleHour = 9)
        val settingsRepository = mockk<SettingsRepository> {
            coEvery { getExportSettings() } returns legacy
            coEvery { updateExportSettings(any()) } returns Unit
        }
        val legacyScheduler = mockk<ExportScheduler>(relaxed = true)
        val scheduler = ScheduledProfileScheduler(
            context = ApplicationProvider.getApplicationContext<Context>(),
            workManager = workManager,
            entryStore = entryStore,
            profileRepository = profileRepository,
            legacySettings = settingsRepository,
            legacyScheduler = legacyScheduler,
        )

        scheduler.reconcile()

        coVerify(exactly = 1) {
            entryStore.beginLegacyMigration(match { it.profileId == "default" })
        }
        coVerify(exactly = 0) { settingsRepository.updateExportSettings(any()) }
        coVerify(exactly = 0) { legacyScheduler.cancel() }
    }

    @Test
    fun `pending migration marker clears only after runtime arming`() = runTest {
        val events = mutableListOf<String>()
        val workManager = workManager().also { manager ->
            every {
                manager.enqueueUniqueWork(
                    any<String>(),
                    any<ExistingWorkPolicy>(),
                    any<OneTimeWorkRequest>(),
                )
            } answers {
                events += "arm"
                successfulOperation()
            }
        }
        val migrated = ScheduledProfileEntry(
            profileId = "default",
            isEnabled = true,
            anchorEpochDay = 20_000,
            zoneId = "UTC",
        )
        val entryStore = mockk<ScheduledProfileEntryStore> {
            coEvery { pendingLegacyMigrationProfileId() } returns "default"
            coEvery { entry("default") } returns migrated
            coEvery { finishLegacyMigration("default") } answers {
                events += "finish"
                true
            }
            coEvery { getEntries() } returns listOf(migrated)
        }
        val defaultProfile = profile("default")
        val profileRepository = mockk<ExportProfileRepository> {
            coEvery { getProfiles() } returns listOf(defaultProfile)
            coEvery { getActiveProfile() } returns defaultProfile
        }
        var legacy = ExportSettings(scheduleEnabled = true)
        val settingsRepository = mockk<SettingsRepository> {
            coEvery { getExportSettings() } answers { legacy }
            coEvery { updateExportSettings(any()) } answers { legacy = firstArg() }
        }
        val legacyScheduler = mockk<ExportScheduler> {
            coEvery { cancel() } returns Unit
        }
        val scheduler = ScheduledProfileScheduler(
            context = ApplicationProvider.getApplicationContext<Context>(),
            workManager = workManager,
            entryStore = entryStore,
            profileRepository = profileRepository,
            legacySettings = settingsRepository,
            legacyScheduler = legacyScheduler,
        )

        scheduler.reconcile()

        assertThat(legacy.scheduleEnabled).isFalse()
        assertThat(events).containsExactly("arm", "finish").inOrder()
        coVerify(exactly = 1) { legacyScheduler.cancel() }
        coVerify(exactly = 1) { entryStore.finishLegacyMigration("default") }
    }

    @Test
    fun `reconcile entry cancellation is serialized and complete when entry is missing`() = runTest {
        val workManager = workManager()
        val entryStore = mockk<ScheduledProfileEntryStore>()
        coEvery { entryStore.entry("missing") } returns null
        val scheduler = scheduler(
            workManager = workManager,
            entries = emptyList(),
            profiles = emptyList(),
            entryStoreOverride = entryStore,
        )

        scheduler.reconcileEntry("missing")

        coVerify(exactly = 1) { entryStore.entry("missing") }
        verify {
            workManager.cancelUniqueWork(ScheduledProfileScheduler.exportWorkName("missing"))
            workManager.cancelUniqueWork(ScheduledProfileScheduler.fallbackName("missing"))
        }
    }

    @Test
    fun `discard fences checkpoints before cancellation and rearms without immediately exporting`() = runTest {
        val events = mutableListOf<String>()
        val requests = mutableListOf<OneTimeWorkRequest>()
        val manager = workManager()
        val oldExportId = UUID.randomUUID()
        val finishedExportId = UUID.randomUUID()
        every { manager.getWorkInfosForUniqueWorkFlow(ScheduledProfileScheduler.exportWorkName("alpha")) } returns flowOf(
            listOf(
                mockk<WorkInfo> { every { id } returns oldExportId; every { state } returns WorkInfo.State.ENQUEUED },
                mockk<WorkInfo> { every { id } returns finishedExportId; every { state } returns WorkInfo.State.SUCCEEDED },
            ),
        )
        every { manager.cancelUniqueWork(any()) } answers {
            events += "cancel:${firstArg<String>()}"
            successfulOperation()
        }
        every { manager.enqueueUniqueWork(any<String>(), any<ExistingWorkPolicy>(), any<OneTimeWorkRequest>()) } answers {
            events += "enqueue:${firstArg<String>()}"
            requests += thirdArg<OneTimeWorkRequest>()
            successfulOperation()
        }
        var current = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
        )
        val entryStore = mockk<ScheduledProfileEntryStore>()
        coEvery { entryStore.discardPendingRecovery("alpha") } answers {
            events += "discard"
            current = current.copy(pendingExports = emptyList(), recoveryGeneration = current.recoveryGeneration + 1)
            true
        }
        coEvery { entryStore.entry("alpha") } answers { current }
        val scheduler = scheduler(manager, listOf(current), listOf(profile("alpha")), entryStore)

        assertThat(scheduler.discardPendingRecovery("alpha")).isTrue()

        assertThat(events).containsExactly(
            "enqueue:profile-schedule-reconcile-alpha", "discard", "cancel:profile-export-alpha", "cancel:scheduled_profile_trigger_work_alpha",
            "enqueue:scheduled_profile_trigger_work_alpha",
        ).inOrder()
        assertThat(requests).hasSize(2)
        val repair = requests.first().workSpec
        assertThat(repair.workerClassName).isEqualTo(ScheduledProfileReconcileWorker::class.java.name)
        assertThat(repair.input.getLong(ScheduledProfileReconcileWorker.INPUT_RECOVERY_GENERATION, -1L)).isEqualTo(1L)
        assertThat(repair.input.getStringArray(ScheduledProfileReconcileWorker.INPUT_OLD_EXPORT_WORK_IDS)?.toList())
            .containsExactly(oldExportId.toString())
        assertThat(requests.last().workSpec.input.getLong(ScheduledProfileTriggerWorker.INPUT_RECOVERY_GENERATION, -1L))
            .isEqualTo(1L)
        verify(exactly = 0) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha"), any<ExistingWorkPolicy>(), any<OneTimeWorkRequest>())
        }

        scheduler.handleAlarm("alpha", current.recoveryGeneration)

        assertThat(requests.last().workSpec.input.getLong(ScheduledProfileExportWorker.INPUT_RECOVERY_GENERATION, -1L))
            .isEqualTo(1L)
        assertThat(requests.last().workSpec.input.getString(ScheduledProfileExportWorker.INPUT_PROFILE_ID))
            .isEqualTo("alpha")
    }

    @Test
    fun `delivered alarm or fallback from a discarded generation cannot admit fresh work`() = runTest {
        val manager = workManager()
        val cleared = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
            recoveryGeneration = 1L,
        )
        val scheduler = scheduler(manager, listOf(cleared), listOf(profile("alpha")))

        scheduler.handleAlarm("alpha", recoveryGeneration = 0L)

        verify(exactly = 0) { manager.enqueueUniqueWork(any<String>(), any<ExistingWorkPolicy>(), any<OneTimeWorkRequest>()) }
        scheduler.handleAlarm("alpha", recoveryGeneration = 1L)
        verify(exactly = 1) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha"), ExistingWorkPolicy.KEEP, any<OneTimeWorkRequest>())
        }
    }

    @Test
    fun `failed discard neither acknowledges success nor cancels runtime`() = runTest {
        val manager = workManager()
        val entryStore = mockk<ScheduledProfileEntryStore>()
        coEvery { entryStore.entry("alpha") } returns ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
        )
        coEvery { entryStore.discardPendingRecovery("alpha") } returns false
        val scheduler = scheduler(manager, emptyList(), emptyList(), entryStore)

        assertThat(scheduler.discardPendingRecovery("alpha")).isFalse()

        verify(exactly = 0) { manager.cancelUniqueWork(any()) }
        verify(exactly = 1) {
            manager.enqueueUniqueWork("profile-schedule-reconcile-alpha", any(), any<OneTimeWorkRequest>())
        }
        verify(exactly = 0) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.fallbackName("alpha"), any(), any<OneTimeWorkRequest>())
        }
        verify(exactly = 0) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha"), any(), any<OneTimeWorkRequest>())
        }
    }

    @Test
    fun `discard keeps a disabled profile disabled without arming work`() = runTest {
        val manager = workManager()
        val entryStore = mockk<ScheduledProfileEntryStore>()
        var current = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = false, anchorEpochDay = 20_000, zoneId = "UTC",
        )
        coEvery { entryStore.discardPendingRecovery("alpha") } answers {
            current = current.copy(pendingExports = emptyList(), recoveryGeneration = current.recoveryGeneration + 1)
            true
        }
        coEvery { entryStore.entry("alpha") } answers { current }
        val scheduler = scheduler(manager, emptyList(), emptyList(), entryStore)

        assertThat(scheduler.discardPendingRecovery("alpha")).isTrue()

        verify(exactly = 1) { manager.cancelUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha")) }
        verify(exactly = 1) { manager.cancelUniqueWork(ScheduledProfileScheduler.fallbackName("alpha")) }
        assertThat(current.isEnabled).isFalse()
        verify(exactly = 1) {
            manager.enqueueUniqueWork("profile-schedule-reconcile-alpha", any(), any<OneTimeWorkRequest>())
        }
        verify(exactly = 0) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.fallbackName("alpha"), any(), any<OneTimeWorkRequest>())
        }
        verify(exactly = 0) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha"), any(), any<OneTimeWorkRequest>())
        }
    }

    @Test
    fun `discard repair cancels only export UUIDs pinned before the discard`() = runTest {
        val manager = workManager()
        val oldExportId = UUID.randomUUID()
        val freshExports = mutableListOf<OneTimeWorkRequest>()
        every {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha"), any(), any<OneTimeWorkRequest>())
        } answers {
            freshExports += thirdArg<OneTimeWorkRequest>()
            successfulOperation()
        }
        val current = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
            recoveryGeneration = 1L,
        )
        val scheduler = scheduler(manager, listOf(current), listOf(profile("alpha")))

        scheduler.handleAlarm("alpha", recoveryGeneration = 1L)
        val newExportId = freshExports.single().id
        scheduler.finishRecoveryDiscard("alpha", 1L, listOf(oldExportId))

        verify(exactly = 1) { manager.cancelWorkById(oldExportId) }
        verify(exactly = 0) { manager.cancelWorkById(newExportId) }
        // The unique chain may now contain a fresh occurrence; cancel it only by the old UUID.
        verify(exactly = 0) { manager.cancelUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha")) }
        verify(exactly = 1) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.fallbackName("alpha"), ExistingWorkPolicy.REPLACE, any<OneTimeWorkRequest>())
        }
        verify(exactly = 1) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha"), ExistingWorkPolicy.KEEP, any<OneTimeWorkRequest>())
        }
    }

    @Test
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    fun `delayed repair preserves a running current generation trigger waiting for the scheduler lock`() = runTest {
        val manager = workManager()
        val oldExportId = UUID.randomUUID()
        val cancellation = SettableFuture.create<Operation.State.SUCCESS>()
        every { manager.cancelWorkById(oldExportId) } returns mockk<Operation>(relaxed = true) {
            every { result } returns cancellation
        }
        every { manager.getWorkInfosForUniqueWorkFlow(ScheduledProfileScheduler.fallbackName("alpha")) } returns flowOf(
            listOf(mockk<WorkInfo> {
                every { state } returns WorkInfo.State.RUNNING
                every { tags } returns setOf("scheduled_profile_trigger_generation_alpha_1")
            }),
        )
        val exports = mutableListOf<OneTimeWorkRequest>()
        every {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha"), any(), any<OneTimeWorkRequest>())
        } answers {
            exports += thirdArg<OneTimeWorkRequest>()
            successfulOperation()
        }
        val current = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
            recoveryGeneration = 1L,
        )
        val scheduler = scheduler(manager, listOf(current), listOf(profile("alpha")))

        val repair = launch { scheduler.finishRecoveryDiscard("alpha", 1L, listOf(oldExportId)) }
        runCurrent()
        val trigger = launch { scheduler.handleAlarm("alpha", recoveryGeneration = 1L) }
        runCurrent()
        assertThat(repair.isActive).isTrue()
        assertThat(trigger.isActive).isTrue()
        assertThat(exports).isEmpty()

        cancellation.set(Operation.SUCCESS)
        repair.join()
        trigger.join()

        verify(exactly = 1) { manager.cancelWorkById(oldExportId) }
        verify(exactly = 0) { manager.cancelUniqueWork(any()) }
        verify(exactly = 0) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.fallbackName("alpha"), any(), any<OneTimeWorkRequest>())
        }
        assertThat(exports).hasSize(1)
        assertThat(exports.single().workSpec.input.getLong(ScheduledProfileExportWorker.INPUT_RECOVERY_GENERATION, -1L))
            .isEqualTo(1L)
    }

    @Test
    fun `delayed repair preserves an enqueued current generation fallback`() = runTest {
        val manager = workManager()
        val oldExportId = UUID.randomUUID()
        every { manager.getWorkInfosForUniqueWorkFlow(ScheduledProfileScheduler.fallbackName("alpha")) } returns flowOf(
            listOf(mockk<WorkInfo> {
                every { state } returns WorkInfo.State.ENQUEUED
                every { tags } returns setOf("scheduled_profile_trigger_generation_alpha_1")
            }),
        )
        val current = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
            recoveryGeneration = 1L,
        )
        val scheduler = scheduler(manager, listOf(current), listOf(profile("alpha")))

        scheduler.finishRecoveryDiscard("alpha", 1L, listOf(oldExportId))

        verify(exactly = 1) { manager.cancelWorkById(oldExportId) }
        verify(exactly = 0) { manager.cancelUniqueWork(any()) }
        verify(exactly = 0) { manager.enqueueUniqueWork(any<String>(), any(), any<OneTimeWorkRequest>()) }
    }

    @Test
    fun `discard repair replaces a fallback belonging to the discarded generation`() = runTest {
        val manager = workManager()
        every { manager.getWorkInfosForUniqueWorkFlow(ScheduledProfileScheduler.fallbackName("alpha")) } returns flowOf(
            listOf(mockk<WorkInfo> {
                every { state } returns WorkInfo.State.ENQUEUED
                every { tags } returns setOf("scheduled_profile_trigger_generation_alpha_0")
            }),
        )
        val replacements = mutableListOf<OneTimeWorkRequest>()
        every {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.fallbackName("alpha"), ExistingWorkPolicy.REPLACE, any<OneTimeWorkRequest>())
        } answers {
            replacements += thirdArg<OneTimeWorkRequest>()
            successfulOperation()
        }
        val current = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
            recoveryGeneration = 1L,
        )
        val scheduler = scheduler(manager, listOf(current), listOf(profile("alpha")))

        scheduler.finishRecoveryDiscard("alpha", 1L, emptyList())

        assertThat(replacements).hasSize(1)
        assertThat(replacements.single().workSpec.input.getLong(ScheduledProfileTriggerWorker.INPUT_RECOVERY_GENERATION, -1L))
            .isEqualTo(1L)
        assertThat(replacements.single().tags).contains("scheduled_profile_trigger_generation_alpha_1")
        verify(exactly = 0) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha"), any(), any<OneTimeWorkRequest>())
        }
    }

    @Test
    fun `discard repair from an older generation leaves the current occurrence untouched`() = runTest {
        val manager = workManager()
        val current = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
            recoveryGeneration = 2L,
        )
        val scheduler = scheduler(manager, listOf(current), listOf(profile("alpha")))

        scheduler.finishRecoveryDiscard("alpha", 1L, listOf(UUID.randomUUID()))

        verify(exactly = 0) { manager.cancelWorkById(any()) }
        verify(exactly = 0) { manager.cancelUniqueWork(any()) }
        verify(exactly = 0) { manager.enqueueUniqueWork(any<String>(), any(), any<OneTimeWorkRequest>()) }
    }

    @Test
    @OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
    fun `discard repair stops when its generation changes during old export cancellation`() = runTest {
        val manager = workManager()
        val oldExportId = UUID.randomUUID()
        val cancellation = SettableFuture.create<Operation.State.SUCCESS>()
        every { manager.cancelWorkById(oldExportId) } returns mockk<Operation>(relaxed = true) {
            every { result } returns cancellation
        }
        val original = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
            recoveryGeneration = 1L,
        )
        val store = mockk<ScheduledProfileEntryStore> {
            coEvery { entry("alpha") } returnsMany listOf(original, original.copy(recoveryGeneration = 2L))
        }
        val scheduler = scheduler(manager, listOf(original), listOf(profile("alpha")), store)

        val repair = launch { scheduler.finishRecoveryDiscard("alpha", 1L, listOf(oldExportId)) }
        runCurrent()
        assertThat(repair.isActive).isTrue()
        coVerify(exactly = 1) { store.entry("alpha") }

        cancellation.set(Operation.SUCCESS)
        repair.join()

        coVerify(exactly = 2) { store.entry("alpha") }
        verify(exactly = 1) { manager.cancelWorkById(oldExportId) }
        verify(exactly = 0) { manager.cancelUniqueWork(any()) }
        verify(exactly = 0) { manager.enqueueUniqueWork(any<String>(), any(), any<OneTimeWorkRequest>()) }
    }

    @Test
    fun `discard repair preserves a disabled entry without arming a replacement`() = runTest {
        val manager = workManager()
        val oldExportId = UUID.randomUUID()
        val current = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = false, anchorEpochDay = 20_000, zoneId = "UTC",
            recoveryGeneration = 1L,
        )
        val scheduler = scheduler(manager, listOf(current), listOf(profile("alpha")))

        scheduler.finishRecoveryDiscard("alpha", 1L, listOf(oldExportId))

        verify(exactly = 1) { manager.cancelWorkById(oldExportId) }
        verify(exactly = 1) { manager.cancelUniqueWork(ScheduledProfileScheduler.exportWorkName("alpha")) }
        verify(exactly = 1) { manager.cancelUniqueWork(ScheduledProfileScheduler.fallbackName("alpha")) }
        verify(exactly = 0) { manager.enqueueUniqueWork(any<String>(), any(), any<OneTimeWorkRequest>()) }
    }

    @Test
    fun `repair admission failure preserves recovery and the existing runtime`() = runTest {
        val manager = workManager()
        every {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.reconcileWorkName("alpha"), any(), any<OneTimeWorkRequest>())
        } returns mockk<Operation>(relaxed = true) {
            every { result } returns Futures.immediateFailedFuture(IllegalStateException("WorkManager database unavailable"))
        }
        val original = ScheduledProfileEntry(
            profileId = "alpha", isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
            pendingExports = listOf(ScheduledProfilePendingExport(
                id = "pending", ownerEpochDays = listOf(19_999L), fireAtMillis = 1_000L,
                settingsSnapshotJson = "frozen-settings", target = ExportTarget.DEVICE_FOLDER, profileName = "Alpha",
            )),
        )
        var current = original
        val store = mockk<ScheduledProfileEntryStore> {
            coEvery { entry("alpha") } answers { current }
            coEvery { discardPendingRecovery("alpha") } answers {
                current = current.copy(pendingExports = emptyList(), recoveryGeneration = 1L)
                true
            }
        }
        val scheduler = scheduler(manager, listOf(original), listOf(profile("alpha")), store)

        assertThat(runCatching { scheduler.discardPendingRecovery("alpha") }.isFailure).isTrue()

        assertThat(current).isEqualTo(original)
        coVerify(exactly = 0) { store.discardPendingRecovery(any()) }
        verify(exactly = 0) { manager.cancelUniqueWork(any()) }
        verify(exactly = 0) { manager.cancelWorkById(any()) }
        verify(exactly = 0) {
            manager.enqueueUniqueWork(ScheduledProfileScheduler.fallbackName("alpha"), any(), any<OneTimeWorkRequest>())
        }
    }

    private fun scheduler(
        workManager: WorkManager,
        entries: List<ScheduledProfileEntry>,
        profiles: List<ExportProfile>,
        entryStoreOverride: ScheduledProfileEntryStore? = null,
    ): ScheduledProfileScheduler {
        val entryStore = entryStoreOverride ?: mockk<ScheduledProfileEntryStore> {
            coEvery { pendingLegacyMigrationProfileId() } returns null
            coEvery { getEntries() } returns entries
            coEvery { entry(any()) } answers {
                entries.firstOrNull { it.profileId == firstArg<String>() }
            }
        }
        val profileRepository = mockk<ExportProfileRepository> {
            coEvery { getProfiles() } returns profiles
            coEvery { getActiveProfile() } returns profiles.firstOrNull()
        }
        val settingsRepository = mockk<SettingsRepository> {
            coEvery { getExportSettings() } returns ExportSettings(scheduleEnabled = false)
        }
        return ScheduledProfileScheduler(
            context = ApplicationProvider.getApplicationContext<Context>(),
            workManager = workManager,
            entryStore = entryStore,
            profileRepository = profileRepository,
            legacySettings = settingsRepository,
            legacyScheduler = mockk(relaxed = true),
        )
    }

    private fun profile(id: String) = ExportProfile(
        id = id,
        name = id,
        settingsSnapshotJson = "{}",
        target = ExportTarget.DEVICE_FOLDER,
        createdAtEpochMillis = 0L,
        updatedAtEpochMillis = 0L,
    )

    private fun workManager(): WorkManager = mockk(relaxed = true) {
        every { getWorkInfosForUniqueWorkFlow(any()) } returns flowOf(emptyList())
        every { cancelWorkById(any()) } returns successfulOperation()
        every { cancelUniqueWork(any<String>()) } returns successfulOperation()
        every {
            enqueueUniqueWork(
                any<String>(),
                any<ExistingWorkPolicy>(),
                any<OneTimeWorkRequest>(),
            )
        } returns successfulOperation()
    }

    private fun successfulOperation(): Operation = mockk(relaxed = true) {
        every { result } returns Futures.immediateFuture(Operation.SUCCESS)
    }
}
