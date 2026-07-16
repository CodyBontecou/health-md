package com.healthmd.rawexport

import androidx.health.connect.client.feature.ExperimentalPersonalHealthRecordApi
import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Metadata
import com.google.common.truth.Truth.assertThat
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkClass
import java.time.Instant
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

@OptIn(ExperimentalPersonalHealthRecordApi::class)
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
        assertThat(records.map { it.rangeBehavior }.all { it == RawRangeBehavior.INSTANT || it == RawRangeBehavior.OVERLAP }).isTrue()
        assertThat(RawExportTypeCatalog.definitions).hasSize(54)
        assertThat(RawExportTypeCatalog.definitions.map { it.typeKey }).containsNoDuplicates()
    }

    @Test fun everyInstantiableCatalogClassTraversesTemporalAndFieldsDispatch() {
        val failures = mutableListOf<String>()
        HealthConnectRecordCatalog.records.forEach { descriptor ->
            runCatching {
                val native = mockkClass(descriptor.recordClass, relaxed = true)
                every { native.metadata } returns Metadata.manualEntry()
                when (descriptor.rangeBehavior) {
                    RawRangeBehavior.INSTANT -> {
                        every { native getProperty "time" } returns Instant.ofEpochSecond(10, 123)
                        every { native getProperty "zoneOffset" } returns null
                    }
                    RawRangeBehavior.OVERLAP -> {
                        every { native getProperty "startTime" } returns Instant.ofEpochSecond(10, 123)
                        every { native getProperty "endTime" } returns Instant.ofEpochSecond(20, 456)
                        every { native getProperty "startZoneOffset" } returns null
                        every { native getProperty "endZoneOffset" } returns null
                    }
                    RawRangeBehavior.UNBOUNDED_NON_TEMPORAL -> error("Catalog records must be temporal")
                }
                if (native is ExerciseSessionRecord) {
                    every { native.exerciseRouteResult } returns ExerciseRouteResult.NoData()
                }
                val mapped = descriptor.mapUntyped(native)
                checkNotNull(mapped)
                check(mapped.wireType == descriptor.wireType)
                check(mapped.hash.length == 64)
            }.onFailure { failures += "${descriptor.wireType}: ${it::class.simpleName}: ${it.message}" }
        }
        assertThat(failures).isEmpty()
    }

    @Test fun sleepSessionHasExplicitIntervalTemporalDispatch() {
        val record = SleepSessionRecord(
            startTime = Instant.ofEpochSecond(10, 1),
            startZoneOffset = null,
            endTime = Instant.ofEpochSecond(20, 2),
            endZoneOffset = null,
            metadata = Metadata.manualEntry(),
            title = null,
            notes = null,
            stages = listOf(SleepSessionRecord.Stage(Instant.ofEpochSecond(11), Instant.ofEpochSecond(12), SleepSessionRecord.STAGE_TYPE_DEEP)),
        )
        val mapped = RawHealthConnectMapper.map(record, "sleep_session")
        assertThat(mapped.startTime).isEqualTo(RawInstant(10, 1))
        assertThat(mapped.endTime).isEqualTo(RawInstant(20, 2))
        assertThat(mapped.fields.getValue("stages").jsonArray).hasSize(1)
    }

    @Test fun medicalResourcePreservesExactFhirAndAllowsMissingSource() {
        val exact = "{\n  \"resourceType\": \"Immunization\", \"value\": 1.00\n}"
        val resourceId = mockk<MedicalResourceId> {
            every { dataSourceId } returns "source"
            every { fhirResourceType } returns FhirResource.FHIR_RESOURCE_TYPE_IMMUNIZATION
            every { fhirResourceId } returns "fhir-id"
        }
        val version = mockk<FhirVersion> {
            every { major } returns 4
            every { minor } returns 0
            every { patch } returns 1
        }
        val fhir = mockk<FhirResource> {
            every { type } returns FhirResource.FHIR_RESOURCE_TYPE_IMMUNIZATION
            every { id } returns "fhir-id"
            every { data } returns exact
        }
        val resource = mockk<MedicalResource> {
            every { type } returns MedicalResource.MEDICAL_RESOURCE_TYPE_VACCINES
            every { id } returns resourceId
            every { dataSourceId } returns "source"
            every { fhirVersion } returns version
            every { fhirResource } returns fhir
        }
        val mapped = RawMedicalResourceMapper.map(resource, null)
        assertThat(mapped.fields.getValue("source").toString()).isEqualTo("null")
        assertThat(mapped.fields.getValue("fhirResource").jsonObject.getValue("fhirResourceJson").jsonPrimitive.content).isEqualTo(exact)
        assertThat(mapped.fields.getValue("fhirResource").jsonObject.getValue("checksumSha256").jsonPrimitive.content)
            .isEqualTo(RawJson.sha256(exact.toByteArray()))
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
