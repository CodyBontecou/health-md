package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.Operation
import androidx.work.WorkManager
import com.google.common.truth.Truth.assertThat
import com.google.common.util.concurrent.Futures
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.test.runTest
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
