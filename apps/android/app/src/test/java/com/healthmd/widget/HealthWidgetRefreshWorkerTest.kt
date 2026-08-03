package com.healthmd.widget

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import androidx.work.Data
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.workDataOf
import com.google.common.truth.Truth.assertThat
import com.healthmd.widget.refresh.HealthWidgetRefreshCoordinator
import com.healthmd.widget.refresh.HealthWidgetRefreshOrigin
import com.healthmd.widget.refresh.HealthWidgetRefreshResult
import com.healthmd.widget.refresh.HealthWidgetRefreshScheduler
import com.healthmd.widget.refresh.HealthWidgetRefreshWorker
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HealthWidgetRefreshWorkerTest {
    @Test
    fun `failed final cache deletion keeps retrying after the ordinary attempt cap`() = runTest {
        val coordinator = mockk<HealthWidgetRefreshCoordinator>()
        coEvery {
            coordinator.refresh(HealthWidgetRefreshOrigin.BACKGROUND, any(), any())
        } returns HealthWidgetRefreshResult.CLEANUP_RETRY
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val worker = worker(coordinator, scheduler, runAttemptCount = 8)

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.retry())
        coVerify(exactly = 0) { scheduler.reconcile() }
    }

    @Test
    fun `cleanup-only retry retains deleted ids and never refreshes Health Connect`() = runTest {
        val coordinator = mockk<HealthWidgetRefreshCoordinator>()
        coEvery { coordinator.deleteSnapshotIfNoWidgets(setOf(91)) } throws
            IllegalStateException("storage unavailable")
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val worker = worker(
            coordinator = coordinator,
            scheduler = scheduler,
            runAttemptCount = 8,
            inputData = workDataOf(
                HealthWidgetRefreshScheduler.CLEANUP_ONLY_KEY to true,
                HealthWidgetRefreshScheduler.CLEANUP_DELETED_IDS_KEY to intArrayOf(91),
            ),
        )

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.retry())
        coVerify(exactly = 1) { coordinator.deleteSnapshotIfNoWidgets(setOf(91)) }
        coVerify(exactly = 0) {
            coordinator.refresh(HealthWidgetRefreshOrigin.BACKGROUND, any(), any())
        }
        coVerify(exactly = 0) { scheduler.reconcile() }
    }

    @Test
    fun `unexpected coordinator failure becomes a retry`() = runTest {
        val coordinator = mockk<HealthWidgetRefreshCoordinator>()
        coEvery {
            coordinator.refresh(HealthWidgetRefreshOrigin.BACKGROUND, any(), any())
        } throws IllegalStateException("storage unavailable")
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val worker = worker(coordinator, scheduler, runAttemptCount = 0)

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.retry())
        coVerify(exactly = 0) { scheduler.reconcile() }
    }

    @Test
    fun `ordinary transient failure stops retrying at the bounded attempt cap`() = runTest {
        val coordinator = mockk<HealthWidgetRefreshCoordinator>()
        coEvery {
            coordinator.refresh(HealthWidgetRefreshOrigin.BACKGROUND, any(), any())
        } returns HealthWidgetRefreshResult.RETRY
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val worker = worker(coordinator, scheduler, runAttemptCount = 3)

        assertThat(worker.doWork()).isEqualTo(ListenableWorker.Result.success())
        coVerify(exactly = 0) { scheduler.reconcile() }
    }

    private fun worker(
        coordinator: HealthWidgetRefreshCoordinator,
        scheduler: HealthWidgetRefreshScheduler,
        runAttemptCount: Int,
        inputData: Data = Data.EMPTY,
    ): HealthWidgetRefreshWorker {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val factory = object : WorkerFactory() {
            override fun createWorker(
                appContext: Context,
                workerClassName: String,
                workerParameters: WorkerParameters,
            ): ListenableWorker = HealthWidgetRefreshWorker(
                appContext,
                workerParameters,
                coordinator,
                scheduler,
            )
        }
        return TestListenableWorkerBuilder<HealthWidgetRefreshWorker>(context)
            .setWorkerFactory(factory)
            .setRunAttemptCount(runAttemptCount)
            .setInputData(inputData)
            .build()
    }
}
