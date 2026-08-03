package com.healthmd.widget.data

import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject

class HealthWidgetSnapshotRepository @Inject constructor(
    private val source: WidgetHealthDataSource,
    private val mapper: HealthWidgetSnapshotMapper,
    private val store: HealthWidgetSnapshotStore,
) {
    suspend fun load(): HealthWidgetSnapshot? = store.load()

    suspend fun refresh(
        selection: HealthConnectWidgetReadSelection,
        today: LocalDate,
        now: Instant,
        zoneId: ZoneId,
        permissionRequiredKinds: Set<HealthWidgetKind> = emptySet(),
    ): HealthWidgetSnapshot {
        val previous = store.load()
        val healthDays = source.readRecentDays(
            today = today,
            selection = selection,
        )
        val captured = mapper.map(
            healthDays = healthDays,
            capturedAt = now,
            zoneId = zoneId,
            permissionRequiredKinds = permissionRequiredKinds,
        )
        val previousReadable = previous?.redactedTo(selection)
        val snapshot = if (!captured.hasAnyData && previousReadable?.hasAnyData == true) {
            previousReadable.copy(
                permissionRequiredKinds = permissionRequiredKinds,
                lastAttemptAtEpochMillis = now.toEpochMilli(),
                lastAttemptOutcome = WidgetRefreshOutcome.NO_DATA,
            )
        } else {
            captured
        }
        store.save(snapshot)
        return snapshot
    }

    suspend fun recordFailedAttempt(
        outcome: WidgetRefreshOutcome,
        attemptedAt: Instant,
        zoneId: ZoneId,
        permissionRequiredKinds: Set<HealthWidgetKind>? = null,
        readableSelection: HealthConnectWidgetReadSelection? = null,
    ): HealthWidgetSnapshot {
        require(outcome != WidgetRefreshOutcome.SUCCESS && outcome != WidgetRefreshOutcome.NO_DATA)
        val existing = store.load()?.let { snapshot ->
            readableSelection?.let(snapshot::redactedTo) ?: snapshot
        }
        val updated = (existing ?: HealthWidgetSnapshot(capturedZoneId = zoneId.id)).copy(
            permissionRequiredKinds = permissionRequiredKinds
                ?: existing?.permissionRequiredKinds
                ?: emptySet(),
            lastAttemptAtEpochMillis = attemptedAt.toEpochMilli(),
            lastAttemptOutcome = outcome,
        )
        store.save(updated)
        return updated
    }

    suspend fun delete() = store.delete()

    suspend fun isHealthConnectAvailable(): Boolean = source.isAvailable()

    fun isBeforeFirstUnlock(): Boolean = source.isBeforeFirstUnlock()
}

private fun HealthWidgetSnapshot.redactedTo(
    selection: HealthConnectWidgetReadSelection,
): HealthWidgetSnapshot = copy(
    days = days.map { day ->
        day.copy(
            steps = if (selection.steps) day.steps else null,
            activeCaloriesKilocalories = if (selection.activeCalories) {
                day.activeCaloriesKilocalories
            } else {
                null
            },
            exerciseMinutes = if (selection.exerciseSessions) day.exerciseMinutes else null,
            sleepDurationMinutes = if (selection.sleepSessions) day.sleepDurationMinutes else null,
            sleepStartEpochMillis = if (selection.sleepSessions) day.sleepStartEpochMillis else null,
            sleepEndEpochMillis = if (selection.sleepSessions) day.sleepEndEpochMillis else null,
            averageHeartRateBpm = if (selection.heartRate) day.averageHeartRateBpm else null,
            minimumHeartRateBpm = if (selection.heartRate) day.minimumHeartRateBpm else null,
            maximumHeartRateBpm = if (selection.heartRate) day.maximumHeartRateBpm else null,
            restingHeartRateBpm = if (selection.restingHeartRate) day.restingHeartRateBpm else null,
            hrvRmssdMillis = if (selection.hrvRmssd) day.hrvRmssdMillis else null,
        )
    },
)
