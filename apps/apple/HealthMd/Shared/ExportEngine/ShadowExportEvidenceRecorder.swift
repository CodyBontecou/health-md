import Foundation
import OSLog

/// Bounded, health-free aggregate evidence for internal shadow rollouts.
///
/// The persisted shape cannot represent health values, dates, paths, filenames, operation/device
/// identities, destinations, payload bytes, digests, byte offsets, or arbitrary error text.
nonisolated struct ShadowExportEvidenceSnapshot: Codable, Equatable, Sendable {
    static let schema = "healthmd.apple_shadow_export_evidence"
    static let version: UInt32 = 1

    var schema: String = Self.schema
    var version: UInt32 = Self.version
    var profiles: [ShadowExportProfileEvidence] = []

    static let empty = ShadowExportEvidenceSnapshot()
}

nonisolated struct ShadowExportProfileEvidence: Codable, Equatable, Sendable {
    let profile: String
    let semanticProfileRevision: UInt32
    let renderProfileRevision: UInt32
    var comparisonCount: UInt64 = 0
    var exactMatchCount: UInt64 = 0
    var mismatchOperationCount: UInt64 = 0
    var reportedMismatchCount: UInt64 = 0
    var rustFailureCount: UInt64 = 0
    var mismatchDimensions: [String: UInt64] = [:]
    var rustFailureCodes: [String: UInt64] = [:]
}

/// Actor serialization keeps evidence writes off caller executors and makes counters race-free.
/// Evidence loss/corruption can reset observability, but must never affect export authority.
actor ShadowExportEvidenceRecorder {
    nonisolated static let productionSink: @Sendable (ShadowExportDiagnostic) async -> Void = {
        diagnostic in
        await ShadowExportEvidenceRecorder.shared.record(diagnostic)
    }

    static let shared = ShadowExportEvidenceRecorder()

    private static let defaultStorageKey = "HealthMd.sharedCore.appleShadowEvidence.v1"
    private static let maximumPersistedBytes = 64 * 1_024
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.codybontecou.obsidianhealth",
        category: "SharedCoreShadow"
    )

    private let userDefaults: UserDefaults
    private let storageKey: String
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(
        userDefaults: UserDefaults = .standard,
        storageKey: String = ShadowExportEvidenceRecorder.defaultStorageKey
    ) {
        self.userDefaults = userDefaults
        self.storageKey = storageKey
        encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        decoder = JSONDecoder()
    }

    func record(_ diagnostic: ShadowExportDiagnostic) {
        guard let event = EvidenceEvent(diagnostic), event.isValid else { return }
        var snapshot = load()
        let index = snapshot.profiles.firstIndex {
            $0.profile == event.profile
                && $0.semanticProfileRevision == event.semanticProfileRevision
                && $0.renderProfileRevision == event.renderProfileRevision
        }
        var profile = index.map { snapshot.profiles[$0] } ?? ShadowExportProfileEvidence(
            profile: event.profile,
            semanticProfileRevision: event.semanticProfileRevision,
            renderProfileRevision: event.renderProfileRevision
        )

        switch event.kind {
        case .comparison(let matches, let mismatchCount):
            Self.increment(&profile.comparisonCount)
            if matches {
                Self.increment(&profile.exactMatchCount)
            } else {
                Self.increment(&profile.mismatchOperationCount)
            }
            Self.increment(&profile.reportedMismatchCount, by: UInt64(mismatchCount))
            let outcome = matches ? "exact_match" : "mismatch"
            Self.logger.info(
                "profile=\(event.profile, privacy: .public) semantic=\(event.semanticProfileRevision) render=\(event.renderProfileRevision) outcome=\(outcome, privacy: .public) mismatch_count=\(mismatchCount)"
            )
        case .mismatch(let dimension):
            Self.increment(&profile.mismatchDimensions, key: dimension)
            Self.logger.info(
                "profile=\(event.profile, privacy: .public) semantic=\(event.semanticProfileRevision) render=\(event.renderProfileRevision) mismatch_dimension=\(dimension, privacy: .public)"
            )
        case .rustFailure(let code):
            Self.increment(&profile.rustFailureCount)
            Self.increment(&profile.rustFailureCodes, key: code)
            Self.logger.info(
                "profile=\(event.profile, privacy: .public) semantic=\(event.semanticProfileRevision) render=\(event.renderProfileRevision) rust_failure=\(code, privacy: .public)"
            )
        }

        if let index {
            snapshot.profiles[index] = profile
        } else {
            snapshot.profiles.append(profile)
        }
        snapshot.profiles.sort {
            ($0.profile, $0.semanticProfileRevision, $0.renderProfileRevision)
                < ($1.profile, $1.semanticProfileRevision, $1.renderProfileRevision)
        }
        persist(snapshot)
    }

    func snapshot() -> ShadowExportEvidenceSnapshot {
        load()
    }

    func reset() {
        userDefaults.removeObject(forKey: storageKey)
    }

    private func load() -> ShadowExportEvidenceSnapshot {
        guard let data = userDefaults.data(forKey: storageKey),
              data.count <= Self.maximumPersistedBytes,
              let decoded = try? decoder.decode(ShadowExportEvidenceSnapshot.self, from: data),
              decoded.schema == ShadowExportEvidenceSnapshot.schema,
              decoded.version == ShadowExportEvidenceSnapshot.version,
              decoded.profiles.count <= 16,
              decoded.profiles.allSatisfy(Self.isValid) else {
            return .empty
        }
        return decoded
    }

    private func persist(_ snapshot: ShadowExportEvidenceSnapshot) {
        guard let data = try? encoder.encode(snapshot),
              data.count <= Self.maximumPersistedBytes else {
            return
        }
        userDefaults.set(data, forKey: storageKey)
    }

    private static func isValid(_ profile: ShadowExportProfileEvidence) -> Bool {
        profile.profile == AppleExportEnginePin.profileID
            && profile.semanticProfileRevision > 0
            && profile.renderProfileRevision > 0
            && profile.mismatchDimensions.keys.allSatisfy {
                NativeExportPlanMismatchDiagnostic.Kind(rawValue: $0) != nil
            }
            && profile.rustFailureCodes.keys.allSatisfy {
                ShadowExportFailureDiagnostic.Kind(rawValue: $0) != nil
            }
    }

    private static func increment(_ value: inout UInt64, by amount: UInt64 = 1) {
        let result = value.addingReportingOverflow(amount)
        value = result.overflow ? .max : result.partialValue
    }

    private static func increment(_ values: inout [String: UInt64], key: String) {
        var value = values[key, default: 0]
        increment(&value)
        values[key] = value
    }

    private struct EvidenceEvent {
        enum Kind {
            case comparison(matches: Bool, mismatchCount: UInt32)
            case mismatch(String)
            case rustFailure(String)
        }

        let profile: String
        let semanticProfileRevision: UInt32
        let renderProfileRevision: UInt32
        let kind: Kind

        init?(_ diagnostic: ShadowExportDiagnostic) {
            switch diagnostic {
            case .comparisonCompleted(let event):
                profile = event.profile
                semanticProfileRevision = event.semanticProfileRevision
                renderProfileRevision = event.renderProfileRevision
                kind = .comparison(matches: event.matches, mismatchCount: event.mismatchCount)
            case .planMismatch(let mismatch):
                profile = mismatch.profile
                semanticProfileRevision = mismatch.semanticProfileRevision
                renderProfileRevision = mismatch.renderProfileRevision
                kind = .mismatch(mismatch.mismatchKind.rawValue)
            case .rustRenderFailed(let failure):
                profile = failure.profile
                semanticProfileRevision = failure.semanticProfileRevision
                renderProfileRevision = failure.renderProfileRevision
                kind = .rustFailure(failure.kind.rawValue)
            }
        }

        var isValid: Bool {
            profile == AppleExportEnginePin.profileID
                && semanticProfileRevision > 0
                && renderProfileRevision > 0
        }
    }
}
