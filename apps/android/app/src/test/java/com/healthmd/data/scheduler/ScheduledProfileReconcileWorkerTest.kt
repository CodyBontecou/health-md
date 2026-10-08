package com.healthmd.data.scheduler

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.Data
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.workDataOf
import com.google.common.truth.Truth.assertThat
import dagger.Lazy
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ScheduledProfileReconcileWorkerTest {
    @Test
    fun `repair dispatches only the persisted profile generation and old export identities`() = runTest {
        val scheduler = mockk<ScheduledProfileScheduler>(relaxed = true)
        val oldIds = listOf(UUID.randomUUID(), UUID.randomUUID())
        val worker = worker(scheduler, repairInput(oldIds))

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.success())

        coVerify(exactly = 1) { scheduler.finishRecoveryDiscard("alpha", 1L, oldIds) }
        coVerify(exactly = 0) { scheduler.handleAlarm(any(), any()) }
        coVerify(exactly = 0) { scheduler.discardPendingRecovery(any()) }
    }

    @Test
    fun `repair without old export work still restores scheduling`() = runTest {
        val scheduler = mockk<ScheduledProfileScheduler>(relaxed = true)
        val worker = worker(scheduler, workDataOf(
            ScheduledProfileReconcileWorker.INPUT_PROFILE_ID to "alpha",
            ScheduledProfileReconcileWorker.INPUT_RECOVERY_GENERATION to 1L,
        ))

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.success())

        coVerify(exactly = 1) { scheduler.finishRecoveryDiscard("alpha", 1L, emptyList()) }
        coVerify(exactly = 0) { scheduler.handleAlarm(any(), any()) }
    }

    @Test
    fun `unreadable repair authority fails without touching any schedule`() = runTest {
        val scheduler = mockk<ScheduledProfileScheduler>(relaxed = true)
        val invalid = listOf(
            Data.EMPTY,
            workDataOf(ScheduledProfileReconcileWorker.INPUT_PROFILE_ID to " ",
                ScheduledProfileReconcileWorker.INPUT_RECOVERY_GENERATION to 1L),
            workDataOf(ScheduledProfileReconcileWorker.INPUT_PROFILE_ID to "alpha"),
            workDataOf(ScheduledProfileReconcileWorker.INPUT_PROFILE_ID to "alpha",
                ScheduledProfileReconcileWorker.INPUT_RECOVERY_GENERATION to -1L),
            workDataOf(ScheduledProfileReconcileWorker.INPUT_PROFILE_ID to "alpha",
                ScheduledProfileReconcileWorker.INPUT_RECOVERY_GENERATION to 1L,
                ScheduledProfileReconcileWorker.INPUT_OLD_EXPORT_WORK_IDS to arrayOf(UUID.randomUUID().toString(), "invalid-uuid")),
        )

        for (input in invalid) {
            assertThat(worker(scheduler, input).doWork()).isEqualTo(ListenableWorker.Result.failure())
        }

        coVerify(exactly = 0) { scheduler.finishRecoveryDiscard(any(), any(), any()) }
        coVerify(exactly = 0) { scheduler.handleAlarm(any(), any()) }
    }

    @Test
    fun `a failed scheduling repair remains retryable`() = runTest {
        val scheduler = mockk<ScheduledProfileScheduler>()
        coEvery { scheduler.finishRecoveryDiscard(any(), any(), any()) } throws IllegalStateException("DataStore unavailable")
        val worker = worker(scheduler, repairInput(emptyList()))

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.retry())

        coVerify(exactly = 1) { scheduler.finishRecoveryDiscard("alpha", 1L, emptyList()) }
    }

    @Test
    fun `WorkManager cancellation propagates instead of acknowledging the repair`() = runTest {
        val scheduler = mockk<ScheduledProfileScheduler>()
        val cancellation = CancellationException("WorkManager stopped this attempt")
        coEvery { scheduler.finishRecoveryDiscard(any(), any(), any()) } throws cancellation
        val worker = worker(scheduler, repairInput(emptyList()))

        assertThat(runCatching { worker.doWork() }.exceptionOrNull()).isSameInstanceAs(cancellation)
    }

    private fun repairInput(oldIds: List<UUID>) = workDataOf(
        ScheduledProfileReconcileWorker.INPUT_PROFILE_ID to "alpha",
        ScheduledProfileReconcileWorker.INPUT_RECOVERY_GENERATION to 1L,
        ScheduledProfileReconcileWorker.INPUT_OLD_EXPORT_WORK_IDS to oldIds.map(UUID::toString).toTypedArray(),
    )

    private fun worker(scheduler: ScheduledProfileScheduler, input: Data): ScheduledProfileReconcileWorker {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val factory = object : WorkerFactory() {
            override fun createWorker(
                appContext: Context,
                workerClassName: String,
                workerParameters: WorkerParameters,
            ): ListenableWorker = ScheduledProfileReconcileWorker(appContext, workerParameters, Lazy { scheduler })
        }
        return TestListenableWorkerBuilder<ScheduledProfileReconcileWorker>(context)
            .setWorkerFactory(factory)
            .setInputData(input)
            .build()
    }
}
