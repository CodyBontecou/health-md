import CryptoKit
import Darwin
import Foundation
import HealthMdConnectionCore
import XCTest
#if canImport(HealthMd)
@testable import HealthMd
#else
@testable import AgentBridgeRequestSettingsHarness
#endif

final class AgentBridgeExportAuthorityStoreTests: XCTestCase {
    func testPrivateCASHasOneWinnerAcrossIndependentStoreHandles() throws {
        let rig = try StoreRig(); defer { rig.cleanup() }
        let second = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: rig.keys)
        let firstGrant = try rig.grant(7), secondGrant = try rig.grant(8)
        let result = CASResult()
        DispatchQueue.concurrentPerform(iterations: 2) { index in
            do {
                try (index == 0 ? rig.store : second).storeNativeDelegation(index == 0 ? firstGrant : secondGrant,
                                                                         expectedGeneration: 0, authorization: IsolatedNativeAuthorization())
                result.record(nil)
            } catch { result.record(error as? AgentBridgeValidationError ?? .invalidRequest) }
        }
        XCTAssertEqual(result.successes, 1)
        XCTAssertEqual(result.failures, [.revisionConflict])
        let snapshot = try second.snapshot()
        XCTAssertEqual(snapshot.generation, 1)
        XCTAssertEqual(snapshot.delegations.count, 1)
        XCTAssertEqual(snapshot.plans.count + snapshot.decisions.count, 0)
    }

    func testDigestRevisionRevocationAndLostKeyAreNeverRepairedOrReenrolled() throws {
        let rig = try StoreRig(); defer { rig.cleanup() }
        let grant = try rig.grant(7)
        try rig.store.storeNativeDelegation(grant, expectedGeneration: 0, authorization: IsolatedNativeAuthorization())
        let before = try rig.bytes()
        let reopened = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: rig.keys)
        let refs = try reopened.snapshot().references(peer: grant.peer, now: AgentBridgeUTC("2026-03-09T00:00:00Z"))
        XCTAssertEqual(refs, [try grant.reference()])
        try reopened.revokeNativeDelegation(refs[0], expectedGeneration: 1, authorization: IsolatedNativeAuthorization())
        XCTAssertTrue(try reopened.snapshot().references(peer: grant.peer, now: AgentBridgeUTC("2026-03-09T00:00:00Z")).isEmpty)
        XCTAssertEqual(try reopened.snapshot().delegations.count, 1) // Retained tombstone.
        XCTAssertThrowsError(try reopened.storeNativeDelegation(rig.grant(7, revision: 2), expectedGeneration: 2, authorization: IsolatedNativeAuthorization()))
        let denied = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: IsolatedKeys(key: nil))
        let revoked = try rig.bytes()
        XCTAssertThrowsError(try denied.snapshot()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(try rig.bytes(), revoked)
        XCTAssertNotEqual(before, revoked)
        let wrongKey = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: IsolatedKeys(key: SymmetricKey(data: Data(repeating: 5, count: 32))))
        XCTAssertThrowsError(try wrongKey.snapshot())
        XCTAssertEqual(try rig.bytes(), revoked)
    }

    func testCrashOrphanIsNotStateAndMissingStateNeverRegenerates() throws {
        let rig = try StoreRig(); defer { rig.cleanup() }
        try rig.store.storeNativeDelegation(rig.grant(7), expectedGeneration: 0, authorization: IsolatedNativeAuthorization())
        let orphan = rig.directory.appendingPathComponent("transaction-crash")
        try Data("partial".utf8).write(to: orphan)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: orphan.path)
        let reopened = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: rig.keys)
        XCTAssertEqual(try reopened.snapshot().delegations.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan.path)) // No unowned crash cleanup/eviction.
        try FileManager.default.removeItem(at: rig.stateFile)
        XCTAssertThrowsError(try reopened.snapshot())
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.stateFile.path))
        XCTAssertThrowsError(try reopened.storeNativeDelegation(rig.grant(8), expectedGeneration: 1, authorization: IsolatedNativeAuthorization()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: rig.stateFile.path))
    }

    func testCorruptionDecodedDuplicateKeysUnknownFieldsUTF8AndMACFailClosed() throws {
        for variant in 0..<5 {
            let rig = try StoreRig(); defer { rig.cleanup() }
            try rig.store.storeNativeDelegation(rig.grant(7), expectedGeneration: 0, authorization: IsolatedNativeAuthorization())
            let original = try rig.bytes(), text = String(decoding: original, as: UTF8.self)
            let damaged: Data
            switch variant {
            case 0: damaged = Data(text.replacingOccurrences(of: "\"generation\":1", with: "\"generation\":2").utf8)
            case 1: damaged = Data(text.replacingOccurrences(of: "\"generation\":1", with: "\"generation\":1,\"gene\\u0072ation\":1").utf8)
            case 2: damaged = Data(text.replacingOccurrences(of: "\"generation\":1", with: "\"generation\":1,\"unknown\":1").utf8)
            case 3: damaged = Data([0xff]) + original
            default: damaged = Data("{}".utf8)
            }
            try damaged.write(to: rig.stateFile)
            XCTAssertThrowsError(try rig.store.snapshot())
            XCTAssertEqual(try rig.bytes(), damaged)
        }
    }

    func testPrivateRootAncestorFileLockHardlinkAndModeSubstitutionReject() throws {
        let rig = try StoreRig(); defer { rig.cleanup() }
        let alias = rig.parent.appendingPathComponent("alias")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: rig.directory)
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore(existingDirectory: alias, protectedKeys: rig.keys))
        let nestedAlias = alias.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: rig.directory.appendingPathComponent("nested"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore(existingDirectory: nestedAlias, protectedKeys: rig.keys))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: rig.directory.path)
        XCTAssertThrowsError(try rig.store.snapshot())
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: rig.directory.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: rig.stateFile.path)
        XCTAssertThrowsError(try rig.store.snapshot())
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: rig.stateFile.path)
        let linked = rig.parent.appendingPathComponent("linked-state")
        guard link(rig.stateFile.path, linked.path) == 0 else { return XCTFail("isolated hardlink setup") }
        XCTAssertThrowsError(try rig.store.snapshot())
        try FileManager.default.removeItem(at: linked)
        let preserved = rig.parent.appendingPathComponent("preserved-state")
        try FileManager.default.moveItem(at: rig.stateFile, to: preserved)
        try FileManager.default.createSymbolicLink(at: rig.stateFile, withDestinationURL: preserved)
        XCTAssertThrowsError(try rig.store.snapshot())
        try FileManager.default.removeItem(at: rig.stateFile)
        try FileManager.default.moveItem(at: preserved, to: rig.stateFile)
        let lockFile = rig.directory.appendingPathComponent("lock"), lockCopy = rig.parent.appendingPathComponent("lock-copy")
        try FileManager.default.moveItem(at: lockFile, to: lockCopy)
        try FileManager.default.createSymbolicLink(at: lockFile, withDestinationURL: lockCopy)
        XCTAssertThrowsError(try rig.store.snapshot())
        try FileManager.default.removeItem(at: lockFile)
        try FileManager.default.moveItem(at: lockCopy, to: lockFile)
        let moved = rig.parent.appendingPathComponent("old-authority")
        try FileManager.default.moveItem(at: rig.directory, to: moved)
        let newlyCreated = try AgentBridgeExportAuthorityStore.createPrivateStore(at: rig.directory, protectedKeys: rig.keys, authorization: IsolatedNativeAuthorization())
        XCTAssertThrowsError(try rig.store.snapshot()) // SAME INSTANCE pins the old root's device/inode.
        XCTAssertEqual(try newlyCreated.snapshot().generation, 0) // Fresh open has no independently protected root identity history.
    }

    func testValidHistoricalSignedSnapshotIsNotAntiRollbackProtection() throws {
        let rig = try StoreRig(); defer { rig.cleanup() }
        let grant = try rig.grant(7)
        try rig.store.storeNativeDelegation(grant, expectedGeneration: 0, authorization: IsolatedNativeAuthorization())
        let validHistoricalSnapshot = try rig.bytes()
        try rig.store.revokeNativeDelegation(grant.reference(), expectedGeneration: 1, authorization: IsolatedNativeAuthorization())
        XCTAssertEqual(try rig.store.snapshot().generation, 2)
        // Deliberately model an actor with private-file write access. This is VALID old HMAC data,
        // not forged/corrupt bytes. There is no protected monotonic counter or anti-rollback claim.
        try validHistoricalSnapshot.write(to: rig.stateFile)
        let fresh = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: rig.keys)
        XCTAssertEqual(try fresh.snapshot().generation, 1)
        XCTAssertEqual(try fresh.snapshot().references(peer: grant.peer, now: AgentBridgeUTC("2026-03-09T00:00:00Z")).count, 1)
    }

    func testInspectAndPublicationHooksReceiveCurrentRevokedCASState() throws {
        let rig = try StoreRig(); defer { rig.cleanup() }
        let grant = try rig.grant(7)
        try rig.store.storeNativeDelegation(grant, expectedGeneration: 0, authorization: IsolatedNativeAuthorization())
        let old = try rig.store.snapshot()
        try rig.store.revokeNativeDelegation(grant.reference(), expectedGeneration: 1, authorization: IsolatedNativeAuthorization())
        let before = try rig.bytes()
        try rig.store.inspectCurrent { current in
            XCTAssertEqual(old.generation, 1)
            XCTAssertFalse(old.delegations[0].revoked)
            XCTAssertEqual(current.generation, 2)
            XCTAssertTrue(current.delegations[0].revoked)
            XCTAssertTrue(try current.references(peer: grant.peer, now: AgentBridgeUTC("2026-03-09T00:00:00Z")).isEmpty)
        }
        var prepared = false
        rig.publication.beforeRename = { candidate in
            prepared = true
            XCTAssertEqual(candidate.generation, 3)
            XCTAssertEqual(candidate.delegations.count, 2)
            XCTAssertTrue(candidate.delegations[0].revoked) // Not the captured generation-1 authority.
            throw AgentBridgeValidationError.planExpired
        }
        XCTAssertThrowsError(try rig.store.storeNativeDelegation(rig.grant(8), expectedGeneration: 2, authorization: IsolatedNativeAuthorization())) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired)
        }
        XCTAssertTrue(prepared)
        XCTAssertEqual(try rig.bytes(), before)
        XCTAssertEqual(try rig.store.snapshot().generation, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rig.directory.path).sorted(), ["lock", "state.json"])
    }

    func testNativeAuthorizationAndIssuerAreNotPayloadFlags() throws {
        let rig = try StoreRig(); defer { rig.cleanup() }
        XCTAssertThrowsError(try rig.store.storeNativeDelegation(rig.grant(7), expectedGeneration: 0, authorization: IsolatedNativeAuthorization(allowed: false)))
        let source = try rig.grant(7)
        let b = source.bounds
        let host = AgentBridgeExportDelegation(authorityID: source.authorityID, issuer: .authorizedHost, grantRevision: 1, peer: source.peer, rights: source.rights, expiresAt: source.expiresAt,
                                               bounds: .init(products: b.products, projectionDetails: b.projectionDetails, projectionObjectIDs: b.projectionObjectIDs, projectionFieldIDs: b.projectionFieldIDs,
                                                             metricIDs: b.metricIDs, calendarTimezones: b.calendarTimezones, datePolicy: b.datePolicy, formats: b.formats, outputProfiles: b.outputProfiles,
                                                             writeModes: b.writeModes, compatibilityDetail: b.compatibilityDetail, nativeArchiveProducts: b.nativeArchiveProducts, destinationPolicy: .registeredHostBindings([try storeID(3)])))
        XCTAssertThrowsError(try rig.store.storeNativeDelegation(host, expectedGeneration: 0, authorization: IsolatedNativeAuthorization()))
        XCTAssertEqual(try rig.store.snapshot().generation, 0)
    }
}

nonisolated private final class CASResult: @unchecked Sendable {
    private let lock = NSLock()
    private var ok = 0
    private var errors: [AgentBridgeValidationError] = []
    func record(_ error: AgentBridgeValidationError?) { lock.lock(); defer { lock.unlock() }; if let error { errors.append(error) } else { ok += 1 } }
    var successes: Int { lock.lock(); defer { lock.unlock() }; return ok }
    var failures: [AgentBridgeValidationError] { lock.lock(); defer { lock.unlock() }; return errors }
}
nonisolated private final class IsolatedKeys: AgentBridgeExportProtectedKeyReading, @unchecked Sendable {
    let key: SymmetricKey?
    init(key: SymmetricKey? = SymmetricKey(data: Data(repeating: 7, count: 32))) { self.key = key }
    func loadExistingExportAuthorityKey() throws -> SymmetricKey? { key }
}
nonisolated private struct IsolatedNativeAuthorization: AgentBridgeExportNativeAuthorizing {
    var allowed = true
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws { guard allowed else { throw AgentBridgeValidationError.permissionRequired } }
}
nonisolated private final class StorePublicationProbe: AgentBridgeExportPublicationObserving {
    var beforeRename: ((AgentBridgeExportAuthoritySnapshot) throws -> Void)?
    func prepared(_ state: AgentBridgeExportAuthoritySnapshot) throws { try beforeRename?(state) }
    func published(_ state: AgentBridgeExportAuthoritySnapshot) throws {}
}
nonisolated private func storeID(_ n: Int) throws -> AgentBridgeUUID { try AgentBridgeUUID(String(format: "00000000-0000-4000-8000-%012x", n)) }
nonisolated private final class StoreRig: @unchecked Sendable {
    let parent: URL
    let directory: URL
    let keys = IsolatedKeys()
    let publication = StorePublicationProbe()
    let store: AgentBridgeExportAuthorityStore
    var stateFile: URL { directory.appendingPathComponent("state.json") }
    init() throws {
        parent = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("healthmd-native-authority-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = parent.appendingPathComponent("authority")
        store = try .createPrivateStore(at: directory, protectedKeys: keys, authorization: IsolatedNativeAuthorization(), publication: publication)
    }
    func grant(_ number: Int, revision: Int64 = 1) throws -> AgentBridgeExportDelegation {
        try .init(authorityID: storeID(number), issuer: .nativeSource, grantRevision: revision,
                  peer: .init(sourceInstallationID: storeID(1), hostInstallationID: storeID(2), platform: .apple), rights: [.discover, .exportExecute, .plan], expiresAt: AgentBridgeUTC("2026-03-09T01:00:00Z"),
                  bounds: .init(products: [.generatedFiles], projectionDetails: [], projectionObjectIDs: [], projectionFieldIDs: [], metricIDs: [AgentBridgeID("steps")], calendarTimezones: [AgentBridgeZone("UTC")],
                                datePolicy: .authorizedHistory(maxDays: 366, allowAllAvailable: true), formats: [.json], outputProfiles: [.appleV8], writeModes: [.overwrite], compatibilityDetail: [.summary], nativeArchiveProducts: [.none], destinationPolicy: .authenticatedHostBindings))
    }
    func bytes() throws -> Data { try Data(contentsOf: stateFile) }
    func cleanup() { try? FileManager.default.removeItem(at: parent) }
}
