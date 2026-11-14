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
        val file = directory.resolve("events.ndjson")
        val previous = if (Files.exists(file)) Files.readAllBytes(file) else byteArrayOf()
        val event = (buildJsonObject { put("kind",kind);put("value",value) }.toString()+"\n").toByteArray(Charsets.UTF_8)
        check(previous.size + event.size <= 256 * 1024) { "Synthetic evidence cap exceeded" }
        ReceiverCoverageAtomicFile.write(file, previous + event)
    }
    fun events(): List<JsonObject> = synchronized(lock) {
        val file = directory.resolve("events.ndjson")
        if (!Files.exists(file)) emptyList() else Files.readAllLines(file).map { Json.parseToJsonElement(it).jsonObject }
    }
    fun retain(record: JsonObject) = synchronized(lock) {
        val date = record.getValue("date").jsonPrimitive.content
        require(java.time.LocalDate.parse(date).toString() == date)
        val bytes = record.toString().toByteArray(Charsets.UTF_8)
        check(bytes.size <= 128 * 1024)
        ReceiverCoverageAtomicFile.write(directory.resolve("retained/$date.json"), bytes)
    }
    fun reset() = synchronized(lock) {
        val port = read()["port"]
        Files.deleteIfExists(directory.resolve("events.ndjson")); Files.deleteIfExists(state)
        update(mapOf("capture_gate" to "false", "http_gate" to "false") + (port?.let { mapOf("port" to it) } ?: emptyMap()))
    }
}
