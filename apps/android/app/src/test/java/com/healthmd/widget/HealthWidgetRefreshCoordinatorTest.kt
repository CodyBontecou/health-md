package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthConnectFeatureAvailability
import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.widget.data.HealthWidgetSnapshotRepository
import com.healthmd.widget.data.WidgetHealthPermissionManager
import com.healthmd.widget.data.WidgetHealthPermissionPolicy
import com.healthmd.widget.data.WidgetHealthPermissionStatus
import com.healthmd.widget.model.HealthWidgetDay
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import com.healthmd.widget.refresh.HealthWidgetInstanceRegistry
import com.healthmd.widget.refresh.HealthWidgetRefreshCoordinator
import com.healthmd.widget.refresh.HealthWidgetRefreshOrigin
import com.healthmd.widget.refresh.HealthWidgetRefreshResult
import com.healthmd.widget.refresh.HealthWidgetUpdater
import io.mockk.Runs
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.just
import io.mockk.mockk
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.Instant
import java.time.ZoneId

class HealthWidgetRefreshCoordinatorTest {
    private val now = Instant.parse("2026-08-02T12:00:00Z")
    private val zone = ZoneId.of("UTC")
    private val activityPermissions = WidgetHealthPermissionPolicy.foregroundPermissions(
        com.healthmd.widget.model.WidgetDataRequirements(activity = true),
    )

    @Test
    fun `removing final widget deletes cache and performs no update`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>()
        coEvery { snapshots.delete() } just Runs
        val updater = CountingUpdater()
        val coordinator = coordinator(emptySet(), snapshots, mockk(), updater)

        val result = coordinator.refresh(HealthWidgetRefreshOrigin.BACKGROUND, now, zone)

        assertThat(result).isEqualTo(HealthWidgetRefreshResult.NO_WIDGETS)
        coVerify(exactly = 1) { snapshots.delete() }
        assertThat(updater.updateCount).isEqualTo(0)
    }

    @Test
    fun `final callback deletes cache when AppWidgetManager still reports its deleted id`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>()
        coEvery { snapshots.delete() } just Runs
        val registry = object : HealthWidgetInstanceRegistry {
            override fun installedKinds() = setOf(HealthWidgetKind.SLEEP)
            override fun installedWidgetCount() = 1
            override fun kindForAppWidgetId(appWidgetId: Int) = HealthWidgetKind.SLEEP
            override fun hasWidgetsExcluding(appWidgetIds: Set<Int>) = 91 !in appWidgetIds
        }
        val coordinator = HealthWidgetRefreshCoordinator(
            instances = registry,
            permissions = mockk(),
            snapshots = snapshots,
            updater = CountingUpdater(),
        )

        val deleted = coordinator.deleteSnapshotIfNoWidgets(setOf(91))

        assertThat(deleted).isTrue()
        coVerify(exactly = 1) { snapshots.delete() }
    }

    @Test
    fun `refresh before first unlock renders a non-sensitive state without storage or health reads`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>()
        every { snapshots.isBeforeFirstUnlock() } returns true
        val updater = CountingUpdater()
        val coordinator = coordinator(
            setOf(HealthWidgetKind.ACTIVITY),
            snapshots,
            mockk(),
            updater,
        )

        val result = coordinator.refresh(HealthWidgetRefreshOrigin.BACKGROUND, now, zone)

        assertThat(result).isEqualTo(HealthWidgetRefreshResult.BEFORE_FIRST_UNLOCK)
        coVerify(exactly = 0) {
            snapshots.recordFailedAttempt(any(), any(), any(), any(), any())
        }
        coVerify(exactly = 0) { snapshots.refresh(any(), any(), any(), any(), any()) }
        assertThat(updater.updateCount).isEqualTo(1)
    }

    @Test
    fun `failed final cache deletion requests a worker retry`() = runTest {
        val snapshots = mockk<HealthWidgetSnapshotRepository>()
        coEvery { snapshots.delete() } throws IOException("disk failure")
        val coordinator = coordinator(emptySet(), snapshots, mockk(), CountingUpdater())

        val result = coordinator.refresh(HealthWidgetRefreshOrigin.BACKGROUND, now, zone)

        assertThat(result).isEqualTo(HealthWidgetRefreshResult.CLEANUP_RETRY)
    }

    @Test
    fun `final removal racing an active refresh leaves no snapshot`() = runTest {
        val registry = MutableRegistry(setOf(HealthWidgetKind.ACTIVITY))
        val snapshots = readySnapshots()
        val readStarted = CompletableDeferred<Unit>()
        val finishRead = CompletableDeferred<Unit>()
        coEvery { snapshots.refresh(any(), any(), any(), any(), any()) } coAnswers {
            readStarted.complete(Unit)
            finishRead.await()
            HealthWidgetSnapshot(
                capturedAtEpochMillis = now.toEpochMilli(),
                capturedZoneId = "UTC",
                days = listOf(HealthWidgetDay("2026-08-02", steps = 8_000)),
            )
        }
        coEvery { snapshots.delete() } just Runs
        val permissions = mockk<WidgetHealthPermissionManager>()
        coEvery { permissions.status(any()) } returns WidgetHealthPermissionStatus(
            requestedForegroundPermissions = activityPermissions,
            grantedForegroundPermissions = activityPermissions,
            missingForegroundPermissions = emptySet(),
            backgroundPermissions = setOf("background"),
            backgroundAvailability = HealthConnectFeatureAvailability.AVAILABLE,
            backgroundGranted = true,
        )
        val coordinator = HealthWidgetRefreshCoordinator(
            instances = registry,
            permissions = permissions,
            snapshots = snapshots,
            updater = CountingUpdater(),
        )

        val refresh = async {
            coordinator.refresh(HealthWidgetRefreshOrigin.FOREGROUND, now, zone)
        }
        readStarted.await()
        registry.kinds = emptySet()
        val deletion = async { coordinator.deleteSnapshotIfNoWidgets() }
        finishRead.complete(Unit)

        assertThat(refresh.await()).isEqualTo(HealthWidgetRefreshResult.NO_WIDGETS)
        assertThat(deletion.await()).isTrue()
        coVerify(atLeast = 1) { snapshots.delete() }
    }

    @Test
    fun `background refresh without background grant preserves cache and updates state`() = runTest {
        val snapshots = readySnapshots()
        val permissions = mockk<WidgetHealthPermissionManager>()
        coEvery { permissions.status(any()) } returns WidgetHealthPermissionStatus(
            requestedForegroundPermissions = activityPermissions,
            grantedForegroundPermissions = activityPermissions,
            missingForegroundPermissions = emptySet(),
            backgroundPermissions = setOf("background"),
            backgroundAvailability = HealthConnectFeatureAvailability.AVAILABLE,
            backgroundGranted = false,
        )
        val updater = CountingUpdater()
        val coordinator = coordinator(
            setOf(HealthWidgetKind.ACTIVITY),
            snapshots,
            permissions,
            updater,
        )

        val result = coordinator.refresh(HealthWidgetRefreshOrigin.BACKGROUND, now, zone)

        assertThat(result).isEqualTo(HealthWidgetRefreshResult.PERMISSION_REQUIRED)
        coVerify {
            snapshots.recordFailedAttempt(
                WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED,
                now,
                zone,
                emptySet(),
                HealthConnectWidgetReadSelection(
                    steps = true,
                    activeCalories = true,
                    exerciseSessions = true,
                ),
            )
        }
        coVerify(exactly = 0) { snapshots.refresh(any(), any(), any(), any(), any()) }
        assertThat(updater.updateCount).isEqualTo(1)
    }

    @Test
    fun `foreground refresh succeeds without background grant`() = runTest {
        val snapshots = readySnapshots()
        val success = HealthWidgetSnapshot(
            capturedAtEpochMillis = now.toEpochMilli(),
            capturedZoneId = "UTC",
            days = listOf(HealthWidgetDay("2026-08-02", steps = 8_000)),
            lastAttemptAtEpochMillis = now.toEpochMilli(),
            lastAttemptOutcome = WidgetRefreshOutcome.SUCCESS,
        )
        coEvery { snapshots.refresh(any(), any(), any(), any(), any()) } returns success
        val permissions = mockk<WidgetHealthPermissionManager>()
        coEvery { permissions.status(any()) } returns WidgetHealthPermissionStatus(
            requestedForegroundPermissions = activityPermissions,
            grantedForegroundPermissions = activityPermissions,
            missingForegroundPermissions = emptySet(),
            backgroundPermissions = setOf("background"),
            backgroundAvailability = HealthConnectFeatureAvailability.AVAILABLE,
            backgroundGranted = false,
        )
        val updater = CountingUpdater()
        val coordinator = coordinator(
            setOf(HealthWidgetKind.ACTIVITY),
            snapshots,
            permissions,
            updater,
        )

        val result = coordinator.refresh(HealthWidgetRefreshOrigin.FOREGROUND, now, zone)

        assertThat(result).isEqualTo(HealthWidgetRefreshResult.UPDATED)
        coVerify(exactly = 1) {
            snapshots.refresh(
                HealthConnectWidgetReadSelection(
                    steps = true,
                    activeCalories = true,
                    exerciseSessions = true,
                ),
                any(),
                now,
                zone,
                emptySet(),
            )
        }
        assertThat(updater.updateCount).isEqualTo(1)
    }

    private fun readySnapshots(): HealthWidgetSnapshotRepository =
        mockk<HealthWidgetSnapshotRepository>().also { snapshots ->
            every { snapshots.isBeforeFirstUnlock() } returns false
            coEvery { snapshots.isHealthConnectAvailable() } returns true
            coEvery {
                snapshots.recordFailedAttempt(any(), any(), any(), any(), any())
            } returns HealthWidgetSnapshot()
        }

    private fun coordinator(
        kinds: Set<HealthWidgetKind>,
        snapshots: HealthWidgetSnapshotRepository,
        permissions: WidgetHealthPermissionManager,
        updater: HealthWidgetUpdater,
    ) = HealthWidgetRefreshCoordinator(
        instances = FakeRegistry(kinds),
        permissions = permissions,
        snapshots = snapshots,
        updater = updater,
    )

    private class FakeRegistry(
        private val kinds: Set<HealthWidgetKind>,
    ) : HealthWidgetInstanceRegistry {
        override fun installedKinds(): Set<HealthWidgetKind> = kinds
        override fun installedWidgetCount(): Int = kinds.size
        override fun kindForAppWidgetId(appWidgetId: Int): HealthWidgetKind? = null
    }

    private class MutableRegistry(
        var kinds: Set<HealthWidgetKind>,
    ) : HealthWidgetInstanceRegistry {
        override fun installedKinds(): Set<HealthWidgetKind> = kinds
        override fun installedWidgetCount(): Int = kinds.size
        override fun kindForAppWidgetId(appWidgetId: Int): HealthWidgetKind? = null
    }

    private class CountingUpdater : HealthWidgetUpdater {
        var updateCount = 0
        override suspend fun updateAll() {
            updateCount += 1
        }
    }
}
