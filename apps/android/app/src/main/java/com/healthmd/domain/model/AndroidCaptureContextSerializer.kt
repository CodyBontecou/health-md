package com.healthmd.domain.model

import java.time.ZoneId
import kotlinx.serialization.KSerializer
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/** Durable operation authority, never portable settings or a reader-local timezone fallback. */
object AndroidCaptureContextSerializer : KSerializer<AndroidCaptureContext> {
    override val descriptor: SerialDescriptor = CaptureAuthorityPayload.serializer().descriptor

    override fun serialize(encoder: Encoder, value: AndroidCaptureContext) {
        require(value.zoneId.id in ZoneId.getAvailableZoneIds()) { "Invalid capture timezone" }
        encoder.encodeSerializableValue(CaptureAuthorityPayload.serializer(), CaptureAuthorityPayload(
            calendarTimeZoneIdentifier = value.zoneId.id,
            sleepDayAttribution = value.sleepDayAttribution.wireValue,
            exportProfileID = value.exportProfileID,
        ))
    }

    override fun deserialize(decoder: Decoder): AndroidCaptureContext {
        val payload = decoder.decodeSerializableValue(CaptureAuthorityPayload.serializer())
        require(payload.calendarTimeZoneIdentifier.length <= 128 &&
            payload.calendarTimeZoneIdentifier in ZoneId.getAvailableZoneIds()) { "Invalid capture timezone" }
        val attribution = SleepDayAttribution.entries.firstOrNull { it.wireValue == payload.sleepDayAttribution }
            ?: throw IllegalArgumentException("Invalid capture attribution")
        // An absent draft discriminator remains absent. Never invoke the fresh constructor default.
        return AndroidCaptureContext(ZoneId.of(payload.calendarTimeZoneIdentifier), attribution, payload.exportProfileID)
    }
}

@Serializable
private data class CaptureAuthorityPayload(
    val calendarTimeZoneIdentifier: String,
    val sleepDayAttribution: String,
    val exportProfileID: String? = null,
)
