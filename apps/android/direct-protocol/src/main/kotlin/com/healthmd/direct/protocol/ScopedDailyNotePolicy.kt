package com.healthmd.direct.protocol

import java.time.LocalDate
import java.time.ZoneId
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.SerializationException
import kotlinx.serialization.descriptors.buildClassSerialDescriptor
import kotlinx.serialization.descriptors.element
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.*

/** Destination behavior; the receiver must also bind the accepted job and actual capture. */
@Serializable(with = ScopedDailyNotePolicySerializer::class)
data class ScopedDailyNotePolicy(
    val version: Int,
    val recordProfile: String,
    val ownerDate: String,
    val calendarTimezone: String,
    val createIfMissing: Boolean,
    val injectSections: Boolean,
) {
    init {
        require(version == 1 && recordProfile in setOf("apple-v8", "apple-v11", "android-frozen-v4", "android-analytical-v5", "android-sleep-v6")) { "Unsupported note policy." }
        require(ownerDate.length == 10 && runCatching {
            val date = LocalDate.parse(ownerDate)
            date.year > 0 && date.toString() == ownerDate
        }.getOrDefault(false)) { "Invalid note policy date." }
        require(calendarTimezone.length <= 128 && (calendarTimezone in ZoneId.getAvailableZoneIds() || calendarTimezone in setOf("UTC", "GMT"))) { "Invalid note policy clock." }
    }
}

/** JSON's permissive Boolean coercion is unsafe for destination write authority. */
object ScopedDailyNotePolicySerializer : KSerializer<ScopedDailyNotePolicy> {
    private val fields = setOf("version", "record_profile", "owner_date", "calendar_timezone", "create_if_missing", "inject_sections")
    override val descriptor = buildClassSerialDescriptor("ScopedDailyNotePolicy") {
        element<Int>("version")
        element<String>("record_profile")
        element<String>("owner_date")
        element<String>("calendar_timezone")
        element<Boolean>("create_if_missing")
        element<Boolean>("inject_sections")
    }

    override fun deserialize(decoder: Decoder): ScopedDailyNotePolicy {
        val json = (decoder as? JsonDecoder)?.decodeJsonElement() as? JsonObject ?: invalid()
        if (json.keys != fields) invalid()
        fun primitive(key: String) = json[key] as? JsonPrimitive ?: invalid()
        fun string(key: String): String = primitive(key).takeIf { it.isString }?.content ?: invalid()
        fun boolean(key: String): Boolean = primitive(key).takeUnless { it.isString }?.booleanOrNull ?: invalid()
        val version = primitive("version").takeUnless { it.isString }?.intOrNull ?: invalid()
        return ScopedDailyNotePolicy(version, string("record_profile"), string("owner_date"),
            string("calendar_timezone"), boolean("create_if_missing"), boolean("inject_sections"))
    }

    override fun serialize(encoder: Encoder, value: ScopedDailyNotePolicy) {
        val json = encoder as? JsonEncoder ?: invalid()
        json.encodeJsonElement(buildJsonObject {
            put("version", value.version)
            put("record_profile", value.recordProfile)
            put("owner_date", value.ownerDate)
            put("calendar_timezone", value.calendarTimezone)
            put("create_if_missing", value.createIfMissing)
            put("inject_sections", value.injectSections)
        })
    }

    private fun invalid(): Nothing = throw SerializationException("Invalid scoped note policy.")
}
