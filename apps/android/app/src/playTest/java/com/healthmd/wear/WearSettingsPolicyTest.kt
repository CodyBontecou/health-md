package com.healthmd.wear

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class WearSettingsPolicyTest {
    @Test fun `multi-watch delivery is partial until every targeted watch acknowledges`() {
        val base = WearPhoneSyncStatus(
            result = WearPhoneSyncResult.SENT,
            sourceState = null,
            deliveryState = WearDeliveryState.REACHABLE,
            lastAttemptEpochMillis = null,
            lastSentEpochMillis = null,
            sentSequence = 7,
            acknowledgedSequence = 7,
            acknowledged = true,
            ackReason = null,
            targetedWatchCount = 2,
            acknowledgedWatchCount = 1,
        )
        assertThat(wearDeliveryIsPartial(base)).isTrue()
        assertThat(wearDeliveryIsPartial(base.copy(acknowledgedWatchCount = 2))).isFalse()
        assertThat(wearDeliveryIsPartial(base.copy(deliveryState = WearDeliveryState.QUEUED))).isFalse()
        assertThat(formatWatchDeliveryProgress(1, 2)).isEqualTo("1/2")
    }
}
