import CryptoKit
import Darwin
import Foundation
import HealthMdConnectionCore

/// OS protection is a native dependency, never a request option. Synthetic SDK tests provide
/// their own implementation; installed callers retain the strict system implementation.
@MainActor
protocol AgentBridgeNativeCaptureProtecting {
    func applyCompleteProtection(_ fd: Int32) throws
    func requireCompleteProtection(_ fd: Int32) throws
}

@MainActor
struct AgentBridgeSystemNativeCaptureProtection: AgentBridgeNativeCaptureProtecting {
    nonisolated init() {}
    func applyCompleteProtection(_ fd: Int32) throws { try AgentBridgeNativeCaptureSpool.protect(fd) }
    func requireCompleteProtection(_ fd: Int32) throws { try AgentBridgeNativeCaptureSpool.verifyProtection(fd) }
}

/// Private captured values, engine identity and immutable generated artifacts. This is not a
/// permission token. A signed transfer frontier records only verified base acknowledgements. The accepted job, protected key and original fence own it.
@MainActor
final class AgentBridgeNativeCaptureSpool {
    nonisolated private struct Record: Codable, Equatable {
        let version: Int
        let requestSHA256: String
        let resolutionSHA256: String
        let claimID: String
        let expiresAt: String
        let kind: String
        let day: String?
        let payload: Data
    }
    nonisolated private struct Signed: Codable { let record: Record; let mac: Data }
    private static let domain = Data("HealthMd.AgentBridge.NativeCaptureSpool.v1\0".utf8)
    nonisolated private struct Progress: Codable {
        var version: Int
        var captures: [String]
        var artifacts: [String]
        var engine: Data
        // Version3 stores exactly16 UUID bytes per sorted artifact day. Keeping this compact
        // preserves the existing progress/record bounds even at4096 approved days.
        var publicArtifactIDs: Data? = nil
        var manifestSHA256: String? = nil
        var manifestByteCount: Int? = nil
        var transferSHA256: String? = nil
        var transferByteCount: Int? = nil
        var committedPartitionCount: Int64? = nil
        var frontierSHA256: String? = nil
    }
    nonisolated struct ArtifactCheckpoint: Sendable { let engine: Data; let payload: Data }
    private static let payloadLimit = 64 * 1024
    private static let progressLimit = 256 * 1024
    private static let recordLimit = 512 * 1024
    private static let jobLimit = 64 * 1024 * 1024
    private let reservation: AgentBridgeExportCaptureReservation
    private let key: SymmetricKey
    private let fileProtection: any AgentBridgeNativeCaptureProtecting
    private let fence: @MainActor () throws -> Void
    private let stopRequest: (@MainActor () throws -> AgentBridgeCancel)?
    private var initializing = true
    private var recordingStop = false
    private var inspectingCancellation = false
    private let issuer: URL
    private let captures: URL
    private let directory: URL
    private var issuerFD: Int32 = -1
    private var capturesFD: Int32 = -1
    private var directoryFD: Int32 = -1
    private var lockFD: Int32 = -1
    private var identities: [AgentBridgeExportFileIdentity] = []
    private var storedBytes = 0
    private var closed = false
    private struct ProtectedFileEvidence { let count: Int; let sha256: String; let identity: AgentBridgeExportFileIdentity }
    private var collectingFileEvidence: [String: ProtectedFileEvidence]?
    private var resumeEvidence: [String: ProtectedFileEvidence]?
    private var admittedResume: AgentBridgeResume?
    private var completionEvidence: [String: ProtectedFileEvidence]?
    private var completionReceipt: AgentBridgeExecutionReceipt?


    init(issuer: URL, reservation: AgentBridgeExportCaptureReservation, key: SymmetricKey, create: Bool,
         fileProtection: any AgentBridgeNativeCaptureProtecting = AgentBridgeSystemNativeCaptureProtection(),
         stopRequest: (@MainActor () throws -> AgentBridgeCancel)? = nil,
         fence: @escaping @MainActor () throws -> Void) throws {
        self.issuer = issuer; self.reservation = reservation; self.key = key; self.fileProtection = fileProtection; self.fence = fence; self.stopRequest = stopRequest
        captures = issuer.appendingPathComponent("captures", isDirectory: true)
        directory = captures.appendingPathComponent(reservation.job.requestSHA256.rawValue, isDirectory: true)
        do {
            try reservation.job.validate()
            guard reservation.claim.version == 1, reservation.claim.requestSHA256 == reservation.job.requestSHA256,
                  reservation.claim.claimedAt.rawValue >= reservation.job.acceptedAt.rawValue,
                  reservation.claim.claimedAt.rawValue < reservation.job.expiresAt.rawValue else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try authorityFence()
            issuerFD = try AgentBridgeExportPrivateFiles.openDirectory(issuer, privateLeaf: true)
            identities = [try AgentBridgeExportPrivateFiles.identity(issuerFD)]
            try check()
            if create { try mkdir(issuerFD, "captures", exclusive: false) }
            capturesFD = try AgentBridgeExportPrivateFiles.openDirectory(captures, privateLeaf: true)
            try fileProtection.requireCompleteProtection(capturesFD)
            identities.append(try AgentBridgeExportPrivateFiles.identity(capturesFD))
            try check()
            if create { try mkdir(capturesFD, reservation.job.requestSHA256.rawValue, exclusive: true) }
            directoryFD = try AgentBridgeExportPrivateFiles.openDirectory(directory, privateLeaf: true)
            try fileProtection.requireCompleteProtection(directoryFD)
            identities.append(try AgentBridgeExportPrivateFiles.identity(directoryFD))
            try check()
            if create {
                let fd = openat(directoryFD, "lock", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard fd >= 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                do { try protectFile(fd); guard fsync(fd) == 0, fsync(directoryFD) == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired } }
                catch { Darwin.close(fd); throw error }
                Darwin.close(fd)
            }
            lockFD = try AgentBridgeExportPrivateFiles.openPrivateFile(directoryFD, "lock", flags: O_RDWR)
            try fileProtection.requireCompleteProtection(lockFD)
            guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw AgentBridgeValidationError.busy }
            guard try fileSize("lock") == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try check()
            for name in try Self.entries(directoryFD) {
                guard name == "lock" || name == "header.json" || name == "progress.json" || name == "manifest.json" || name == "transfer.json" || name == "partition-awaiting-ack.json" || name == "completion.json" || name == "capture-stop.json" || Self.hostCommitName(name) || Self.dayName(name) || Self.pendingName(name) else {
                    throw AgentBridgeValidationError.spoolMissingRestartRequired
                }
                storedBytes += try fileSize(name)
                guard storedBytes <= Self.jobLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
            }
            if create {
                try publish("header.json", record: record(kind: "job", day: nil))
                try publish("progress.json", record: record(kind: "progress", day: nil, payload: JSONEncoder().encode([String]())))
            } else {
                guard try read("header.json") == record(kind: "job", day: nil) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                _ = try progress()
            }
            try validateStoredProgress()
            try check()
            initializing = false
        } catch { close(); throw Self.safe(error) }
    }
    deinit { Darwin.close(lockFD); Darwin.close(directoryFD); Darwin.close(capturesFD); Darwin.close(issuerFD) }

    /// A retained successful capture is immutable. A started marker without captured bytes is
    /// ambiguous and must never trigger a second SDK read, including after process restart.
    func loadOrBegin(_ day: AgentBridgeDate) throws -> Data? {
        do {
            try check()
            let started = "started-\(day.rawValue).json", captured = "day-\(day.rawValue).json"
            let (previous, state) = try progress()
            let days = state.captures
            if days.contains(day.rawValue) {
                guard try exists(captured) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                guard try read(started) == record(kind: "started", day: day.rawValue) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                let value = try read(captured)
                guard value.kind == "captured", value.day == day.rawValue, !value.payload.isEmpty else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                try check(); return value.payload
            }
            guard try !exists(started), try !exists(captured) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            guard state.publicArtifactIDs == nil else { throw AgentBridgeValidationError.bindingChanged }
            guard days.count < 4096 else { throw AgentBridgeValidationError.queryBudgetExceeded }
            guard storedBytes + 2 * Self.payloadLimit < Self.jobLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
            var nextState = state; nextState.captures = (days + [day.rawValue]).sorted()
            let next = try progressBytes(nextState)
            try publish("progress.json", record: record(kind: "progress", day: nil, payload: next), replacing: previous)
            try publish(started, record: record(kind: "started", day: day.rawValue))
            return nil
        } catch { throw Self.safe(error) }
    }
    func commit(_ day: AgentBridgeDate, payload: Data) throws {
        do {
            guard !payload.isEmpty, payload.count <= Self.payloadLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
            try check()
            guard try progress().1.captures.contains(day.rawValue) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            guard try read("started-\(day.rawValue).json") == record(kind: "started", day: day.rawValue) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try publish("day-\(day.rawValue).json", record: record(kind: "captured", day: day.rawValue, payload: payload))
        } catch { throw Self.safe(error) }
    }
    /// Completed bytes are reusable without consulting the current renderer. A recorded start
    /// without its immutable artifact is ambiguous and never permits regeneration.
    func retainedArtifact(_ day: AgentBridgeDate) throws -> ArtifactCheckpoint? {
        do {
            try check()
            let state = try progress().1
            guard state.artifacts.contains(day.rawValue) else { return nil }
            guard state.captures.contains(day.rawValue), !state.engine.isEmpty,
                  try read("artifact-started-\(day.rawValue).json") == record(kind: "artifact-started", day: day.rawValue) else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
            let value = try read("artifact-\(day.rawValue).json")
            guard value.kind == "artifact", value.day == day.rawValue, !value.payload.isEmpty else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
            try check(); return .init(engine: state.engine, payload: value.payload)
        } catch { throw Self.safe(error) }
    }
    func beginArtifact(_ day: AgentBridgeDate, engine: Data) throws {
        do {
            try check()
            let (previous, state) = try progress()
            guard !engine.isEmpty, engine.count <= 4096 else { throw AgentBridgeValidationError.queryBudgetExceeded }
            guard state.engine.isEmpty || state.engine == engine else { throw AgentBridgeValidationError.bindingChanged }
            guard state.publicArtifactIDs == nil else { throw AgentBridgeValidationError.bindingChanged }
            guard state.artifacts.count < 4096 else { throw AgentBridgeValidationError.queryBudgetExceeded }
            guard !state.artifacts.contains(day.rawValue),
                  try !exists("artifact-started-\(day.rawValue).json"), try !exists("artifact-\(day.rawValue).json") else {
                throw AgentBridgeValidationError.busy
            }
            var next = state; next.artifacts = (state.artifacts + [day.rawValue]).sorted(); next.engine = engine
            try publish("progress.json", record: record(kind: "progress", day: nil, payload: progressBytes(next)), replacing: previous)
            try publish("artifact-started-\(day.rawValue).json", record: record(kind: "artifact-started", day: day.rawValue))
        } catch { throw Self.safe(error) }
    }
    func commitArtifact(_ day: AgentBridgeDate, engine: Data, payload: Data) throws {
        do {
            try check()
            let state = try progress().1
            guard state.engine == engine, state.artifacts.contains(day.rawValue), state.captures.contains(day.rawValue),
                  try read("artifact-started-\(day.rawValue).json") == record(kind: "artifact-started", day: day.rawValue) else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
            let captured = try read("day-\(day.rawValue).json")
            guard captured.kind == "captured", captured.day == day.rawValue, !captured.payload.isEmpty else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            guard !payload.isEmpty, payload.count <= Self.payloadLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
            try publish("artifact-\(day.rawValue).json", record: record(kind: "artifact", day: day.rawValue, payload: payload))
        } catch { throw Self.safe(error) }
    }

    /// Bind only a complete approved set. The signed progress publication is the single
    /// issuance point; recovery derives the same day/UUID mapping without another random ID.
    func bindPublicArtifactIDs(_ approvedDays: [AgentBridgeDate]) throws -> [String: String] {
        do {
            try check()
            let approved = approvedDays.map(\.rawValue)
            let (previous, state) = try progress()
            guard !approved.isEmpty, Set(approved).count == approved.count,
                  approved.sorted() == state.captures, state.captures == state.artifacts else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
            try validateStoredProgress()
            if state.publicArtifactIDs == nil {
                var bytes = Data()
                for _ in state.artifacts {
                    var uuid = UUID().uuid
                    withUnsafeBytes(of: &uuid) { bytes.append(contentsOf: $0) }
                }
                var next = state; next.version = 3; next.publicArtifactIDs = bytes
                _ = try Self.publicIDs(next) // Reject malformed or duplicate generator output before publication.
                try publish("progress.json", record: record(kind: "progress", day: nil, payload: progressBytes(next)), replacing: previous)
            }
            let result = try Self.publicIDs(progress().1)
            try check(); return result
        } catch { throw Self.safe(error) }
    }

    /// Preserve exact public metadata from this job's signed inputs, never incoming caller
    /// metadata. A pinned manifest missing its bytes is ambiguous and cannot be regenerated.
    func preserveManifest() throws -> Data {
        do {
            try check(); try validateStoredProgress()
            let (previous, state) = try progress()
            if state.manifestSHA256 != nil { return try readManifest(state) }
            let bytes = try makeManifest(state)
            var next = state; next.version = 4
            next.manifestSHA256 = AgentBridgeV4Codec.sha256(bytes); next.manifestByteCount = bytes.count
            // Advance the durable frontier before raw publication. Interruption cannot cause
            // a missing manifest to be silently rebuilt or reinterpreted by a newer writer.
            try publish("progress.json", record: record(kind: "progress", day: nil, payload: progressBytes(next)), replacing: previous)
            try publishBytes("manifest.json", bytes: bytes, previousBytes: nil)
            let retained = try readManifest(progress().1)
            try check(); return retained
        } catch { throw Self.safe(error) }
    }
    private func makeManifest(_ state: Progress) throws -> Data {
        let ids = try Self.publicIDs(state)
        let resolution = try PropertyListDecoder().decode(AgentBridgeRequestSettingsResolution.self, from: reservation.job.nativeResolution)
        let selected = Set(resolution.selection.map(\.semanticID))
        guard !selected.isEmpty, selected.count == resolution.selection.count,
              resolution.requestedDays.map(\.rawValue).sorted() == state.artifacts else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        var counts = Dictionary(uniqueKeysWithValues: selected.map { ($0, Int64(0)) })
        var artifacts: [AgentBridgeArtifact] = []
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        for day in resolution.requestedDays {
            let saved = try read("artifact-\(day.rawValue).json")
            let result = try AgentBridgeNativeArtifactJournal.restore(.init(engine: state.engine, payload: saved.payload),
                day: day, resolution: resolution, fingerprint: acceptedRequestSHA256)
            let capturedRecord = try read("day-\(day.rawValue).json")
            let captured = try JSONDecoder().decode(AgentBridgeCapturedScalarDay.self, from: capturedRecord.payload)
            guard saved.kind == "artifact", saved.day == day.rawValue,
                  capturedRecord.kind == "captured", capturedRecord.day == day.rawValue,
                  captured.version == 1, captured.day == day.rawValue,
                  captured.calendarTimezone == resolution.settings.calendarTimeZoneIdentifier,
                  Set(captured.values.keys).isSubset(of: selected), captured.values.values.allSatisfy({ $0.isFinite && $0 >= 0 }),
                  try encoder.encode(captured) == capturedRecord.payload, let id = ids[day.rawValue] else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
            // Summary record units are captured daily observations, including meaningful zero.
            // These counters never infer the number of underlying HealthKit samples.
            for selector in captured.values.keys { counts[selector, default: 0] += 1 }
            artifacts.append(.init(artifactId: try AgentBridgeUUID(id), byteCount: Int64(result.artifact.byteCount),
                mediaType: .applicationJson, profile: .appleV8, relativePath: try AgentBridgePath(result.artifact.relativePath ?? ""),
                sha256: try AgentBridgeDigest(result.artifact.sha256), writeMode: .overwrite))
        }
        let request = try reservation.job.request()
        let manifest = AgentBridgeArtifactManifest(artifacts: artifacts, binding: AgentBridgeSemantics.binding(request.plan),
            branchStatuses: try selected.sorted().map { .init(recordCount: counts[$0, default: 0], selectorId: try AgentBridgeID($0), status: .success) },
            captureStatus: .complete, jobId: request.jobId, requestSha256: reservation.job.requestSHA256)
        return try AgentBridgeV4Codec.encode(manifest)
    }
    private func readManifest(_ state: Progress) throws -> Data {
        try check()
        guard let digest = state.manifestSHA256, let count = state.manifestByteCount,
              try exists("manifest.json") else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        let bytes = try readProtectedFile("manifest.json", maximumBytes: AgentBridgeV4Codec.maximumBytes)
        do {
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: bytes)
            let request = try reservation.job.request()
            guard bytes.count == count, AgentBridgeV4Codec.sha256(bytes) == digest,
                  try AgentBridgeV4Codec.encode(manifest) == bytes,
                  manifest.jobId == request.jobId, manifest.requestSha256 == reservation.job.requestSHA256,
                  manifest.binding == AgentBridgeSemantics.binding(request.plan),
                  Set(manifest.artifacts.map { $0.artifactId.rawValue }) == Set(try Self.publicIDs(state).values) else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
        } catch { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        try check(); return bytes
    }

    /// Read-only preflight. Missing unpinned metadata is not created; a pinned missing/corrupt
    /// record still rejects through the same original-job validation as recovery.
    func retainedTransferPlan() throws -> Data? {
        do {
            try check(); try validateStoredProgress()
            let state = try progress().1
            let result = state.transferSHA256 == nil ? nil : try readTransferPlan(state)
            try check(); return result
        } catch { throw Self.safe(error) }
    }

    /// Pin compact exact session/partition metadata before raw publication. A pin without its
    /// original bytes is ambiguous and never permits a new session or random partition IDs.
    func preserveTransferPlan(_ negotiation: DirectTransferNegotiation) throws -> Data {
        do {
            try check(); try validateStoredProgress()
            let (previous, state) = try progress()
            if state.transferSHA256 != nil { return try readTransferPlan(state) }
            try AgentBridgeNativeTransferCheckpoint.validateNegotiation(negotiation)
            let manifestBytes = try readManifest(state)
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: manifestBytes)
            let checkpoint = try AgentBridgeNativeTransferCheckpoint.create(requestSHA256: acceptedRequestSHA256,
                manifestSHA256: AgentBridgeV4Codec.sha256(manifestBytes), createdAt: reservation.job.acceptedAt.rawValue,
                expiresAt: reservation.job.expiresAt.rawValue, count: manifest.artifacts.count, negotiation: negotiation)
            _ = try checkpoint.validate(requestSHA256: acceptedRequestSHA256, manifestSHA256: AgentBridgeV4Codec.sha256(manifestBytes),
                createdAt: reservation.job.acceptedAt.rawValue, expiresAt: reservation.job.expiresAt.rawValue,
                artifactIDs: manifest.artifacts.map { $0.artifactId.rawValue })
            let bytes = try checkpoint.canonical()
            guard bytes.count <= AgentBridgeNativeTransferCheckpoint.maximumBytes else { throw AgentBridgeValidationError.queryBudgetExceeded }
            var next = state; next.version = 5
            next.transferSHA256 = AgentBridgeV4Codec.sha256(bytes); next.transferByteCount = bytes.count
            try publish("progress.json", record: record(kind: "progress", day: nil, payload: progressBytes(next)), replacing: previous)
            try publishBytes("transfer.json", bytes: bytes, previousBytes: nil)
            let retained = try readTransferPlan(progress().1)
            try check(); return retained
        } catch { throw Self.safe(error) }
    }
    private func readTransferPlan(_ state: Progress) throws -> Data {
        try check()
        guard let digest = state.transferSHA256, let count = state.transferByteCount, try exists("transfer.json") else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        let bytes = try readProtectedFile("transfer.json", maximumBytes: AgentBridgeNativeTransferCheckpoint.maximumBytes)
        do {
            guard bytes.count == count, AgentBridgeV4Codec.sha256(bytes) == digest else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            let manifestBytes = try readManifest(state)
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: manifestBytes)
            let checkpoint = try AgentBridgeNativeTransferCheckpoint.decode(bytes)
            _ = try checkpoint.validate(requestSHA256: acceptedRequestSHA256, manifestSHA256: AgentBridgeV4Codec.sha256(manifestBytes),
                createdAt: reservation.job.acceptedAt.rawValue, expiresAt: reservation.job.expiresAt.rawValue,
                artifactIDs: manifest.artifacts.map { $0.artifactId.rawValue })
        } catch { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        try check(); return bytes
    }

    /// Existing-job Resume admission. An optional exact original ACK may advance only its
    /// proven pending prefix; no migration, metadata repair or caller-provided prefix installation.
    func requireResume(_ resume: AgentBridgeResume, acknowledging acknowledgement: DirectTransferPartitionAcknowledgement? = nil) throws {
        do {
            try check()
            collectingFileEvidence = [:]
            defer { collectingFileEvidence = nil }
            guard try read("header.json") == record(kind: "job", day: nil) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try validateStoredProgress()
            let (previous, state) = try progress()
            let request = try reservation.job.request()
            let manifest = try readManifest(state)
            let current = try checkedTransferFrontier(state)
            let frontier = try acknowledgement.map { try acknowledgementFrontier($0, state: state) } ?? current
            guard resume.jobId == request.jobId, resume.peer == request.plan.intent.peer,
                  resume.destination == request.plan.intent.destination,
                  resume.binding == AgentBridgeSemantics.binding(request.plan),
                  resume.requestSha256 == reservation.job.requestSHA256,
                  resume.manifestSha256.rawValue == AgentBridgeV4Codec.sha256(manifest),
                  resume.committedPartitionCount == frontier.committedPartitionCount,
                  resume.frontierSha256 == frontier.sha256 else { throw AgentBridgeValidationError.bindingChanged }
            if frontier != current {
                // Compare the complete Resume before writing. Re-pin original files after the
                // last native callback and immediately before the single progress publication.
                guard let evidence = collectingFileEvidence else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                _ = try publishAcknowledgedFrontier(frontier, previous: previous, state: state, evidence: evidence)
                try validateStoredProgress()
                guard try checkedTransferFrontier(progress().1) == frontier else { throw AgentBridgeValidationError.bindingChanged }
            }
            resumeEvidence = collectingFileEvidence
            admittedResume = resume
            try check(); try requirePreservedResume(resume)
        } catch { throw Self.safe(error) }
    }

    /// Local-only admission tail after every delaying authority callback.
    func requirePreservedResume(_ resume: AgentBridgeResume) throws {
        guard admittedResume == resume, let evidence = resumeEvidence else { throw AgentBridgeValidationError.bindingChanged }
        try requireProtectedEvidence(evidence)
    }

    /// Initialize only from the exact pinned manifest/session. Legacy v5 had no durable
    /// acknowledged prefix; its explicit migration starts at zero and never remints metadata.
    func preserveTransferFrontier() throws -> AgentBridgeTransferFrontier {
        do {
            try check(); try validateStoredProgress()
            let (previous, state) = try progress()
            if state.version == 6 { return try checkedTransferFrontier(state) }
            guard state.version == 5 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            let frontier = try computedTransferFrontier(state, count: 0)
            var next = state; next.version = 6
            next.committedPartitionCount = 0; next.frontierSHA256 = frontier.sha256.rawValue
            try publish("progress.json", record: record(kind: "progress", day: nil, payload: progressBytes(next)), replacing: previous)
            let result = try checkedTransferFrontier(progress().1)
            try check(); return result
        } catch { throw Self.safe(error) }
    }

    /// Persist only after the exact chunk acknowledgement, before PartitionComplete.
    /// The record authorizes no reads and advances no frontier; recovery may verify one lost ACK.
    func preserveAwaitingPartitionAcknowledgement(_ index: Int64) throws {
        do {
            try check(); try validateStoredProgress()
            let state = try progress().1
            let frontier = try checkedTransferFrontier(state)
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: readManifest(state))
            guard index == frontier.committedPartitionCount, index >= 0, index < Int64(manifest.artifacts.count) else {
                throw AgentBridgeValidationError.bindingChanged
            }
            let previous = try exists("partition-awaiting-ack.json") ? read("partition-awaiting-ack.json") : nil
            let value = try record(kind: "partition_awaiting_ack", day: nil, payload: Self.canonical(index))
            if previous != value { try publish("partition-awaiting-ack.json", record: value, replacing: previous) }
            guard try awaitingPartitionAcknowledgement(state) == index else { throw AgentBridgeValidationError.bindingChanged }
            try check()
        } catch { throw Self.safe(error) }
    }

    /// Reconcile only the exact original pending ACK, or the exact last committed ACK.
    /// Incoming counts/frontiers never install native progress.
    func reconcilePartitionAcknowledgement(_ ack: DirectTransferPartitionAcknowledgement) throws -> AgentBridgeTransferFrontier {
        do {
            try check()
            collectingFileEvidence = [:]
            defer { collectingFileEvidence = nil }
            guard try read("header.json") == record(kind: "job", day: nil) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try validateStoredProgress()
            let (previous, state) = try progress()
            let frontier = try acknowledgementFrontier(ack, state: state)
            if frontier.committedPartitionCount == state.committedPartitionCount { try check(); return frontier }
            guard let evidence = collectingFileEvidence else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            return try publishAcknowledgedFrontier(frontier, previous: previous, state: state, evidence: evidence)
        } catch { throw Self.safe(error) }
    }

    private func acknowledgementFrontier(_ ack: DirectTransferPartitionAcknowledgement, state: Progress) throws -> AgentBridgeTransferFrontier {
        let frontier = try checkedTransferFrontier(state)
        let bytes = try readManifest(state)
        let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: bytes)
        let checkpoint = try AgentBridgeNativeTransferCheckpoint.decode(readTransferPlan(state))
        let ids = try checkpoint.validate(requestSHA256: acceptedRequestSHA256, manifestSHA256: AgentBridgeV4Codec.sha256(bytes),
            createdAt: reservation.job.acceptedAt.rawValue, expiresAt: reservation.job.expiresAt.rawValue,
            artifactIDs: manifest.artifacts.map { $0.artifactId.rawValue })
        let index = Int64(ack.partitionIndex)
        guard ack.accepted, ack.sessionID.uuidString.lowercased() == checkpoint.sessionID,
              ack.jobID == UUID(uuidString: manifest.jobId.rawValue), index >= 0, index < Int64(manifest.artifacts.count),
              (index == frontier.committedPartitionCount || index == frontier.committedPartitionCount - 1),
              ack.transferID == ids[Int(index)], ack.partitionSHA256 == manifest.artifacts[Int(index)].sha256.rawValue else {
            throw AgentBridgeValidationError.bindingChanged
        }
        if index < frontier.committedPartitionCount { return frontier }
        guard try awaitingPartitionAcknowledgement(state) == index else { throw AgentBridgeValidationError.bindingChanged }
        return try computedTransferFrontier(state, count: index + 1)
    }

    private func publishAcknowledgedFrontier(_ frontier: AgentBridgeTransferFrontier, previous: Record, state: Progress,
        evidence: [String: ProtectedFileEvidence]) throws -> AgentBridgeTransferFrontier {
        var next = state; next.committedPartitionCount = frontier.committedPartitionCount
        next.frontierSHA256 = frontier.sha256.rawValue
        try publish("progress.json", record: record(kind: "progress", day: nil, payload: progressBytes(next)),
            replacing: previous, evidenceBeforePublication: evidence)
        let result = try checkedTransferFrontier(progress().1)
        guard result == frontier else { throw AgentBridgeValidationError.bindingChanged }
        try check(); return result
    }

    private func awaitingPartitionAcknowledgement(_ state: Progress) throws -> Int64? {
        guard try exists("partition-awaiting-ack.json") else { return nil }
        let record = try read("partition-awaiting-ack.json")
        let index = try JSONDecoder().decode(Int64.self, from: record.payload)
        // Later alreadyCommitted dispositions can advance beyond the last chunked partition.
        // Historical evidence never satisfies the exact-next eligibility check above.
        let frontier = try checkedTransferFrontier(state)
        let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: readManifest(state))
        guard record.kind == "partition_awaiting_ack", record.day == nil, record.payload == (try Self.canonical(index)),
              index >= 0, index < Int64(manifest.artifacts.count),
              index <= frontier.committedPartitionCount else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        try check(); return index
    }

    /// Called only after the original owner validated a partition acknowledgement or an exact
    /// alreadyCommitted disposition. Publication must finish before the next send/finalize.
    func recordAcknowledgedTransferPartition(_ index: Int64) throws -> AgentBridgeTransferFrontier {
        do {
            try check(); try validateStoredProgress()
            let (previous, state) = try progress()
            let current = try checkedTransferFrontier(state)
            guard index >= 0, index <= current.committedPartitionCount else { throw AgentBridgeValidationError.bindingChanged }
            // Exact earlier dispositions are idempotent; they do not reset or rewrite the prefix.
            if index < current.committedPartitionCount { try check(); return current }
            let frontier = try computedTransferFrontier(state, count: index + 1)
            var next = state; next.committedPartitionCount = frontier.committedPartitionCount
            next.frontierSHA256 = frontier.sha256.rawValue
            try publish("progress.json", record: record(kind: "progress", day: nil, payload: progressBytes(next)), replacing: previous)
            let result = try checkedTransferFrontier(progress().1)
            try check(); return result
        } catch { throw Self.safe(error) }
    }
    private func checkedTransferFrontier(_ state: Progress) throws -> AgentBridgeTransferFrontier {
        guard state.version == 6, let count = state.committedPartitionCount, let hash = state.frontierSHA256 else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        let result = try computedTransferFrontier(state, count: count)
        guard result.sha256.rawValue == hash else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        try check(); return result
    }
    private func computedTransferFrontier(_ state: Progress, count: Int64) throws -> AgentBridgeTransferFrontier {
        let checkpoint = try AgentBridgeNativeTransferCheckpoint.decode(readTransferPlan(state))
        let bytes = try readManifest(state)
        let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: bytes)
        guard count >= 0, count <= Int64(manifest.artifacts.count) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        let ids = try checkpoint.validate(requestSHA256: acceptedRequestSHA256, manifestSHA256: AgentBridgeV4Codec.sha256(bytes),
            createdAt: reservation.job.acceptedAt.rawValue, expiresAt: reservation.job.expiresAt.rawValue,
            artifactIDs: manifest.artifacts.map { $0.artifactId.rawValue })
        var frontier = try AgentBridgeTransferFrontier(jobID: manifest.jobId, requestSHA256: manifest.requestSha256,
            manifestSHA256: AgentBridgeDigest(AgentBridgeV4Codec.sha256(bytes)), sessionID: AgentBridgeUUID(checkpoint.sessionID))
        for index in 0..<Int(count) {
            let artifact = manifest.artifacts[index]
            guard artifact.byteCount > 0, artifact.byteCount <= Int64(DirectTransferLimits.chunkBytes) else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
            frontier = try frontier.appending(.init(partitionIndex: Int64(index), transferID: AgentBridgeUUID(ids[index].uuidString.lowercased()),
                artifactID: artifact.artifactId, artifactOffset: 0, byteCount: artifact.byteCount, chunkCount: 1, sha256: artifact.sha256))
        }
        try check(); return frontier
    }

    /// Each signed receipt is its own atomic journal entry; the manifest supplies its fixed
    /// position. A contiguous authenticated set needs no separately updated counter.
    func recordHostCommit(_ receipt: AgentBridgeCommitReceipt) throws {
        do {
            try check(); try validateStoredProgress()
            let state = try progress().1
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: readManifest(state))
            let commits = try readHostCommits(state, manifest: manifest)
            guard let index = manifest.artifacts.firstIndex(where: { $0.artifactId == receipt.artifactId }),
                  index <= commits.count else { throw AgentBridgeValidationError.bindingChanged }
            try validateHostCommit(receipt, artifact: manifest.artifacts[index], manifest: manifest)
            guard try checkedTransferFrontier(state).committedPartitionCount == Int64(manifest.artifacts.count) else { throw AgentBridgeValidationError.bindingChanged }
            if index < commits.count {
                try AgentBridgeSemantics.validateCommitReplay(receipt, persisted: commits[index])
            } else {
                try publish("host-commit-\(receipt.artifactId.rawValue).json", record: record(kind: "host_commit", day: receipt.artifactId.rawValue,
                    payload: AgentBridgeV4Codec.encode(receipt)))
            }
            try validateStoredProgress(); try check()
        } catch { throw Self.safe(error) }
    }
    /// Read-only retained state, not authority to acknowledge cancellation. A missing manifest
    /// or frontier stays absent; inspection never advances capture or creates completion.
    final class CancellationCheckpoint {
        let capturedDayCount: Int
        let artifactCount: Int?
        let manifestSHA256: String?
        let committedPartitionCount: Int64?
        let frontierSHA256: String?
        let completion: AgentBridgeExecutionReceipt?

        fileprivate init(capturedDayCount: Int, artifactCount: Int?, manifestSHA256: String?,
                         frontier: AgentBridgeTransferFrontier?, completion: AgentBridgeExecutionReceipt?) {
            self.capturedDayCount = capturedDayCount; self.artifactCount = artifactCount
            self.manifestSHA256 = manifestSHA256; committedPartitionCount = frontier?.committedPartitionCount
            frontierSHA256 = frontier?.sha256.rawValue; self.completion = completion
        }
    }
    private var cancellationCheckpoint: CancellationCheckpoint?
    private var cancellationEvidence: [String: ProtectedFileEvidence]?

    func inspectCancellationCheckpoint() throws -> CancellationCheckpoint {
        let previous = inspectingCancellation; inspectingCancellation = true
        defer { inspectingCancellation = previous }
        do {
            try check()
            collectingFileEvidence = [:]
            defer { collectingFileEvidence = nil }
            guard try read("header.json") == record(kind: "job", day: nil) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try validateStoredProgress()
            let state = try progress().1
            let manifest = try state.manifestSHA256.map { _ in
                try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: readManifest(state))
            }
            let frontier = try state.version == 6 ? checkedTransferFrontier(state) : nil
            // validateStoredProgress has authenticated any existing completion and its commits.
            // Do not call preserveCompletion: absence must never become a new completion here.
            let completion = try exists("completion.json") ? manifest.map { try completionCandidate(state, manifest: $0) } : nil
            let checkpoint = CancellationCheckpoint(capturedDayCount: try state.captures.filter { try exists("day-\($0).json") }.count,
                artifactCount: manifest?.artifacts.count, manifestSHA256: state.manifestSHA256,
                frontier: frontier, completion: completion)
            let evidence = collectingFileEvidence ?? [:]
            try check(); try requireProtectedEvidence(evidence)
            cancellationCheckpoint = checkpoint; cancellationEvidence = evidence
            return checkpoint
        } catch { throw Self.safe(error) }
    }
    /// Local-only publication tail: no SDK, native callback, repair or file creation.
    func requireCancellationCheckpoint(_ checkpoint: CancellationCheckpoint) throws {
        guard cancellationCheckpoint === checkpoint, let evidence = cancellationEvidence else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        do { try requireProtectedEvidence(evidence) }
        catch AgentBridgeValidationError.bindingChanged {
            // This tail has only local file/identity checks. Changed retained evidence cannot
            // qualify cancellation; no authority callback error is reclassified here.
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
    }

    /// Only an authenticated retained checkpoint can supply this value. It does not persist a
    /// terminal stop; the issuer must commit it while this exclusive spool lock is still held.
    func cancellationReceipt(_ checkpoint: CancellationCheckpoint) throws -> AgentBridgeExecutionReceipt {
        try requireCancellationCheckpoint(checkpoint)
        if let completion = checkpoint.completion { return completion }
        let accepted = try reservation.job.acceptedReceipt()
        if checkpoint.manifestSHA256 == nil {
            // Captured private bytes may exist; only the public manifest/frontier are absent.
            return .init(artifactCount: 0, binding: accepted.binding, committedPartitionCount: 0,
                expiresAt: accepted.expiresAt, frontierSha256: accepted.frontierSha256, jobId: accepted.jobId,
                manifestSha256: accepted.manifestSha256, requestSha256: accepted.requestSha256,
                sourceAcknowledged: true, status: .cancelled)
        }
        guard let manifest = checkpoint.manifestSHA256, let count = checkpoint.artifactCount,
              let committed = checkpoint.committedPartitionCount, let frontier = checkpoint.frontierSHA256 else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        return .init(artifactCount: Int64(count), binding: accepted.binding, committedPartitionCount: committed,
            expiresAt: accepted.expiresAt, frontierSha256: try AgentBridgeDigest(frontier), jobId: accepted.jobId,
            manifestSha256: try AgentBridgeDigest(manifest), requestSha256: accepted.requestSha256,
            sourceAcknowledged: true, status: .cancelled)
    }
    func requireCancellationOwner(issuer: URL, reservation expected: AgentBridgeExportCaptureReservation) throws {
        guard self.issuer.standardizedFileURL == issuer.standardizedFileURL,
              reservation.job == expected.job, reservation.claim == expected.claim else {
            throw AgentBridgeValidationError.bindingChanged
        }
        try pins(includeProtection: false)
    }

    /// Persist the exact source-owned acknowledgement before any confirmation send. This is
    /// recoverable source state, not evidence that the host received the confirmation.
    func preserveCompletion() throws -> AgentBridgeExecutionReceipt {
        do {
            try check(); try validateStoredProgress()
            let state = try progress().1
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: readManifest(state))
            guard try readHostCommits(state, manifest: manifest).count == manifest.artifacts.count else { throw AgentBridgeValidationError.bindingChanged }
            let receipt = try completionCandidate(state, manifest: manifest)
            let bytes = try AgentBridgeV4Codec.encode(receipt)
            if try exists("completion.json") {
                guard try read("completion.json") == record(kind: "completion", day: nil, payload: bytes) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            } else { try publish("completion.json", record: record(kind: "completion", day: nil, payload: bytes)) }
            // Collect only bytes whose signed records and original plan hashes were validated.
            // The snapshot is immutable across all subsequent native authority callbacks.
            collectingFileEvidence = [:]
            defer { collectingFileEvidence = nil }
            guard try read("header.json") == record(kind: "job", day: nil) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try validateStoredProgress()
            completionEvidence = collectingFileEvidence
            completionReceipt = receipt
            try check(); try requirePreservedCompletion(receipt); return receipt
        } catch { throw Self.safe(error) }
    }
    func requireCompletionIfPreserved() throws {
        if let receipt = completionReceipt { try requirePreservedCompletion(receipt) }
    }
    /// Local-only tail: never re-create missing evidence or call native/SDK callbacks here.
    func requirePreservedCompletion(_ receipt: AgentBridgeExecutionReceipt) throws {
        guard completionReceipt == receipt, let evidence = completionEvidence,
              evidence["completion.json"] != nil else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        try requireProtectedEvidence(evidence)
    }
    private func requireProtectedEvidence(_ evidence: [String: ProtectedFileEvidence]) throws {
        do {
            try pins(includeProtection: false)
            guard Set(try Self.entries(directoryFD).filter { !Self.pendingName($0) }) == Set(evidence.keys).union(["lock"]) else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
            for (name, expected) in evidence {
                let bytes = try AgentBridgeExportPrivateFiles.read(directoryFD, name, maximumBytes: expected.count) { fd in
                    guard try AgentBridgeExportPrivateFiles.identity(fd) == expected.identity else { throw AgentBridgeValidationError.bindingChanged }
                }
                guard bytes.count == expected.count, AgentBridgeV4Codec.sha256(bytes) == expected.sha256 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            }
            try pins(includeProtection: false)
        } catch { throw Self.safe(error) }
    }
    private static func hostCommitName(_ name: String) -> Bool {
        name.range(of: "^host-commit-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\\.json$", options: .regularExpression) != nil
    }
    private func validateHostCommit(_ receipt: AgentBridgeCommitReceipt, artifact: AgentBridgeArtifact,
        manifest: AgentBridgeArtifactManifest) throws {
        let request = try reservation.job.request()
        try AgentBridgeSemantics.validate(receipt)
        guard receipt.status != .conflict, receipt.jobId == request.jobId,
              receipt.artifactId == artifact.artifactId, receipt.peer == request.plan.intent.peer,
              receipt.destination == request.plan.intent.destination, receipt.requestSha256 == reservation.job.requestSHA256,
              receipt.manifestSha256.rawValue == AgentBridgeV4Codec.sha256(try AgentBridgeV4Codec.encode(manifest)),
              receipt.relativePath == artifact.relativePath, receipt.writeMode.rawValue == artifact.writeMode.rawValue,
              receipt.inputSha256 == artifact.sha256,
              receipt.writeMode != .overwrite || receipt.afterSha256 == receipt.inputSha256 else { throw AgentBridgeValidationError.bindingChanged }
    }
    private func readHostCommits(_ state: Progress, manifest: AgentBridgeArtifactManifest) throws -> [AgentBridgeCommitReceipt] {
        var result: [AgentBridgeCommitReceipt] = []; var missing = false
        for artifact in manifest.artifacts {
            let name = "host-commit-\(artifact.artifactId.rawValue).json"
            if try !exists(name) { missing = true; continue }
            guard !missing else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            let value = try read(name)
            let receipt = try AgentBridgeV4Codec.decode(AgentBridgeCommitReceipt.self, from: value.payload)
            guard value.kind == "host_commit", value.day == artifact.artifactId.rawValue,
                  try AgentBridgeV4Codec.encode(receipt) == value.payload else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try validateHostCommit(receipt, artifact: artifact, manifest: manifest)
            result.append(receipt)
        }
        if !result.isEmpty {
            guard try checkedTransferFrontier(state).committedPartitionCount == Int64(manifest.artifacts.count) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        }
        return result
    }
    private func completionCandidate(_ state: Progress, manifest: AgentBridgeArtifactManifest) throws -> AgentBridgeExecutionReceipt {
        let frontier = try checkedTransferFrontier(state)
        guard frontier.committedPartitionCount == Int64(manifest.artifacts.count) else { throw AgentBridgeValidationError.bindingChanged }
        let status: AgentBridgeExecutionReceiptStatus
        switch manifest.captureStatus {
        case .complete: status = .complete
        case .completeEmpty: status = .completeEmpty
        case .partial: status = .partial
        default: throw AgentBridgeValidationError.bindingChanged
        }
        let request = try reservation.job.request()
        return .init(artifactCount: Int64(manifest.artifacts.count), binding: AgentBridgeSemantics.binding(request.plan),
            committedPartitionCount: frontier.committedPartitionCount, expiresAt: reservation.job.expiresAt, frontierSha256: frontier.sha256,
            jobId: request.jobId, manifestSha256: try AgentBridgeDigest(AgentBridgeV4Codec.sha256(AgentBridgeV4Codec.encode(manifest))),
            requestSha256: reservation.job.requestSHA256, sourceAcknowledged: true, status: status)
    }

    var acceptedRequestSHA256: String { reservation.job.requestSHA256.rawValue }

    func close() {
        if closed { return }; closed = true
        if lockFD >= 0 { _ = flock(lockFD, LOCK_UN); Darwin.close(lockFD); lockFD = -1 }
        if directoryFD >= 0 { Darwin.close(directoryFD); directoryFD = -1 }
        if capturesFD >= 0 { Darwin.close(capturesFD); capturesFD = -1 }
        if issuerFD >= 0 { Darwin.close(issuerFD); issuerFD = -1 }
    }
    private func record(kind: String, day: String?, payload: Data = Data()) -> Record {
        .init(version: 1, requestSHA256: reservation.job.requestSHA256.rawValue,
              resolutionSHA256: AgentBridgeV4Codec.sha256(reservation.job.nativeResolution),
              claimID: reservation.claim.claimID.rawValue, expiresAt: reservation.job.expiresAt.rawValue,
              kind: kind, day: day, payload: payload)
    }
    /// Failure-only owner journal. This records that the native context has invalidated all
    /// further reads; it does not claim recall of SDK work or create a captured result/frontier.
    func preserveCaptureStop() throws {
        guard !closed, !recordingStop, let stopRequest else { throw AgentBridgeValidationError.permissionRequired }
        recordingStop = true; defer { recordingStop = false }
        do {
            try check()
            let request = try stopRequest()
            try requireBoundStopRequest(request)
            collectingFileEvidence = [:]
            defer { collectingFileEvidence = nil }
            guard try read("header.json") == record(kind: "job", day: nil) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try validateStoredProgress(allowInterruptedCapture: true)
            let evidence = collectingFileEvidence ?? [:]; collectingFileEvidence = nil
            let stopped = try record(kind: "capture_stop", day: nil, payload: AgentBridgeV4Codec.encode(request))
            if try exists("capture-stop.json") {
                guard try read("capture-stop.json") == stopped else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                try check(); try requireProtectedEvidence(evidence)
            } else { try publish("capture-stop.json", record: stopped, evidenceBeforePublication: evidence) }
            _ = try inspectCancellationCheckpoint() // Fresh exact evidence after all native callbacks.
        } catch { throw Self.safe(error) }
    }
    private func requireBoundStopRequest(_ request: AgentBridgeCancel) throws {
        let original = try reservation.job.request()
        guard request.peer == original.plan.intent.peer, request.jobId == original.jobId,
              request.requestSha256 == reservation.job.requestSHA256, request.approvalId == original.approval.approvalId,
              request.authorityId == original.plan.authorityReferences.native.authorityId else { throw AgentBridgeValidationError.bindingChanged }
    }
    private func checkedCaptureStop() throws -> AgentBridgeCancel? {
        guard try exists("capture-stop.json") else { return nil }
        let value = try read("capture-stop.json")
        let request = try AgentBridgeV4Codec.decode(AgentBridgeCancel.self, from: value.payload)
        try requireBoundStopRequest(request)
        guard value.kind == "capture_stop", value.day == nil,
              try AgentBridgeV4Codec.encode(request) == value.payload else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return request
    }
    private func authorityFence() throws {
        if recordingStop {
            guard let stopRequest else { throw AgentBridgeValidationError.permissionRequired }
            try requireBoundStopRequest(stopRequest())
        } else { try fence() }
        if !initializing, !recordingStop, !inspectingCancellation, try exists("capture-stop.json") {
            throw AgentBridgeValidationError.permissionRequired
        }
    }
    private func validateStoredProgress(allowInterruptedCapture: Bool = false) throws {
        let (_, state) = try progress()
        let days = state.captures
        var expected: Set<String> = ["lock", "header.json", "progress.json"]
        let stopped = try checkedCaptureStop() != nil
        if stopped { expected.insert("capture-stop.json") }
        let mayLackPayload = (stopped || allowInterruptedCapture) && state.manifestSHA256 == nil && state.transferSHA256 == nil
        for day in days {
            let started = "started-\(day).json", captured = "day-\(day).json"
            expected.insert(started)
            guard try read(started) == record(kind: "started", day: day) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            if try !exists(captured) {
                guard mayLackPayload else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                continue
            }
            expected.insert(captured)
            let value = try read(captured)
            guard value.kind == "captured", value.day == day, !value.payload.isEmpty else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        }
        for day in state.artifacts {
            expected.insert("artifact-started-\(day).json")
            guard days.contains(day), !state.engine.isEmpty,
                  try read("artifact-started-\(day).json") == record(kind: "artifact-started", day: day) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            if try !exists("artifact-\(day).json") {
                guard mayLackPayload else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                continue
            }
            expected.insert("artifact-\(day).json")
            let value = try read("artifact-\(day).json")
            guard value.kind == "artifact", value.day == day, !value.payload.isEmpty else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        }
        if state.manifestSHA256 != nil {
            expected.insert("manifest.json")
            _ = try readManifest(state)
        }
        if state.transferSHA256 != nil {
            expected.insert("transfer.json")
            _ = try readTransferPlan(state)
        }
        if state.version == 6 { _ = try checkedTransferFrontier(state) }
        if try exists("partition-awaiting-ack.json") {
            _ = try awaitingPartitionAcknowledgement(state)
            expected.insert("partition-awaiting-ack.json")
        }
        if state.manifestSHA256 != nil {
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: readManifest(state))
            let commits = try readHostCommits(state, manifest: manifest)
            for receipt in commits { expected.insert("host-commit-\(receipt.artifactId.rawValue).json") }
            if try exists("completion.json") {
                guard commits.count == manifest.artifacts.count,
                      try read("completion.json") == record(kind: "completion", day: nil, payload: AgentBridgeV4Codec.encode(completionCandidate(state, manifest: manifest))) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                expected.insert("completion.json")
            }
        }
        let names = Set(try Self.entries(directoryFD).filter { !Self.pendingName($0) })
        guard names == expected else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
    }
    private func progressBytes(_ state: Progress) throws -> Data {
        if state.publicArtifactIDs == nil && state.engine.isEmpty && state.artifacts.isEmpty { return try JSONEncoder().encode(state.captures) }
        return try Self.canonical(state)
    }
    private func progress() throws -> (Record, Progress) {
        let value = try read("progress.json")
        let state: Progress
        if let days = try? JSONDecoder().decode([String].self, from: value.payload) {
            state = .init(version: 2, captures: days, artifacts: [], engine: Data())
        } else { state = try JSONDecoder().decode(Progress.self, from: value.payload) }
        let noManifest = state.manifestSHA256 == nil && state.manifestByteCount == nil
        let noTransfer = state.transferSHA256 == nil && state.transferByteCount == nil
        let noFrontier = state.committedPartitionCount == nil && state.frontierSHA256 == nil
        guard value.kind == "progress", value.day == nil,
              ((state.version == 2 && state.publicArtifactIDs == nil && noManifest && noTransfer) ||
              (state.version == 3 && state.publicArtifactIDs != nil && noManifest && noTransfer) ||
              (state.version == 4 && state.publicArtifactIDs != nil && state.manifestSHA256 != nil && state.manifestByteCount != nil && noTransfer) ||
              (state.version == 5 && state.publicArtifactIDs != nil && state.manifestSHA256 != nil && state.manifestByteCount != nil && state.transferSHA256 != nil && state.transferByteCount != nil)) && noFrontier ||
              (state.version == 6 && state.publicArtifactIDs != nil && state.manifestSHA256 != nil && state.manifestByteCount != nil && state.transferSHA256 != nil && state.transferByteCount != nil && state.committedPartitionCount != nil && state.frontierSHA256 != nil),
              state.engine.count <= 4096, state.artifacts.isEmpty == state.engine.isEmpty,
              try progressBytes(state) == value.payload else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        for days in [state.captures, state.artifacts] {
            guard days.count <= 4096, Set(days).count == days.count, days == days.sorted() else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            for day in days { _ = try AgentBridgeDate(day) }
        }
        if state.version >= 3 { _ = try Self.publicIDs(state) }
        if state.version >= 4 {
            guard let hash = state.manifestSHA256, hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  let count = state.manifestByteCount, count > 0, count <= AgentBridgeV4Codec.maximumBytes else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
        }
        if state.version >= 5 {
            guard let hash = state.transferSHA256, hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil,
                  let count = state.transferByteCount, count > 0, count <= AgentBridgeNativeTransferCheckpoint.maximumBytes else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
        }
        if state.version == 6 {
            guard let count = state.committedPartitionCount, (0...4096).contains(count),
                  let hash = state.frontierSHA256, hash.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
        }
        return (value, state)
    }
    private static func publicIDs(_ state: Progress) throws -> [String: String] {
        guard (3...6).contains(state.version), let data = state.publicArtifactIDs,
              !state.artifacts.isEmpty, state.artifacts.count <= 4096,
              state.captures == state.artifacts, data.count == state.artifacts.count * 16 else {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        let bytes = [UInt8](data)
        var result: [String: String] = [:]
        for (index, day) in state.artifacts.enumerated() {
            let offset = index * 16
            guard bytes[offset + 6] >> 4 == 4, bytes[offset + 8] & 0xc0 == 0x80 else {
                throw AgentBridgeValidationError.spoolMissingRestartRequired
            }
            let hex = bytes[offset..<offset + 16].map { String(format: "%02x", $0) }
            let id = [hex[0..<4], hex[4..<6], hex[6..<8], hex[8..<10], hex[10..<16]].map { $0.joined() }.joined(separator: "-")
            _ = try AgentBridgeUUID(id)
            result[day] = id
        }
        guard Set(result.values).count == state.artifacts.count else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return result
    }
    private func check() throws {
        try pins()
        try authorityFence()
        // Final tail contains only local identity checks, never another native SDK callback.
        try pins(includeProtection: false)
    }
    private func pins(includeProtection: Bool = true) throws {
        guard !closed, !identities.isEmpty else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        for (index, url) in [issuer, captures, directory].prefix(identities.count).enumerated() {
            let fd = try AgentBridgeExportPrivateFiles.openDirectory(url, privateLeaf: true)
            defer { Darwin.close(fd) }
            guard try AgentBridgeExportPrivateFiles.identity(fd) == identities[index] else { throw AgentBridgeValidationError.bindingChanged }
            if index > 0 && includeProtection { try fileProtection.requireCompleteProtection(fd) }
        }
        if lockFD >= 0 {
            try AgentBridgeExportPrivateFiles.checkPath(directoryFD, "lock", fd: lockFD)
            if includeProtection { try fileProtection.requireCompleteProtection(lockFD) }
        }
    }
    private func exists(_ name: String) throws -> Bool {
        var value = stat()
        if fstatat(directoryFD, name, &value, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        guard errno == ENOENT else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return false
    }
    private func fileSize(_ name: String) throws -> Int {
        let fd = try AgentBridgeExportPrivateFiles.openPrivateFile(directoryFD, name, flags: O_RDONLY)
        defer { Darwin.close(fd) }
        let expected = try AgentBridgeExportPrivateFiles.identity(fd)
        try fileProtection.requireCompleteProtection(fd)
        try authorityFence(); try pins(includeProtection: false)
        guard try AgentBridgeExportPrivateFiles.identity(fd) == expected else { throw AgentBridgeValidationError.bindingChanged }
        try AgentBridgeExportPrivateFiles.checkPath(directoryFD, name, fd: fd)
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_size >= 0, value.st_size <= (name == "manifest.json" ? AgentBridgeV4Codec.maximumBytes : (name == "transfer.json" ? AgentBridgeNativeTransferCheckpoint.maximumBytes : Self.recordLimit)) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return Int(value.st_size)
    }
    private func read(_ name: String) throws -> Record {
        try check()
        guard try exists(name), try fileSize(name) > 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        let bytes = try readProtectedFile(name)
        let record: Record
        do {
            let canonical = try AgentBridgeV4Codec.canonicalize(bytes)
            let value = try JSONDecoder().decode(Signed.self, from: canonical)
            guard try Self.canonical(value) == canonical,
                  HMAC<SHA256>.isValidAuthenticationCode(value.mac, authenticating: Self.domain + (try Self.canonical(value.record)), using: key),
                  value.record == self.record(kind: value.record.kind, day: value.record.day, payload: value.record.payload),
                  value.record.payload.count <= (value.record.kind == "progress" ? Self.progressLimit : Self.payloadLimit) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            record = value.record
        } catch { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        try check(); return record
    }
    private func readProtectedFile(_ name: String) throws -> Data {
        try readProtectedFile(name, maximumBytes: Self.recordLimit)
    }
    private func readProtectedFile(_ name: String, maximumBytes: Int) throws -> Data {
        var protectedIdentity: AgentBridgeExportFileIdentity?
        let bytes = try AgentBridgeExportPrivateFiles.read(directoryFD, name, maximumBytes: maximumBytes) { fd in
            try fileProtection.requireCompleteProtection(fd)
            protectedIdentity = try AgentBridgeExportPrivateFiles.identity(fd)
            try authorityFence(); try pins(includeProtection: false)
        }
        if collectingFileEvidence != nil {
            guard let identity = protectedIdentity else { throw AgentBridgeValidationError.bindingChanged }
            collectingFileEvidence?[name] = .init(count: bytes.count, sha256: AgentBridgeV4Codec.sha256(bytes), identity: identity)
        }
        return bytes
    }
    private func publish(_ name: String, record: Record, replacing previous: Record? = nil,
        evidenceBeforePublication: [String: ProtectedFileEvidence]? = nil) throws {
        let body = try Self.canonical(record)
        let bytes = try Self.canonical(Signed(record: record, mac: Data(HMAC<SHA256>.authenticationCode(for: Self.domain + body, using: key))))
        guard bytes.count <= Self.recordLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
        let previousBytes = try previous.map { value in
            try Self.canonical(Signed(record: value, mac: Data(HMAC<SHA256>.authenticationCode(for: Self.domain + (try Self.canonical(value)), using: key))))
        }
        try publishBytes(name, bytes: bytes, previousBytes: previousBytes, evidenceBeforePublication: evidenceBeforePublication)
    }
    private func publishBytes(_ name: String, bytes: Data, previousBytes: Data?,
        evidenceBeforePublication: [String: ProtectedFileEvidence]? = nil) throws {
        guard !bytes.isEmpty, bytes.count <= AgentBridgeV4Codec.maximumBytes,
              storedBytes + bytes.count <= Self.jobLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
        try check()
        if let previousBytes {
            guard try readProtectedFile(name) == previousBytes else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        } else { guard try !exists(name) else { throw AgentBridgeValidationError.busy } }
        let temporary = "pending-" + UUID().uuidString.lowercased()
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        defer {
            if (try? AgentBridgeExportPrivateFiles.checkPath(directoryFD, temporary, fd: fd)) != nil { _ = unlinkat(directoryFD, temporary, 0) }
            Darwin.close(fd)
        }
        try protectFile(fd)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                offset += count
            }
        }
        try AgentBridgeExportPrivateFiles.checkPath(directoryFD, temporary, fd: fd)
        guard fsync(fd) == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        try check()
        try AgentBridgeExportPrivateFiles.checkPath(directoryFD, temporary, fd: fd)
        if let previousBytes {
            guard try readProtectedFile(name) == previousBytes else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        }
        if let evidenceBeforePublication { try requireProtectedEvidence(evidenceBeforePublication) }
        // The protected read may invoke a native callback; re-pin the staged file afterwards.
        try AgentBridgeExportPrivateFiles.checkPath(directoryFD, temporary, fd: fd)
        guard renameatx_np(directoryFD, temporary, directoryFD, name, previousBytes == nil ? UInt32(RENAME_EXCL) : 0) == 0,
              fsync(directoryFD) == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        storedBytes += bytes.count - (previousBytes?.count ?? 0)
        try AgentBridgeExportPrivateFiles.checkPath(directoryFD, name, fd: fd)
        try check()
    }
    private static func canonical<T: Encodable>(_ value: T) throws -> Data { try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(value)) }
    private func mkdir(_ parent: Int32, _ name: String, exclusive: Bool) throws {
        if mkdirat(parent, name, 0o700) != 0 {
            guard !exclusive, errno == EEXIST else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        } else {
            let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            defer { Darwin.close(fd) }
            try protectFile(fd)
            guard fsync(fd) == 0, fsync(parent) == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        }
    }
    private func protectFile(_ fd: Int32) throws {
        try check()
        try fileProtection.applyCompleteProtection(fd)
        try check()
    }
    static func protect(_ fd: Int32) throws {
        #if os(iOS)
        let path = try protectedPath(fd)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        try verifyProtection(fd)
        #endif
    }
    static func verifyProtection(_ fd: Int32) throws {
        #if os(iOS)
        let path = try protectedPath(fd)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        // Accept Foundation's documented NSString bridge and its typed representation; absence denies.
        let value = attributes[.protectionKey]
        let protection = (value as? FileProtectionType)?.rawValue ?? (value as? String)
        guard protection == FileProtectionType.complete.rawValue,
              try protectedPath(fd) == path else { throw AgentBridgeValidationError.permissionRequired }
        #endif
    }
    /// Foundation owns the public protection-class mapping. Pin its pathname to the original
    /// descriptor before and after attribute work; never repair protection while opening a spool.
    static func protectedPath(_ fd: Int32) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) == 0 else { throw AgentBridgeValidationError.permissionRequired }
        let path = String(cString: buffer)
        var opened = stat(), named = stat()
        guard fstat(fd, &opened) == 0, lstat(path, &named) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
              named.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK) else { throw AgentBridgeValidationError.bindingChanged }
        return path
    }
    private static func entries(_ fd: Int32) throws -> [String] {
        // dup shares the original directory cursor. Each inventory needs a fresh description.
        let inventoryFD = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard inventoryFD >= 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        guard let directory = fdopendir(inventoryFD) else {
            Darwin.close(inventoryFD)
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        defer { closedir(directory) }
        var result: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard result.count < 16450 else { throw AgentBridgeValidationError.queryBudgetExceeded }
            result.append(name)
        }
        guard errno == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return result
    }
    private static func dayName(_ name: String) -> Bool { name.range(of: "^(artifact-started|artifact|started|day)-[0-9]{4}-[0-9]{2}-[0-9]{2}\\.json$", options: .regularExpression) != nil }
    private static func pendingName(_ name: String) -> Bool { name.range(of: "^pending-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil }
    private static func safe(_ error: Error) -> Error {
        if error is CancellationError || error is AgentBridgeValidationError { return error }
        return AgentBridgeValidationError.spoolMissingRestartRequired
    }
}

/// Private capture payload v1: canonical scalar values only. Never reuse public HealthData Codable
/// as a private journal format; adding output fields must not reinterpret an already captured day.
nonisolated struct AgentBridgeCapturedScalarDay: Codable {
    let version: Int
    let day: String
    let calendarTimezone: String
    let values: [String: Double]
}
