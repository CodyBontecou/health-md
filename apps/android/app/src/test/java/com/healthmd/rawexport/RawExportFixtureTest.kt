package com.healthmd.rawexport

import com.google.common.truth.Truth.assertThat
import java.util.Base64
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

class RawExportFixtureTest {
    @Test fun plannedManualCompletionFixtureDecodesNestedDiscriminator() {
        val text = requireNotNull(javaClass.getResource("/raw-export/v1/planned-manual-completion-record.json")).readText()
        val record = RawJson.codec.decodeFromString(RawRecord.serializer(), text)
        val goal = record.fields.getValue("blocks").jsonArray.single().jsonObject
            .getValue("steps").jsonArray.single().jsonObject
            .getValue("completionGoal").jsonObject
        assertThat(goal.keys).containsExactly("type")
        assertThat(goal.getValue("type").jsonPrimitive.content).isEqualTo("manual_completion")
    }

    @Test fun independentPhrGoldenTypedDecodesExactFhirWithoutPretendingItIsAnSdkRecord() {
        val text = requireNotNull(javaClass.getResource("/raw-export/v1/medical-exact-fhir-record.json")).readText()
        val decoded = RawRecordDecoder.decode(RawJson.codec.parseToJsonElement(text).jsonObject)
        val medical = (decoded.fields as DecodedFields.Medical).payload
        val exact = "{\n  \"resourceType\": \"Immunization\", \"value\": 1.00\n}"
        assertThat(medical.fhirResource.exactJson).isEqualTo(exact)
        assertThat(medical.fhirResource.checksumSha256).isEqualTo("40e265fae33721f33275120890f3f0b791d3578a5177c87eeeddc78bed107bdc")
        assertThat(decoded.metadata).isNull()
        val corrupted = text.replace("40e265fae33721f33275120890f3f0b791d3578a5177c87eeeddc78bed107bdc", "0".repeat(64))
        val failure = runCatching {
            RawRecordDecoder.decode(RawJson.codec.parseToJsonElement(corrupted).jsonObject)
        }.exceptionOrNull() as RawDecodeException
        assertThat(failure.code).isEqualTo("fhir_checksum")
        assertThat(failure.message).doesNotContain(exact)
    }

    @Test fun providerDecoderPreservesExactBytesAndAllowsStrictCharsetFailureOnlyWithNullText() {
        fun providerRecord(bytes: ByteArray, text: String?, endpoint: String = "steps:${"a".repeat(24)}"): RawRecord {
            val checksum = RawJson.sha256(bytes)
            val payload = RawProviderPayload(
                providerId = "fitbit",
                endpointKey = "steps",
                endpointIdentifier = endpoint,
                fetchedAt = RawInstant(10, 7),
                httpStatus = 200,
                contentType = "application/json",
                charset = "UTF-8",
                pageOrdinal = 1,
                responseBytesBase64 = Base64.getEncoder().encodeToString(bytes),
                responseText = text,
                responseSha256 = checksum,
            )
            return RawRecord(
                wireType = "provider_payload",
                nativeIdentity = "",
                recordKind = RawRecordKind.PROVIDER_PAYLOAD,
                source = RawSourceDescriptor("fitbit", RawProviderFidelity.NATIVE_API_PAYLOAD, "steps"),
                fields = JsonObject(emptyMap()),
                providerPayload = payload,
                hash = "",
            ).withCanonicalIdentityAndHash()
        }

        val jsonBytes = "{\"ok\":true}".toByteArray()
        val decoded = RawRecordDecoder.decode(
            RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(providerRecord(jsonBytes, "{\"ok\":true}"))).jsonObject,
        )
        assertThat((decoded.fields as DecodedFields.Provider).payload.exactResponseBytes).isEqualTo(jsonBytes)

        val malformed = byteArrayOf(0xc3.toByte(), 0x28)
        val exactOnly = RawRecordDecoder.decode(
            RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(providerRecord(malformed, null))).jsonObject,
        )
        assertThat((exactOnly.fields as DecodedFields.Provider).payload.exactResponseBytes).isEqualTo(malformed)

        val contradictory = runCatching {
            RawRecordDecoder.decode(
                RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(providerRecord(malformed, "wrong"))).jsonObject,
            )
        }.exceptionOrNull() as RawDecodeException
        assertThat(contradictory.code).isEqualTo("provider_text")

        val invalidEndpoint = runCatching {
            RawRecordDecoder.decode(
                RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(providerRecord(jsonBytes, "{\"ok\":true}", "https://secret/path"))).jsonObject,
            )
        }.exceptionOrNull() as RawDecodeException
        assertThat(invalidEndpoint.code).isEqualTo("endpoint_identifier")
    }

    @Test fun medicalDecoderRejectsContradictoryWrapperIdentifiersWithoutChangingExactFhir() {
        val text = requireNotNull(javaClass.getResource("/raw-export/v1/medical-exact-fhir-record.json")).readText()
        val contradictory = text.replaceFirst("\"dataSourceId\": \"source\"", "\"dataSourceId\": \"different\"")
        val failure = runCatching {
            RawRecordDecoder.decode(RawJson.codec.parseToJsonElement(contradictory).jsonObject)
        }.exceptionOrNull() as RawDecodeException
        assertThat(failure.code).isEqualTo("medical_data_source")
    }

    @Test fun v1FixtureDecodesWithPinnedHonestyCapabilities() {
        val text = requireNotNull(javaClass.getResource("/raw-export/v1/minimal-snapshot.json")).readText()
        val snapshot = RawJson.codec.decodeFromString(RawSnapshotDocument.serializer(), text)
        assertThat(snapshot.header.version).isEqualTo(1)
        assertThat(snapshot.header.capabilities.nonTransactional).isTrue()
        assertThat(snapshot.header.capabilities.preservesSourceUnits).isFalse()
        assertThat(snapshot.header.capabilities.preservesUnknownSdkFields).isFalse()
        assertThat(snapshot.manifest.status).isEqualTo(RawSnapshotStatus.COMPLETE)
    }
}
