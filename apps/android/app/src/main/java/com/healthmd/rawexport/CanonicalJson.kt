package com.healthmd.rawexport

import java.io.InputStream
import java.security.MessageDigest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject

object RawJson {
    val codec = Json {
        encodeDefaults = true
        explicitNulls = true
        ignoreUnknownKeys = false
        prettyPrint = false
        classDiscriminator = "kind"
    }

    fun canonical(element: JsonElement): String = buildString { appendCanonical(element) }

    fun canonicalRecord(record: RawRecord): String =
        canonical(codec.encodeToJsonElement(RawRecord.serializer(), record))

    fun recordHash(record: RawRecord): String {
        val withoutHash = codec.encodeToJsonElement(RawRecord.serializer(), record).jsonObject
            .filterKeys { it != "hash" }
        return sha256(canonical(JsonObject(withoutHash)))
    }

    fun manifestHash(manifest: RawSnapshotManifest): String {
        val unsigned = codec.encodeToJsonElement(RawSnapshotManifest.serializer(), manifest).jsonObject
            .filterKeys { it != "manifestChecksumSha256" && it != "artifactChecksumSha256" }
        return sha256(canonical(JsonObject(unsigned)))
    }

    fun sha256(value: String): String = sha256(value.toByteArray(Charsets.UTF_8))

    fun sha256(value: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(value).toHex()

    fun sha256(input: InputStream): String {
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            if (count > 0) digest.update(buffer, 0, count)
        }
        return digest.digest().toHex()
    }

    private fun StringBuilder.appendCanonical(element: JsonElement) {
        when (element) {
            is JsonObject -> {
                append('{')
                element.entries.sortedBy { it.key }.forEachIndexed { index, (key, value) ->
                    if (index > 0) append(',')
                    append(RawJson.codec.encodeToString(JsonPrimitive(key)))
                    append(':')
                    appendCanonical(value)
                }
                append('}')
            }
            is JsonArray -> {
                append('[')
                element.forEachIndexed { index, value ->
                    if (index > 0) append(',')
                    appendCanonical(value)
                }
                append(']')
            }
            JsonNull -> append("null")
            is JsonPrimitive -> append(element.toString())
        }
    }

    private fun ByteArray.toHex(): String = joinToString("") { "%02x".format(it) }
}

fun RawRecord.withCanonicalIdentityAndHash(): RawRecord {
    val identity = when {
        !metadata?.id.isNullOrBlank() -> "hc:${metadata!!.id}"
        !metadata?.clientRecordId.isNullOrBlank() ->
            "client:${metadata!!.dataOriginPackageName}:${metadata.clientRecordId}:${metadata.clientRecordVersion}"
        nativeIdentity.isNotBlank() -> nativeIdentity
        else -> {
            val seed = copy(nativeIdentity = "", hash = "")
            "synthetic:${RawJson.recordHash(seed)}"
        }
    }
    val identified = copy(nativeIdentity = identity, hash = "")
    return identified.copy(hash = RawJson.recordHash(identified))
}
