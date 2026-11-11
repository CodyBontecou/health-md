package com.healthmd.receiverqa

import android.content.Context
import com.healthmd.data.receivercoverage.ReceiverCoverageAtomicFile
import java.nio.file.Files
import kotlinx.serialization.json.*

/** Synthetic-only test evidence, separate from the production plan/admission stores. */
class ReceiverQaState(context: Context) {
    private val directory = context.filesDir.toPath().resolve("receiver-qa")
    private val state = directory.resolve("state.json")
    companion object { private val lock = Any() }
    fun read(): Map<String, String> = synchronized(lock) {
        if (!Files.exists(state)) emptyMap() else Json.parseToJsonElement(String(Files.readAllBytes(state), Charsets.UTF_8)).jsonObject.mapValues { it.value.jsonPrimitive.content }
    }
    fun update(values: Map<String, String>) = synchronized(lock) {
        val value = read() + values
        ReceiverCoverageAtomicFile.write(state, JsonObject(value.toSortedMap().mapValues { JsonPrimitive(it.value) }).toString().toByteArray())
    }
    fun event(kind: String, value: String) = synchronized(lock) {
        Files.createDirectories(directory)
        Files.write(directory.resolve("events.ndjson"), (buildJsonObject { put("kind",kind);put("value",value) }.toString()+"\n").toByteArray(Charsets.UTF_8),
            java.nio.file.StandardOpenOption.CREATE, java.nio.file.StandardOpenOption.APPEND)
    }
    fun events(): List<JsonObject> = synchronized(lock) {
        val file = directory.resolve("events.ndjson")
        if (!Files.exists(file)) emptyList() else Files.readAllLines(file).map { Json.parseToJsonElement(it).jsonObject }
    }
    fun reset() = synchronized(lock) {
        val port = read()["port"]
        Files.deleteIfExists(directory.resolve("events.ndjson")); Files.deleteIfExists(state)
        update(mapOf("capture_gate" to "false", "http_gate" to "false") + (port?.let { mapOf("port" to it) } ?: emptyMap()))
    }
}
