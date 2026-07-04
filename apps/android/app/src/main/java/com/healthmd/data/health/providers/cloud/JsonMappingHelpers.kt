package com.healthmd.data.health.providers.cloud

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId

internal fun JsonElement.obj(): JsonObject? = this as? JsonObject
internal fun JsonElement.array(): JsonArray? = this as? JsonArray
internal fun JsonObject.obj(key: String): JsonObject? = this[key]?.obj()
internal fun JsonObject.array(key: String): JsonArray? = this[key]?.array()
internal fun JsonObject.string(key: String): String? = this[key]?.jsonPrimitive?.contentOrNull
internal fun JsonObject.double(key: String): Double? = this[key]?.jsonPrimitive?.doubleOrNull
internal fun JsonObject.int(key: String): Int? = this[key]?.jsonPrimitive?.intOrNull
internal fun JsonObject.long(key: String): Long? = string(key)?.toLongOrNull() ?: double(key)?.toLong()
internal fun JsonObject.booleanString(key: String): Boolean? = string(key)?.toBooleanStrictOrNull()

internal fun JsonObject.firstArray(vararg keys: String): JsonArray =
    keys.firstNotNullOfOrNull { array(it) } ?: JsonArray(emptyList())

internal fun JsonElement.asObjectList(): List<JsonObject> = when (this) {
    is JsonArray -> this.mapNotNull { it.obj() }
    is JsonObject -> listOf(this)
    else -> emptyList()
}

internal fun epochSecondsToLocalDateTime(epochSeconds: Long, zone: ZoneId = ZoneId.systemDefault()): LocalDateTime =
    LocalDateTime.ofInstant(Instant.ofEpochSecond(epochSeconds), zone)

internal fun isoToLocalDateTime(value: String?, zone: ZoneId = ZoneId.systemDefault()): LocalDateTime? =
    value?.let { raw ->
        runCatching { Instant.parse(raw).atZone(zone).toLocalDateTime() }.getOrNull()
            ?: runCatching { LocalDateTime.parse(raw) }.getOrNull()
            ?: runCatching { LocalDate.parse(raw).atStartOfDay() }.getOrNull()
    }

internal fun secondsToHours(seconds: Double?): Double? = seconds?.div(3600.0)
internal fun millisToLocalDateTime(millis: Long, zone: ZoneId = ZoneId.systemDefault()): LocalDateTime =
    LocalDateTime.ofInstant(Instant.ofEpochMilli(millis), zone)
