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
nonisolated enum AgentBridgeExportNativeAction {
    case createPrivateStore
    case storeDelegation(AgentBridgeExportDelegation)
    case revokeDelegation(AgentBridgeAuthorityReference)
    case decideExport(planID: AgentBridgeUUID, binding: AgentBridgeBinding)
}
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
nonisolated struct AgentBridgeExportAuthoritySnapshot: Codable {
    var generation: Int64
    var delegations: [AgentBridgeExportStoredDelegation]
    var plans: [AgentBridgeExportIssuedPlan]
    var decisions: [AgentBridgeExportStoredDecision]

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
    private struct SignedState: Codable {
        let version: Int
        let state: AgentBridgeExportAuthoritySnapshot
        let mac: Data
    }

    init(existingDirectory: URL, protectedKeys: any AgentBridgeExportProtectedKeyReading,
         publication: any AgentBridgeExportPublicationObserving = AgentBridgeExportUnobservedPublication()) throws {
        directory = existingDirectory
        rootFD = try AgentBridgeExportPrivateFiles.openDirectory(existingDirectory, privateLeaf: true)
        do { rootIdentity = try AgentBridgeExportPrivateFiles.identity(rootFD) }
        catch { close(rootFD); throw error }
        keys = protectedKeys
        self.publication = publication
    }
    deinit { close(rootFD) }

    /// Explicit local-native bootstrap only. Keys must already exist under independent native
    /// protection. The remote service has no access to this method or an authorizing context.
    static func createPrivateStore(at directory: URL, protectedKeys: any AgentBridgeExportProtectedKeyReading,
                                   authorization: any AgentBridgeExportNativeAuthorizing,
                                   publication: any AgentBridgeExportPublicationObserving = AgentBridgeExportUnobservedPublication()) throws -> AgentBridgeExportAuthorityStore {
        try authorization.requireNativeAuthorization(for: .createPrivateStore)
        let key = try existingKey(protectedKeys)
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
        try store.write(.init(generation: 0, delegations: [], plans: [], decisions: []), key: key)
        return store
    }

    func snapshot() throws -> AgentBridgeExportAuthoritySnapshot {
        try inspectCurrent { $0 }
    }

    /// Load protected key and current private state under the same lock as CAS/publication. The
    /// validator receives THIS state, never an earlier captured snapshot presented as a refresh.
    func inspectCurrent<T>(_ inspect: (AgentBridgeExportAuthoritySnapshot) throws -> T) throws -> T {
        try transaction { state in (try inspect(state), false) }
    }

    func storeNativeDelegation(_ value: AgentBridgeExportDelegation, expectedGeneration: Int64,
                               authorization: any AgentBridgeExportNativeAuthorizing) throws {
        guard value.issuer == .nativeSource, value.peer.platform == .apple else { throw AgentBridgeValidationError.approvalRequired }
        let bytes = try AgentBridgeV4Codec.encode(value)
        guard bytes.count <= Self.recordLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
        try authorization.requireNativeAuthorization(for: .storeDelegation(value))
        try transaction { state in
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
        try authorization.requireNativeAuthorization(for: .revokeDelegation(reference))
        try transaction { state in
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
        try authorization.requireNativeAuthorization(for: .decideExport(planID: planID, binding: binding))
        try transaction(beforeCommit: requireCurrentAuthority) { state in
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

    private func transaction<T>(beforeCommit: (AgentBridgeExportAuthoritySnapshot) throws -> Void = { _ in }, _ body: (inout AgentBridgeExportAuthoritySnapshot) throws -> (T, Bool)) throws -> T {
        // Reopen the entire path without following symlinks: moving/replacing the private root does
        // not silently redirect authority to a formerly valid retained directory handle.
        let current = try AgentBridgeExportPrivateFiles.openDirectory(directory, privateLeaf: true)
        defer { close(current) }
        guard try AgentBridgeExportPrivateFiles.identity(current) == rootIdentity else { throw AgentBridgeValidationError.bindingChanged }
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
        try AgentBridgeExportPrivateFiles.checkPath(rootFD, "lock", fd: lock)
        let key = try Self.existingKey(keys)
        var state = try read(key: key)
        let (result, changed) = try body(&state)
        try beforeCommit(state)
        if changed {
            guard state.generation < Int64.max else { throw AgentBridgeValidationError.busy }
            state.generation += 1
            try validate(state)
            try write(state, key: key, beforePublish: beforeCommit)
            // Post-rename/root-fsync expiry or revocation suppresses return. Publication cannot be
            // undone here: stale private metadata remains retained and every consumer revalidates it.
            try beforeCommit(state)
        }
        return result
    }

    private func read(key: SymmetricKey) throws -> AgentBridgeExportAuthoritySnapshot {
        do {
            let bytes = try AgentBridgeExportPrivateFiles.read(rootFD, "state.json")
            // Strict raw UTF8/scalar/depth/node/key bounds, including decoded duplicate keys, BEFORE
            // Foundation decoding. Re-encoding rejects unknown/null/noncanonical private fields.
            let canonical = try AgentBridgeV4Codec.canonicalize(bytes)
            let signed = try JSONDecoder().decode(SignedState.self, from: canonical)
            guard signed.version == 1, try canonicalPrivate(signed) == canonical,
                  HMAC<SHA256>.isValidAuthenticationCode(signed.mac, authenticating: Self.domain + (try canonicalPrivate(signed.state)), using: key) else { throw AgentBridgeValidationError.bindingChanged }
            try validate(signed.state)
            return signed.state
        } catch let error as AgentBridgeValidationError { throw error }
        catch { throw AgentBridgeValidationError.bindingChanged }
    }

    private func validate(_ state: AgentBridgeExportAuthoritySnapshot) throws {
        guard state.generation >= 0, state.delegations.count <= 32, state.plans.count <= 32, state.decisions.count <= 32 else { throw AgentBridgeValidationError.bindingChanged }
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
        try AgentBridgeExportPrivateFiles.replace(rootFD, "state.json", bytes: canonicalPrivate(SignedState(version: 1, state: state, mac: mac)),
            beforeRename: {
                try self.publication.prepared(state)
                // Canonical serialization, HMAC, temp write and fsync have ALREADY completed. This
                // state-aware guard is the last callback before atomic rename; session THEN live time.
                try beforePublish(state)
            }, afterSync: { try self.publication.published(state) })
    }
}

nonisolated private struct AgentBridgeExportFileIdentity: Equatable {
    let device: dev_t
    let inode: ino_t
}
nonisolated private enum AgentBridgeExportPrivateFiles {
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
    static func read(_ root: Int32, _ name: String) throws -> Data {
        let fd = try openPrivateFile(root, name, flags: O_RDONLY)
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_size > 0, info.st_size <= AgentBridgeV4Codec.maximumBytes else { throw AgentBridgeValidationError.bindingChanged }
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
        guard Darwin.read(fd, &extra, 1) == 0 else { throw AgentBridgeValidationError.bindingChanged }
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
