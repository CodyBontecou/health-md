package com.healthmd.wear.sync

import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.wearable.contract.WearAckReason
import com.healthmd.wearable.contract.WearHealthSnapshot
import com.healthmd.wearable.contract.WearHealthSnapshotCodec
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.After
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class WearDataLayerDeliveryTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()

    @After fun cleanup() { WearSnapshotRepository.clear(context) }

    @Test fun `valid duplicate and out-of-order deliveries return correlated acknowledgements`() {
        val applied = applyWearSnapshotPayload(context, 2, encoded(2))
        assertThat(applied.ack?.reason).isEqualTo(WearAckReason.APPLIED)
        assertThat(applied.invalidateSurfaces).isTrue()

        val duplicate = applyWearSnapshotPayload(context, 2, encoded(2))
        assertThat(duplicate.ack?.reason).isEqualTo(WearAckReason.DUPLICATE)
        assertThat(duplicate.ack?.accepted).isTrue()
        assertThat(duplicate.invalidateSurfaces).isFalse()

        val old = applyWearSnapshotPayload(context, 1, encoded(1))
        assertThat(old.ack?.reason).isEqualTo(WearAckReason.OUT_OF_ORDER)
        assertThat(old.ack?.accepted).isFalse()
        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(2)
    }

    @Test fun `declared sequence mismatch and malformed data are rejected`() {
        val mismatch = applyWearSnapshotPayload(context, 7, encoded(8))
        assertThat(mismatch.ack?.sequence).isEqualTo(7)
        assertThat(mismatch.ack?.reason).isEqualTo(WearAckReason.INVALID)
        assertThat(WearSnapshotRepository.load(context)).isNull()

        val malformed = applyWearSnapshotPayload(context, 9, "not-json".encodeToByteArray())
        assertThat(malformed.ack?.reason).isEqualTo(WearAckReason.INVALID)
    }

    @Test fun `post-floor cache write failure invalidates surfaces and fails closed`() {
        assertThat(applyWearSnapshotPayload(context, 9, encoded(9)).ack?.reason)
            .isEqualTo(WearAckReason.APPLIED)
        WearSnapshotRepository.writeSnapshotOverride = { _, _ -> error("disk full") }

        val failed = applyWearSnapshotPayload(context, 10, encoded(10))

        assertThat(failed.ack?.accepted).isFalse()
        assertThat(failed.ack?.reason).isEqualTo(WearAckReason.INVALID)
        assertThat(failed.invalidateSurfaces).isTrue()
        assertThat(WearSnapshotRepository.snapshots.value).isNull()
        assertThat(WearSnapshotRepository.load(context)).isNull()
        assertThat(applyWearSnapshotPayload(context, 9, encoded(9)).ack?.reason)
            .isEqualTo(WearAckReason.OUT_OF_ORDER)
    }

    @Test fun `future schema ordering marker rejects older compatible delivery until newer recovery`() {
        applyWearSnapshotPayload(context, 2, encoded(2))
        val json = Json.parseToJsonElement(encoded(10).decodeToString()).jsonObject.toMutableMap()
        json["schemaVersion"] = kotlinx.serialization.json.JsonPrimitive(99)
        val future = kotlinx.serialization.json.JsonObject(json).toString().encodeToByteArray()

        val rejected = applyWearSnapshotPayload(context, 10, future)
        assertThat(rejected.ack?.reason).isEqualTo(WearAckReason.VERSION_MISMATCH)
        assertThat(rejected.invalidateSurfaces).isTrue()
        assertThat(WearSnapshotRepository.versionMismatch.value).isTrue()

        val delayed = applyWearSnapshotPayload(context, 9, encoded(9))
        assertThat(delayed.ack?.reason).isEqualTo(WearAckReason.OUT_OF_ORDER)
        assertThat(WearSnapshotRepository.versionMismatch.value).isTrue()
        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(2)

        applyWearSnapshotPayload(context, 11, encoded(11))
        assertThat(WearSnapshotRepository.versionMismatch.value).isFalse()
        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(11)
    }

    @Test fun `durable tombstone payload decodes to the same deletion ordering barrier`() {
        val request = com.healthmd.wearable.contract.WearDeleteRequestCodec.decode(
            com.healthmd.wearable.contract.WearDeleteRequestCodec.encode(
                com.healthmd.wearable.contract.WearDeleteRequest(11),
            ),
        )
        val deleted = deleteLocalWearData(context, requireNotNull(request).clearedThroughSequence)
        assertThat(deleted.ack?.sequence).isEqualTo(11)
        assertThat(deleted.ack?.reason).isEqualTo(WearAckReason.DELETED)
    }

    @Test fun `physical delete failure still invalidates surfaces after durable clear barrier`() {
        applyWearSnapshotPayload(context, 5, encoded(5))
        WearSnapshotRepository.deleteSnapshotOverride = { false }

        val outcome = deleteLocalWearData(context, clearedThroughSequence = 5)

        assertThat(outcome.ack?.accepted).isFalse()
        assertThat(outcome.ack?.reason).isEqualTo(WearAckReason.INVALID)
        assertThat(outcome.invalidateSurfaces).isTrue()
        assertThat(WearSnapshotRepository.snapshots.value).isNull()
        assertThat(WearSnapshotRepository.load(context)).isNull()
    }

    @Test fun `delayed durable tombstone cannot erase later explicit sync`() {
        applyWearSnapshotPayload(context, 12, encoded(12))
        val delayed = deleteLocalWearData(context, clearedThroughSequence = 11)
        assertThat(delayed.ack?.accepted).isFalse()
        assertThat(delayed.ack?.reason).isEqualTo(WearAckReason.OUT_OF_ORDER)
        assertThat(delayed.ack?.sequence).isEqualTo(12)
        assertThat(delayed.invalidateSurfaces).isFalse()
        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(12)
    }

    @Test fun `delayed mismatch older than compatible cache is rejected without stale guidance`() {
        applyWearSnapshotPayload(context, 12, encoded(12))
        val json = Json.parseToJsonElement(encoded(10).decodeToString()).jsonObject.toMutableMap()
        json["schemaVersion"] = kotlinx.serialization.json.JsonPrimitive(99)
        val future = kotlinx.serialization.json.JsonObject(json).toString().encodeToByteArray()
        val delayed = applyWearSnapshotPayload(context, 10, future)
        assertThat(delayed.ack?.reason).isEqualTo(WearAckReason.OUT_OF_ORDER)
        assertThat(delayed.invalidateSurfaces).isFalse()
        assertThat(WearSnapshotRepository.versionMismatch.value).isFalse()
        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(12)
    }

    @Test fun `clear preserves newer mismatch floor until compatible recovery`() {
        val json = Json.parseToJsonElement(encoded(10).decodeToString()).jsonObject.toMutableMap()
        json["schemaVersion"] = kotlinx.serialization.json.JsonPrimitive(99)
        val future = kotlinx.serialization.json.JsonObject(json).toString().encodeToByteArray()
        applyWearSnapshotPayload(context, 10, future)

        val deleted = deleteLocalWearData(context, clearedThroughSequence = 2)
        assertThat(deleted.ack?.accepted).isTrue()
        assertThat(deleted.ack?.sequence).isEqualTo(10)
        assertThat(WearSnapshotRepository.versionMismatch.value).isTrue()
        assertThat(applyWearSnapshotPayload(context, 9, encoded(9)).ack?.reason).isEqualTo(WearAckReason.OUT_OF_ORDER)
        assertThat(WearSnapshotRepository.versionMismatch.value).isTrue()
        assertThat(applyWearSnapshotPayload(context, 11, encoded(11)).ack?.reason).isEqualTo(WearAckReason.APPLIED)
        assertThat(WearSnapshotRepository.versionMismatch.value).isFalse()
    }

    @Test fun `delete tombstone rejects delayed pre-clear payload and permits later sync`() {
        applyWearSnapshotPayload(context, 11, encoded(11))
        val deleted = deleteLocalWearData(context, clearedThroughSequence = 11)
        assertThat(deleted.ack?.sequence).isEqualTo(11)
        assertThat(deleted.ack?.accepted).isTrue()
        assertThat(deleted.ack?.reason).isEqualTo(WearAckReason.DELETED)
        assertThat(deleted.invalidateSurfaces).isTrue()
        assertThat(WearSnapshotRepository.load(context)).isNull()

        val delayed = applyWearSnapshotPayload(context, 11, encoded(11))
        assertThat(delayed.ack?.reason).isEqualTo(WearAckReason.OUT_OF_ORDER)
        assertThat(WearSnapshotRepository.load(context)).isNull()

        val later = applyWearSnapshotPayload(context, 12, encoded(12))
        assertThat(later.ack?.reason).isEqualTo(WearAckReason.APPLIED)
        assertThat(WearSnapshotRepository.load(context)?.sequence).isEqualTo(12)
    }

    private fun encoded(sequence: Long) = WearHealthSnapshotCodec.encode(
        WearHealthSnapshot(
            sequence = sequence,
            capturedAtEpochMillis = System.currentTimeMillis(),
            capturedZoneId = "UTC",
            days = emptyList(),
        ),
    )
}
