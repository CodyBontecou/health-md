package com.healthmd.wear.surface

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.wearable.contract.WearHealthDay
import com.healthmd.wearable.contract.WearHealthSnapshot
import java.time.Instant
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class WearSurfacePolicyTest {
    private val now = Instant.parse("2025-01-02T00:30:00Z").toEpochMilli()

    @Test fun `current day uses captured zone rather than host zone`() {
        val snapshot = WearHealthSnapshot(sequence=1, capturedAtEpochMillis=now, capturedZoneId="America/Los_Angeles", days=listOf(
            WearHealthDay("2025-01-01", steps=12), WearHealthDay("2025-01-02", steps=34)))
        assertThat(snapshot.currentDay(now)?.steps).isEqualTo(12)
    }

    @Test fun `recovery permits yesterday but hides older journal values`() {
        val snapshot = WearHealthSnapshot(
            sequence = 1,
            capturedAtEpochMillis = now,
            capturedZoneId = "UTC",
            days = listOf(
                WearHealthDay("2024-12-31", sleepMinutes = 600.0, hrvRmssdMillis = 99.0),
                WearHealthDay("2025-01-01", sleepMinutes = 480.0),
            ),
        )
        val recovery = snapshot.recoveryDay(now)
        assertThat(recovery?.sleepMinutes).isEqualTo(480.0)
        assertThat(recovery?.hrvRmssdMillis).isNull()

        val oldOnly = snapshot.copy(days = listOf(WearHealthDay("2024-12-31", sleepMinutes = 600.0)))
        assertThat(oldOnly.recoveryDay(now)).isNull()
    }

    @Test fun `tile summaries omit absent values instead of fabricating zero`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val activity = activitySummary(context, WearHealthDay("2025-01-01", exerciseMinutes=7.0))
        val recovery = recoverySummary(context, WearHealthDay("2025-01-01", hrvRmssdMillis=42.0))
        assertThat(activity).contains("7")
        assertThat(activity).doesNotContain("0 steps")
        assertThat(recovery).contains("42")
        assertThat(recovery).doesNotContain("0 hr")
    }
}
