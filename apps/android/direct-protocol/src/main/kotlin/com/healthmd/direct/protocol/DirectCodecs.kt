package com.healthmd.direct.protocol

import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.util.Base64
import kotlinx.serialization.DeserializationStrategy
import kotlinx.serialization.SerializationStrategy
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

object DirectJson {
    val json = Json {
        encodeDefaults = true
        explicitNulls = false
        ignoreUnknownKeys = false
    }

    fun canonicalBytes(value: JsonElement): ByteArray =
        canonicalString(value).toByteArray(StandardCharsets.UTF_8)

    fun canonicalString(value: JsonElement): String = when (value) {
        is JsonObject -> value.entries
            .sortedWith { left, right -> compareCodePoints(left.key, right.key) }
            .joinToString(prefix = "{", postfix = "}", separator = ",") { (key, child) ->
                "${json.encodeToString(key)}:${canonicalString(child)}"
            }
        is JsonArray -> value.joinToString(prefix = "[", postfix = "]", separator = ",") {
            canonicalString(it)
        }
        is JsonPrimitive -> value.toString()
        JsonNull -> "null"
    }

    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun compareCodePoints(left: String, right: String): Int {
        val leftPoints = left.codePoints().toArray()
        val rightPoints = right.codePoints().toArray()
        val shared = minOf(leftPoints.size, rightPoints.size)
        for (index in 0 until shared) {
            if (leftPoints[index] != rightPoints[index]) {
                return leftPoints[index].compareTo(rightPoints[index])
            }
        }
        return leftPoints.size.compareTo(rightPoints.size)
    }
}

data class ReceivedEnvelope(
    val type: String,
    val payload: JsonObject,
)

object V2Codec {
    fun <T> encode(type: String, serializer: SerializationStrategy<T>, payload: T): ByteArray {
        val root = buildJsonObject {
            put("protocol_version", ANDROID_APPLICATION_PROTOCOL_VERSION)
            put("type", type)
            put("payload", DirectJson.json.encodeToJsonElement(serializer, payload))
        }
        return DirectJson.canonicalBytes(root)
    }

    fun decode(bytes: ByteArray): ReceivedEnvelope {
        val root = DirectJson.json.parseToJsonElement(bytes.toString(StandardCharsets.UTF_8)).jsonObject
        require(root.keys == setOf("protocol_version", "type", "payload")) {
            "Malformed direct protocol envelope."
        }
        require(root.getValue("protocol_version").jsonPrimitive.content.toInt() == ANDROID_APPLICATION_PROTOCOL_VERSION) {
            "Unsupported direct application protocol version."
        }
        return ReceivedEnvelope(
            type = root.getValue("type").jsonPrimitive.content,
            payload = root.getValue("payload").jsonObject,
        )
    }

    fun <T> decodePayload(envelope: ReceivedEnvelope, deserializer: DeserializationStrategy<T>): T =
        DirectJson.json.decodeFromJsonElement(deserializer, envelope.payload)

    fun requestFingerprint(request: ExportRequest): String = DirectJson.sha256Hex(
        DirectJson.canonicalBytes(DirectJson.json.encodeToJsonElement(ExportRequest.serializer(), request)),
    )

    fun exactDateSelection(startDate: String, endDate: String): JsonObject = buildJsonObject {
        put("type", "exact")
        put("start_date", startDate)
        put("end_date", endDate)
    }

    fun allAvailableDateSelection(): JsonObject = buildJsonObject {
        put("type", "all_available")
    }

    fun rawSnapshotProduct(
        providerId: String,
        format: ArtifactFormat,
        selectedMetricIds: List<String>?,
        includeExerciseRoutes: Boolean,
    ): JsonObject = buildJsonObject {
        put("product_id", "android_provider_native_snapshot_v1")
        put("provider_id", providerId)
        put("format", when (format) {
            ArtifactFormat.JSON -> "json"
            ArtifactFormat.NDJSON -> "ndjson"
            else -> error("Raw snapshots support JSON or NDJSON only.")
        })
        put("scope", if (selectedMetricIds == null) {
            buildJsonObject { put("type", "all_authorized_supported_data") }
        } else {
            buildJsonObject {
                put("type", "selected_record_types")
                put("selected_metric_ids", JsonArray(selectedMetricIds.sorted().map(::JsonPrimitive)))
            }
        })
        put("include_exercise_routes", includeExerciseRoutes)
    }

    fun generatedFilesProduct(settingsPolicy: SettingsPolicy): JsonObject = buildJsonObject {
        put("product_id", "generated_files_v1")
        put("settings_policy", when (settingsPolicy) {
            SettingsPolicy.REQUESTED_SCOPE -> "requested_scope"
            SettingsPolicy.SAVED_DEVICE_SETTINGS -> "saved_device_settings"
        })
    }
}

data class PairingRequest(
    val protocolVersion: Int,
    val deviceName: String,
    val clientPublicKey: ByteArray,
    val clientNonce: ByteArray,
    val codeVerifier: ByteArray,
    val clientInstallationId: String,
    val trustedVerifier: ByteArray?,
)

data class PairingResponse(
    val protocolVersion: Int,
    val listenerName: String,
    val serverPublicKey: ByteArray,
    val serverNonce: ByteArray,
    val listenerInstallationId: String,
    val authenticationVerifier: ByteArray,
    val sealedReconnectSecret: CryptoFrame,
)

object LegacyCodec {
    private val base64Encoder = Base64.getEncoder()
    private val base64Decoder = Base64.getDecoder()

    fun pairingRequest(request: PairingRequest): ByteArray {
        val payload = buildJsonObject {
            put("protocolVersion", request.protocolVersion)
            put("deviceName", request.deviceName)
            put("clientPublicKey", base64Encoder.encodeToString(request.clientPublicKey))
            put("clientNonce", base64Encoder.encodeToString(request.clientNonce))
            put("codeVerifier", base64Encoder.encodeToString(request.codeVerifier))
            put("clientInstallationID", request.clientInstallationId.uppercase())
            request.trustedVerifier?.let {
                put("trustedVerifier", base64Encoder.encodeToString(it))
            }
        }
        return DirectJson.canonicalBytes(buildJsonObject {
            put("pairingRequest", buildJsonObject { put("_0", payload) })
        })
    }

    fun pairingResponse(bytes: ByteArray): PairingResponse {
        val root = parse(bytes)
        root["pairingRejected"]?.jsonObject?.get("_0")?.jsonObject?.let { rejection ->
            error(rejection["reason"]?.jsonPrimitive?.content ?: "Pairing was rejected.")
        }
        val payload = root.getValue("pairingResponse").jsonObject.getValue("_0").jsonObject
        val sealed = payload.getValue("sealedReconnectSecret").jsonObject
        return PairingResponse(
            protocolVersion = payload.getValue("protocolVersion").jsonPrimitive.content.toInt(),
            listenerName = payload.getValue("macName").jsonPrimitive.content,
            serverPublicKey = base64Decoder.decode(payload.getValue("serverPublicKey").jsonPrimitive.content),
            serverNonce = base64Decoder.decode(payload.getValue("serverNonce").jsonPrimitive.content),
            listenerInstallationId = payload.getValue("macInstallationID").jsonPrimitive.content.lowercase(),
            authenticationVerifier = base64Decoder.decode(
                payload.getValue("authenticationVerifier").jsonPrimitive.content,
            ),
            sealedReconnectSecret = CryptoFrame(
                nonce = base64Decoder.decode(sealed.getValue("nonce").jsonPrimitive.content),
                ciphertext = base64Decoder.decode(sealed.getValue("ciphertext").jsonPrimitive.content),
                tag = base64Decoder.decode(sealed.getValue("tag").jsonPrimitive.content),
            ),
        )
    }

    fun encrypted(frame: CryptoFrame): ByteArray = DirectJson.canonicalBytes(buildJsonObject {
        put("encrypted", buildJsonObject {
            put("_0", buildJsonObject {
                put("nonce", base64Encoder.encodeToString(frame.nonce))
                put("ciphertext", base64Encoder.encodeToString(frame.ciphertext))
                put("tag", base64Encoder.encodeToString(frame.tag))
            })
        })
    })

    fun encryptedFrame(bytes: ByteArray): CryptoFrame {
        val payload = parse(bytes).getValue("encrypted").jsonObject.getValue("_0").jsonObject
        return CryptoFrame(
            nonce = base64Decoder.decode(payload.getValue("nonce").jsonPrimitive.content),
            ciphertext = base64Decoder.decode(payload.getValue("ciphertext").jsonPrimitive.content),
            tag = base64Decoder.decode(payload.getValue("tag").jsonPrimitive.content),
        )
    }

    fun hello(hello: NegotiationHello): ByteArray = DirectJson.canonicalBytes(buildJsonObject {
        put("hello", buildJsonObject {
            put("_0", DirectJson.json.encodeToJsonElement(NegotiationHello.serializer(), hello))
        })
    })

    fun parseHello(bytes: ByteArray): NegotiationHello {
        val payload = parse(bytes).getValue("hello").jsonObject.getValue("_0")
        val decoded = DirectJson.json.decodeFromJsonElement(NegotiationHello.serializer(), payload)
        return decoded.copy(installationId = decoded.installationId.lowercase())
    }

    private fun parse(bytes: ByteArray): JsonObject =
        DirectJson.json.parseToJsonElement(bytes.toString(StandardCharsets.UTF_8)).jsonObject
}
