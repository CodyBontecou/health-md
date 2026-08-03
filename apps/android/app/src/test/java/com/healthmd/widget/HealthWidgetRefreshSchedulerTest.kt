package com.healthmd.widget

import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequest
import androidx.work.Operation
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import com.google.common.truth.Truth.assertThat
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.SettableFuture
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.refresh.HealthWidgetInstanceRegistry
import com.healthmd.widget.refresh.HealthWidgetRefreshScheduler
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.verify
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Test

class HealthWidgetRefreshSchedulerTest {
    @Test
    fun `reconcile schedules one unique privacy pulse whenever a widget exists`() = runTest {
        val workManager = relaxedWorkManager()
        val scheduler = HealthWidgetRefreshScheduler(
            workManager,
            FakeRegistry(setOf(HealthWidgetKind.ACTIVITY)),
        )

        scheduler.reconcile()

        verify(exactly = 1) {
            workManager.enqueueUniquePeriodicWork(
                HealthWidgetRefreshScheduler.PERIODIC_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                any(),
            )
        }
    }

    @Test
    fun `reconcile cancels all work after the final widget is removed`() = runTest {
        val workManager = relaxedWorkManager()
        val scheduler = HealthWidgetRefreshScheduler(
            workManager,
            FakeRegistry(emptySet()),
        )

        scheduler.reconcile()

        verify { workManager.cancelUniqueWork(HealthWidgetRefreshScheduler.PERIODIC_WORK_NAME) }
        verify { workManager.cancelUniqueWork(HealthWidgetRefreshScheduler.IMMEDIATE_WORK_NAME) }
        verify { workManager.cancelUniqueWork(HealthWidgetRefreshScheduler.CLEANUP_WORK_NAME) }
    }

    @OptIn(ExperimentalCoroutinesApi::class)
    @Test
    fun `cancel waits for WorkManager to durably finish cancellation`() = runTest {
        val workManager = relaxedWorkManager()
        val pending = SettableFuture.create<Operation.State.SUCCESS>()
        every { workManager.cancelUniqueWork(any<String>()) } returns pendingOperation(pending)
        val scheduler = HealthWidgetRefreshScheduler(
            workManager,
            FakeRegistry(emptySet()),
        )

        val cancellation = async { scheduler.cancel() }
        runCurrent()

        assertThat(cancellation.isCompleted).isFalse()
        pending.set(Operation.SUCCESS)
        cancellation.await()
        assertThat(cancellation.isCompleted).isTrue()
    }

    @Test
    fun `immediate refresh is not enqueued with no remaining widget`() {
        val workManager = relaxedWorkManager()
        val scheduler = HealthWidgetRefreshScheduler(
            workManager,
            FakeRegistry(emptySet()),
        )

        scheduler.enqueueImmediate()

        verify(exactly = 0) {
            workManager.enqueueUniqueWork(
                HealthWidgetRefreshScheduler.IMMEDIATE_WORK_NAME,
                ExistingWorkPolicy.KEEP,
                any<OneTimeWorkRequest>(),
            )
        }
    }

    @Test
    fun `cleanup is enqueued even with no remaining widget and retains deleted ids`() {
        val workManager = relaxedWorkManager()
        val scheduler = HealthWidgetRefreshScheduler(
            workManager,
            FakeRegistry(emptySet()),
        )
        val request = slot<OneTimeWorkRequest>()

        scheduler.enqueueCleanup(setOf(41, 42))

        verify {
            workManager.enqueueUniqueWork(
                HealthWidgetRefreshScheduler.CLEANUP_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                capture(request),
            )
        }
        assertThat(
            request.captured.workSpec.input.getBoolean(
                HealthWidgetRefreshScheduler.CLEANUP_ONLY_KEY,
                false,
            ),
        ).isTrue()
        assertThat(
            request.captured.workSpec.input.getIntArray(
                HealthWidgetRefreshScheduler.CLEANUP_DELETED_IDS_KEY,
            )?.toSet(),
        ).isEqualTo(setOf(41, 42))
    }

    private fun relaxedWorkManager(): WorkManager = mockk(relaxed = true) {
        every {
            enqueueUniqueWork(
                any<String>(),
                any<ExistingWorkPolicy>(),
                any<OneTimeWorkRequest>(),
            )
        } returns mockk<Operation>(relaxed = true)
        every {
            enqueueUniquePeriodicWork(
                any<String>(),
                any<ExistingPeriodicWorkPolicy>(),
                any<PeriodicWorkRequest>(),
            )
        } returns mockk<Operation>(relaxed = true)
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

    private class FakeRegistry(
        private val kinds: Set<HealthWidgetKind>,
    ) : HealthWidgetInstanceRegistry {
        override fun installedKinds(): Set<HealthWidgetKind> = kinds
        override fun installedWidgetCount(): Int = kinds.size
        override fun kindForAppWidgetId(appWidgetId: Int): HealthWidgetKind? = null
    }
}
