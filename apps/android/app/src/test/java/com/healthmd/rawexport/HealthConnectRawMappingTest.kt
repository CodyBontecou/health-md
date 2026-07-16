package com.healthmd.rawexport

import androidx.health.connect.client.records.HeartRateRecord
import androidx.health.connect.client.records.metadata.Metadata
import com.google.common.truth.Truth.assertThat
import java.time.Instant
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class HealthConnectRawMappingTest {
    @Test fun catalogHasMapperPermissionMetricsAndUniqueWireTypeForEveryEntry() {
        val records = HealthConnectRecordCatalog.records
        assertThat(records).hasSize(42)
        assertThat(records.map { it.recordClass }).containsNoDuplicates()
        assertThat(records.map { it.wireType }).containsNoDuplicates()
        assertThat(records.all { it.readPermission.isNotBlank() }).isTrue()
        assertThat(records.all { it.metricIds.isNotEmpty() }).isTrue()
        assertThat(records.all { it.mapper != null }).isTrue()
        assertThat(HealthConnectRecordCatalog.selected(setOf("running_power")).map { it.wireType })
            .containsAtLeast("exercise_session", "power")
    }

    @Test fun heartRateMappingPreservesNanosNullOffsetsSamplesAndDeterministicIdentity() {
        val start = Instant.ofEpochSecond(100, 123_456_789)
        val end = Instant.ofEpochSecond(101, 987_654_321)
        val record = HeartRateRecord(
            startTime = start,
            startZoneOffset = null,
            endTime = end,
            endZoneOffset = null,
            samples = listOf(
                HeartRateRecord.Sample(Instant.ofEpochSecond(100, 999), 61),
                HeartRateRecord.Sample(Instant.ofEpochSecond(100, 12), 60),
            ),
            metadata = Metadata.manualEntry(clientRecordId = "client-heart", clientRecordVersion = 4),
        )
        val mapped = RawHealthConnectMapper.map(record, "heart_rate")
        assertThat(mapped.startTime).isEqualTo(RawInstant(100, 123_456_789))
        assertThat(mapped.endTime).isEqualTo(RawInstant(101, 987_654_321))
        assertThat(mapped.startZoneOffsetSeconds).isNull()
        assertThat(mapped.endZoneOffsetSeconds).isNull()
        assertThat(mapped.nativeIdentity).isEqualTo("client::client-heart:4")
        assertThat(mapped.hash).hasLength(64)
        val samples = mapped.fields.getValue("samples").jsonArray
        assertThat(samples[0].jsonObject.getValue("beatsPerMinute").jsonPrimitive.content.toLong()).isEqualTo(60)
        assertThat(samples[1].jsonObject.getValue("beatsPerMinute").jsonPrimitive.content.toLong()).isEqualTo(61)
        assertThat(RawJson.canonicalRecord(mapped)).doesNotContain("HeartRateRecord(")
    }
}
