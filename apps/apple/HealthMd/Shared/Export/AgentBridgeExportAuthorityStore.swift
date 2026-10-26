import CryptoKit
import Darwin
import Foundation
import HealthMdConnectionCore

/// Native-protected key lookup only. There is intentionally no create/enroll/reset fallback.
nonisolated protocol AgentBridgeExportProtectedKeyReading {
    func loadExistingExportAuthorityKey() throws -> SymmetricKey?
}

/// Non-wire private-files boundary observer, used to exercise serialization/fsync delays. It has
/// no authority to approve a write or bypass validators; throwing can only reject an operation.
nonisolated protocol AgentBridgeExportPublicationObserving {
    func prepared(_ state: AgentBridgeExportAuthoritySnapshot) throws
    func published(_ state: AgentBridgeExportAuthoritySnapshot) throws
}
nonisolated private struct AgentBridgeExportUnobservedPublication: AgentBridgeExportPublicationObserving {
    func prepared(_ state: AgentBridgeExportAuthoritySnapshot) throws {}
    func published(_ state: AgentBridgeExportAuthoritySnapshot) throws {}
}

/// These non-Codable actions are presented by a trusted native UI/policy adapter, never wire JSON.
nonisolated enum AgentBridgeExportNativeAction: Equatable, Sendable {
    case createPrivateStore
    case storeDelegation(AgentBridgeExportDelegation)
    case revokeDelegation(AgentBridgeAuthorityReference)
    case decideExport(planID: AgentBridgeUUID, binding: AgentBridgeBinding)
}
/// Revalidate an already reviewed native decision without prompting or minting authority.
/// A single native operation calls this repeatedly around delaying SDK/storage boundaries.
nonisolated protocol AgentBridgeExportNativeAuthorizing {
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws
}

nonisolated struct AgentBridgeExportStoredDelegation: Codable {
    let sanitizedBytes: Data
    let sha256: AgentBridgeDigest
    var revoked: Bool
    func description() throws -> AgentBridgeExportDelegation {
        let value = try AgentBridgeV4Codec.decode(AgentBridgeExportDelegation.self, from: sanitizedBytes)
        guard value.issuer == .nativeSource, value.peer.platform == .apple,
              try AgentBridgeV4Codec.encode(value) == sanitizedBytes,
              AgentBridgeV4Codec.sha256(sanitizedBytes) == sha256.rawValue else { throw AgentBridgeValidationError.bindingChanged }
        return value
    }
}

/// Versioned private record. Native resolver material retains its existing v1 plist shape; no new
/// required field was silently added to AgentBridgeRequestSettingsResolution/1 or a portable DTO.
nonisolated struct AgentBridgeExportIssuedPlan: Codable {
    let version: Int
    let requestBytes: Data
    let planBytes: Data
    let nativeResolution: Data
    let nativeAuthorityBytes: Data
    func request() throws -> AgentBridgePlanRequest {
        let envelope = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: requestBytes)
        guard case .planRequest(let value) = envelope.payload else { throw AgentBridgeValidationError.bindingChanged }
        return value
    }
    func plan() throws -> AgentBridgePlan { try AgentBridgeV4Codec.decode(AgentBridgePlan.self, from: planBytes) }
}
nonisolated struct AgentBridgeExportStoredDecision: Codable {
    let planID: AgentBridgeUUID
    let approvalBytes: Data
    func approval() throws -> AgentBridgeApproval { try AgentBridgeV4Codec.decode(AgentBridgeApproval.self, from: approvalBytes) }
}
/// Immutable accepted-pending-capture journal entry. No capture/claim/transfer state is implied.
nonisolated struct AgentBridgeExportAcceptedJob: Codable, Equatable {
    let version: Int
    let requestBytes: Data
    let requestSHA256: AgentBridgeDigest
    let nativeResolution: Data
    let acceptedAt: AgentBridgeUTC
    let expiresAt: AgentBridgeUTC
    func request() throws -> AgentBridgeExecute { try AgentBridgeV4Codec.decode(AgentBridgeExecute.self, from: requestBytes) }
    /// Deterministic pre-capture receipt derived only from the signed original acceptance.
    /// Zero digests/counts mean no manifest/frontier exists yet, matching the v4 native fixtures.
    func acceptedReceipt() throws -> AgentBridgeExecutionReceipt {
        try validate()
        let request = try request()
        let absent = try AgentBridgeDigest(String(repeating: "0", count: 64))
        return .init(artifactCount: 0, binding: AgentBridgeSemantics.binding(request.plan),
            committedPartitionCount: 0, expiresAt: expiresAt, frontierSha256: absent,
            jobId: request.jobId, manifestSha256: absent, requestSha256: requestSHA256,
            sourceAcknowledged: false, status: .accepted)
    }
    /// Confirmation for an issuer-locked proof that no capture claim or spool exists.
    /// Callers must establish that proof; this value alone is never cancellation authority.
    func unclaimedCancellationReceipt() throws -> AgentBridgeExecutionReceipt {
        let accepted = try acceptedReceipt()
        return .init(artifactCount: 0, binding: accepted.binding, committedPartitionCount: 0,
            expiresAt: accepted.expiresAt, frontierSha256: accepted.frontierSha256,
            jobId: accepted.jobId, manifestSha256: accepted.manifestSha256, requestSha256: accepted.requestSha256,
            sourceAcknowledged: true, status: .cancelled)
    }
    func validate() throws {
        let value = try request()
        let formatter = ISO8601DateFormatter()
        guard version == 1, requestBytes.count <= 48 * 1024, nativeResolution.count <= 48 * 1024,
              try AgentBridgeV4Codec.encode(value) == requestBytes,
              AgentBridgeV4Codec.sha256(requestBytes) == requestSHA256.rawValue,
              let accepted = formatter.date(from: acceptedAt.rawValue), let expires = formatter.date(from: expiresAt.rawValue),
              expires.timeIntervalSince(accepted) == 604800,
              acceptedAt.rawValue >= value.plan.issuedAt.rawValue, acceptedAt.rawValue < value.plan.expiresAt.rawValue,
              value.approval.approvedAt.rawValue <= acceptedAt.rawValue else { throw AgentBridgeValidationError.bindingChanged }
        // The MainActor service validates native resolution semantics; store validation below
        // requires byte equality with that issuer-owned plan, without crossing actor isolation.
    }
}
nonisolated struct AgentBridgeExportJobAcceptance {
    let job: AgentBridgeExportAcceptedJob
    let newlyAccepted: Bool // Retry may inspect the stored job; it must never start another capture.
}

/// A permanent single-capture reservation, not proof that capture ran or a spool exists.
nonisolated struct AgentBridgeExportStoredCaptureClaim: Codable, Equatable {
    let version: Int
    let claimID: AgentBridgeUUID
    let requestSHA256: AgentBridgeDigest
    let claimedAt: AgentBridgeUTC
}
/// A durable request to stop the original accepted job, not a terminal cancellation receipt.
/// Kept in the signed issuer ledger so an interrupted controller cannot resume health reads.
nonisolated struct AgentBridgeExportCancellationIntent: Codable, Equatable {
    let version: Int
    let requestBytes: Data
    let requestedAt: AgentBridgeUTC
    let terminalReceiptBytes: Data?
    let confirmedAt: AgentBridgeUTC?

    init(version: Int, requestBytes: Data, requestedAt: AgentBridgeUTC,
         terminalReceiptBytes: Data? = nil, confirmedAt: AgentBridgeUTC? = nil) {
        self.version = version; self.requestBytes = requestBytes; self.requestedAt = requestedAt
        self.terminalReceiptBytes = terminalReceiptBytes; self.confirmedAt = confirmedAt
    }
    func terminalReceipt() throws -> AgentBridgeExecutionReceipt? {
        try terminalReceiptBytes.map { try AgentBridgeV4Codec.decode(AgentBridgeExecutionReceipt.self, from: $0) }
    }
    func request() throws -> AgentBridgeCancel { try AgentBridgeV4Codec.decode(AgentBridgeCancel.self, from: requestBytes) }
    func validate(job: AgentBridgeExportAcceptedJob) throws {
        let cancel = try request(), original = try job.request()
        guard [1, 2, 3].contains(version), requestBytes.count <= 48 * 1024,
              try AgentBridgeV4Codec.encode(cancel) == requestBytes,
              cancel.peer == original.plan.intent.peer, cancel.jobId == original.jobId,
              cancel.requestSha256 == job.requestSHA256,
              cancel.approvalId == original.approval.approvalId,
              cancel.authorityId == original.plan.authorityReferences.native.authorityId,
              requestedAt.rawValue >= job.acceptedAt.rawValue, requestedAt.rawValue < job.expiresAt.rawValue else {
            throw AgentBridgeValidationError.bindingChanged
        }
        if version == 1 {
            guard terminalReceiptBytes == nil, confirmedAt == nil else { throw AgentBridgeValidationError.bindingChanged }
        } else {
            guard let bytes = terminalReceiptBytes, bytes.count <= 48 * 1024, let confirmedAt,
                  confirmedAt.rawValue >= requestedAt.rawValue, confirmedAt.rawValue < job.expiresAt.rawValue,
                  let receipt = try terminalReceipt(), try AgentBridgeV4Codec.encode(receipt) == bytes else { throw AgentBridgeValidationError.bindingChanged }
            if version == 2 {
                guard receipt == (try job.unclaimedCancellationReceipt()) else { throw AgentBridgeValidationError.bindingChanged }
            } else {
                let accepted = try job.acceptedReceipt(), zero = String(repeating: "0", count: 64)
                guard receipt.binding == accepted.binding, receipt.jobId == accepted.jobId,
                      receipt.requestSha256 == job.requestSHA256, receipt.expiresAt == job.expiresAt,
                      receipt.sourceAcknowledged, [.cancelled, .complete, .completeEmpty, .partial].contains(receipt.status),
                      receipt.artifactCount >= 0, receipt.committedPartitionCount >= 0,
                      receipt.committedPartitionCount <= receipt.artifactCount else { throw AgentBridgeValidationError.bindingChanged }
                try AgentBridgeSemantics.validate(receipt)
                if receipt.manifestSha256.rawValue == zero {
                    guard receipt.status == .cancelled, receipt.artifactCount == 0,
                          receipt.committedPartitionCount == 0, receipt.frontierSha256.rawValue == zero else { throw AgentBridgeValidationError.bindingChanged }
                } else {
                    guard receipt.frontierSha256.rawValue != zero,
                          receipt.status == .cancelled || receipt.committedPartitionCount == receipt.artifactCount else { throw AgentBridgeValidationError.bindingChanged }
                }
            }
        }
    }
}

nonisolated struct AgentBridgeExportCaptureReservation {
    let job: AgentBridgeExportAcceptedJob
    let claim: AgentBridgeExportStoredCaptureClaim
}

nonisolated struct AgentBridgeExportAuthoritySnapshot: Codable {
    var generation: Int64
    var delegations: [AgentBridgeExportStoredDelegation]
    var plans: [AgentBridgeExportIssuedPlan]
    var decisions: [AgentBridgeExportStoredDecision]
    var nativeCatalog: AgentBridgeNativeCatalogPublication? = nil
    var acceptedJobs: [AgentBridgeExportAcceptedJob]? = nil
    var captureClaims: [AgentBridgeExportStoredCaptureClaim]? = nil
    var cancellationIntents: [AgentBridgeExportCancellationIntent]? = nil

    func references(peer: AgentBridgePeer, now: AgentBridgeUTC) throws -> [AgentBridgeAuthorityReference] {
        let active = try delegations.filter { !$0.revoked }.map { try $0.description() }
            .filter { $0.peer == peer && $0.expiresAt.rawValue > now.rawValue && $0.rights.contains(.discover) }
        guard active.count <= 32 else { throw AgentBridgeValidationError.queryBudgetExceeded }
        return try active.sorted { $0.authorityID.rawValue < $1.authorityID.rawValue }.map { try $0.reference() }
    }
    func delegation(id: AgentBridgeUUID, revision: Int64, peer: AgentBridgePeer, now: AgentBridgeUTC) throws -> AgentBridgeExportDelegation {
        for record in delegations {
            let value = try record.description()
            if value.authorityID == id {
                guard !record.revoked, value.expiresAt.rawValue > now.rawValue else { throw AgentBridgeValidationError.approvalRequired }
                guard value.peer == peer else { throw AgentBridgeValidationError.bindingChanged }
                guard value.grantRevision == revision else { throw AgentBridgeValidationError.revisionConflict }
                return value
            }
        }
        throw AgentBridgeValidationError.approvalRequired
    }
    func issued(id: AgentBridgeUUID, peer: AgentBridgePeer) throws -> AgentBridgeExportIssuedPlan {
        for record in plans {
            let value = try record.plan()
            if value.planId == id {
                guard value.intent.peer == peer else { throw AgentBridgeValidationError.bindingChanged }
                return record
            }
        }
        throw AgentBridgeValidationError.bindingChanged
    }
}

/// Bounded issuer-private store, not a destination store. No defaults, bookmarks, OS credentials,
/// settings, health backend, quota, wake, output root or portable grant-registration endpoint.
/// A missing/corrupt store/key fails closed. Reads never initialize or repair state.
nonisolated final class AgentBridgeExportAuthorityStore: @unchecked Sendable {
    private let directory: URL
    private let rootFD: Int32
    private let rootIdentity: AgentBridgeExportFileIdentity
    private let keys: any AgentBridgeExportProtectedKeyReading
    private let publication: any AgentBridgeExportPublicationObserving
    private static let domain = Data("HealthMd.AgentBridge.NativeExportAuthorityStore.v1\0".utf8)
    private static let recordLimit = 48 * 1024
    /// Parse reuse only, never authority or protected-key reuse. Each transaction still reads
    /// the current protected file and authenticates it with the freshly loaded native key.
    /// Snapshot fields are owned value types; callers cannot mutate this retained parse.
    private struct ParsedState {
        let bytes: Data
        let body: Data
        let mac: Data
        let state: AgentBridgeExportAuthoritySnapshot
    }
    private let parsedStateLock = NSLock()
    private var parsedState: ParsedState?
    private struct SignedState: Codable {
        let version: Int
        let state: AgentBridgeExportAuthoritySnapshot
        let mac: Data
    }

    init(existingDirectory: URL, protectedKeys: any AgentBridgeExportProtectedKeyReading = AgentBridgeExportProtectedKey(),
         publication: any AgentBridgeExportPublicationObserving = AgentBridgeExportUnobservedPublication()) throws {
        directory = existingDirectory
        rootFD = try AgentBridgeExportPrivateFiles.openDirectory(existingDirectory, privateLeaf: true)
        do { rootIdentity = try AgentBridgeExportPrivateFiles.identity(rootFD) }
        catch { close(rootFD); throw error }
        keys = protectedKeys
        self.publication = publication
    }
    deinit { close(rootFD) }

    /// Original native owner only. Supplemental capture files never contain issuer grants or
    /// replace the ledger; their own versioned MAC binds this exact accepted job and claim.
    @MainActor
    func openCaptureSpool(_ reservation: AgentBridgeExportCaptureReservation, create: Bool,
                          fileProtection: any AgentBridgeNativeCaptureProtecting = AgentBridgeSystemNativeCaptureProtection(),
                          stopRequest: (@MainActor () throws -> AgentBridgeCancel)? = nil,
                          fence: @escaping @MainActor () throws -> Void) throws -> AgentBridgeNativeCaptureSpool {
        try requireCurrentRoot(); try fence(); try requireCurrentRoot()
        let key = try Self.existingKey(keys)
        try requireCurrentRoot(); try fence(); try requireCurrentRoot()
        return try AgentBridgeNativeCaptureSpool(issuer: directory, reservation: reservation, key: key, create: create,
            fileProtection: fileProtection, stopRequest: stopRequest.map { stop in
                { @MainActor [self] in try requireCurrentRoot(); let request = try stop(); try requireCurrentRoot(); return request }
            }) { [self] in
            try requireCurrentRoot(); try fence(); try requireCurrentRoot()
        }
    }

    /// Explicit local-native bootstrap only. Keys must already exist under independent native
    /// protection. The remote service has no access to this method or an authorizing context.
    static func createPrivateStore(at directory: URL, protectedKeys: any AgentBridgeExportProtectedKeyReading = AgentBridgeExportProtectedKey(),
                                   authorization: any AgentBridgeExportNativeAuthorizing,
                                   publication: any AgentBridgeExportPublicationObserving = AgentBridgeExportUnobservedPublication()) throws -> AgentBridgeExportAuthorityStore {
        try authorization.requireNativeAuthorization(for: .createPrivateStore)
        // After releasing issuer locks, invalidate even on an ambiguous failed write.
        // Initial native authorization rejection is silent; reads/catalog/decisions never emit.
        defer { NotificationCenter.default.post(name: .healthMdAgentExportAuthorityDidChange, object: nil) }
        let key = try existingKey(protectedKeys)
        let store = try reservePrivateDirectory(at: directory, protectedKeys: protectedKeys, publication: publication)
        try store.write(.init(generation: 0, delegations: [], plans: [], decisions: []), key: key)
        return store
    }

    /// Explicit human/native setup, distinct from opening or repairing an existing issuer. The
    /// exclusive directory reservation happens BEFORE any Keychain write. Concurrent setup and
    /// existing/interrupted ledgers therefore cannot rotate a missing key or erase revocations.
    /// A failed SDK operation leaves a reserved, unusable directory; readers never repair it.
    static func createNativePrivateStore(at directory: URL,
        authorization: any AgentBridgeExportNativeAuthorizing,
        provisioner: AgentBridgeExportProtectedKeyProvisioner = .init()) throws -> AgentBridgeExportAuthorityStore {
        try authorization.requireNativeAuthorization(for: .createPrivateStore)
        // After releasing issuer locks, invalidate even on an ambiguous failed write.
        // Initial native authorization rejection is silent; reads/catalog/decisions never emit.
        defer { NotificationCenter.default.post(name: .healthMdAgentExportAuthorityDidChange, object: nil) }
        let store = try reservePrivateDirectory(at: directory, protectedKeys: provisioner.reader,
                                               publication: AgentBridgeExportUnobservedPublication())
        // Permission records remain local to this installation, like their nonmigrating key.
        // Do this only after explicit native approval/reservation, never from a load-only reader.
        var localDirectory = directory
        var protection = URLResourceValues()
        protection.isExcludedFromBackup = true
        try localDirectory.setResourceValues(protection)
        guard try localDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true else {
            throw AgentBridgeValidationError.permissionRequired
        }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: directory.path)
        #endif
        try store.requireCurrentRoot()
        try authorization.requireNativeAuthorization(for: .createPrivateStore)
        try store.requireCurrentRoot()
        let key = try provisioner.loadOrCreateForNewPrivateStore()
        // Revalidate the pinned private directory after potentially delaying SDK work,
        // again after staging/fsync, and before exposing the initialized store.
        try store.requireCurrentRoot()
        try authorization.requireNativeAuthorization(for: .createPrivateStore)
        try store.requireCurrentRoot()
        try store.write(.init(generation: 0, delegations: [], plans: [], decisions: []), key: key,
                        beforePublish: { _ in
                            try store.requireCurrentRoot()
                            try authorization.requireNativeAuthorization(for: .createPrivateStore)
                            try store.requireCurrentRoot()
                        })
        try store.requireCurrentRoot()
        try authorization.requireNativeAuthorization(for: .createPrivateStore)
        try store.requireCurrentRoot()
        return store
    }

    private static func reservePrivateDirectory(at directory: URL,
        protectedKeys: any AgentBridgeExportProtectedKeyReading,
        publication: any AgentBridgeExportPublicationObserving) throws -> AgentBridgeExportAuthorityStore {
        let parent = try AgentBridgeExportPrivateFiles.openDirectory(directory.deletingLastPathComponent(), privateLeaf: false)
        defer { close(parent) }
        let leaf = directory.lastPathComponent
        guard !leaf.isEmpty, leaf != ".", leaf != "..", !leaf.contains("/"),
              mkdirat(parent, leaf, 0o700) == 0 else { throw AgentBridgeValidationError.bindingChanged }
        let store = try Self(existingDirectory: directory, protectedKeys: protectedKeys, publication: publication)
        let lock = openat(store.rootFD, "lock", O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard lock >= 0 else { throw AgentBridgeValidationError.bindingChanged }
        defer { close(lock) }
        guard fsync(lock) == 0 else { throw AgentBridgeValidationError.bindingChanged }
        return store
    }

    func snapshot() throws -> AgentBridgeExportAuthoritySnapshot {
        try inspectCurrent { $0 }
    }

    /// Load protected key and current private state under the same lock as CAS/publication. The
    /// validator receives THIS state, never an earlier captured snapshot presented as a refresh.
    /// Native lifecycle publication only, never called by a wire reader. Uses the existing
    /// signed/fsynced issuer transaction; does not initialize state, keys, grants or consent.
    /// Sampling must not reenter this issuer store. Readers receive its locked publication value.
    /// A native observer can invalidate an observed transition that coalesced before sampling.
    /// That publication advances the revision even for equal facts; ordinary retries leave it false.
    func publishNativeCatalog(sourceInstallationID: AgentBridgeUUID, invalidatingObservedChange: Bool = false,
                              sample: () throws -> AgentBridgeNativePlanningFacts) throws -> AgentBridgeNativeCatalogPublication {
        var selected: AgentBridgeNativeCatalogPublication?
        return try transaction(beforeCommit: { _ in
            guard let selected, selected.factsSHA256 == (try sample().fingerprint(sourceInstallationID: sourceInstallationID)) else {
                throw AgentBridgeValidationError.bindingChanged
            }
        }) { state in
            let digest = try sample().fingerprint(sourceInstallationID: sourceInstallationID)
            if let current = state.nativeCatalog {
                guard current.sourceInstallationID == sourceInstallationID else { throw AgentBridgeValidationError.bindingChanged }
                if current.factsSHA256 == digest && !invalidatingObservedChange { selected = current; return (current, false) }
                guard current.revision < Int64(Int32.max) else { throw AgentBridgeValidationError.busy }
            }
            let next = AgentBridgeNativeCatalogPublication(revision: (state.nativeCatalog?.revision ?? 0) + 1,
                sourceInstallationID: sourceInstallationID, factsSHA256: digest)
            state.nativeCatalog = next
            selected = next
            return (next, true)
        }
    }

    func inspectCurrent<T>(_ inspect: (AgentBridgeExportAuthoritySnapshot) throws -> T) throws -> T {
        try transaction { state in (try inspect(state), false) }
    }

    /// The same signed transaction serializes the idempotency index and authority checks. Callers
    /// cannot initialize a missing ledger; publication is fsynced before a new acceptance returns.
    func acceptExecution(request: AgentBridgeExecute, requestBytes: Data,
        prepare: (AgentBridgeExportAuthoritySnapshot) throws -> AgentBridgeExportAcceptedJob,
        requireCurrent: (AgentBridgeExportAuthoritySnapshot, AgentBridgeExportAcceptedJob, Bool) throws -> Void) throws -> AgentBridgeExportJobAcceptance {
        var selected: AgentBridgeExportAcceptedJob?
        var isNew = false
        return try transaction(beforeCommit: { state in
            guard let selected else { throw AgentBridgeValidationError.bindingChanged }
            try requireCurrent(state, selected, isNew)
        }) { state in
            let jobs = state.acceptedJobs ?? []
            if let existing = try jobs.first(where: { try $0.request().plan.intent.peer == request.plan.intent.peer && $0.request().jobId == request.jobId }) {
                guard existing.requestBytes == requestBytes else { throw AgentBridgeValidationError.bindingChanged }
                selected = existing
                return (.init(job: existing, newlyAccepted: false), false)
            }
            guard jobs.count < 16 else { throw AgentBridgeValidationError.busy }
            let record = try prepare(state)
            guard record.requestBytes == requestBytes else { throw AgentBridgeValidationError.bindingChanged }
            try record.validate()
            state.acceptedJobs = jobs + [record]
            selected = record; isNew = true
            return (.init(job: record, newlyAccepted: true), true)
        }
    }

    /// Persist only a bound stop intent. This does not prove a worker stopped, remove a spool,
    /// or replace an existing completion receipt. Replay preserves the original intent bytes.
    func recordCancellationIntent(_ request: AgentBridgeCancel,
        prepare: (AgentBridgeExportAuthoritySnapshot, AgentBridgeExportAcceptedJob) throws -> AgentBridgeExportCancellationIntent,
        requireCurrent: (AgentBridgeExportAuthoritySnapshot, AgentBridgeExportAcceptedJob, AgentBridgeExportCancellationIntent) throws -> Void
    ) throws -> AgentBridgeExportCancellationIntent {
        var selected: (AgentBridgeExportAcceptedJob, AgentBridgeExportCancellationIntent)?
        return try transaction(beforeCommit: { state in
            guard let selected, state.acceptedJobs?.contains(selected.0) == true,
                  state.cancellationIntents?.contains(selected.1) == true else { throw AgentBridgeValidationError.bindingChanged }
            try requireCurrent(state, selected.0, selected.1)
        }) { state in
            guard let job = state.acceptedJobs?.first(where: { $0.requestSHA256 == request.requestSha256 }) else {
                throw AgentBridgeValidationError.bindingChanged
            }
            let intents = state.cancellationIntents ?? []
            if let existing = try intents.first(where: { try $0.request().requestSha256 == job.requestSHA256 }) {
                guard try existing.request() == request else { throw AgentBridgeValidationError.bindingChanged }
                try requireCurrent(state, job, existing)
                selected = (job, existing)
                return (existing, false)
            }
            guard intents.count < 16 else { throw AgentBridgeValidationError.busy }
            let intent = try prepare(state, job)
            guard try intent.request() == request else { throw AgentBridgeValidationError.bindingChanged }
            try intent.validate(job: job)
            try requireCurrent(state, job, intent)
            state.cancellationIntents = intents + [intent]
            selected = (job, intent)
            return (intent, true)
        }
    }

    /// Confirm only the zero-capture case under the issuer lock. Captured jobs require a
    /// separate retained-spool proof; a stop intent or missing worker is insufficient.
    func finalizeUnclaimedCancellation(_ request: AgentBridgeCancel,
        prepare: (AgentBridgeExportAcceptedJob, AgentBridgeExportCancellationIntent) throws -> AgentBridgeExportCancellationIntent,
        requireCurrent: (AgentBridgeExportAcceptedJob, AgentBridgeExportCancellationIntent) throws -> Void
    ) throws -> AgentBridgeExportCancellationIntent {
        var selected: (AgentBridgeExportAcceptedJob, AgentBridgeExportCancellationIntent)?
        func requireUnclaimed(_ state: AgentBridgeExportAuthoritySnapshot, _ job: AgentBridgeExportAcceptedJob) throws {
            guard state.captureClaims?.contains(where: { $0.requestSHA256 == job.requestSHA256 }) != true else {
                throw AgentBridgeValidationError.busy
            }
            try requireNoCaptureSpool(job)
        }
        return try transaction(beforeCommit: { state in
            guard let selected, state.acceptedJobs?.contains(selected.0) == true,
                  state.cancellationIntents?.contains(selected.1) == true else { throw AgentBridgeValidationError.bindingChanged }
            try requireCurrent(selected.0, selected.1)
            try requireUnclaimed(state, selected.0) // Local proof follows delaying native callbacks.
        }) { state in
            guard let job = state.acceptedJobs?.first(where: { $0.requestSHA256 == request.requestSha256 }),
                  var intents = state.cancellationIntents,
                  let index = try intents.firstIndex(where: { try $0.request() == request }) else {
                throw AgentBridgeValidationError.bindingChanged
            }
            let previous = intents[index]
            try requireUnclaimed(state, job)
            if previous.version == 2 {
                try requireCurrent(job, previous)
                selected = (job, previous)
                return (previous, false)
            }
            let terminal = try prepare(job, previous)
            guard terminal.version == 2, try terminal.request() == request,
                  terminal.requestedAt == previous.requestedAt else { throw AgentBridgeValidationError.bindingChanged }
            try terminal.validate(job: job)
            try requireCurrent(job, terminal)
            intents[index] = terminal
            state.cancellationIntents = intents
            selected = (job, terminal)
            return (terminal, true)
        }
    }

    /// Publish only the receipt proven by this issuer's original exclusively locked spool.
    /// A stored completion wins; neither capture claims nor retained payloads are removed.
    @MainActor
    func finalizeCapturedCancellation(_ request: AgentBridgeCancel, reservation: AgentBridgeExportCaptureReservation,
        spool: AgentBridgeNativeCaptureSpool, checkpoint: AgentBridgeNativeCaptureSpool.CancellationCheckpoint,
        confirmedAt: AgentBridgeUTC,
        requireCurrent: (AgentBridgeExportAcceptedJob, AgentBridgeExportCancellationIntent) throws -> Void
    ) throws -> AgentBridgeExportCancellationIntent {
        var selected: AgentBridgeExportCancellationIntent?
        func requireRetained(_ state: AgentBridgeExportAuthoritySnapshot, _ intent: AgentBridgeExportCancellationIntent) throws {
            guard state.acceptedJobs?.contains(reservation.job) == true,
                  state.captureClaims?.contains(reservation.claim) == true,
                  reservation.job.requestSHA256 == request.requestSha256 else { throw AgentBridgeValidationError.bindingChanged }
            try requireCurrent(reservation.job, intent)
            // Local-only evidence proof follows all delaying authority callbacks.
            try spool.requireCancellationOwner(issuer: directory, reservation: reservation)
            guard try intent.terminalReceipt() == spool.cancellationReceipt(checkpoint) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        }
        return try transaction(beforeCommit: { state in
            guard let selected, state.cancellationIntents?.contains(selected) == true else { throw AgentBridgeValidationError.bindingChanged }
            try requireRetained(state, selected)
        }) { state in
            guard var intents = state.cancellationIntents,
                  let index = try intents.firstIndex(where: { try $0.request() == request }),
                  state.acceptedJobs?.contains(reservation.job) == true,
                  state.captureClaims?.contains(reservation.claim) == true else { throw AgentBridgeValidationError.bindingChanged }
            let previous = intents[index]
            try requireCurrent(reservation.job, previous)
            try spool.requireCancellationOwner(issuer: directory, reservation: reservation)
            let receipt = try spool.cancellationReceipt(checkpoint)
            let terminal: AgentBridgeExportCancellationIntent
            if previous.version == 3 { terminal = previous }
            else {
                guard previous.version == 1 else { throw AgentBridgeValidationError.bindingChanged }
                terminal = .init(version: 3, requestBytes: previous.requestBytes, requestedAt: previous.requestedAt,
                    terminalReceiptBytes: try AgentBridgeV4Codec.encode(receipt), confirmedAt: confirmedAt)
            }
            try terminal.validate(job: reservation.job)
            try requireRetained(state, terminal)
            selected = terminal
            intents[index] = terminal; state.cancellationIntents = intents
            return (terminal, terminal != previous)
        }
    }

    /// Refuse unknown/orphan capture state rather than deleting it or inferring no capture.
    private func requireNoCaptureSpool(_ job: AgentBridgeExportAcceptedJob) throws {
        try job.validate(); try requireCurrentRoot()
        var named = stat()
        if fstatat(rootFD, "captures", &named, AT_SYMLINK_NOFOLLOW) != 0 {
            guard errno == ENOENT else { throw AgentBridgeValidationError.bindingChanged }
            try requireCurrentRoot()
            return
        }
        let captures = try AgentBridgeExportPrivateFiles.openDirectory(directory.appendingPathComponent("captures"), privateLeaf: true)
        defer { close(captures) }
        func requireOriginalParent() throws {
            var opened = stat(), current = stat()
            guard fstat(captures, &opened) == 0,
                  fstatat(rootFD, "captures", &current, AT_SYMLINK_NOFOLLOW) == 0,
                  opened.st_dev == current.st_dev, opened.st_ino == current.st_ino,
                  current.st_mode & S_IFMT == S_IFDIR, opened.st_uid == geteuid(), current.st_uid == geteuid(),
                  opened.st_mode & 0o7777 == 0o700, current.st_mode & 0o7777 == 0o700 else { throw AgentBridgeValidationError.bindingChanged }
            try requireCurrentRoot()
        }
        try requireOriginalParent()
        var leaf = stat()
        if fstatat(captures, job.requestSHA256.rawValue, &leaf, AT_SYMLINK_NOFOLLOW) == 0 {
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        guard errno == ENOENT else { throw AgentBridgeValidationError.bindingChanged }
        try requireOriginalParent()
    }

    /// Reserve once under the original issuer lock. A claimed-but-interrupted job is never
    /// reclaimed here; only future immutable spool recovery may continue it without recapture.
    func claimCapture(requestBytes: Data,
        prepare: (AgentBridgeExportAuthoritySnapshot, AgentBridgeExportAcceptedJob) throws -> AgentBridgeExportStoredCaptureClaim,
        requireCurrent: (AgentBridgeExportAuthoritySnapshot, AgentBridgeExportCaptureReservation) throws -> Void) throws -> AgentBridgeExportCaptureReservation {
        var selected: AgentBridgeExportCaptureReservation?
        return try transaction(beforeCommit: { state in
            guard let selected else { throw AgentBridgeValidationError.bindingChanged }
            try requireCurrent(state, selected)
        }) { state in
            guard let job = state.acceptedJobs?.first(where: { $0.requestBytes == requestBytes }) else {
                throw AgentBridgeValidationError.bindingChanged
            }
            let claims = state.captureClaims ?? []
            guard try state.cancellationIntents?.contains(where: { try $0.request().requestSha256 == job.requestSHA256 }) != true else {
                throw AgentBridgeValidationError.permissionRequired
            }
            guard !claims.contains(where: { $0.requestSHA256 == job.requestSHA256 }) else { throw AgentBridgeValidationError.busy }
            guard claims.count < 16 else { throw AgentBridgeValidationError.busy }
            let claim = try prepare(state, job)
            guard claim.requestSHA256 == job.requestSHA256 else { throw AgentBridgeValidationError.bindingChanged }
            state.captureClaims = claims + [claim]
            let result = AgentBridgeExportCaptureReservation(job: job, claim: claim)
            selected = result
            return (result, true)
        }
    }

    func storeNativeDelegation(_ value: AgentBridgeExportDelegation, expectedGeneration: Int64,
                               authorization: any AgentBridgeExportNativeAuthorizing) throws {
        guard value.issuer == .nativeSource, value.peer.platform == .apple else { throw AgentBridgeValidationError.approvalRequired }
        let bytes = try AgentBridgeV4Codec.encode(value)
        guard bytes.count <= Self.recordLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
        let action = AgentBridgeExportNativeAction.storeDelegation(value)
        try authorization.requireNativeAuthorization(for: action)
        // After releasing issuer locks, invalidate even on an ambiguous failed write.
        // Initial native authorization rejection is silent; reads/catalog/decisions never emit.
        defer { NotificationCenter.default.post(name: .healthMdAgentExportAuthorityDidChange, object: nil) }
        try transaction(beforeCommit: { _ in
            try authorization.requireNativeAuthorization(for: action)
        }) { state in
            guard state.generation == expectedGeneration else { throw AgentBridgeValidationError.revisionConflict }
            if let index = try state.delegations.firstIndex(where: { try $0.description().authorityID == value.authorityID }) {
                let old = try state.delegations[index].description()
                guard !state.delegations[index].revoked, old.peer == value.peer,
                      value.grantRevision == old.grantRevision + 1 else { throw AgentBridgeValidationError.revisionConflict }
                state.delegations[index] = .init(sanitizedBytes: bytes, sha256: try AgentBridgeDigest(AgentBridgeV4Codec.sha256(bytes)), revoked: false)
            } else {
                guard value.grantRevision == 1, state.delegations.count < 32 else { throw AgentBridgeValidationError.queryBudgetExceeded }
                state.delegations.append(.init(sanitizedBytes: bytes, sha256: try AgentBridgeDigest(AgentBridgeV4Codec.sha256(bytes)), revoked: false))
            }
            return ((), true)
        }
    }

    func revokeNativeDelegation(_ reference: AgentBridgeAuthorityReference, expectedGeneration: Int64,
                                authorization: any AgentBridgeExportNativeAuthorizing) throws {
        let action = AgentBridgeExportNativeAction.revokeDelegation(reference)
        try authorization.requireNativeAuthorization(for: action)
        // After releasing issuer locks, invalidate even on an ambiguous failed write.
        // Initial native authorization rejection is silent; reads/catalog/decisions never emit.
        defer { NotificationCenter.default.post(name: .healthMdAgentExportAuthorityDidChange, object: nil) }
        try transaction(beforeCommit: { _ in
            try authorization.requireNativeAuthorization(for: action)
        }) { state in
            guard state.generation == expectedGeneration else { throw AgentBridgeValidationError.revisionConflict }
            guard let index = try state.delegations.firstIndex(where: { try $0.description().reference() == reference }) else { throw AgentBridgeValidationError.approvalRequired }
            let changed = !state.delegations[index].revoked
            state.delegations[index].revoked = true // Tombstone is never evicted/reused, even after expiry.
            return ((), changed)
        }
    }

    func persistIssuedPlan(_ record: AgentBridgeExportIssuedPlan, expectedGeneration: Int64,
                           requireCurrentAuthority: (AgentBridgeExportAuthoritySnapshot) throws -> Void) throws -> AgentBridgeExportIssuedPlan {
        try transaction(beforeCommit: requireCurrentAuthority) { state in
            guard state.generation == expectedGeneration else { throw AgentBridgeValidationError.revisionConflict }
            let request = try record.request()
            if let previous = try state.plans.first(where: { try $0.request().requestId == request.requestId && $0.request().intent.peer == request.intent.peer }) {
                guard previous.requestBytes == record.requestBytes else { throw AgentBridgeValidationError.bindingChanged }
                return (previous, false)
            }
            guard state.plans.count < 32 else { throw AgentBridgeValidationError.busy }
            state.plans.append(record)
            return (record, true)
        }
    }

    func persistNativeDecision(planID: AgentBridgeUUID, binding: AgentBridgeBinding, expectedGeneration: Int64,
                               authorization: any AgentBridgeExportNativeAuthorizing,
                               makeDecision: (AgentBridgeExportAuthoritySnapshot) throws -> AgentBridgeExportStoredDecision,
                               requireCurrentAuthority: (AgentBridgeExportAuthoritySnapshot) throws -> Void) throws {
        // Native consent may delay or revoke authority. It runs outside the private lock, then the
        // builder/validator receive the freshly loaded CAS state after protected-key lookup.
        let action = AgentBridgeExportNativeAction.decideExport(planID: planID, binding: binding)
        try authorization.requireNativeAuthorization(for: action)
        try transaction(beforeCommit: { current in
            try authorization.requireNativeAuthorization(for: action)
            try requireCurrentAuthority(current) // Sample live authority/time AFTER the native callback.
        }) { state in
            guard state.generation == expectedGeneration else { throw AgentBridgeValidationError.revisionConflict }
            let decision = try makeDecision(state), approval = try decision.approval()
            let plan = try state.issued(id: planID, peer: binding.peer).plan()
            guard decision.planID == planID, approval.binding == binding, binding == AgentBridgeSemantics.binding(plan),
                  approval.approvedAt.rawValue >= plan.issuedAt.rawValue, approval.approvedAt.rawValue < plan.expiresAt.rawValue else { throw AgentBridgeValidationError.bindingChanged }
            if let previous = state.decisions.first(where: { $0.planID == planID }) {
                guard previous.approvalBytes == decision.approvalBytes else { throw AgentBridgeValidationError.bindingChanged }
                return ((), false)
            }
            guard state.decisions.count < 32 else { throw AgentBridgeValidationError.busy }
            state.decisions.append(decision)
            return ((), true)
        }
    }

    private static func existingKey(_ provider: any AgentBridgeExportProtectedKeyReading) throws -> SymmetricKey {
        do {
            guard let key = try provider.loadExistingExportAuthorityKey(), key.bitCount == 256 else { throw AgentBridgeValidationError.permissionRequired }
            return key
        } catch { throw AgentBridgeValidationError.permissionRequired }
    }

    private func requireCurrentRoot() throws {
        let current = try AgentBridgeExportPrivateFiles.openDirectory(directory, privateLeaf: true)
        defer { close(current) }
        guard try AgentBridgeExportPrivateFiles.identity(current) == rootIdentity else { throw AgentBridgeValidationError.bindingChanged }
    }

    private func transaction<T>(beforeCommit: (AgentBridgeExportAuthoritySnapshot) throws -> Void = { _ in }, _ body: (inout AgentBridgeExportAuthoritySnapshot) throws -> (T, Bool)) throws -> T {
        // Reopen the entire path without following symlinks: moving/replacing the private root does
        // not silently redirect authority to a formerly valid retained directory handle.
        try requireCurrentRoot()
        let lock = try AgentBridgeExportPrivateFiles.openPrivateFile(rootFD, "lock", flags: O_RDWR)
        defer { close(lock) }
        var acquired = false
        for _ in 0..<50 {
            if flock(lock, LOCK_EX | LOCK_NB) == 0 { acquired = true; break }
            guard errno == EWOULDBLOCK || errno == EINTR else { throw AgentBridgeValidationError.bindingChanged }
            usleep(10_000)
        }
        guard acquired else { throw AgentBridgeValidationError.busy }
        defer { _ = flock(lock, LOCK_UN) }
        func requireLockedIdentity() throws {
            try requireCurrentRoot()
            try AgentBridgeExportPrivateFiles.checkPath(rootFD, "lock", fd: lock)
        }
        func revalidate(_ candidate: AgentBridgeExportAuthoritySnapshot) throws {
            try beforeCommit(candidate)
            // A native callback can replace either name. Holding the old lock descriptor alone
            // cannot serialize against another handle that opened the replacement lock inode.
            try requireLockedIdentity()
        }
        try requireLockedIdentity()
        let key = try Self.existingKey(keys)
        try requireLockedIdentity() // Keychain lookup can delay or invoke native callbacks too.
        var state = try read(key: key)
        let (result, changed) = try body(&state)
        try revalidate(state)
        if changed {
            guard state.generation < Int64.max else { throw AgentBridgeValidationError.busy }
            state.generation += 1
            try validate(state)
            try write(state, key: key, beforePublish: revalidate)
            // Post-rename/root-fsync expiry or revocation suppresses return. Publication cannot be
            // undone here: stale private metadata remains retained and every consumer revalidates it.
            try revalidate(state)
        }
        return result
    }

    private func read(key: SymmetricKey) throws -> AgentBridgeExportAuthoritySnapshot {
        do {
            let bytes = try AgentBridgeExportPrivateFiles.read(rootFD, "state.json")
            parsedStateLock.lock(); let previous = parsedState; parsedStateLock.unlock()
            if let previous, previous.bytes == bytes {
                // Exact bytes already passed grammar, model and cross-record validation. Do not
                // retain a key or skip its current MAC: key replacement/loss still denies.
                guard HMAC<SHA256>.isValidAuthenticationCode(previous.mac, authenticating: Self.domain + previous.body, using: key) else {
                    throw AgentBridgeValidationError.bindingChanged
                }
                return previous.state
            }
            // Strict raw UTF8/scalar/depth/node/key bounds, including decoded duplicate keys, BEFORE
            // Foundation decoding. Re-encoding rejects unknown/null/noncanonical private fields.
            let canonical = try AgentBridgeV4Codec.canonicalize(bytes)
            let signed = try JSONDecoder().decode(SignedState.self, from: canonical)
            let body = try canonicalPrivate(signed.state)
            guard signed.version == (signed.state.cancellationIntents != nil ? 5 : (signed.state.captureClaims != nil ? 4 : (signed.state.acceptedJobs != nil ? 3 : (signed.state.nativeCatalog == nil ? 1 : 2)))), try canonicalPrivate(signed) == canonical,
                  HMAC<SHA256>.isValidAuthenticationCode(signed.mac, authenticating: Self.domain + body, using: key) else { throw AgentBridgeValidationError.bindingChanged }
            try validate(signed.state)
            let parsed = ParsedState(bytes: bytes, body: body, mac: signed.mac, state: signed.state)
            parsedStateLock.lock(); parsedState = parsed; parsedStateLock.unlock()
            return signed.state
        } catch {
            parsedStateLock.lock(); parsedState = nil; parsedStateLock.unlock()
            if let error = error as? AgentBridgeValidationError { throw error }
            throw AgentBridgeValidationError.bindingChanged
        }
    }

    private func validate(_ state: AgentBridgeExportAuthoritySnapshot) throws {
        guard state.generation >= 0, state.delegations.count <= 32, state.plans.count <= 32, state.decisions.count <= 32 else { throw AgentBridgeValidationError.bindingChanged }
        try state.nativeCatalog?.validate()
        var grants = Set<AgentBridgeUUID>(), plans = Set<AgentBridgeUUID>(), requests = Set<String>(), decisions = Set<AgentBridgeUUID>()
        for record in state.delegations {
            guard record.sanitizedBytes.count <= Self.recordLimit, try grants.insert(record.description().authorityID).inserted else { throw AgentBridgeValidationError.bindingChanged }
        }
        for record in state.plans {
            guard record.version == 1, [record.requestBytes, record.planBytes, record.nativeResolution, record.nativeAuthorityBytes].allSatisfy({ !$0.isEmpty && $0.count <= Self.recordLimit }) else { throw AgentBridgeValidationError.bindingChanged }
            let request = try record.request(), plan = try record.plan()
            let authority = try AgentBridgeV4Codec.decode(AgentBridgeAuthority.self, from: record.nativeAuthorityBytes)
            guard try AgentBridgeV4Codec.encode(plan) == record.planBytes, plans.insert(plan.planId).inserted,
                  requests.insert(request.intent.peer.sourceInstallationID.rawValue + "/" + request.intent.peer.hostInstallationID.rawValue + "/" + request.requestId.rawValue).inserted,
                  plan.intent == request.intent, request.capabilitySha256 == plan.capabilitySha256,
                  request.hostAuthorityReference == plan.authorityReferences.host,
                  request.authorityId == plan.authorityReferences.native.authorityId,
                  request.authorityRevision == plan.authorityReferences.native.grantRevision,
                  authority.issuer == .nativeSource, authority.peer == plan.intent.peer,
                  authority.authorityId == request.authorityId, authority.grantRevision == request.authorityRevision,
                  authority.scopeSha256 == plan.scopeSha256, authority.expiresAt == plan.expiresAt,
                  authority.destinationBindingIds == [plan.intent.destination.bindingID], authority.controlReadScope == nil,
                  authority.rights.allSatisfy({ [.discover, .plan, .exportExecute].contains($0) }) else { throw AgentBridgeValidationError.bindingChanged }
        }
        for record in state.decisions {
            let approval = try record.approval()
            guard record.approvalBytes.count <= Self.recordLimit, try AgentBridgeV4Codec.encode(approval) == record.approvalBytes,
                  decisions.insert(approval.approvalId).inserted,
                  approval.binding == (try AgentBridgeSemantics.binding(state.issued(id: record.planID, peer: approval.binding.peer).plan())) else { throw AgentBridgeValidationError.bindingChanged }
        }
        if let jobs = state.acceptedJobs {
            guard !jobs.isEmpty, jobs.count <= 16 else { throw AgentBridgeValidationError.bindingChanged }
            var identities = Set<String>()
            for job in jobs {
                try job.validate()
                let request = try job.request(), peer = request.plan.intent.peer
                let record = try state.issued(id: request.plan.planId, peer: peer)
                guard try record.plan() == request.plan, record.nativeResolution == job.nativeResolution,
                      state.decisions.contains(where: { $0.planID == request.plan.planId && (try? $0.approval()) == request.approval }),
                      identities.insert(peer.sourceInstallationID.rawValue + ":" + peer.hostInstallationID.rawValue + ":" + request.jobId.rawValue).inserted else {
                    throw AgentBridgeValidationError.bindingChanged
                }
            }
        }
        if let claims = state.captureClaims {
            guard !claims.isEmpty, claims.count <= 16, Set(claims.map(\.claimID)).count == claims.count,
                  Set(claims.map(\.requestSHA256)).count == claims.count else { throw AgentBridgeValidationError.bindingChanged }
            for claim in claims {
                guard claim.version == 1, let job = state.acceptedJobs?.first(where: { $0.requestSHA256 == claim.requestSHA256 }),
                      claim.claimedAt.rawValue >= job.acceptedAt.rawValue, claim.claimedAt.rawValue < job.expiresAt.rawValue,
                      claim.claimedAt.rawValue < (try job.request().plan.expiresAt).rawValue else { throw AgentBridgeValidationError.bindingChanged }
            }
        }
        if let intents = state.cancellationIntents {
            guard !intents.isEmpty, intents.count <= 16 else { throw AgentBridgeValidationError.bindingChanged }
            var requests = Set<AgentBridgeDigest>()
            for intent in intents {
                let cancel = try intent.request()
                guard requests.insert(cancel.requestSha256).inserted,
                      let job = state.acceptedJobs?.first(where: { $0.requestSHA256 == cancel.requestSha256 }) else {
                    throw AgentBridgeValidationError.bindingChanged
                }
                try intent.validate(job: job)
                if intent.version == 2 {
                    guard state.captureClaims?.contains(where: { $0.requestSHA256 == job.requestSHA256 }) != true else {
                        throw AgentBridgeValidationError.bindingChanged
                    }
                }
                if intent.version == 3 {
                    guard state.captureClaims?.contains(where: { $0.requestSHA256 == job.requestSHA256 }) == true else {
                        throw AgentBridgeValidationError.bindingChanged
                    }
                }
            }
        }
        guard Set(state.decisions.map(\.planID)).count == state.decisions.count else { throw AgentBridgeValidationError.bindingChanged }
    }

    private func canonicalPrivate<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try AgentBridgeV4Codec.canonicalize(encoder.encode(value))
    }
    private func write(_ state: AgentBridgeExportAuthoritySnapshot, key: SymmetricKey,
                       beforePublish: (AgentBridgeExportAuthoritySnapshot) throws -> Void = { _ in }) throws {
        let stateBytes = try canonicalPrivate(state)
        let mac = Data(HMAC<SHA256>.authenticationCode(for: Self.domain + stateBytes, using: key))
        try AgentBridgeExportPrivateFiles.replace(rootFD, "state.json", bytes: canonicalPrivate(SignedState(version: state.cancellationIntents != nil ? 5 : (state.captureClaims != nil ? 4 : (state.acceptedJobs != nil ? 3 : (state.nativeCatalog == nil ? 1 : 2))), state: state, mac: mac)),
            beforeRename: {
                try self.publication.prepared(state)
                // Canonical serialization, HMAC, temp write and fsync have ALREADY completed. This
                // state-aware guard is the last callback before atomic rename; session THEN live time.
                try beforePublish(state)
            }, afterSync: { try self.publication.published(state) })
    }
}

nonisolated struct AgentBridgeExportFileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}
nonisolated enum AgentBridgeExportPrivateFiles {
    static func identity(_ fd: Int32) throws -> AgentBridgeExportFileIdentity {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw AgentBridgeValidationError.bindingChanged }
        return .init(device: info.st_dev, inode: info.st_ino)
    }
    static func openDirectory(_ url: URL, privateLeaf: Bool) throws -> Int32 {
        guard url.isFileURL, url.path.hasPrefix("/"), !url.path.contains("\0") else { throw AgentBridgeValidationError.unsafePath }
        let components = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.isEmpty, !components.contains("."), !components.contains("..") else { throw AgentBridgeValidationError.unsafePath }
        var fd = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else { throw AgentBridgeValidationError.bindingChanged }
        do {
            for (index, component) in components.enumerated() {
                let next = openat(fd, component, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
                guard next >= 0 else { throw AgentBridgeValidationError.bindingChanged }
                close(fd); fd = next
                var info = stat()
                guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR,
                      info.st_uid == geteuid() || info.st_uid == 0 else { throw AgentBridgeValidationError.bindingChanged }
                if privateLeaf && index == components.count - 1 {
                    guard info.st_uid == geteuid(), info.st_mode & 0o777 == 0o700 else { throw AgentBridgeValidationError.bindingChanged }
                } else if info.st_mode & 0o022 != 0 {
                    guard info.st_mode & S_ISVTX != 0, info.st_uid == 0 else { throw AgentBridgeValidationError.bindingChanged }
                }
            }
            return fd
        } catch { close(fd); throw error }
    }
    static func openPrivateFile(_ root: Int32, _ name: String, flags: Int32) throws -> Int32 {
        let fd = openat(root, name, flags | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw AgentBridgeValidationError.bindingChanged }
        do { try checkPath(root, name, fd: fd); return fd }
        catch { close(fd); throw error }
    }
    static func checkPath(_ root: Int32, _ name: String, fd: Int32) throws {
        var opened = stat(), named = stat()
        guard fstat(fd, &opened) == 0, fstatat(root, name, &named, AT_SYMLINK_NOFOLLOW) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
              opened.st_mode & S_IFMT == S_IFREG, opened.st_uid == geteuid(), opened.st_nlink == 1,
              opened.st_mode & 0o777 == 0o600 else { throw AgentBridgeValidationError.bindingChanged }
    }
    static func read(_ root: Int32, _ name: String, maximumBytes: Int = AgentBridgeV4Codec.maximumBytes,
                     verifyDescriptor: (Int32) throws -> Void = { _ in }) throws -> Data {
        let fd = try openPrivateFile(root, name, flags: O_RDONLY)
        defer { close(fd) }
        let expected = try identity(fd)
        try verifyDescriptor(fd)
        guard try identity(fd) == expected else { throw AgentBridgeValidationError.bindingChanged }
        try checkPath(root, name, fd: fd)
        var info = stat()
        guard maximumBytes > 0, maximumBytes <= AgentBridgeV4Codec.maximumBytes,
              fstat(fd, &info) == 0, info.st_size > 0, info.st_size <= maximumBytes else { throw AgentBridgeValidationError.bindingChanged }
        var data = Data(count: Int(info.st_size))
        try data.withUnsafeMutableBytes { buffer in
            var position = 0
            while position < buffer.count {
                let count = Darwin.read(fd, buffer.baseAddress!.advanced(by: position), buffer.count - position)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AgentBridgeValidationError.bindingChanged }
                position += count
            }
        }
        var extra: UInt8 = 0
        guard Darwin.read(fd, &extra, 1) == 0, try identity(fd) == expected else { throw AgentBridgeValidationError.bindingChanged }
        try checkPath(root, name, fd: fd)
        return data
    }
    static func replace(_ root: Int32, _ name: String, bytes: Data, beforeRename: () throws -> Void, afterSync: () throws -> Void) throws {
        guard !bytes.isEmpty, bytes.count <= AgentBridgeV4Codec.maximumBytes else { throw AgentBridgeValidationError.queryBudgetExceeded }
        let temporary = "transaction-" + UUID().uuidString.lowercased()
        let fd = openat(root, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AgentBridgeValidationError.bindingChanged }
        defer { close(fd); _ = unlinkat(root, temporary, 0) } // Only this transaction's uncommitted file.
        try bytes.withUnsafeBytes { buffer in
            var position = 0
            while position < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: position), buffer.count - position)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AgentBridgeValidationError.bindingChanged }
                position += count
            }
        }
        try checkPath(root, temporary, fd: fd)
        guard fsync(fd) == 0 else { throw AgentBridgeValidationError.bindingChanged }
        try beforeRename()
        guard renameat(root, temporary, root, name) == 0, fsync(root) == 0 else { throw AgentBridgeValidationError.bindingChanged }
        try afterSync()
    }
}

/// Transient proof of ONE exact native confirmation, not a grant or serializable capability.
/// Only the native confirmation handler enters this scope. The proof cannot escape the operation,
/// authorize another action, survive observed policy loss, or renew itself when policy recovers.
nonisolated final class AgentBridgeExportNativeConsent: AgentBridgeExportNativeAuthorizing, @unchecked Sendable {
    private let expectedAction: AgentBridgeExportNativeAction
    private let lock = NSLock()
    private var active = true
    private let requireCurrentNativePolicy: @Sendable () throws -> Void
    private let now: @Sendable () -> ContinuousClock.Instant
    private let deadline: ContinuousClock.Instant

    private init(action: AgentBridgeExportNativeAction, policy: @escaping @Sendable () throws -> Void,
                 now: @escaping @Sendable () -> ContinuousClock.Instant) {
        expectedAction = action
        requireCurrentNativePolicy = policy
        self.now = now
        deadline = now().advanced(by: .seconds(30))
    }

    static func withNativeConfirmation<T>(
        for action: AgentBridgeExportNativeAction,
        requireCurrentNativePolicy: @escaping @Sendable () throws -> Void,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        _ operation: (any AgentBridgeExportNativeAuthorizing) throws -> T
    ) throws -> T {
        let consent = Self(action: action, policy: requireCurrentNativePolicy, now: now)
        defer { consent.invalidate() }
        try consent.requireNativeAuthorization(for: action)
        let result = try operation(consent)
        try consent.requireNativeAuthorization(for: action)
        return result
    }

    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws {
        do {
            guard action == expectedAction, lock.withLock({ active }), now() < deadline else {
                throw AgentBridgeValidationError.approvalRequired
            }
            try requireCurrentNativePolicy()
            guard lock.withLock({ active }), now() < deadline else { throw AgentBridgeValidationError.approvalRequired }
        } catch {
            invalidate()
            throw AgentBridgeValidationError.approvalRequired
        }
    }

    private func invalidate() { lock.withLock { active = false } }
}

/// Setup has a deliberately narrower entry point; it can never authorize grant or approval actions.
nonisolated enum AgentBridgeExportNativeSetupConsent {
    static func withNativeConfirmation<T>(
        requireCurrentNativePolicy: @escaping @Sendable () throws -> Void,
        now: @escaping @Sendable () -> ContinuousClock.Instant = { ContinuousClock.now },
        _ operation: (any AgentBridgeExportNativeAuthorizing) throws -> T
    ) throws -> T {
        try AgentBridgeExportNativeConsent.withNativeConfirmation(for: .createPrivateStore,
            requireCurrentNativePolicy: requireCurrentNativePolicy, now: now, operation)
    }
}
