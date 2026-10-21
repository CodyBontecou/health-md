import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust

nonisolated enum AgentBridgeNativeRenderFailure: String, Error {
    case invalidInput = "invalid_render_input"
    case incompatibleCore = "incompatible_render_core"
    case invalidArtifact = "invalid_render_artifact"
    case renderFailed = "native_render_failed"
}

/// Post-capture evidence only. The caller must bind this and the bytes to the original signed job
/// before publication. A rendered artifact is neither capture permission nor a committed receipt.
nonisolated struct AgentBridgeNativeRenderedDay: Sendable {
    let day: AgentBridgeDate
    let artifact: NativeExportArtifact
    let buildInfo: CoreBuildInfo
    let registrySHA256: String
}

/// Pure, bounded JSON rendering for the currently reviewed bridge dialect. Uses the actual frozen
/// v8 core profile, never a v10 native document relabeled as v8. No SDK, preference or destination IO.
@MainActor
enum AgentBridgeNativeDayRenderer {
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
}
