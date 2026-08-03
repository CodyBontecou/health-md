package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthConnectWidgetReadSelection
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HeartData
import com.healthmd.widget.data.HealthWidgetSnapshotMapper
import com.healthmd.widget.data.HealthWidgetSnapshotRepository
import com.healthmd.widget.data.HealthWidgetSnapshotStore
import com.healthmd.widget.data.WidgetHealthDataSource
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId

class HealthWidgetSnapshotRepositoryTest {
    @Test
    fun `successful refresh maps and persists one bounded snapshot`() = runTest {
        val today = LocalDate.parse("2026-08-02")
        val store = FakeSnapshotStore()
        val source = FakeWidgetHealthDataSource(
            records = listOf(HealthData(today, activity = ActivityData(steps = 4_321))),
        )
        val repository = HealthWidgetSnapshotRepository(source, HealthWidgetSnapshotMapper(), store)

        val selection = HealthConnectWidgetReadSelection(steps = true)
        val snapshot = repository.refresh(
            selection = selection,
            today = today,
            now = Instant.parse("2026-08-02T12:00:00Z"),
            zoneId = ZoneId.of("UTC"),
        )

        assertThat(snapshot.days.single().steps).isEqualTo(4_321)
        assertThat(store.snapshot).isEqualTo(snapshot)
        assertThat(source.lastSelection).isEqualTo(selection)
    }

    @Test
    fun `empty capture keeps last-good measurements and original capture time`() = runTest {
        val today = LocalDate.parse("2026-08-02")
        val store = FakeSnapshotStore()
        val source = FakeWidgetHealthDataSource(
            listOf(HealthData(today, activity = ActivityData(steps = 7_000))),
        )
        val repository = HealthWidgetSnapshotRepository(source, HealthWidgetSnapshotMapper(), store)
        val firstCapture = Instant.parse("2026-08-02T12:00:00Z")
        repository.refresh(
            selection = HealthConnectWidgetReadSelection(steps = true),
            today = today,
            now = firstCapture,
            zoneId = ZoneId.of("UTC"),
        )
        source.records = listOf(HealthData(today))

        val fallback = repository.refresh(
            selection = HealthConnectWidgetReadSelection(steps = true),
            today = today,
            now = Instant.parse("2026-08-02T13:00:00Z"),
            zoneId = ZoneId.of("UTC"),
        )

        assertThat(fallback.days.single().steps).isEqualTo(7_000)
        assertThat(fallback.capturedAtEpochMillis).isEqualTo(firstCapture.toEpochMilli())
        assertThat(fallback.lastAttemptOutcome).isEqualTo(WidgetRefreshOutcome.NO_DATA)
    }

    @Test
    fun `empty capture preserves only the metrics selected by remaining widgets`() = runTest {
        val today = LocalDate.parse("2026-08-02")
        val store = FakeSnapshotStore()
        val source = FakeWidgetHealthDataSource(
            listOf(
                HealthData(
                    today,
                    activity = ActivityData(steps = 7_000),
                    heart = HeartData(averageHeartRate = 70.0),
                ),
            ),
        )
        val repository = HealthWidgetSnapshotRepository(source, HealthWidgetSnapshotMapper(), store)
        repository.refresh(
            selection = HealthConnectWidgetReadSelection(steps = true, heartRate = true),
            today = today,
            now = Instant.parse("2026-08-02T12:00:00Z"),
            zoneId = ZoneId.of("UTC"),
        )
        source.records = listOf(HealthData(today))

        val fallback = repository.refresh(
            selection = HealthConnectWidgetReadSelection(heartRate = true),
            today = today,
            now = Instant.parse("2026-08-02T13:00:00Z"),
            zoneId = ZoneId.of("UTC"),
        )

        assertThat(fallback.days.single().steps).isNull()
        assertThat(fallback.days.single().averageHeartRateBpm).isEqualTo(70.0)
        assertThat(fallback.lastAttemptOutcome).isEqualTo(WidgetRefreshOutcome.NO_DATA)
    }

    @Test
    fun `permission reconciliation removes denied cached metrics`() = runTest {
        val store = FakeSnapshotStore().apply {
            snapshot = HealthWidgetSnapshot(
                capturedAtEpochMillis = Instant.parse("2026-08-02T12:00:00Z").toEpochMilli(),
                capturedZoneId = "UTC",
                days = listOf(
                    com.healthmd.widget.model.HealthWidgetDay(
                        localDate = "2026-08-02",
                        steps = 7_000,
                        sleepDurationMinutes = 480.0,
                        averageHeartRateBpm = 70.0,
                    )
                ),
            )
        }
        val repository = HealthWidgetSnapshotRepository(
            FakeWidgetHealthDataSource(emptyList()),
            HealthWidgetSnapshotMapper(),
            store,
        )

        val reconciled = repository.recordFailedAttempt(
            outcome = WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED,
            attemptedAt = Instant.parse("2026-08-02T13:00:00Z"),
            zoneId = ZoneId.of("UTC"),
            readableSelection = HealthConnectWidgetReadSelection(steps = true),
        )

        assertThat(reconciled.days.single().steps).isEqualTo(7_000)
        assertThat(reconciled.days.single().sleepDurationMinutes).isNull()
        assertThat(reconciled.days.single().averageHeartRateBpm).isNull()
    }

    @Test
    fun `failed attempt keeps last-good measurements`() = runTest {
        val store = FakeSnapshotStore()
        val repository = HealthWidgetSnapshotRepository(
            FakeWidgetHealthDataSource(
                listOf(
                    HealthData(
                        LocalDate.parse("2026-08-02"),
                        activity = ActivityData(steps = 7_000),
                    )
                )
            ),
            HealthWidgetSnapshotMapper(),
            store,
        )
        val captured = repository.refresh(
            selection = HealthConnectWidgetReadSelection(steps = true),
            today = LocalDate.parse("2026-08-02"),
            now = Instant.parse("2026-08-02T12:00:00Z"),
            zoneId = ZoneId.of("UTC"),
        )

        val failed = repository.recordFailedAttempt(
            outcome = WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED,
            attemptedAt = Instant.parse("2026-08-02T13:00:00Z"),
            zoneId = ZoneId.of("UTC"),
        )

        assertThat(failed.days).isEqualTo(captured.days)
        assertThat(failed.capturedAtEpochMillis).isEqualTo(captured.capturedAtEpochMillis)
        assertThat(failed.lastAttemptOutcome)
            .isEqualTo(WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED)
    }

    private class FakeSnapshotStore : HealthWidgetSnapshotStore {
        var snapshot: HealthWidgetSnapshot? = null
        override suspend fun load(): HealthWidgetSnapshot? = snapshot
        override suspend fun save(snapshot: HealthWidgetSnapshot) {
            this.snapshot = snapshot
        }
        override suspend fun delete() {
            snapshot = null
        }
    }

    private class FakeWidgetHealthDataSource(
        var records: List<HealthData>,
    ) : WidgetHealthDataSource {
        var lastSelection: HealthConnectWidgetReadSelection? = null
        override suspend fun readRecentDays(
            today: LocalDate,
            selection: HealthConnectWidgetReadSelection,
            dayCount: Int,
        ): List<HealthData> {
            lastSelection = selection
            return records
        }

        override suspend fun isAvailable(): Boolean = true
        override fun isBeforeFirstUnlock(): Boolean = false
    }
}
