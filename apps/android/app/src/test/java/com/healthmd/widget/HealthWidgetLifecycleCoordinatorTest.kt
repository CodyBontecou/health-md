package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import com.healthmd.widget.data.HealthWidgetSnapshotRepository
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import com.healthmd.widget.refresh.HealthWidgetInstanceRegistry
import com.healthmd.widget.refresh.HealthWidgetLifecycleCoordinator
import com.healthmd.widget.refresh.HealthWidgetRefreshCoordinator
import com.healthmd.widget.refresh.HealthWidgetRefreshOrigin
import com.healthmd.widget.refresh.HealthWidgetRefreshResult
import com.healthmd.widget.refresh.HealthWidgetRefreshScheduler
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.verify
import java.io.IOException
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Test

class HealthWidgetLifecycleCoordinatorTest {
    @Test
    fun `final widget removal promptly deletes snapshot and cancels work`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>(relaxed = true)
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val refreshCoordinator = mockk<HealthWidgetRefreshCoordinator>(relaxed = true)
        coEvery { refreshCoordinator.deleteSnapshotIfNoWidgets(emptySet()) } returns true
        val coordinator = HealthWidgetLifecycleCoordinator(
            instances = FakeRegistry(emptySet()),
            snapshots = snapshots,
            refreshCoordinator = refreshCoordinator,
            scheduler = scheduler,
        )

        coordinator.onInstancesChanged()

        coVerify(exactly = 1) { refreshCoordinator.deleteSnapshotIfNoWidgets() }
        coVerify(exactly = 1) { scheduler.cancel() }
        verify(exactly = 0) { scheduler.enqueueImmediate() }
    }

    @Test
    fun `final deletion callback ignores its AppWidgetManager stale id`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>(relaxed = true)
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val refreshCoordinator = mockk<HealthWidgetRefreshCoordinator>(relaxed = true)
        coEvery { refreshCoordinator.deleteSnapshotIfNoWidgets(setOf(91)) } returns true
        val coordinator = HealthWidgetLifecycleCoordinator(
            instances = FakeRegistry(
                kinds = setOf(HealthWidgetKind.SLEEP),
                appWidgetIds = setOf(91),
            ),
            snapshots = snapshots,
            refreshCoordinator = refreshCoordinator,
            scheduler = scheduler,
        )

        coordinator.onInstancesChanged(deletedAppWidgetIds = setOf(91))

        coVerify(exactly = 1) {
            refreshCoordinator.deleteSnapshotIfNoWidgets(setOf(91))
        }
        coVerify(exactly = 1) { scheduler.cancel() }
        verify(exactly = 0) { scheduler.enqueueImmediate() }
    }

    @Test
    fun `onDisabled stale ids never reactivate widget work`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>(relaxed = true)
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val refreshCoordinator = mockk<HealthWidgetRefreshCoordinator>(relaxed = true)
        val coordinator = HealthWidgetLifecycleCoordinator(
            instances = FakeRegistry(
                kinds = setOf(HealthWidgetKind.SLEEP),
                appWidgetIds = setOf(91),
            ),
            snapshots = snapshots,
            refreshCoordinator = refreshCoordinator,
            scheduler = scheduler,
        )

        coordinator.onInstancesChanged(scheduleIfWidgetsRemain = false)

        coVerify(exactly = 0) { scheduler.cancel() }
        verify(exactly = 0) { scheduler.enqueueImmediate() }
        coVerify(exactly = 0) { scheduler.reconcile() }
        coVerify(exactly = 0) { refreshCoordinator.deleteSnapshotIfNoWidgets(any()) }
    }

    @Test
    fun `widget added while cancellation settles has its work restored`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>(relaxed = true)
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val cancellationStarted = CompletableDeferred<Unit>()
        val finishCancellation = CompletableDeferred<Unit>()
        coEvery { scheduler.cancel() } coAnswers {
            cancellationStarted.complete(Unit)
            finishCancellation.await()
        }
        val registry = MutableRegistry(emptySet())
        val refreshCoordinator = HealthWidgetRefreshCoordinator(
            instances = registry,
            permissions = mockk(),
            snapshots = snapshots,
            updater = mockk(),
        )
        val coordinator = HealthWidgetLifecycleCoordinator(
            instances = registry,
            snapshots = snapshots,
            refreshCoordinator = refreshCoordinator,
            scheduler = scheduler,
        )

        val reconciliation = async { coordinator.onInstancesChanged() }
        cancellationStarted.await()
        registry.kinds = setOf(HealthWidgetKind.ACTIVITY)
        finishCancellation.complete(Unit)
        reconciliation.await()

        coVerify(exactly = 0) { snapshots.delete() }
        verify(exactly = 1) { scheduler.enqueueImmediate() }
        coVerify(exactly = 1) { scheduler.reconcile() }
    }

    @Test
    fun `failed final cache deletion schedules a retry`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>(relaxed = true)
        val refreshCoordinator = mockk<HealthWidgetRefreshCoordinator>(relaxed = true)
        coEvery { refreshCoordinator.deleteSnapshotIfNoWidgets() } throws IOException("disk failure")
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val coordinator = HealthWidgetLifecycleCoordinator(
            instances = FakeRegistry(emptySet()),
            snapshots = snapshots,
            refreshCoordinator = refreshCoordinator,
            scheduler = scheduler,
        )

        runCatching { coordinator.onInstancesChanged() }

        verify(exactly = 1) { scheduler.enqueueCleanup(emptySet()) }
    }

    @Test
    fun `failed stale-id cleanup carries callback ids into its retry`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>(relaxed = true)
        val refreshCoordinator = mockk<HealthWidgetRefreshCoordinator>(relaxed = true)
        coEvery { refreshCoordinator.deleteSnapshotIfNoWidgets(setOf(91)) } throws
            IOException("disk failure")
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val coordinator = HealthWidgetLifecycleCoordinator(
            instances = FakeRegistry(
                kinds = setOf(HealthWidgetKind.SLEEP),
                appWidgetIds = setOf(91),
            ),
            snapshots = snapshots,
            refreshCoordinator = refreshCoordinator,
            scheduler = scheduler,
        )

        runCatching { coordinator.onInstancesChanged(setOf(91)) }

        verify(exactly = 1) { scheduler.enqueueCleanup(setOf(91)) }
    }

    @Test
    fun `removing one of several widgets reconciles remaining work`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>(relaxed = true)
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val coordinator = HealthWidgetLifecycleCoordinator(
            instances = FakeRegistry(setOf(HealthWidgetKind.SLEEP)),
            snapshots = snapshots,
            refreshCoordinator = mockk<HealthWidgetRefreshCoordinator>(relaxed = true),
            scheduler = scheduler,
        )

        coordinator.onInstancesChanged()

        coVerify(exactly = 0) { snapshots.delete() }
        verify(exactly = 1) { scheduler.enqueueImmediate() }
        coVerify(exactly = 1) { scheduler.reconcile() }
    }

    @Test
    fun `foreground resume throttles a recent refresh attempt`() = runTest {
        val now = Instant.parse("2026-08-02T12:00:00Z")
        val snapshots = mockk<HealthWidgetSnapshotRepository>()
        coEvery { snapshots.load() } returns HealthWidgetSnapshot(
            lastAttemptAtEpochMillis = now.minusSeconds(5 * 60).toEpochMilli(),
            lastAttemptOutcome = WidgetRefreshOutcome.SUCCESS,
        )
        val refreshCoordinator = mockk<HealthWidgetRefreshCoordinator>(relaxed = true)
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val coordinator = HealthWidgetLifecycleCoordinator(
            instances = FakeRegistry(setOf(HealthWidgetKind.ACTIVITY)),
            snapshots = snapshots,
            refreshCoordinator = refreshCoordinator,
            scheduler = scheduler,
        )

        val result = coordinator.refreshFromForeground(now = now, zoneId = ZoneId.of("UTC"))

        assertThat(result).isEqualTo(HealthWidgetRefreshResult.UPDATED)
        coVerify(exactly = 0) {
            refreshCoordinator.refresh(any(), any(), any())
        }
        coVerify(exactly = 1) { scheduler.reconcile() }
    }

    @Test
    fun `foreground resume refreshes after a recent background denial`() = runTest {
        val now = Instant.parse("2026-08-02T12:00:00Z")
        val snapshots = mockk<HealthWidgetSnapshotRepository>()
        coEvery { snapshots.load() } returns HealthWidgetSnapshot(
            lastAttemptAtEpochMillis = now.minusSeconds(5 * 60).toEpochMilli(),
            lastAttemptOutcome = WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED,
        )
        val refreshCoordinator = mockk<HealthWidgetRefreshCoordinator>()
        coEvery {
            refreshCoordinator.refresh(HealthWidgetRefreshOrigin.FOREGROUND, now, ZoneId.of("UTC"))
        } returns HealthWidgetRefreshResult.NO_DATA
        val scheduler = mockk<HealthWidgetRefreshScheduler>(relaxed = true)
        val coordinator = HealthWidgetLifecycleCoordinator(
            instances = FakeRegistry(setOf(HealthWidgetKind.ACTIVITY)),
            snapshots = snapshots,
            refreshCoordinator = refreshCoordinator,
            scheduler = scheduler,
        )

        val result = coordinator.refreshFromForeground(now = now, zoneId = ZoneId.of("UTC"))

        assertThat(result).isEqualTo(HealthWidgetRefreshResult.NO_DATA)
        coVerify(exactly = 1) {
            refreshCoordinator.refresh(HealthWidgetRefreshOrigin.FOREGROUND, now, ZoneId.of("UTC"))
        }
        coVerify(exactly = 1) { scheduler.reconcile() }
    }

    private class MutableRegistry(
        var kinds: Set<HealthWidgetKind>,
    ) : HealthWidgetInstanceRegistry {
        override fun installedKinds(): Set<HealthWidgetKind> = kinds
        override fun installedWidgetCount(): Int = kinds.size
        override fun kindForAppWidgetId(appWidgetId: Int): HealthWidgetKind? = null
    }

    private class FakeRegistry(
        private val kinds: Set<HealthWidgetKind>,
        private val appWidgetIds: Set<Int>? = null,
    ) : HealthWidgetInstanceRegistry {
        override fun installedKinds(): Set<HealthWidgetKind> = kinds
        override fun installedWidgetCount(): Int = appWidgetIds?.size ?: kinds.size
        override fun kindForAppWidgetId(appWidgetId: Int): HealthWidgetKind? = null
        override fun hasWidgetsExcluding(appWidgetIds: Set<Int>): Boolean =
            this.appWidgetIds?.any { it !in appWidgetIds } ?: hasWidgets()
    }
}
