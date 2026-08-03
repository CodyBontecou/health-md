package com.healthmd.widget.refresh

import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.widget.data.HealthWidgetSnapshotRepository
import com.healthmd.widget.data.WidgetHealthPermissionManager
import com.healthmd.widget.data.WidgetHealthPermissionPolicy
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.WidgetDataRequirements
import com.healthmd.widget.model.WidgetRefreshOutcome
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton

interface HealthWidgetInstanceRegistry {
    fun installedKinds(): Set<HealthWidgetKind>
    fun installedWidgetCount(): Int
    fun kindForAppWidgetId(appWidgetId: Int): HealthWidgetKind?

    fun requirements(): WidgetDataRequirements =
        WidgetDataRequirements.forKinds(installedKinds())

    fun hasWidgets(): Boolean = installedKinds().isNotEmpty()

    /**
     * AppWidgetManager can still report IDs while their onDeleted callback is running. Production
     * registries override this so final-instance cleanup can ignore the IDs in that callback.
     */
    fun hasWidgetsExcluding(appWidgetIds: Set<Int>): Boolean = hasWidgets()
}

interface HealthWidgetUpdater {
    suspend fun updateAll()
}

enum class HealthWidgetRefreshOrigin {
    FOREGROUND,
    BACKGROUND,
}

enum class HealthWidgetRefreshResult {
    UPDATED,
    NO_DATA,
    NO_WIDGETS,
    PERMISSION_REQUIRED,
    HEALTH_CONNECT_UNAVAILABLE,
    BEFORE_FIRST_UNLOCK,
    RETRY,
    CLEANUP_RETRY,
}

@Singleton
class HealthWidgetRefreshCoordinator @Inject constructor(
    private val instances: HealthWidgetInstanceRegistry,
    private val permissions: WidgetHealthPermissionManager,
    private val snapshots: HealthWidgetSnapshotRepository,
    private val updater: HealthWidgetUpdater,
) {
    private val refreshLock = Mutex()

    /** Serializes final-instance deletion with foreground and worker refreshes. */
    suspend fun deleteSnapshotIfNoWidgets(
        deletedAppWidgetIds: Set<Int> = emptySet(),
    ): Boolean = refreshLock.withLock {
        if (instances.hasWidgetsExcluding(deletedAppWidgetIds)) return@withLock false
        snapshots.delete()
        true
    }

    suspend fun refresh(
        origin: HealthWidgetRefreshOrigin,
        now: Instant = Instant.now(),
        zoneId: ZoneId = ZoneId.systemDefault(),
    ): HealthWidgetRefreshResult = refreshLock.withLock {
        val installedKinds = instances.installedKinds()
        if (installedKinds.isEmpty()) {
            return@withLock try {
                snapshots.delete()
                HealthWidgetRefreshResult.NO_WIDGETS
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                HealthWidgetRefreshResult.CLEANUP_RETRY
            }
        }
        val requestedRequirements = WidgetDataRequirements.forKinds(installedKinds)

        if (snapshots.isBeforeFirstUnlock()) {
            // Credential-protected storage is intentionally unavailable here. The provider builds
            // the same non-sensitive state in memory without touching the snapshot file.
            updater.updateAll()
            return@withLock HealthWidgetRefreshResult.BEFORE_FIRST_UNLOCK
        }

        val available = try {
            snapshots.isHealthConnectAvailable()
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            return@withLock recordTemporaryFailure(now, zoneId)
        }
        if (!available) {
            recordFailureAndUpdate(
                WidgetRefreshOutcome.HEALTH_CONNECT_UNAVAILABLE,
                now,
                zoneId,
            )
            return@withLock HealthWidgetRefreshResult.HEALTH_CONNECT_UNAVAILABLE
        }

        val permissionStatus = try {
            permissions.status(requestedRequirements)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            return@withLock recordTemporaryFailure(now, zoneId)
        }
        val permissionRequiredKinds = WidgetHealthPermissionPolicy.kindsWithoutAnyGrantedPermission(
            kinds = installedKinds,
            grantedPermissions = permissionStatus.grantedForegroundPermissions,
        )
        val readSelection = WidgetHealthPermissionPolicy.readSelection(
            requirements = requestedRequirements,
            grantedPermissions = permissionStatus.grantedForegroundPermissions,
        )
        val readableKinds = installedKinds - permissionRequiredKinds
        if (readableKinds.isEmpty()) {
            recordFailureAndUpdate(
                outcome = WidgetRefreshOutcome.FOREGROUND_PERMISSION_REQUIRED,
                now = now,
                zoneId = zoneId,
                permissionRequiredKinds = permissionRequiredKinds,
                readableSelection = readSelection,
            )
            return@withLock HealthWidgetRefreshResult.PERMISSION_REQUIRED
        }
        if (origin == HealthWidgetRefreshOrigin.BACKGROUND && !permissionStatus.canRefreshInBackground) {
            recordFailureAndUpdate(
                outcome = WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED,
                now = now,
                zoneId = zoneId,
                permissionRequiredKinds = permissionRequiredKinds,
                readableSelection = readSelection,
            )
            return@withLock HealthWidgetRefreshResult.PERMISSION_REQUIRED
        }
        if (!readSelection.hasAny) {
            recordFailureAndUpdate(
                outcome = WidgetRefreshOutcome.FOREGROUND_PERMISSION_REQUIRED,
                now = now,
                zoneId = zoneId,
                permissionRequiredKinds = installedKinds,
                readableSelection = readSelection,
            )
            return@withLock HealthWidgetRefreshResult.PERMISSION_REQUIRED
        }

        try {
            val snapshot = snapshots.refresh(
                selection = readSelection,
                today = LocalDate.now(zoneId),
                now = now,
                zoneId = zoneId,
                permissionRequiredKinds = permissionRequiredKinds,
            )
            if (!instances.hasWidgets()) {
                snapshots.delete()
                return@withLock HealthWidgetRefreshResult.NO_WIDGETS
            }
            updater.updateAll()
            if (snapshot.hasAnyData) {
                HealthWidgetRefreshResult.UPDATED
            } else {
                HealthWidgetRefreshResult.NO_DATA
            }
        } catch (error: CancellationException) {
            throw error
        } catch (_: SecurityException) {
            val outcome = if (origin == HealthWidgetRefreshOrigin.BACKGROUND) {
                WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED
            } else {
                WidgetRefreshOutcome.FOREGROUND_PERMISSION_REQUIRED
            }
            recordFailureAndUpdate(
                outcome = outcome,
                now = now,
                zoneId = zoneId,
                permissionRequiredKinds = if (origin == HealthWidgetRefreshOrigin.FOREGROUND) {
                    installedKinds
                } else {
                    permissionRequiredKinds
                },
                readableSelection = HealthConnectWidgetReadSelection(),
            )
            HealthWidgetRefreshResult.PERMISSION_REQUIRED
        } catch (_: Exception) {
            recordFailureAndUpdate(
                WidgetRefreshOutcome.TEMPORARY_FAILURE,
                now,
                zoneId,
                permissionRequiredKinds,
                readSelection,
            )
            HealthWidgetRefreshResult.RETRY
        }
    }

    private suspend fun recordTemporaryFailure(
        now: Instant,
        zoneId: ZoneId,
    ): HealthWidgetRefreshResult {
        recordFailureAndUpdate(WidgetRefreshOutcome.TEMPORARY_FAILURE, now, zoneId)
        return HealthWidgetRefreshResult.RETRY
    }

    private suspend fun recordFailureAndUpdate(
        outcome: WidgetRefreshOutcome,
        now: Instant,
        zoneId: ZoneId,
        permissionRequiredKinds: Set<HealthWidgetKind>? = null,
        readableSelection: HealthConnectWidgetReadSelection? = null,
    ) {
        runCatching {
            snapshots.recordFailedAttempt(
                outcome = outcome,
                attemptedAt = now,
                zoneId = zoneId,
                permissionRequiredKinds = permissionRequiredKinds,
                readableSelection = readableSelection,
            )
        }
        runCatching { updater.updateAll() }
    }
}
