package com.healthmd.wear.sync

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.wearable.contract.WearHealthSnapshot
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class WearSnapshotObservableTest {
    @Test fun `apply mismatch persistence and clear update observable state`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        WearSnapshotRepository.clear(context)
        val snapshot = WearHealthSnapshot(
            sequence = 1L,
            capturedAtEpochMillis = 1L,
            capturedZoneId = "UTC",
            days = emptyList<com.healthmd.wearable.contract.WearHealthDay>(),
        )
        WearSnapshotRepository.apply(context, snapshot)
        WearSnapshotRepository.recordVersionMismatch(context, sequence = 2L)
        assertThat(WearSnapshotRepository.versionMismatch.value).isTrue()
        WearSnapshotRepository.initialize(context)
        assertThat(WearSnapshotRepository.versionMismatch.value).isTrue()
        assertThat(WearSnapshotRepository.snapshots.value?.sequence).isEqualTo(1L)

        assertThat(WearSnapshotRepository.apply(context, snapshot.copy(sequence = 0L)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.OUT_OF_ORDER)
        assertThat(WearSnapshotRepository.versionMismatch.value).isTrue()
        assertThat(WearSnapshotRepository.apply(context, snapshot))
            .isEqualTo(WearSnapshotRepository.ApplyResult.OUT_OF_ORDER)
        assertThat(WearSnapshotRepository.versionMismatch.value).isTrue()
        assertThat(WearSnapshotRepository.apply(context, snapshot.copy(sequence = 3L)))
            .isEqualTo(WearSnapshotRepository.ApplyResult.APPLIED)
        assertThat(WearSnapshotRepository.versionMismatch.value).isFalse()

        WearSnapshotRepository.clear(context)
        assertThat(WearSnapshotRepository.snapshots.value).isNull()
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(WearSnapshotRepository.versionMismatch.value).isFalse()
    }
}
