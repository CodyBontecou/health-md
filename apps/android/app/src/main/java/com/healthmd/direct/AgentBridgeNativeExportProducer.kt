package com.healthmd.direct

import com.healthmd.data.health.HealthConnectManager
import com.healthmd.direct.protocol.*
import kotlinx.coroutines.CancellationException

/** All approved days in frozen order, backed by signed day artifacts. Not a transfer manifest,
 * receipt, or authority outside the original native owner. */
internal class AgentBridgeNativePreparedExport(val requestSha256: String,
    days: List<AgentBridgeNativeRenderedDay>, val totalByteCount: ULong) {
    val days: List<AgentBridgeNativeRenderedDay> = java.util.Collections.unmodifiableList(ArrayList(days))
}

internal suspend fun AgentBridgeNativePlanningSession.prepareExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()
): AgentBridgeNativePreparedExport = withCaptureContext(request) { context ->
    AgentBridgeNativeExportProducer.prepare(manager, context, renderer)
}

/** Explicit retained recovery; failed new execution never falls back to this operation. */
internal suspend fun AgentBridgeNativePlanningSession.prepareRetainedExport(request: AgentBridgeExecuteRequest,
    manager: HealthConnectManager, renderer: AgentBridgeNativeDayRenderer = AgentBridgeNativeDayRenderer()
): AgentBridgeNativePreparedExport = withRetainedCaptureContext(request) { context ->
    AgentBridgeNativeExportProducer.prepare(manager, context, renderer)
}

private object AgentBridgeNativeExportProducer {
    suspend fun prepare(manager: HealthConnectManager, context: AgentBridgeNativeCaptureContext,
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
            return AgentBridgeNativePreparedExport(fingerprint, days, total)
        } catch (failure: Throwable) {
            context.invalidate()
            if (failure is CancellationException || failure is AgentBridgeException || failure is AgentBridgeNativeRenderException ||
                failure is VirtualMachineError || failure is ThreadDeath) throw failure
            fail(AgentBridgeNativeRenderFailure.RENDER_FAILED)
        }
    }
    private fun fail(code: AgentBridgeNativeRenderFailure): Nothing = throw AgentBridgeNativeRenderException(code)
}
