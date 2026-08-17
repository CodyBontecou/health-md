package com.healthmd.wear

import com.google.common.truth.Truth.assertThat
import com.healthmd.wearable.contract.WearHealthDay
import com.healthmd.wearable.contract.WearHealthSnapshot
import java.time.Instant
import java.time.ZoneId
import org.junit.Test

class DashboardTimePolicyTest {
    @Test fun `current dashboard wakes at stale boundary`() {
        val captured = Instant.parse("2026-08-12T10:00:00Z").toEpochMilli()
        val snapshot = snapshot(captured)
        assertThat(dashboardNextUpdate(snapshot, captured, ZoneId.of("America/Los_Angeles")))
            .isEqualTo(captured + WearHealthSnapshot.CURRENT_MILLIS + 1L)
    }

    @Test fun `stale dashboard wakes at captured-zone midnight before expiry`() {
        val captured = Instant.parse("2026-08-12T10:00:00Z").toEpochMilli()
        val now = Instant.parse("2026-08-12T20:00:00Z").toEpochMilli()
        val snapshot = snapshot(captured)
        assertThat(dashboardNextUpdate(snapshot, now, ZoneId.of("UTC")))
            .isEqualTo(Instant.parse("2026-08-12T21:00:00Z").toEpochMilli())
    }

    @Test fun `midnight boundary wins when expiry is one millisecond later`() {
        val captured = Instant.parse("2026-08-12T00:00:00Z").toEpochMilli()
        val now = captured + WearHealthSnapshot.MAX_DISPLAY_MILLIS - 30_000L
        val snapshot = snapshot(captured)
        assertThat(dashboardNextUpdate(snapshot, now, ZoneId.of("America/Los_Angeles")))
            .isEqualTo(Instant.parse("2026-08-13T00:00:00Z").toEpochMilli())
    }

    private fun snapshot(captured: Long) = WearHealthSnapshot(
        sequence = 1,
        capturedAtEpochMillis = captured,
        capturedZoneId = "UTC",
        days = listOf(WearHealthDay("2026-08-12", steps = 1)),
    )
}
