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
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Cancellation at real WorkManager suspension boundaries must not strand an enabled schedule. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
class ScheduledProfileSchedulerDiscardInterruptionTest {
    @Test
    fun `caller cancellation after the generation write still arms the replacement occurrence`() = runTest {
        val harness = Harness()
        val exportCancellation = SettableFuture.create<Operation.State.SUCCESS>()
        every { harness.manager.cancelUniqueWork(ScheduledProfileScheduler.exportWorkName(PROFILE_ID)) } returns
            operation(exportCancellation)

        val discard = launch { harness.scheduler.discardPendingRecovery(PROFILE_ID) }
        runCurrent()
        assertThat(harness.current.recoveryGeneration).isEqualTo(1L)
        assertThat(harness.current.pendingExports).isEmpty()
        verify(exactly = 0) { harness.manager.cancelUniqueWork(ScheduledProfileScheduler.fallbackName(PROFILE_ID)) }

        discard.cancel()
        exportCancellation.set(Operation.SUCCESS)
        discard.join()

        harness.assertReplacementArmed()
    }

    @Test
    fun `caller cancellation after export cancellation still arms the replacement occurrence`() = runTest {
        val harness = Harness()
        val fallbackCancellation = SettableFuture.create<Operation.State.SUCCESS>()
        every { harness.manager.cancelUniqueWork(ScheduledProfileScheduler.fallbackName(PROFILE_ID)) } returns
            operation(fallbackCancellation)

        val discard = launch { harness.scheduler.discardPendingRecovery(PROFILE_ID) }
        runCurrent()
        assertThat(harness.current.recoveryGeneration).isEqualTo(1L)
        verify(exactly = 1) { harness.manager.cancelUniqueWork(ScheduledProfileScheduler.exportWorkName(PROFILE_ID)) }

        discard.cancel()
        fallbackCancellation.set(Operation.SUCCESS)
        discard.join()

        harness.assertReplacementArmed()
        // An old wake remains inert even after cancellation; repair must never upload immediately.
        harness.scheduler.handleAlarm(PROFILE_ID, recoveryGeneration = 0L)
        verify(exactly = 0) {
            harness.manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName(PROFILE_ID), any(), any<OneTimeWorkRequest>())
        }
    }

    @Test
    fun `caller cancellation while waiting for the scheduler lock leaves recovery untouched`() = runTest {
        val harness = Harness()
        val admission = SettableFuture.create<Operation.State.SUCCESS>()
        every {
            harness.manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName(PROFILE_ID), any(), any<OneTimeWorkRequest>())
        } returns operation(admission)
        val alarm = launch { harness.scheduler.handleAlarm(PROFILE_ID, recoveryGeneration = 0L) }
        runCurrent()

        val discard = launch { harness.scheduler.discardPendingRecovery(PROFILE_ID) }
        runCurrent()
        discard.cancelAndJoin()
        admission.set(Operation.SUCCESS)
        alarm.join()

        assertThat(harness.current).isEqualTo(harness.original)
        coVerify(exactly = 0) { harness.store.discardPendingRecovery(any()) }
        verify(exactly = 0) { harness.manager.cancelUniqueWork(any()) }
        verify(exactly = 0) {
            harness.manager.enqueueUniqueWork(repairName(), any(), any<OneTimeWorkRequest>())
        }
    }

    @Test
    fun `repair delivery is durable before recovery generation is invalidated`() = runTest {
        val harness = Harness()
        val durableRepair = SettableFuture.create<Operation.State.SUCCESS>()
        every { harness.manager.enqueueUniqueWork(repairName(), any(), any<OneTimeWorkRequest>()) } returns
            operation(durableRepair)

        val discard = launch { harness.scheduler.discardPendingRecovery(PROFILE_ID) }
        runCurrent()

        assertThat(harness.current).isEqualTo(harness.original)
        coVerify(exactly = 0) { harness.store.discardPendingRecovery(any()) }
        verify(exactly = 1) {
            harness.manager.enqueueUniqueWork(repairName(), any(), any<OneTimeWorkRequest>())
        }
        verify(exactly = 0) { harness.manager.cancelUniqueWork(any()) }

        // Once admission has begun, the transition finishes even if the initiating UI disappears.
        discard.cancel()
        durableRepair.set(Operation.SUCCESS)
        discard.join()

        harness.assertReplacementArmed()
        verify(exactly = 0) { harness.manager.cancelUniqueWork(repairName()) }
    }

    private class Harness {
        val original = ScheduledProfileEntry(
            profileId = PROFILE_ID, isEnabled = true, anchorEpochDay = 20_000, zoneId = "UTC",
            lastSuccessEpochMillis = 1_000L, lastRefreshSuccessEpochMillis = 2_000L,
            pendingExports = listOf(ScheduledProfilePendingExport(
                id = "obsolete-recovery", ownerEpochDays = listOf(19_998L, 19_999L), fireAtMillis = 500L,
                settingsSnapshotJson = "frozen-output-settings", target = ExportTarget.API_ENDPOINT,
                profileName = "Alpha", apiEndpointUrl = "https://example.invalid/old-recovery",
            )),
        )
        var current = original
        val replacements = mutableListOf<OneTimeWorkRequest>()
        val store = mockk<ScheduledProfileEntryStore> {
            coEvery { discardPendingRecovery(PROFILE_ID) } answers {
                current = current.copy(pendingExports = emptyList(), recoveryGeneration = current.recoveryGeneration + 1)
                true
            }
            coEvery { entry(PROFILE_ID) } answers { current }
        }
        val manager = mockk<WorkManager>(relaxed = true) {
            every { getWorkInfosForUniqueWorkFlow(any()) } returns flowOf(emptyList())
            every { cancelUniqueWork(any()) } returns successfulOperation()
            every { enqueueUniqueWork(any<String>(), any<ExistingWorkPolicy>(), any<OneTimeWorkRequest>()) } returns successfulOperation()
        }.also { manager ->
            every {
                manager.enqueueUniqueWork(ScheduledProfileScheduler.fallbackName(PROFILE_ID), any(), any<OneTimeWorkRequest>())
            } answers {
                replacements += thirdArg<OneTimeWorkRequest>()
                successfulOperation()
            }
        }
        val scheduler = ScheduledProfileScheduler(
            context = ApplicationProvider.getApplicationContext<Context>(), workManager = manager,
            entryStore = store, profileRepository = mockk<ExportProfileRepository>(relaxed = true),
            legacySettings = mockk<SettingsRepository> {
                coEvery { getExportSettings() } returns ExportSettings(scheduleEnabled = false)
            },
            legacyScheduler = mockk(relaxed = true),
        )

        fun assertReplacementArmed() {
            assertThat(current).isEqualTo(original.copy(pendingExports = emptyList(), recoveryGeneration = 1L))
            assertThat(replacements).hasSize(1)
            val request = replacements.single().workSpec
            assertThat(request.workerClassName).isEqualTo(ScheduledProfileTriggerWorker::class.java.name)
            assertThat(request.input.getString(ScheduledProfileTriggerWorker.INPUT_PROFILE_ID)).isEqualTo(PROFILE_ID)
            assertThat(request.input.getLong(ScheduledProfileTriggerWorker.INPUT_RECOVERY_GENERATION, -1L)).isEqualTo(1L)
            assertThat(request.initialDelay).isGreaterThan(0L)
            verify(exactly = 1) { manager.cancelUniqueWork(ScheduledProfileScheduler.exportWorkName(PROFILE_ID)) }
            verify(exactly = 1) { manager.cancelUniqueWork(ScheduledProfileScheduler.fallbackName(PROFILE_ID)) }
            verify(exactly = 0) {
                manager.enqueueUniqueWork(ScheduledProfileScheduler.exportWorkName(PROFILE_ID), any(), any<OneTimeWorkRequest>())
            }
        }
    }

    companion object {
        private const val PROFILE_ID = "alpha"
        private fun repairName() = ScheduledProfileScheduler.reconcileWorkName(PROFILE_ID)
        private fun operation(future: com.google.common.util.concurrent.ListenableFuture<Operation.State.SUCCESS>) =
            mockk<Operation>(relaxed = true) { every { result } returns future }
        private fun successfulOperation() = operation(Futures.immediateFuture(Operation.SUCCESS))
    }
}
