package com.healthmd.direct

import com.healthmd.direct.protocol.*
import com.healthmd.domain.exportengine.*
import com.healthmd.domain.model.HealthData
import java.time.LocalDate
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*

internal enum class AgentBridgeNativeRenderFailure { INVALID_INPUT, INCOMPATIBLE_CORE, INVALID_ARTIFACT, RENDER_FAILED }
internal class AgentBridgeNativeRenderException(val code: AgentBridgeNativeRenderFailure) :
    RuntimeException(code.name.lowercase(java.util.Locale.ROOT))

/** Post-capture bytes and actual renderer evidence, never permission or a committed receipt. */
internal class AgentBridgeNativeRenderedDay(val day: String, val artifact: ExportArtifactPlanItem, val pin: ExportEnginePin)

/** Frozen-v4 JSON rendering and original-owner capture/journal composition. Pure render performs
 * no SDK/destination IO; capture commits exact bytes in its accepted job before returning. */
internal class AgentBridgeNativeDayRenderer(
    private val core: DailyAggregateRustPlanner? = null,
    private val pinLoader: (suspend (String) -> ExportEnginePin)? = null,
) {
    /** Pin → real SDK → frozen renderer → immutable signed artifact. Transfer receipts remain separate. */
    suspend fun capture(day: String, manager: com.healthmd.data.health.HealthConnectManager,
        context: AgentBridgeNativeCaptureContext): AgentBridgeNativeRenderedDay {
        try {
            val fingerprint = context.requestFingerprintForRead()
            val resolution = context.configurationForRead()
            context.retainedArtifact(day)?.let { checkpoint ->
                val result = AgentBridgeNativeArtifactJournal.restore(checkpoint, day, resolution, fingerprint)
                context.configurationForRead(); return result
            }
            val pin = pinLoader?.invoke(resolution.calendarTimezone) ?: withContext(Dispatchers.Default) {
                val service = com.healthmd.core.HealthMdCoreService()
                ExportEnginePin.create(ExportEngineMode.rust, AndroidExportProfile.android_frozen_v4,
                    resolution.calendarTimezone, service.checkReadiness(),
                    service.getMetricRegistry(com.healthmd.core.CoreMetricRegistryProfile.ANDROID_FROZEN_V4))
            }
            validateBridgeRenderPin(pin, resolution)
            val engine = AgentBridgeNativeArtifactJournal.engine(pin)
            context.beginArtifact(day, engine)
            val data = manager.captureAgentBridgeDay(day, context)
            val result = render(day, data, context.configurationForRead(), fingerprint, pin)
            if (result.pin != pin) fail(AgentBridgeNativeRenderFailure.INCOMPATIBLE_CORE)
            context.commitArtifact(day, engine, AgentBridgeNativeArtifactJournal.payload(result))
            context.configurationForRead()
            return result
        } catch (failure: Throwable) {
            context.invalidate()
            if (failure is CancellationException || failure is AgentBridgeException || failure is AgentBridgeNativeRenderException ||
                failure is VirtualMachineError || failure is ThreadDeath) throw failure
            fail(AgentBridgeNativeRenderFailure.RENDER_FAILED)
        }
    }

    suspend fun render(day: String, data: HealthData, resolution: AgentBridgeRequestSettingsResolution,
        requestSha256: String, pinnedEngine: ExportEnginePin? = null): AgentBridgeNativeRenderedDay {
        try {
            currentCoroutineContext().ensureActive()
            val index = resolution.requestedDays.indexOf(day)
            if (resolution.version != 1 || !requestSha256.matches(Regex("[0-9a-f]{64}")) || index < 0 ||
                resolution.predictedRelativePaths.size != resolution.requestedDays.size || data.date.toString() != day ||
                LocalDate.parse(day).toString() != day) fail(AgentBridgeNativeRenderFailure.INVALID_INPUT)
            val settings = resolution.exporterSettings().copy(executionEnginePin = pinnedEngine)
            val selected = resolution.selection.map { it.semanticId }.toSet()
            if (selected.isEmpty() || selected.size != resolution.selection.size ||
                !setOf("steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "android.hrv_rmssd").containsAll(selected) ||
                settings.metricSelection.enabledMetrics != resolution.selection.map { it.nativeMetricId }.toSet()) {
                fail(AgentBridgeNativeRenderFailure.INVALID_INPUT)
            }
            // The native presentation document is opaque to the semantic selection filter.
            // Supply only approved scalar facts, never the caller's broader captured model.
            val scoped = HealthData(date = data.date,
                activity = com.healthmd.domain.model.ActivityData(steps = data.activity.steps.takeIf { "steps" in selected }),
                heart = com.healthmd.domain.model.HeartData(
                    averageHeartRate = data.heart.averageHeartRate.takeIf { "heart_rate_avg" in selected },
                    heartRateMin = data.heart.heartRateMin.takeIf { "heart_rate_min" in selected },
                    heartRateMax = data.heart.heartRateMax.takeIf { "heart_rate_max" in selected },
                    restingHeartRate = data.heart.restingHeartRate.takeIf { "resting_heart_rate" in selected },
                    hrv = data.heart.hrv.takeIf { "android.hrv_rmssd" in selected }))
            val request = FrozenDailyAggregateExportRequest.capture(scoped, settings, AndroidExportProfile.android_frozen_v4,
                ExportEngineMode.rust, DailyAggregateExportIds(requestSha256, "$requestSha256-$day"))
            val renderer = core ?: HealthMdRustDailyAggregatePlanner(zoneIdProvider = { java.time.ZoneId.of(resolution.calendarTimezone) })
            val result = renderer.plan(request)
            currentCoroutineContext().ensureActive()
            val pin = result.pin
            validateBridgeRenderPin(pin, resolution)
            val plan = result.plan
            val item = plan.items.singleOrNull() ?: fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            val path = resolution.predictedRelativePaths[index]
            if (plan.profile != AndroidExportProfile.android_frozen_v4 || plan.requestId != request.ids.requestId ||
                plan.sessionId != request.ids.sessionId || item.relativePath != path || request.relativePath(com.healthmd.domain.model.ExportFormat.JSON) != path ||
                item.mediaType != "application/json" || item.writeMode != ExportArtifactWriteMode.overwrite ||
                item.byteCount == 0uL || item.byteCount > 1_048_576uL) fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            val json = Json.parseToJsonElement(item.content.decodeToString()).jsonObject
            // Frozen v4 files identify their profile through the artifact/pin, not an in-file
            // schema envelope. Adding analytical-v5 metadata would rewrite the shipped contract.
            if (json.keys.any { it !in setOf("date", "type", "units", "activity", "heart") } ||
                json["date"]?.jsonPrimitive?.content != day || json["type"]?.jsonPrimitive?.content != "health-data" ||
                json["units"]?.jsonPrimitive?.content != "metric") {
                fail(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
            }
            return AgentBridgeNativeRenderedDay(day, item, pin)
        } catch (error: CancellationException) { throw error }
        catch (error: AgentBridgeNativeRenderException) { throw error }
        catch (_: Exception) { fail(AgentBridgeNativeRenderFailure.RENDER_FAILED) }
    }
    private fun fail(code: AgentBridgeNativeRenderFailure): Nothing = throw AgentBridgeNativeRenderException(code)
}

internal fun validateBridgeRenderPin(pin: ExportEnginePin, resolution: AgentBridgeRequestSettingsResolution) {
            if (pin.engine != ExportEngineMode.rust || pin.profile != AndroidExportProfile.android_frozen_v4 ||
                pin.publicSchema != "healthmd.health_data" || pin.publicSchemaVersion != 4u || pin.coreApiVersion != 5u ||
                pin.semanticInputVersion != 1u || pin.canonicalModelVersion != 1u || pin.renderInputVersion != 1u ||
                pin.artifactPlanVersion != 1u || pin.registryVersion != 1u || pin.registrySha256 != resolution.registrySha256 ||
                pin.semanticProfileRevision != 1u || pin.renderProfileRevision != 2u || pin.ianaTimeZone != resolution.calendarTimezone ||
                pin.coreSourceRevision.isBlank() || pin.coreSourceRevision.length > 256) throw AgentBridgeNativeRenderException(AgentBridgeNativeRenderFailure.INCOMPATIBLE_CORE)
 }
