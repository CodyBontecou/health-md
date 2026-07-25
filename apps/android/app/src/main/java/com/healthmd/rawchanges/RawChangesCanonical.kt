package com.healthmd.rawchanges

import com.healthmd.rawexport.RawJson
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject

object RawChangesCanonical {
    fun scopeJson(scope: RawChangesScope): String = RawJson.canonical(
        RawJson.codec.encodeToJsonElement(RawChangesScope.serializer(), scope.canonical()),
    )

    fun scopeHash(scope: RawChangesScope): String = RawJson.sha256("healthmd.raw-changes.scope.v1\n${scopeJson(scope)}")

    fun eventHash(event: RawChangeEvent): String {
        val excluded = if (event is RawChangeEvent.Deletion) {
            setOf("eventHash", "ordinal", "observedAt")
        } else {
            setOf("eventHash", "ordinal")
        }
        val unsigned = RawJson.codec.encodeToJsonElement(RawChangeEvent.serializer(), event).jsonObject
            .filterKeys { it !in excluded }
        return RawJson.sha256(RawJson.canonical(JsonObject(unsigned)))
    }

    fun signed(event: RawChangeEvent): RawChangeEvent = when (event) {
        is RawChangeEvent.Upsertion -> event.copy(eventHash = eventHash(event))
        is RawChangeEvent.Deletion -> event.copy(eventHash = eventHash(event))
    }

    fun canonicalEvent(event: RawChangeEvent): String = RawJson.canonical(
        RawJson.codec.encodeToJsonElement(RawChangeEvent.serializer(), event),
    )

    fun manifestHash(manifest: RawChangesManifest): String {
        val unsigned = RawJson.codec.encodeToJsonElement(RawChangesManifest.serializer(), manifest).jsonObject
            .filterKeys { it != "manifestChecksumSha256" && it != "artifactChecksumSha256" }
        return RawJson.sha256(RawJson.canonical(JsonObject(unsigned)))
    }
}
