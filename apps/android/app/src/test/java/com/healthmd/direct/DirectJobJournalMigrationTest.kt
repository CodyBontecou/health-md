package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.ExportAccepted
import com.healthmd.direct.protocol.PeerBinding
import com.healthmd.direct.protocol.PreparedTransfer
import com.healthmd.direct.protocol.ProductId
import com.healthmd.direct.protocol.ResolvedRange
import com.healthmd.direct.protocol.TransferSession
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.testing.syntheticExportEnginePin
import java.util.UUID
import kotlinx.serialization.SerializationException
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertThrows
import org.junit.Test

class DirectJobJournalMigrationTest {
    private val json = Json {
        encodeDefaults = true
        explicitNulls = true
        ignoreUnknownKeys = false
    }

    @Test
    fun v1WithoutVersionOrPinDecodesAsLegacy() {
        val current = DirectJobJournal(
            requestFingerprint = "request-fingerprint",
            expiresAt = "2027-01-16T00:00:00Z",
            transfer = transfer(),
        )
        val currentObject = json.parseToJsonElement(json.encodeToString(current)).jsonObject
        val oldJson = JsonObject(currentObject - "version" - "enginePin" - "protocolPin").toString()

        val decoded = json.decodeFromString<DirectJobJournal>(oldJson)

        assertThat(decoded.version).isEqualTo(DirectJobJournal.LEGACY_VERSION)
        assertThat(decoded.enginePin).isNull()
        assertThat(decoded.protocolPin).isNull()
        assertThat(decoded.transfer).isEqualTo(current.transfer)

        val unexpectedPinWithoutVersion = json.parseToJsonElement(
            json.encodeToString(current.copy(enginePin = syntheticExportEnginePin())),
        ).jsonObject.let { JsonObject(it - "version") }.toString()
        assertThat(
            json.decodeFromString<DirectJobJournal>(unexpectedPinWithoutVersion).enginePin,
        ).isNull()
    }

    @Test
    fun v3RoundTripRetainsExactPinsAndDoesNotAlterTransferBytes() {
        val pin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val protocolPin = protocolPin(AndroidDirectProtocolEngineMode.rust)
        val journal = DirectJobJournal(
            requestFingerprint = "request-fingerprint",
            expiresAt = "2027-01-16T00:00:00Z",
            transfer = transfer(),
            enginePin = pin,
            protocolPin = protocolPin,
        )

        val encoded = json.encodeToString(journal)
        val decoded = json.decodeFromString<DirectJobJournal>(encoded)

        assertThat(decoded.version).isEqualTo(DirectJobJournal.CURRENT_VERSION)
        assertThat(decoded.enginePin).isEqualTo(pin)
        assertThat(decoded.protocolPin).isEqualTo(protocolPin)
        assertThat(decoded.transfer).isEqualTo(journal.transfer)

        val v2 = json.parseToJsonElement(encoded).jsonObject.toMutableMap().apply {
            put("version", kotlinx.serialization.json.JsonPrimitive(DirectJobJournal.EXPORT_PIN_VERSION))
        }.let(::JsonObject).toString()
        assertThat(json.decodeFromString<DirectJobJournal>(v2).protocolPin).isNull()
    }

    @Test
    fun unknownJournalPinAndPinMutationAreRejected() {
        val pendingPin = syntheticExportEnginePin(mode = ExportEngineMode.shadow)
        val journal = DirectJobJournal(
            requestFingerprint = "request-fingerprint",
            expiresAt = "2027-01-16T00:00:00Z",
            transfer = transfer(),
            enginePin = pendingPin,
        )
        val unknown = json.encodeToString(journal)
            .replace("\"engine\":\"shadow\"", "\"engine\":\"future\"")

        assertThrows(SerializationException::class.java) {
            json.decodeFromString<DirectJobJournal>(unknown)
        }
        assertThrows(IllegalArgumentException::class.java) {
            requireDirectPinContinuity(
                pendingPin = pendingPin,
                journalPin = syntheticExportEnginePin(mode = ExportEngineMode.rust),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            requireDirectProtocolPinContinuity(
                pendingPin = protocolPin(AndroidDirectProtocolEngineMode.shadow),
                journalPin = protocolPin(AndroidDirectProtocolEngineMode.rust),
            )
        }
        assertThrows(IllegalArgumentException::class.java) {
            DirectJobJournal(
                requestFingerprint = "request-fingerprint",
                expiresAt = "2027-01-16T00:00:00Z",
                transfer = transfer(timeZoneId = "UTC"),
                enginePin = pendingPin,
            )
        }
    }

    private fun protocolPin(mode: AndroidDirectProtocolEngineMode) = AndroidDirectProtocolPin(
        engine = mode,
        coreApiVersion = 4u,
        protocolApiRevision = 1u,
        androidApplicationProtocolVersion = 2u,
        transferProtocolVersion = 1u,
        coreCrateVersion = "0.1.0-test",
        coreSourceRevision = "test-revision",
    )

    private fun transfer(timeZoneId: String = "America/Los_Angeles"): PreparedTransfer {
        val jobId = UUID.fromString("10000000-0000-4000-8000-000000000001").toString()
        val binding = PeerBinding(
            sourceInstallationId = "20000000-0000-4000-8000-000000000002",
            destinationInstallationId = "30000000-0000-4000-8000-000000000003",
        )
        val accepted = ExportAccepted(
            jobId = jobId,
            acceptedAt = "2027-01-15T00:00:00Z",
            peerBinding = binding,
            productId = ProductId.GENERATED_FILES_V1,
            resolvedRange = ResolvedRange(
                startDate = "2027-01-14",
                endDate = "2027-01-14",
                timeZoneId = timeZoneId,
            ),
            requestFingerprint = "request-fingerprint",
        )
        return PreparedTransfer(
            accepted = accepted,
            session = TransferSession(
                sessionId = "40000000-0000-4000-8000-000000000004",
                jobId = jobId,
                requestFingerprint = "request-fingerprint",
                peerBinding = binding,
                partitionTargetBytes = 1_048_576,
                createdAt = "2027-01-15T00:00:00Z",
            ),
            manifests = emptyList(),
            partitions = emptyList(),
            artifactPaths = emptyMap(),
        )
    }
}
