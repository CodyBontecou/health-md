package com.healthmd.direct

import com.healthmd.data.health.HealthConnectManager
import com.healthmd.direct.protocol.*
import kotlinx.coroutines.CancellationException

/** Owned base-v2 bytes and metadata. Neither this value nor its descriptor grants authority. */
internal class AgentBridgeNativePreparedFile(val manifest: ArtifactManifest, private val artifact: com.healthmd.domain.exportengine.ExportArtifactPlanItem) {
    val content: ByteArray get() = artifact.content
}

/** All approved days cross-checked against v4 and unchanged base-v2 metadata. */
internal class AgentBridgeNativePreparedExport private constructor(val requestSha256: String,
    days: List<AgentBridgeNativeRenderedDay>, val totalByteCount: ULong, publicArtifactIDs: Map<String, String>,
    manifestCanonical: ByteArray, baseFiles: List<AgentBridgeNativePreparedFile>) {
    val days: List<AgentBridgeNativeRenderedDay> = java.util.Collections.unmodifiableList(ArrayList(days))
    private val manifestBytes = manifestCanonical.copyOf()
    val manifestCanonical: ByteArray get() = manifestBytes.copyOf()
    val publicArtifactIDs: Map<String, String> = java.util.Collections.unmodifiableMap(LinkedHashMap(publicArtifactIDs))
    val baseFiles: List<AgentBridgeNativePreparedFile> = java.util.Collections.unmodifiableList(ArrayList(baseFiles))

    companion object {
        /** Pure adapter, never a v4-to-v2 request conversion. Installed senders still require
         * the original native owner and fresh fences at every bounded write. */
        fun make(request: AgentBridgeExecuteRequest, days: List<AgentBridgeNativeRenderedDay>,
            totalByteCount: ULong, publicArtifactIDs: Map<String, String>, manifestCanonical: ByteArray): AgentBridgeNativePreparedExport {
            val fingerprint = AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request))
            val manifest = AgentBridgeCodec.decode(manifestCanonical) as? AgentBridgeArtifactManifest ?: invalid()
            if (!AgentBridgeCodec.encode(manifest).contentEquals(manifestCanonical) || manifest.jobId != request.jobId ||
                manifest.requestSha256 != fingerprint || manifest.binding != AgentBridgeValidation.bindingFor(request.plan) ||
                manifest.captureStatus != AgentBridgeArtifactManifestCaptureStatus.COMPLETE || days.isEmpty() || days.size > 4096 ||
                manifest.artifacts.size != days.size || days.map { it.day }.toSet().size != days.size ||
                publicArtifactIDs.keys != days.map { it.day }.toSet() || publicArtifactIDs.values.toSet().size != days.size) invalid()
            // Bind the complete ordered set to the ORIGINAL plan as well as to each other.
            val plan = request.plan as? AgentBridgeGeneratedPlan ?: invalid()
            val range = (plan.resolvedDates as? AgentBridgeDatesExact)?.range ?: invalid()
            val first = java.time.LocalDate.parse(range.startDate)
            val count = java.time.temporal.ChronoUnit.DAYS.between(first, java.time.LocalDate.parse(range.endDate)) + 1
            if (count != days.size.toLong() || days.withIndex().any { (index, day) -> day.day != first.plusDays(index.toLong()).toString() } ||
                manifest.artifacts.map { it.relativePath } != plan.predictedPaths) invalid()
            var total = 0uL
            val files = manifest.artifacts.zip(days).map { (item, day) ->
                val bytes = day.artifact.content
                if (item.artifactId != publicArtifactIDs[day.day] || item.relativePath != day.artifact.relativePath || day.artifact.mediaType != "application/json" ||
                    day.artifact.writeMode != com.healthmd.domain.exportengine.ExportArtifactWriteMode.overwrite ||
                    item.mediaType != AgentBridgeArtifactMediaType.APPLICATION_JSON || item.profile != AgentBridgeArtifactProfile.ANDROID_FROZEN_V4 ||
                    item.writeMode != AgentBridgeWriteMode.OVERWRITE || item.byteCount != bytes.size.toLong() ||
                    item.byteCount.toULong() != day.artifact.byteCount || item.sha256 != day.artifact.sha256 ||
                    AgentBridgeCodec.sha256(bytes) != item.sha256 || bytes.isEmpty() || total + bytes.size.toULong() > 64uL * 1024uL * 1024uL) invalid()
                total += bytes.size.toULong()
                AgentBridgeNativePreparedFile(ArtifactManifest(jobId = request.jobId, artifactId = item.artifactId,
                    kind = ArtifactKind.GENERATED_FILE, schema = ArtifactSchema("healthmd.generated-files", 1),
                    mediaType = "application/json", byteCount = item.byteCount, sha256 = item.sha256,
                    relativePath = item.relativePath, writeMode = FileWriteMode.OVERWRITE), day.artifact)
            }
            if (total != totalByteCount) invalid()
            return AgentBridgeNativePreparedExport(fingerprint, days, total, publicArtifactIDs, manifestCanonical, files)
        }
        private fun invalid(): Nothing = throw AgentBridgeNativeRenderException(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
    }
}

internal suspend fun AgentBridgeNativePlanningSession.prepareExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()
): AgentBridgeNativePreparedExport = withCaptureContext(request) { context ->
    AgentBridgeNativeExportProducer.prepare(request, manager, context, renderer)
}

/** Explicit retained recovery; failed new execution never falls back to this operation. */
internal suspend fun AgentBridgeNativePlanningSession.prepareRetainedExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()
): AgentBridgeNativePreparedExport = withRetainedCaptureContext(request) { context ->
    AgentBridgeNativeExportProducer.prepare(request, manager, context, renderer)
}

private object AgentBridgeNativeExportProducer {
    suspend fun prepare(request: AgentBridgeExecuteRequest, manager: HealthConnectManager, context: AgentBridgeNativeCaptureContext,
        renderer: AgentBridgeNativeDayRenderer): AgentBridgeNativePreparedExport {
        try {
            val resolution = context.begin()
            val fingerprint = context.requestFingerprintForRead()
            val approved = resolution.requestedDays
            if (approved.isEmpty() || approved.size > 4096 || approved.toSet().size != approved.size ||
                resolution.predictedRelativePaths.size != approved.size) fail(AgentBridgeNativeRenderFailure.INVALID_INPUT)
            val days = mutableListOf<AgentBridgeNativeRenderedDay>()
            var total = 0uL
            val limit = 64uL * 1024uL * 1024uL
            approved.forEachIndexed { index, day ->
                val result = renderer.capture(day, manager, context)
                if (result.day != day || result.artifact.relativePath != resolution.predictedRelativePaths[index] ||
                    result.artifact.byteCount > limit || total > limit - result.artifact.byteCount ||
                    days.firstOrNull()?.let { it.pin != result.pin } == true) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
                total += result.artifact.byteCount
                days += result
            }
            if (days.size != approved.size || days.map { it.artifact.artifactId }.toSet().size != days.size ||
                context.requestFingerprintForRead() != fingerprint) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            val publicIDs = context.bindPublicArtifactIDs()
            if (publicIDs.keys != approved.toSet() || context.requestFingerprintForRead() != fingerprint) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            val manifest = context.preserveManifest()
            if (context.requestFingerprintForRead() != fingerprint) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            val prepared = AgentBridgeNativePreparedExport.make(request, days, total, publicIDs, manifest)
            if (prepared.requestSha256 != fingerprint || context.requestFingerprintForRead() != fingerprint) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            return prepared
        } catch (failure: Throwable) {
            context.invalidate()
            if (failure is CancellationException || failure is AgentBridgeException || failure is AgentBridgeNativeRenderException ||
                failure is VirtualMachineError || failure is ThreadDeath) throw failure
            fail(AgentBridgeNativeRenderFailure.RENDER_FAILED)
        }
    }
    private fun fail(code: AgentBridgeNativeRenderFailure): Nothing = throw AgentBridgeNativeRenderException(code)
}
