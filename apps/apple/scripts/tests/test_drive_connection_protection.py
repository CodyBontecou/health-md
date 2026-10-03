#!/usr/bin/env python3
"""Isolated production connection/store tests; OAuth/API DTO collaborators are doubles.
No Xcode, OS authentication, real Keychain, or native app typechecking is performed.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

APPLE = Path(__file__).resolve().parents[2]
STUBS = r'''
import Foundation
protocol ObservableObject {}
@propertyWrapper struct Published<Value> { var wrappedValue: Value }
enum ConfigurationProtectionManager { static let storageKey = "synthetic.protection" }
enum GoogleDriveErrorID: Error { case configurationMissing, reauthorizationRequired, accountMismatch, folderUnavailable, permissionDenied, remoteConflict, ambiguousCommit, quotaExceeded, rateLimited, checksumMismatch, partialCompletion }
struct GoogleDriveError: Error { let id: GoogleDriveErrorID; init(_ id: GoogleDriveErrorID, isRetryable: Bool = false) { self.id = id } }
enum GoogleDriveReadiness { case destinationMissing, configurationMissing, reauthorizationRequired, ready, folderUnavailable; var errorID: GoogleDriveErrorID? { nil } }
struct GoogleDriveConfiguration: Sendable { static func from() -> Self? { Self() } }
struct GoogleDriveTokenCredential: Codable, Equatable, Sendable { var accessToken = "synthetic"; var refreshToken = "synthetic"; var expiresAt = Date.distantFuture; var isDriveFileOnly: Bool { true } }
struct GoogleDriveDestination: Codable, Sendable {
    static let currentVersion = 1
    var version = 1
    var id: UUID; var credentialReferenceID: UUID; var accountPermissionID: String
    var folderID: String; var sharedDriveID: String?; var resourceKey: String?
    var accountLabel: String?; var folderLabel: String?; var canAddChildren: Bool; var lastValidatedAt: Date
}
struct GoogleDriveFileMetadata: Sendable {
    static let folderMIMEType = "folder"
    var mimeType = "folder"; var trashed = false; var canAddChildren: Bool? = true
    var id = "synthetic-folder"; var driveID: String?; var resourceKey: String?; var name = "Synthetic"
}
struct GoogleDriveAuthorizationRequest { var state = "state"; var pkce = PKCE(); struct PKCE { var verifier = "synthetic" }; static func make(configuration: GoogleDriveConfiguration) throws -> Self { Self() } }
struct GoogleDriveAuthorizationCallback { var code = "synthetic"; var selection = Selection(); struct Selection { var folderID = "synthetic-folder"; var resourceKey: String?; var sharedDriveID: String?; var folderLabel: String? }; static func parse(url: URL, expectedState: String) throws -> Self { Self() } }
@MainActor protocol GoogleDriveWebAuthorizing { func authorize(_ request: GoogleDriveAuthorizationRequest) async throws -> URL }
@MainActor final class ASWebGoogleDriveAuthorizer: GoogleDriveWebAuthorizing { func authorize(_ request: GoogleDriveAuthorizationRequest) async throws -> URL { URL(string: "https://synthetic.invalid")! } }
@MainActor final class AcquisitionTrace {
    var token = 0; var about = 0; var metadata = 0; var revoke = 0
}
struct GoogleDriveTokenEndpoint: Sendable {
    var trace: AcquisitionTrace?; var gate: Gate?; var revokeGate: Gate?
    func exchange(code: String, pkceVerifier: String, configuration: GoogleDriveConfiguration) async throws -> GoogleDriveTokenCredential {
        if let trace { await MainActor.run { trace.token += 1 } }
        if let gate { await gate.pause() }
        return GoogleDriveTokenCredential()
    }
    func refresh(refreshToken: String, configuration: GoogleDriveConfiguration) async throws -> GoogleDriveTokenCredential { GoogleDriveTokenCredential() }
    func revoke(token: String) async throws {
        if let trace { await MainActor.run { trace.revoke += 1 } }
        if let revokeGate { await revokeGate.pause() }
    }
}
protocol GoogleDriveAPIClientProtocol: Sendable {
    func about(accessToken: String) async throws -> String
    func metadata(id: String, resourceKey: String?, accessToken: String) async throws -> GoogleDriveFileMetadata
    func validateFolder(_ destination: GoogleDriveDestination, accessToken: String) async throws -> GoogleDriveFileMetadata
}
struct GoogleDriveAPIClient: GoogleDriveAPIClientProtocol {
    func about(accessToken: String) async throws -> String { "synthetic-permission" }
    func metadata(id: String, resourceKey: String?, accessToken: String) async throws -> GoogleDriveFileMetadata { GoogleDriveFileMetadata() }
    func validateFolder(_ destination: GoogleDriveDestination, accessToken: String) async throws -> GoogleDriveFileMetadata { GoogleDriveFileMetadata() }
}
protocol KeychainStoring: Sendable { func readStringOrThrow(key: String) throws -> String?; func writeStringOrThrow(key: String, value: String) throws; func removeOrThrow(key: String) throws }
struct SystemKeychainStore: KeychainStoring { func readStringOrThrow(key: String) throws -> String? { nil }; func writeStringOrThrow(key: String, value: String) throws {}; func removeOrThrow(key: String) throws {} }
final class CountingKeychain: KeychainStoring, @unchecked Sendable {
    var writes = 0; var removals = 0; var values: [String: String] = [:]
    func readStringOrThrow(key: String) throws -> String? { values[key] }
    func writeStringOrThrow(key: String, value: String) throws { writes += 1; values[key] = value }
    func removeOrThrow(key: String) throws { removals += 1; values.removeValue(forKey: key) }
}
actor GoogleDriveJournalStore { init() throws {}; func cleanupForDisconnect(destinationID: UUID) async throws {} }
@MainActor struct GoogleDriveManagedObjectStore {
    static var removalCount = 0
    func removeAll(destinationID: UUID) throws { Self.removalCount += 1 }
}
final class CountingDefaults: UserDefaults, @unchecked Sendable {
    var destinationWrites = 0
    override func set(_ value: Any?, forKey key: String) { if key == "googleDrive.destinations.envelope" { destinationWrites += 1 }; super.set(value, forKey: key) }
}
actor Gate {
    var paused = false; var continuation: CheckedContinuation<Void, Never>?
    func pause() async { await withCheckedContinuation { continuation = $0; paused = true } }
    func resume() { continuation?.resume(); continuation = nil }
}
@MainActor final class DelayedAuthorizer: GoogleDriveWebAuthorizing {
    let gate: Gate?; var calls = 0
    init(gate: Gate?) { self.gate = gate }
    func authorize(_ request: GoogleDriveAuthorizationRequest) async throws -> URL { calls += 1; if let gate { await gate.pause() }; return URL(string: "https://synthetic.invalid")! }
}
struct DelayedAPI: GoogleDriveAPIClientProtocol {
    let trace: AcquisitionTrace; let aboutGate: Gate?; let metadataGate: Gate?
    func about(accessToken: String) async throws -> String {
        await MainActor.run { trace.about += 1 }
        if let aboutGate { await aboutGate.pause() }
        return "synthetic-permission"
    }
    func metadata(id: String, resourceKey: String?, accessToken: String) async throws -> GoogleDriveFileMetadata {
        await MainActor.run { trace.metadata += 1 }
        if let metadataGate { await metadataGate.pause() }
        return GoogleDriveFileMetadata()
    }
    func validateFolder(_ destination: GoogleDriveDestination, accessToken: String) async throws -> GoogleDriveFileMetadata { GoogleDriveFileMetadata() }
}
'''
COORDINATOR_STUBS = r'''
struct Profile: Equatable { var id = UUID(); var googleDriveDestinationID: UUID? }
struct Entry: Equatable { var profileID: UUID; var isEnabled = true }
@MainActor final class ProfileStore {
    var profiles: [Profile] = []; var writes = 0; var activeProfileID: UUID?
    func setGoogleDriveBinding(profileID: UUID, destinationID: UUID?) -> Bool {
        writes += 1
        guard let index = profiles.firstIndex(where: { $0.id == profileID }) else { return false }
        profiles[index].googleDriveDestinationID = destinationID
        return true
    }
}
@MainActor final class EntryStore {
    var entries: [Entry] = []; var writes = 0
    func update(profileID: UUID, change: (inout Entry) -> Void) -> Bool {
        writes += 1
        guard let index = entries.firstIndex(where: { $0.profileID == profileID }) else { return false }
        change(&entries[index]); return true
    }
}
@MainActor final class ExportProfileCoordinator {
    let googleDriveDestinationStore: GoogleDriveDestinationStore
    let profileStore = ProfileStore(); let scheduledEntryStore = EntryStore()
    init(store: GoogleDriveDestinationStore) { googleDriveDestinationStore = store }
'''
CHECKS = r'''
@main struct Checks {
    @MainActor static func main() async throws {
        for cancel in [false, true] {
        for stage in 0...3 {
            for existingBinding in [false, true] {
                let suite = "Synthetic.DriveProtection.\(UUID())"
                let defaults = CountingDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                let keychain = CountingKeychain()
                let credentials = GoogleDriveCredentialStore(keychain: keychain)
                let store = GoogleDriveDestinationStore(userDefaults: defaults)
                var existingID: UUID?
                if existingBinding {
                    let destination = GoogleDriveDestination(id: UUID(), credentialReferenceID: UUID(), accountPermissionID: "synthetic-permission", folderID: "synthetic-folder", sharedDriveID: nil, resourceKey: nil, accountLabel: nil, folderLabel: nil, canAddChildren: true, lastValidatedAt: Date())
                    store.upsert(destination)
                    try credentials.save(GoogleDriveTokenCredential(), referenceID: destination.credentialReferenceID)
                    existingID = destination.id
                }
                keychain.writes = 0; defaults.destinationWrites = 0
                let gate = Gate()
                let trace = AcquisitionTrace()
                let authorizer = DelayedAuthorizer(gate: stage == 0 ? gate : nil)
                let manager = GoogleDriveConnectionManager(
                    destinationStore: store, credentialStore: credentials,
                    tokenEndpoint: GoogleDriveTokenEndpoint(trace: trace, gate: stage == 1 ? gate : nil),
                    api: DelayedAPI(trace: trace, aboutGate: stage == 2 ? gate : nil, metadataGate: stage == 3 ? gate : nil),
                    authorizer: authorizer
                )
                var protected = false
                var selectionWrites = 0
                let task = Task { @MainActor in
                    do {
                        _ = try await manager.connect(replacing: existingID, commitAllowed: { !protected })
                        selectionWrites += 1
                        return false
                    } catch is CancellationError { return true }
                    catch { fatalError("Unexpected acquisition failure: \(error)") }
                }
                while !(await gate.paused) { await Task.yield() }
                if cancel { task.cancel() } else { protected = true }
                let before = defaults.dictionaryRepresentation() as NSDictionary
                let credentialBefore = keychain.values
                await gate.resume()
                let rejected = await task.value
                precondition(trace.token == (stage >= 1 ? 1 : 0), "OAuth denial must stop token exchange")
                precondition(trace.about == (stage >= 2 ? 1 : 0), "Token denial must stop about.get")
                precondition(trace.metadata == (stage >= 3 ? 1 : 0), "About denial must stop folder metadata")
                precondition(rejected && keychain.writes == 0 && defaults.destinationWrites == 0 && selectionWrites == 0)
                precondition(defaults.dictionaryRepresentation() as NSDictionary == before && keychain.values == credentialBefore)
                precondition(store.destinations.count == (existingBinding ? 1 : 0))
            }
        }
        }
        try await disconnectChecks()
        let authorizer = DelayedAuthorizer(gate: nil)
        let manager = GoogleDriveConnectionManager(authorizer: authorizer)
        do { _ = try await manager.connect(commitAllowed: { false }); fatalError("Protected consent admitted") } catch is CancellationError {}
        precondition(authorizer.calls == 0)
        let suite = "Synthetic.DriveAllowed.\(UUID())"
        let defaults = CountingDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let keychain = CountingKeychain()
        let store = GoogleDriveDestinationStore(userDefaults: defaults)
        let allowed = GoogleDriveConnectionManager(destinationStore: store, credentialStore: GoogleDriveCredentialStore(keychain: keychain), authorizer: authorizer)
        _ = try await allowed.connect(commitAllowed: { true })
        precondition(keychain.writes == 1 && defaults.destinationWrites == 1 && store.destinations.count == 1)
        print("PASS: production acquisition and disconnect boundaries reject live protection/cancellation; subsequent acquisition calls and denied local commits are zero; unlocked connect/disconnect succeed")
    }

    @MainActor static func disconnectChecks() async throws {
        let key = ConfigurationProtectionManager.storageKey
        let previous = UserDefaults.standard.object(forKey: key)
        defer { if let previous { UserDefaults.standard.set(previous, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) } }
        // Entry/pre-task-lock, journal cleanup and delayed revocation, including cancellation.
        // Run both injected live admission and the actual default persisted preference.
        for persisted in [false, true] {
        for stage in 0...2 {
            for cancel in [false, true] {
                let suite = "Synthetic.DriveDisconnect.\(UUID())"
                let defaults = CountingDefaults(suiteName: suite)!
                defer { defaults.removePersistentDomain(forName: suite) }
                let keychain = CountingKeychain()
                let credentials = GoogleDriveCredentialStore(keychain: keychain)
                let store = GoogleDriveDestinationStore(userDefaults: defaults)
                let destination = GoogleDriveDestination(id: UUID(), credentialReferenceID: UUID(), accountPermissionID: "synthetic-permission", folderID: "synthetic-folder", sharedDriveID: nil, resourceKey: nil, accountLabel: nil, folderLabel: nil, canAddChildren: true, lastValidatedAt: Date())
                store.upsert(destination)
                try credentials.save(GoogleDriveTokenCredential(), referenceID: destination.credentialReferenceID)
                let coordinator = ExportProfileCoordinator(store: store)
                let profile = Profile(googleDriveDestinationID: destination.id)
                coordinator.profileStore.profiles = [profile, Profile(googleDriveDestinationID: destination.id)]
                coordinator.profileStore.activeProfileID = profile.id
                coordinator.scheduledEntryStore.entries = coordinator.profileStore.profiles.map { Entry(profileID: $0.id) }
                let profilesBefore = coordinator.profileStore.profiles
                let entriesBefore = coordinator.scheduledEntryStore.entries
                let trace = AcquisitionTrace(); let gate = Gate()
                var cleanupCalls = 0
                let manager = GoogleDriveConnectionManager(
                    destinationStore: store, credentialStore: credentials,
                    tokenEndpoint: GoogleDriveTokenEndpoint(trace: trace, revokeGate: stage == 2 ? gate : nil),
                    cleanupForDisconnect: { _ in
                        await MainActor.run { cleanupCalls += 1 }
                        if stage == 1 { await gate.pause() }
                    }
                )
                var selection: UUID? = destination.id
                var protected = stage == 0 && !cancel
                UserDefaults.standard.set(protected, forKey: key)
                keychain.writes = 0; defaults.destinationWrites = 0
                GoogleDriveManagedObjectStore.removalCount = 0
                let credentialBefore = keychain.values
                let before = defaults.dictionaryRepresentation() as NSDictionary
                let task = Task { @MainActor in
                    do {
                        if persisted {
                            try await coordinator.disconnectGoogleDrive(destinationID: destination.id, manager: manager)
                        } else {
                            try await coordinator.disconnectGoogleDrive(destinationID: destination.id, manager: manager, commitAllowed: { !protected })
                        }
                        try Task.checkCancellation()
                        if !protected { selection = nil }
                        return false
                    } catch is CancellationError { return true }
                    catch { fatalError("Unexpected disconnect failure: \(error)") }
                }
                if stage == 0 {
                    if cancel { task.cancel() }
                } else {
                    while !(await gate.paused) { await Task.yield() }
                    if cancel { task.cancel() } else {
                        protected = true
                        UserDefaults.standard.set(true, forKey: key)
                    }
                    await gate.resume()
                }
                let rejected = await task.value
                precondition(rejected && trace.revoke == (stage == 2 ? 1 : 0))
                precondition(cleanupCalls == (stage == 0 ? 0 : 1))
                precondition(keychain.values == credentialBefore && keychain.removals == 0 && keychain.writes == 0)
                precondition(GoogleDriveManagedObjectStore.removalCount == 0)
                precondition(defaults.destinationWrites == 0 && defaults.dictionaryRepresentation() as NSDictionary == before)
                precondition(store.destination(id: destination.id) != nil && selection == destination.id)
                precondition(coordinator.profileStore.profiles == profilesBefore && coordinator.profileStore.writes == 0)
                precondition(coordinator.profileStore.activeProfileID == profile.id)
                precondition(coordinator.scheduledEntryStore.entries == entriesBefore && coordinator.scheduledEntryStore.writes == 0)
            }
        }
        }
        // Exercise the actual default persisted preference for initial connect as well.
        UserDefaults.standard.set(true, forKey: key)
        let authorizer = DelayedAuthorizer(gate: nil)
        let manager = GoogleDriveConnectionManager(authorizer: authorizer)
        do { _ = try await manager.connect(); fatalError("Default protected connect admitted") } catch is CancellationError {}
        do { try await manager.disconnect(destinationID: UUID()); fatalError("Default protected disconnect admitted") } catch is CancellationError {}
        precondition(authorizer.calls == 0)

        // A separate admission protects the coordinator commit after the manager's await.
        // Authority already removed cannot be restored here: do not claim cross-store atomicity.
        UserDefaults.standard.set(false, forKey: key)
        let suite = "Synthetic.DriveDetach.\(UUID())"
        let defaults = CountingDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = GoogleDriveDestinationStore(userDefaults: defaults)
        let keychain = CountingKeychain(); let credentials = GoogleDriveCredentialStore(keychain: keychain)
        let destination = GoogleDriveDestination(id: UUID(), credentialReferenceID: UUID(), accountPermissionID: "synthetic-permission", folderID: "synthetic-folder", sharedDriveID: nil, resourceKey: nil, accountLabel: nil, folderLabel: nil, canAddChildren: true, lastValidatedAt: Date())
        store.upsert(destination)
        try credentials.save(GoogleDriveTokenCredential(), referenceID: destination.credentialReferenceID)
        let coordinator = ExportProfileCoordinator(store: store)
        let profile = Profile(googleDriveDestinationID: destination.id)
        coordinator.profileStore.profiles = [profile]
        coordinator.scheduledEntryStore.entries = [Entry(profileID: profile.id)]
        let connection = GoogleDriveConnectionManager(destinationStore: store, credentialStore: credentials)
        var admissions = 0
        do {
            try await coordinator.disconnectGoogleDrive(destinationID: destination.id, manager: connection, commitAllowed: { admissions += 1; return admissions < 5 })
            fatalError("Coordinator post-await denial admitted")
        } catch is CancellationError {}
        precondition(store.destinations.isEmpty && keychain.values.isEmpty)
        precondition(coordinator.profileStore.profiles == [profile] && coordinator.profileStore.writes == 0)
        precondition(coordinator.scheduledEntryStore.entries == [Entry(profileID: profile.id)] && coordinator.scheduledEntryStore.writes == 0)
        store.upsert(destination)
        try credentials.save(GoogleDriveTokenCredential(), referenceID: destination.credentialReferenceID)
        try await coordinator.disconnectGoogleDrive(destinationID: destination.id, manager: connection)
        precondition(store.destinations.isEmpty && keychain.values.isEmpty)
        precondition(coordinator.profileStore.profiles[0].googleDriveDestinationID == nil)
        precondition(!coordinator.scheduledEntryStore.entries[0].isEnabled)
    }
}
'''


class DriveConnectionProtectionTests(unittest.TestCase):
    def test_production_connection_and_stores_with_synthetic_acquisition(self):
        production = (APPLE / "HealthMd/Shared/GoogleDrive/GoogleDriveDestinationStore.swift").read_text()
        production = production.replace("import Combine\n", "")
        coordinator = (APPLE / "HealthMd/Shared/Managers/ExportProfileCoordinator.swift").read_text()
        # Compile the exact production disconnect method with synthetic profile/schedule stores.
        method = coordinator[coordinator.index("    func disconnectGoogleDrive("):coordinator.index("    // MARK: - Profile management")]
        with tempfile.TemporaryDirectory(prefix=".drive-protection-test-", dir=APPLE) as temp:
            source = Path(temp) / "Checks.swift"
            source.write_text(STUBS + production + COORDINATOR_STUBS + method + "}\n" + CHECKS)
            binary = Path(temp) / "checks"
            subprocess.run(["swiftc", "-parse-as-library", "-swift-version", "6", str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
