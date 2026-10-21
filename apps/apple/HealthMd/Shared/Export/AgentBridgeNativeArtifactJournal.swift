import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust

/// Private artifact payload1 and engine1. Signed spool records bind these to the accepted job;
/// neither decoding nor an engine fingerprint supplies native authority or a transfer receipt.
nonisolated enum AgentBridgeNativeArtifactJournal {
    nonisolated private struct Engine: Codable {
        let version: Int
        let profile: String
        let calendarTimezone: String
        let crateVersion: String
        let coreSourceRevision: String
        let registrySha256: String
        let coreApiVersion: UInt32
        let semanticInputVersion: UInt32
        let canonicalModelVersion: UInt32
        let registryVersion: UInt32
        let renderInputVersion: UInt32
        let artifactPlanVersion: UInt32
        let renderProfileRevision: UInt32
        let persistedStateVersion: UInt32
        init(info: CoreBuildInfo, zone: String) {
            version = 1; profile = "apple_health_data_v8"; calendarTimezone = zone
            crateVersion = info.crateVersion
            coreSourceRevision = info.coreSourceRevision
            registrySha256 = info.registrySha256
            coreApiVersion = info.coreApiVersion
            semanticInputVersion = info.semanticInputVersion
            canonicalModelVersion = info.canonicalModelVersion
            registryVersion = info.registryVersion
            renderInputVersion = info.renderInputVersion
            artifactPlanVersion = info.artifactPlanVersion
            renderProfileRevision = info.renderProfileRevision
            persistedStateVersion = info.persistedStateVersion
        }
        var info: CoreBuildInfo { .init(crateVersion: crateVersion, coreSourceRevision: coreSourceRevision, registrySha256: registrySha256, coreApiVersion: coreApiVersion, semanticInputVersion: semanticInputVersion, canonicalModelVersion: canonicalModelVersion, registryVersion: registryVersion, renderInputVersion: renderInputVersion, artifactPlanVersion: artifactPlanVersion, renderProfileRevision: renderProfileRevision, persistedStateVersion: persistedStateVersion) }
        func validate(_ resolution: AgentBridgeRequestSettingsResolution) throws {
            guard version == 1, profile == "apple_health_data_v8", calendarTimezone == resolution.settings.calendarTimeZoneIdentifier,
                  registrySha256 == resolution.registrySHA256, coreApiVersion == 5, semanticInputVersion == 1,
                  canonicalModelVersion == 1, registryVersion == 1, renderInputVersion == 1,
                  artifactPlanVersion == 1, renderProfileRevision == 2, !crateVersion.isEmpty,
                  crateVersion.utf8.count <= 128, !coreSourceRevision.isEmpty, coreSourceRevision.utf8.count <= 256 else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
        }
    }
    nonisolated private struct Artifact: Codable {
        let version: Int
        let day: String
        let id: String
        let relativePath: String
        let sha256: String
        let content: Data
    }
    static func engine(info: CoreBuildInfo, resolution: AgentBridgeRequestSettingsResolution) throws -> Data {
        let value = Engine(info: info, zone: resolution.settings.calendarTimeZoneIdentifier ?? "")
        try value.validate(resolution)
        return try canonical(value)
    }
    static func payload(_ result: AgentBridgeNativeRenderedDay) throws -> Data {
        try canonical(Artifact(version: 1, day: result.day.rawValue, id: result.artifact.id,
            relativePath: result.artifact.relativePath ?? "", sha256: result.artifact.sha256,
            content: result.artifact.content.materializedData()))
    }
    static func restore(_ checkpoint: AgentBridgeNativeCaptureSpool.ArtifactCheckpoint,
        day: AgentBridgeDate, resolution: AgentBridgeRequestSettingsResolution, fingerprint: String) throws -> AgentBridgeNativeRenderedDay {
        do {
            let engine = try JSONDecoder().decode(Engine.self, from: checkpoint.engine)
            try engine.validate(resolution)
            guard try canonical(engine) == checkpoint.engine else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            let value = try JSONDecoder().decode(Artifact.self, from: checkpoint.payload)
            guard try canonical(value) == checkpoint.payload, value.version == 1, value.day == day.rawValue,
                  let index = resolution.requestedDays.firstIndex(of: day),
                  resolution.predictedRelativePaths.indices.contains(index),
                  value.relativePath == resolution.predictedRelativePaths[index], !value.content.isEmpty,
                  value.id == NativeExportArtifactPlan.artifactID(requestID: fingerprint, sessionID: fingerprint + "-" + day.rawValue,
                    profile: .appleHealthDataV8, relativePath: value.relativePath, mediaType: "application/json",
                    writeMode: .overwrite, contentSHA256: value.sha256) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            let artifact = try NativeExportArtifact(role: .file, id: value.id, relativePath: value.relativePath,
                mediaType: "application/json", writeMode: .overwrite, inlineData: value.content,
                byteCount: UInt64(value.content.count), sha256: value.sha256)
            return .init(day: day, artifact: artifact, buildInfo: engine.info, registrySHA256: engine.registrySha256)
        } catch { throw AgentBridgeValidationError.spoolMissingRestartRequired }
    }
    private static func canonical<T: Encodable>(_ value: T) throws -> Data {
        try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(value))
    }
}
