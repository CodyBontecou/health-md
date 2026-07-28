package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import java.nio.charset.StandardCharsets
import java.util.UUID
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assume.assumeTrue
import org.junit.Test

class LiveCliInteropTest {
    @Test
    fun pairsAndNegotiatesWithRustListener() {
        val port = System.getenv("HEALTHMD_LIVE_DIRECT_PORT")?.toIntOrNull()
        assumeTrue("Set HEALTHMD_LIVE_DIRECT_PORT to run the live Rust/Kotlin gate.", port != null)
        val code = System.getenv("HEALTHMD_LIVE_PAIRING_CODE") ?: "12345678901234567890"
        val installationId = UUID.randomUUID().toString()
        val connected = DirectClient.connect(
            host = "127.0.0.1",
            port = requireNotNull(port),
            installationId = installationId,
            displayName = "Kotlin live-test Android",
            pairingCode = code,
        )
        connected.channel.use { channel ->
            channel.sendNegotiationHello(installationId)
            val listener = channel.receiveNegotiationHello()
            assertThat(listener.platform).isEqualTo("macos_cli")
            assertThat(listener.protocolVersions).contains(ANDROID_APPLICATION_PROTOCOL_VERSION)
            assertThat(listener.installationId).isEqualTo(connected.listener.installationId)
            val identity = SourceIdentity(
                installationId = installationId,
                displayName = "Kotlin live-test Android",
                appVersion = "test",
            )
            channel.sendV2(
                "source_hello",
                SourceHello.serializer(),
                SourceHello(
                    source = identity,
                    products = listOf(ProductCapability(
                        productId = ProductId.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1,
                        artifactSchema = ArtifactSchema("healthmd.raw-snapshot", 1),
                        formats = listOf(ArtifactFormat.JSON, ArtifactFormat.NDJSON),
                        providers = listOf("health_connect"),
                    )),
                ),
            )
            val statusRequest = channel.receiveV2()
            assertThat(statusRequest.type).isEqualTo("status_request")
            channel.sendV2(
                "status_response",
                SourceStatus.serializer(),
                SourceStatus(
                    source = identity,
                    appActive = true,
                    protectedDataAvailable = true,
                    exportInProgress = false,
                    availableProducts = listOf(ProductId.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1),
                ),
            )

            val exportEnvelope = channel.receiveV2()
            assertThat(exportEnvelope.type).isEqualTo("export_request")
            val request = V2Codec.decodePayload(exportEnvelope, ExportRequest.serializer())
            val fingerprint = V2Codec.requestFingerprint(request)
            val header = DirectJson.json.parseToJsonElement(
                """{"schema":"healthmd.raw-snapshot","version":1,"snapshotId":"0123456789abcdef0123456789abcdef","createdAt":{"epochSecond":"1784764800","nano":0},"request":{"format":"JSON","scope":"ALL_AUTHORIZED_SUPPORTED_DATA","startTime":{"epochSecond":"1784764800","nano":0},"endTime":{"epochSecond":"1784851200","nano":0},"selectedMetricIds":[],"pageSize":1000,"includeExerciseRoutes":false,"calendarZoneId":"UTC"},"capabilities":{"sdkVersion":"test","available":true,"providerId":"health_connect","fidelityLevel":"HEALTH_CONNECT_API_PROJECTED","grantedPermissions":[],"availableFeatures":[],"historicalReadGranted":true,"nonTransactional":true,"preservesSourceUnits":false,"preservesUnknownSdkFields":false}}""",
            )
            val logicalChecksum = DirectJson.sha256Hex(
                "header\u0000".toByteArray(StandardCharsets.US_ASCII) +
                    DirectJson.canonicalBytes(header) + byteArrayOf('\n'.code.toByte()),
            )
            val manifestWithoutChecksums = DirectJson.json.parseToJsonElement(
                """{"schema":"healthmd.raw-snapshot.manifest","version":1,"snapshotId":"0123456789abcdef0123456789abcdef","status":"COMPLETE","completedAt":{"epochSecond":"1784764801","nano":0},"recordCount":0,"issueCount":0,"duplicateCount":0,"identityCollisionCount":0,"typeCounts":[],"typeReports":[],"logicalChecksumSha256":"$logicalChecksum"}""",
            ).jsonObject
            val manifestChecksum = DirectJson.sha256Hex(
                DirectJson.canonicalBytes(manifestWithoutChecksums),
            )
            val rawManifest = JsonObject(
                manifestWithoutChecksums + mapOf(
                    "manifestChecksumSha256" to JsonPrimitive(manifestChecksum),
                    "artifactChecksumSha256" to JsonNull,
                ),
            )
            val artifactBytes = DirectJson.canonicalBytes(JsonObject(mapOf(
                "header" to header,
                "records" to DirectJson.json.parseToJsonElement("[]"),
                "issues" to DirectJson.json.parseToJsonElement("[]"),
                "manifest" to rawManifest,
            )))
            val artifact = kotlin.io.path.createTempFile("healthmd-live-", ".json").toFile().apply {
                deleteOnExit()
                writeBytes(artifactBytes)
            }
            val artifactId = UUID.randomUUID().toString()
            val manifest = ArtifactManifest(
                jobId = request.jobId,
                artifactId = artifactId,
                kind = ArtifactKind.RAW_SNAPSHOT,
                schema = ArtifactSchema("healthmd.raw-snapshot", 1),
                mediaType = "application/vnd.healthmd.raw-snapshot+json",
                byteCount = artifact.length(),
                sha256 = DirectJson.sha256Hex(artifact.readBytes()),
                logicalChecksumSha256 = logicalChecksum,
                snapshotStatus = "COMPLETE",
                providerId = "health_connect",
            )
            val accepted = ExportAccepted(
                jobId = request.jobId,
                acceptedAt = "2026-07-24T10:11:12Z",
                peerBinding = PeerBinding(
                    sourceInstallationId = installationId,
                    destinationInstallationId = connected.listener.installationId,
                ),
                productId = ProductId.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1,
                resolvedRange = ResolvedRange("2026-07-23", "2026-07-23", "UTC"),
                providerId = "health_connect",
                requestFingerprint = fingerprint,
            )
            val plan = TransferPlanBuilder.build(
                accepted = accepted,
                manifests = listOf(manifest),
                artifactFiles = mapOf(artifactId to artifact),
                partitionTargetBytes = MINIMUM_PARTITION_BYTES,
                createdAt = "2026-07-24T10:11:12Z",
            )
            val acknowledgement = ArtifactTransferClient(channel).transfer(plan)
            assertThat(acknowledgement.accepted).isTrue()
        }
        assertThat(connected.listener.reconnectSecret).hasLength(32)
    }
}
