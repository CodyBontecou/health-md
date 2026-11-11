package com.healthmd.data.receivercoverage

import kotlinx.serialization.json.*

/** Private scheduled snapshot wrapper. Version 4 is rejected by older native snapshot codecs,
 * rather than ignored as optional fields. No public daily/export profile bytes change. */
object ReceiverCoverageSnapshot {
    const val SCHEMA = "healthmd.receiver_scheduled_snapshot"
    class Authority(val configuration: String, val planId: String, val binding: String, val fingerprint: String)
    private val fields = setOf("schema","schema_version","version","output_settings","configuration","plan_id","destination_binding","destination_fingerprint")
    fun wrap(output: String, configuration: String, planId: String, binding: String, fingerprint: String): String {
        val value = buildJsonObject {
            put("schema",SCHEMA); put("schema_version",1); put("version",4)
            put("output_settings",output); put("configuration",configuration); put("plan_id",planId)
            put("destination_binding",binding); put("destination_fingerprint",fingerprint)
        }
        val result = JsonObject(value.toSortedMap()).toString()
        requireNotNull(checked(result))
        return result
    }
    fun authority(raw: String): Authority? = checked(raw)?.let {
        Authority(it.getValue("configuration").jsonPrimitive.content,it.getValue("plan_id").jsonPrimitive.content,
            it.getValue("destination_binding").jsonPrimitive.content,it.getValue("destination_fingerprint").jsonPrimitive.content)
    }
    fun outputSettings(raw: String): String = checked(raw)?.getValue("output_settings")?.jsonPrimitive?.content ?: raw
    /** Coverage and retry identity must include the accepted source, including Night begins. */
    fun requireProviderBinding(output: String) {
        val snapshot = Json.parseToJsonElement(output).jsonObject
        require(snapshot.getValue("version").jsonPrimitive.int in setOf(3, 5) &&
            snapshot["providerCaptureAuthority"] is JsonObject) { "Original receiver source authority is missing" }
    }
    private fun checked(raw: String): JsonObject? = try { record(raw) }
        catch (_: Exception) { throw ReceiverCoveragePreflight.BoundaryException() }
    private fun record(raw: String): JsonObject? {
        val value = try { Json.parseToJsonElement(raw) as? JsonObject } catch (_: Exception) { null } ?: return null
        if (value["schema"]?.jsonPrimitive?.content != SCHEMA) return null
        require(raw.toByteArray().size <= 128 * 1024 && value.keys == fields)
        require(value.getValue("schema_version") == JsonPrimitive(1) && value.getValue("version") == JsonPrimitive(4))
        require(JsonObject(value.toSortedMap()).toString() == raw) // No duplicate/extra/coerced fields.
        for (key in fields - setOf("schema_version","version")) require(value.getValue(key).jsonPrimitive.isString)
        val output = Json.parseToJsonElement(value.getValue("output_settings").jsonPrimitive.content).jsonObject
        require(output.getValue("version").jsonPrimitive.int in setOf(1, 2, 3, 5))
        ReceiverCoverageConfiguration.parse(value.getValue("configuration").jsonPrimitive.content)
        require(Regex("[A-Za-z0-9_-]{1,128}").matches(value.getValue("plan_id").jsonPrimitive.content))
        for (key in listOf("destination_binding","destination_fingerprint")) require(Regex("[a-f0-9]{64}").matches(value.getValue(key).jsonPrimitive.content))
        return value
    }
}
