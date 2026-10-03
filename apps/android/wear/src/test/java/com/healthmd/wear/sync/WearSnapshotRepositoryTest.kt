package com.healthmd.wear.sync

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.wearable.contract.WearHealthDay
import com.healthmd.wearable.contract.WearHealthSnapshot
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import java.io.File

@RunWith(RobolectricTestRunner::class)
class WearSnapshotRepositoryTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    @After fun cleanup() { runCatching { WearSnapshotRepository.clear(context) } }

    @Test fun `applies duplicate and rejects out of order without regression`() {
        assertThat(WearSnapshotRepository.apply(context, snapshot(2))).isEqualTo(WearSnapshotRepository.ApplyResult.APPLIED)
        assertThat(WearSnapshotRepository.apply(context, snapshot(2))).isEqualTo(WearSnapshotRepository.ApplyResult.DUPLICATE)
        assertThat(WearSnapshotRepository.apply(context, snapshot(1))).isEqualTo(WearSnapshotRepository.ApplyResult.OUT_OF_ORDER)
        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(2)
    }

    @Test fun `corruption fails closed and reset removes private directory`() {
        WearSnapshotRepository.apply(context, snapshot(2))
        val file = File(context.noBackupFilesDir, "wear-health/snapshot-v1.json")
        file.writeText("not-json")
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.snapshots.value).isNull()
        assertThat(file.exists()).isFalse()
        WearSnapshotRepository.clear(context)
        assertThat(File(context.noBackupFilesDir, "wear-health").exists()).isFalse()
    }

    @Test fun `corrupt aggregate-free cache retains sequence floor and rejects older measurements`() {
        val redacted = WearHealthSnapshot(
            sequence = 10,
            capturedAtEpochMillis = System.currentTimeMillis(),
            capturedZoneId = "UTC",
            days = emptyList(),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
        )
        assertThat(WearSnapshotRepository.apply(context, redacted))
            .isEqualTo(WearSnapshotRepository.ApplyResult.APPLIED)
        File(context.noBackupFilesDir, "wear-health/snapshot-v1.json").writeText("not-json")

        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.apply(context, snapshot(9)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.OUT_OF_ORDER)
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.apply(context, snapshot(11)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.APPLIED)
    }

    @Test fun `cache write failure after floor commit hides old values and preserves ordering`() {
        assertThat(WearSnapshotRepository.apply(context, snapshot(9)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.APPLIED)
        WearSnapshotRepository.writeSnapshotOverride = { _, _ -> error("disk full") }
        val redacted = WearHealthSnapshot(
            sequence = 10,
            capturedAtEpochMillis = System.currentTimeMillis(),
            capturedZoneId = "UTC",
            days = emptyList(),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
        )

        assertThat(WearSnapshotRepository.apply(context, redacted))
            .isEqualTo(WearSnapshotRepository.ApplyResult.FAILED_CLOSED)
        assertThat(WearSnapshotRepository.snapshots.value).isNull()
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.apply(context, snapshot(9)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.OUT_OF_ORDER)
    }

    @Test fun `corrupt last applied floor hides cache and requires explicit clear recovery`() {
        assertThat(WearSnapshotRepository.apply(context, snapshot(8)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.APPLIED)
        File(context.noBackupFilesDir, "wear-health/last-applied-sequence-v1")
            .writeText("not-a-sequence")

        WearSnapshotRepository.reload(context)
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.orderingCorrupt.value).isTrue()
        assertThat(WearSnapshotRepository.apply(context, snapshot(9)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.OUT_OF_ORDER)

        assertThat(WearSnapshotRepository.clearThrough(context, 10))
            .isEqualTo(WearSnapshotRepository.ClearResult(10, deleted = true))
        assertThat(WearSnapshotRepository.orderingCorrupt.value).isFalse()
        assertThat(WearSnapshotRepository.apply(context, snapshot(11)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.APPLIED)
    }

    @Test fun `local clock rollback does not destructively remove accepted cache`() {
        val acceptedAt = System.currentTimeMillis()
        WearSnapshotRepository.apply(context, snapshot(2, capturedAt = acceptedAt))
        val file = File(context.noBackupFilesDir, "wear-health/snapshot-v1.json")
        // Model the wall clock moving backward after ingress by making the already-accepted capture
        // appear beyond today's ingress skew allowance. Stored decoding must remain structural.
        val future = acceptedAt + WearHealthSnapshot.MAX_CLOCK_SKEW_MILLIS + 60_000L
        file.writeText(file.readText().replace(acceptedAt.toString(), future.toString()))

        WearSnapshotRepository.reload(context)

        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(2)
        assertThat(file.exists()).isTrue()
    }

    @Test fun `clear ordering tombstone survives initialize and blocks resurrection`() {
        WearSnapshotRepository.apply(context, snapshot(5))
        assertThat(WearSnapshotRepository.clearThrough(context, 7))
            .isEqualTo(WearSnapshotRepository.ClearResult(7, deleted = true))
        WearSnapshotRepository.initialize(context)
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.apply(context, snapshot(6))).isEqualTo(WearSnapshotRepository.ApplyResult.OUT_OF_ORDER)
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.apply(context, snapshot(8))).isEqualTo(WearSnapshotRepository.ApplyResult.APPLIED)
        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(8)
    }

    @Test fun `delete failure after durable clear hides observable cache and reload stays fail closed`() {
        WearSnapshotRepository.apply(context, snapshot(5))
        val file = File(context.noBackupFilesDir, "wear-health/snapshot-v1.json")
        WearSnapshotRepository.deleteSnapshotOverride = { false }

        val result = WearSnapshotRepository.clearThrough(context, 5)

        assertThat(result).isEqualTo(WearSnapshotRepository.ClearResult(5, deleted = false, barrierCommitted = true))
        assertThat(WearSnapshotRepository.snapshots.value).isNull()
        assertThat(file.exists()).isTrue()
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(file.exists()).isFalse()
    }

    @Test fun `interrupted clear marker hides and cleans pre-clear snapshot`() {
        WearSnapshotRepository.apply(context, snapshot(5))
        File(context.noBackupFilesDir, "wear-health/cleared-through-v1").writeText("5\n")
        WearSnapshotRepository.initialize(context)
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(File(context.noBackupFilesDir, "wear-health/snapshot-v1.json").exists()).isFalse()
    }

    @Test fun `delayed old tombstone cannot delete a newer snapshot`() {
        WearSnapshotRepository.apply(context, snapshot(8))
        assertThat(WearSnapshotRepository.clearThrough(context, 7))
            .isEqualTo(WearSnapshotRepository.ClearResult(8, deleted = false))
        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(8)
    }

    @Test fun `corrupt clear marker hides cache and blocks apply until explicit clear recovers`() {
        WearSnapshotRepository.apply(context, snapshot(8))
        val marker = File(context.noBackupFilesDir, "wear-health/cleared-through-v1")
        marker.writeText("not-a-sequence")

        WearSnapshotRepository.initialize(context)
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.orderingCorrupt.value).isTrue()
        assertThat(File(context.noBackupFilesDir, "wear-health/snapshot-v1.json").exists()).isFalse()
        assertThat(WearSnapshotRepository.apply(context, snapshot(9)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.OUT_OF_ORDER)

        assertThat(WearSnapshotRepository.clearThrough(context, 10))
            .isEqualTo(WearSnapshotRepository.ClearResult(10, deleted = true))
        assertThat(WearSnapshotRepository.orderingCorrupt.value).isFalse()
        assertThat(WearSnapshotRepository.apply(context, snapshot(11)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.APPLIED)
    }

    @Test fun `oversized corrupt mismatch marker hides cache and blocks replacement`() {
        WearSnapshotRepository.apply(context, snapshot(3))
        val marker = File(context.noBackupFilesDir, "wear-health/version-mismatch-v1")
        marker.writeText("x".repeat(33))

        WearSnapshotRepository.reload(context)
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.orderingCorrupt.value).isTrue()
        assertThat(WearSnapshotRepository.versionMismatch.value).isFalse()
        assertThat(WearSnapshotRepository.apply(context, snapshot(4)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.OUT_OF_ORDER)
    }

    private fun snapshot(sequence: Long, capturedAt: Long = System.currentTimeMillis()) = WearHealthSnapshot(
        sequence = sequence, capturedAtEpochMillis = capturedAt,
        capturedZoneId = "UTC", days = listOf(WearHealthDay("2025-01-01", steps = 42)),
    )
}
