import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust

nonisolated enum AgentBridgeNativeRenderFailure: String, Error {
    case invalidInput = "invalid_render_input"
    case incompatibleCore = "incompatible_render_core"
    case invalidArtifact = "invalid_render_artifact"
    case renderFailed = "native_render_failed"
}

/// Rendering evidence, never capture permission or a transfer receipt. Pure render callers still
/// require durable binding; capture commits these bytes in the original signed native spool.
nonisolated struct AgentBridgeNativeRenderedDay: Sendable {
    let day: AgentBridgeDate
    let artifact: NativeExportArtifact
    let buildInfo: CoreBuildInfo
    let registrySHA256: String
}

/// Frozen v8 JSON rendering and original-owner capture/journal composition. The pure render
/// entry point performs no SDK or destination IO; capture persists bytes under its original job.
@MainActor
enum AgentBridgeNativeDayRenderer {
    /// Compose the real native SDK adapter and frozen renderer under the original capture owner.
    /// Engine identity and immutable artifact bytes are signed and fsynced before return.
    /// Transfer manifests and receipts remain separate obligations.
    static func capture(
        day: AgentBridgeDate,
        manager: HealthKitManager,
        context: AgentBridgeNativeCaptureContext,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws -> AgentBridgeNativeRenderedDay {
        do {
            let fingerprint = try context.requestFingerprintForRead()
            let resolution = try context.configurationForRead()
            if let checkpoint = try context.retainedArtifact(day) {
                let result = try AgentBridgeNativeArtifactJournal.restore(checkpoint, day: day, resolution: resolution, fingerprint: fingerprint)
                _ = try context.configurationForRead(); return result
            }
            let prepared = try await core.loadContext()
            try validateCore(prepared, resolution: resolution)
            let engine = try AgentBridgeNativeArtifactJournal.engine(info: prepared.buildInfo, resolution: resolution)
            try context.beginArtifact(day, engine: engine)
            let data = try await manager.captureAgentBridgeDay(day, context: context)
            let result = try await render(day: day, data: data, resolution: context.configurationForRead(),
                requestSHA256: fingerprint, core: PreparedBridgeCore(context: prepared, core: core))
            guard result.buildInfo == prepared.buildInfo else { throw AgentBridgeNativeRenderFailure.incompatibleCore }
            try context.commitArtifact(day, engine: engine, payload: AgentBridgeNativeArtifactJournal.payload(result))
            _ = try context.configurationForRead()
            return result
        } catch {
            context.invalidate()
            if error is CancellationError || error is AgentBridgeValidationError || error is AgentBridgeNativeRenderFailure { throw error }
            throw AgentBridgeNativeRenderFailure.renderFailed
        }
    }

    static func render(
        day: AgentBridgeDate,
        data: HealthData,
        resolution: AgentBridgeRequestSettingsResolution,
        requestSHA256: String,
        core: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(profile: .appleHealthDataV8)
    ) async throws -> AgentBridgeNativeRenderedDay {
        do {
            try Task.checkCancellation()
            guard resolution.version == 1, AppleExportEnginePin.isLowercaseSHA256(requestSHA256),
                  let index = resolution.requestedDays.firstIndex(of: day),
                  resolution.predictedRelativePaths.count == resolution.requestedDays.count,
                  let zone = resolution.settings.calendarTimeZoneIdentifier,
                  data.timeContext.calendarTimeZoneIdentifier == zone,
                  let timeZone = TimeZone(identifier: zone) else { throw AgentBridgeNativeRenderFailure.invalidInput }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
            let parts = calendar.dateComponents([.era, .year, .month, .day], from: data.date)
            guard parts.era == 1, String(format: "%04d-%02d-%02d", locale: Locale(identifier: "en_US_POSIX"), parts.year ?? 0, parts.month ?? 0, parts.day ?? 0) == day.rawValue else {
                throw AgentBridgeNativeRenderFailure.invalidInput
            }
            let path = try AgentBridgePath(resolution.predictedRelativePaths[index]).rawValue
            guard path.hasSuffix(".json") else { throw AgentBridgeNativeRenderFailure.invalidInput }
            let context = try await core.loadContext()
            try Task.checkCancellation()
            try validateCore(context, resolution: resolution)
            let info = context.buildInfo, registry = context.registry
            let sessionID = requestSHA256 + "-" + day.rawValue
            let selected = Set(resolution.selection.map(\.semanticID))
            guard !selected.isEmpty, selected.count == resolution.selection.count,
                  selected.isSubset(of: ["steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "hrv"]),
                  resolution.settings.metricSelection.enabledMetricIDs == Set(resolution.selection.map(\.nativeMetricID)) else {
                throw AgentBridgeNativeRenderFailure.invalidInput
            }
            var scoped = HealthData(date: data.date, timeContext: data.timeContext)
            if selected.contains("steps") { scoped.activity.steps = data.activity.steps }
            if selected.contains("heart_rate_avg") { scoped.heart.averageHeartRate = data.heart.averageHeartRate }
            if selected.contains("heart_rate_min") { scoped.heart.heartRateMin = data.heart.heartRateMin }
            if selected.contains("heart_rate_max") { scoped.heart.heartRateMax = data.heart.heartRateMax }
            if selected.contains("resting_heart_rate") { scoped.heart.restingHeartRate = data.heart.restingHeartRate }
            if selected.contains("hrv") { scoped.heart.hrv = data.heart.hrv }
            let selection = MetricSelectionState()
            resolution.settings.metricSelection.apply(to: selection)
            let customization = FormatCustomization()
            resolution.settings.formatCustomization.apply(to: customization)
            let semanticConfig = try HealthMdSemanticInputAdapter.sessionConfiguration(
                sessionID: sessionID, selection: selection, registry: registry, profile: .frozenV8,
                customization: customization, calendarTimeZoneIdentifier: zone,
                retainPlatformExtensions: false, rollupPeriods: [])
            let semanticBatches = try HealthMdSemanticInputAdapter.boundedBatches(
                sessionID: sessionID, healthData: [scoped], registry: registry, profile: .frozenV8,
                customization: customization, calendarTimeZoneIdentifier: zone).map(\.data)
            let semanticResult = try await core.processSemantic(configuration: semanticConfig, batches: semanticBatches)
            try Task.checkCancellation()
            let components = path.split(separator: "/").map(String.init)
            let renderInput = try HealthMdRenderInputAdapter.encode(
                semanticResult: semanticResult, registry: registry, calendarTimeZoneIdentifier: zone,
                options: .init(requestID: requestSHA256, formats: ["json"], jsonPlacement: .appleV8Summary, unitSystem: "metric", includeMetadata: true,
                               groupByCategory: true, baseDirectory: components.dropLast().joined(separator: "/"),
                               filenameTemplate: String(components.last!.dropLast(5))),
                allowNativeProfileDocuments: false, presentationCustomization: customization)
            let plan = try await core.render(configuration: renderInput.configuration, semanticResult: semanticResult, batches: renderInput.batches)
            try Task.checkCancellation()
            guard plan.schema == NativeExportArtifactPlan.schema, plan.artifactPlanVersion == 1,
                  plan.requestId == requestSHA256, plan.sessionId == sessionID, plan.profile == .appleHealthDataV8,
                  plan.items.count == 1, let item = plan.items.first,
                  item.relativePath == path, item.mediaType == "application/json", item.writeMode == .overwrite,
                  item.byteCount > 0, item.byteCount <= 1_048_576, plan.totalByteCount == item.byteCount,
                  item.artifactId == NativeExportArtifactPlan.artifactID(requestID: requestSHA256, sessionID: sessionID,
                      profile: .appleHealthDataV8, relativePath: path, mediaType: item.mediaType,
                      writeMode: item.writeMode, contentSHA256: item.sha256),
                  let json = try JSONSerialization.jsonObject(with: item.content) as? [String: Any],
                  json["schema"] as? String == "healthmd.health_data", json["schema_version"] as? Int == 8,
                  json["date"] as? String == day.rawValue,
                  (json["time_context"] as? [String: Any])?["calendar_timezone"] as? String == zone else {
                throw AgentBridgeNativeRenderFailure.invalidArtifact
            }
            let artifact = try NativeExportArtifact(role: .file, id: item.artifactId, relativePath: path,
                mediaType: item.mediaType, writeMode: item.writeMode, inlineData: item.content,
                byteCount: item.byteCount, sha256: item.sha256)
            return .init(day: day, artifact: artifact, buildInfo: info, registrySHA256: registry.registrySha256)
        } catch is CancellationError { throw CancellationError() }
        catch let failure as AgentBridgeNativeRenderFailure { throw failure }
        catch { throw AgentBridgeNativeRenderFailure.renderFailed }
    }
    private static func validateCore(_ context: AppleLooseDailyCoreContext, resolution: AgentBridgeRequestSettingsResolution) throws {
        let info = context.buildInfo, registry = context.registry
        guard info.coreApiVersion == 5, info.semanticInputVersion == 1, info.canonicalModelVersion == 1,
              info.renderInputVersion == 1, info.artifactPlanVersion == 1, info.renderProfileRevision == 2,
              info.registryVersion == 1, registry.registryVersion == 1, registry.profileRevision == 1,
              registry.profileId == "apple_health_data_v8", registry.publicProfileId == "apple-v8",
              registry.publicSchema == "healthmd.health_data", registry.publicSchemaVersion == 8,
              registry.registrySha256 == resolution.registrySHA256, info.registrySha256 == registry.registrySha256,
              !info.coreSourceRevision.isEmpty, info.coreSourceRevision.utf8.count <= 256 else { throw AgentBridgeNativeRenderFailure.incompatibleCore }
        guard resolution.selection.allSatisfy({ selected in registry.metrics.contains {
            $0.semanticId == selected.semanticID && $0.selectionId == selected.nativeMetricID &&
            $0.categoryId == selected.nativeCategoryID && $0.sourceSelector == selected.sourceSelector &&
            $0.sourceAggregation == selected.sourceReducer && $0.unit == selected.canonicalUnit
        } }) else { throw AgentBridgeNativeRenderFailure.incompatibleCore }
    }

}

nonisolated private struct PreparedBridgeCore: AppleLooseDailyCoreExecuting {
    let context: AppleLooseDailyCoreContext
    let core: any AppleLooseDailyCoreExecuting
    func loadContext() async throws -> AppleLooseDailyCoreContext { context }
    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        try await core.processSemantic(configuration: configuration, batches: batches)
    }
    func render(configuration: Data, semanticResult: Data, batches: [Data]) async throws -> CoreArtifactPlan {
        try await core.render(configuration: configuration, semanticResult: semanticResult, batches: batches)
    }
}
