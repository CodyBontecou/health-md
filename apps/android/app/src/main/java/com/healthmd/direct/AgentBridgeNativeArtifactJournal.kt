package com.healthmd.direct

import com.healthmd.direct.protocol.*
import com.healthmd.domain.exportengine.*
import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** Private artifact1; signed spool records bind these bytes and the engine pin to the accepted job. */
internal object AgentBridgeNativeArtifactJournal {
    private val json = Json { encodeDefaults = true; explicitNulls = true; ignoreUnknownKeys = false }
    @Serializable private data class Engine(val version: Int, val pin: ExportEnginePin)
    @Serializable private data class Artifact(val version: Int, val day: String, val id: String,
        val relativePath: String, val sha256: String, val content: String)
    fun engine(pin: ExportEnginePin): ByteArray = AgentBridgeCodec.canonicalize(json.encodeToString(Engine(1, pin)).toByteArray())
    fun payload(result: AgentBridgeNativeRenderedDay): ByteArray = AgentBridgeCodec.canonicalize(json.encodeToString(
        Artifact(1, result.day, result.artifact.artifactId, result.artifact.relativePath, result.artifact.sha256,
            Base64.getEncoder().encodeToString(result.artifact.content))).toByteArray())
    fun restore(checkpoint: AgentBridgeNativeCaptureSpool.ArtifactCheckpoint, day: String,
        resolution: AgentBridgeRequestSettingsResolution, fingerprint: String): AgentBridgeNativeRenderedDay {
        try {
            val saved = json.decodeFromString<Engine>(checkpoint.engine.decodeToString())
            if (saved.version != 1) fail()
            val pin = saved.pin
            validateBridgeRenderPin(pin, resolution)
            if (!engine(pin).contentEquals(checkpoint.engine)) fail()
            val value = json.decodeFromString<Artifact>(checkpoint.payload.decodeToString())
            if (!AgentBridgeCodec.canonicalize(json.encodeToString(value).toByteArray()).contentEquals(checkpoint.payload) ||
                value.version != 1 || value.day != day) fail()
            val index = resolution.requestedDays.indexOf(day)
            if (index < 0 || resolution.predictedRelativePaths.getOrNull(index) != value.relativePath) fail()
            val content = Base64.getDecoder().decode(value.content)
            if (content.isEmpty() || Base64.getEncoder().encodeToString(content) != value.content || value.id !=
                artifactIdHex(fingerprint, "$fingerprint-$day", AndroidExportProfile.android_frozen_v4,
                    value.relativePath, "application/json", ExportArtifactWriteMode.overwrite, value.sha256)) fail()
            val artifact = ExportArtifactPlanItem(value.id, value.relativePath, "application/json",
                ExportArtifactWriteMode.overwrite, content, content.size.toULong(), value.sha256)
            return AgentBridgeNativeRenderedDay(day, artifact, pin)
        } catch (_: Exception) { fail() }
    }
    private fun fail(): Nothing = throw AgentBridgeException(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED)
}
