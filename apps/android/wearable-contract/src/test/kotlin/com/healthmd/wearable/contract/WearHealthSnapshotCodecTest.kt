package com.healthmd.wearable.contract

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class WearHealthSnapshotCodecTest {
    private val now = 1_735_689_600_000L

    @Test fun `checked in fixture decodes and round trips`() {
        val bytes = requireNotNull(javaClass.getResourceAsStream("/fixtures/wear-health-snapshot-v1.json")).readBytes()
        val snapshot = WearHealthSnapshotCodec.decode(bytes, now)
        assertThat(snapshot).isEqualTo(fixture())
        assertThat(WearHealthSnapshotCodec.decode(WearHealthSnapshotCodec.encode(requireNotNull(snapshot)), now)).isEqualTo(snapshot)
    }

    @Test fun `rejects ordering duplicate date invalid zone nonfinite and unknown fields`() {
        val day = fixture().days.single()
        assertThat(fixture().copy(days = listOf(day.copy(localDate = "2025-01-02"), day)).isValid(now)).isFalse()
        assertThat(fixture().copy(days = listOf(day, day)).isValid(now)).isFalse()
        assertThat(fixture().copy(capturedZoneId = "Not/AZone").isValid(now)).isFalse()
        assertThat(fixture().copy(days = listOf(day.copy(moveKilocalories = Double.POSITIVE_INFINITY))).isValid(now)).isFalse()
        assertThat(WearHealthSnapshotCodec.decode("{\"schemaVersion\":1,\"sequence\":1,\"capturedAtEpochMillis\":1,\"capturedZoneId\":\"UTC\",\"days\":[],\"future\":true}".encodeToByteArray(), now)).isNull()
    }

    @Test fun `requires an explicit bounded top level schema version`() {
        val missing = "{\"sequence\":1,\"capturedAtEpochMillis\":1,\"capturedZoneId\":\"UTC\",\"days\":[]}".encodeToByteArray()
        val nested = "{\"schemaVersion\":1,\"sequence\":1,\"capturedAtEpochMillis\":1,\"capturedZoneId\":\"UTC\",\"days\":[],\"future\":{\"schemaVersion\":99}}".encodeToByteArray()
        assertThat(WearHealthSnapshotCodec.decodeResult(missing, now))
            .isEqualTo(WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID))
        assertThat(WearHealthSnapshotCodec.decodeResult(nested, now))
            .isEqualTo(WearSnapshotDecodeResult.Rejected(WearAckReason.INVALID))
        assertThat(WearHealthSnapshotCodec.decodeResult(
            "{\"schemaVersion\":99,\"sequence\":1,\"capturedAtEpochMillis\":1,\"capturedZoneId\":\"UTC\",\"days\":[]}".encodeToByteArray(), now,
        )).isEqualTo(WearSnapshotDecodeResult.Rejected(WearAckReason.VERSION_MISMATCH))
    }

    @Test fun `rejects future skew invalid version and excessive payload`() {
        assertThat(WearHealthSnapshotCodec.decode(WearHealthSnapshotCodec.encode(fixture().copy(
            capturedAtEpochMillis = now + WearHealthSnapshot.MAX_CLOCK_SKEW_MILLIS + 1,
        )), now)).isNull()
        assertThat(WearHealthSnapshotCodec.decode(
            "{\"schemaVersion\":99,\"sequence\":1,\"capturedAtEpochMillis\":1,\"capturedZoneId\":\"UTC\",\"days\":[]}".encodeToByteArray(), now,
        )).isNull()
        assertThat(WearHealthSnapshotCodec.decode(ByteArray(WearHealthSnapshot.MAX_ENCODED_BYTES + 1), now)).isNull()
    }

    @Test fun `rejects out of range health values`() {
        assertThat(fixture().copy(days = listOf(fixture().days.single().copy(bloodOxygenPercent = 101.0))).isValid(now)).isFalse()
        assertThat(fixture().copy(days = listOf(fixture().days.single().copy(hrvRmssdMillis = Double.NaN))).isValid(now)).isFalse()
    }

    @Test fun `ack codec is bounded and idempotent`() {
        val ack = WearSnapshotAck(7, accepted = true, WearAckReason.APPLIED)
        assertThat(WearSnapshotAckCodec.decode(WearSnapshotAckCodec.encode(ack))).isEqualTo(ack)
        assertThat(WearSnapshotAckCodec.decode(ByteArray(1025))).isNull()
        assertThat(WearSnapshotAckCodec.decode("{\"sequence\":-1,\"accepted\":true}".encodeToByteArray())).isNull()
    }

    @Test fun `delete request codec is bounded strict and nonnegative`() {
        val request = WearDeleteRequest(7)
        assertThat(WearDeleteRequestCodec.decode(WearDeleteRequestCodec.encode(request))).isEqualTo(request)
        assertThat(WearDeleteRequestCodec.decode(ByteArray(1025))).isNull()
        assertThat(WearDeleteRequestCodec.decode("{\"clearedThroughSequence\":-1}".encodeToByteArray())).isNull()
        assertThat(WearDeleteRequestCodec.decode("{\"clearedThroughSequence\":7,\"future\":true}".encodeToByteArray())).isNull()
        assertThat(WearDeleteRequestCodec.decode(byteArrayOf(0xC3.toByte(), 0x28))).isNull()
    }

    @Test fun `freshness uses current stale and expired policy`() {
        assertThat(fixture().freshness(now + WearHealthSnapshot.CURRENT_MILLIS)).isEqualTo(WearFreshness.CURRENT)
        assertThat(fixture().freshness(now + WearHealthSnapshot.CURRENT_MILLIS + 1)).isEqualTo(WearFreshness.STALE)
        assertThat(fixture().freshness(now + WearHealthSnapshot.MAX_DISPLAY_MILLIS + 1)).isEqualTo(WearFreshness.EXPIRED)
    }

    private fun fixture() = WearHealthSnapshot(
        sequence = 7,
        capturedAtEpochMillis = now,
        capturedZoneId = "UTC",
        days = listOf(WearHealthDay(
            localDate = "2025-01-01", steps = 8420, moveKilocalories = 410.0,
            exerciseMinutes = 34.0, sleepMinutes = 450.0, restingHeartRateBpm = 58.0,
            averageHeartRateBpm = 72.0, hrvRmssdMillis = 46.0, bloodOxygenPercent = 98.0,
        )),
    )
}
