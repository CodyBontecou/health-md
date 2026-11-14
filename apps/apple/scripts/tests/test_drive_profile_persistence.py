#!/usr/bin/env python3
"""Cheap Foundation-only integration checks of the *production* persistence codec/transaction.

Native materialization/DTO collaborators are synthetic doubles. This is not an Xcode/native
unit-test receipt; the native XCTest suites remain the authority for full profile semantics.
Generated Swift and its executable stay in a temporary directory inside the Apple component.
"""
from pathlib import Path
import subprocess
import tempfile
import unittest

APPLE = Path(__file__).resolve().parents[2]

STUBS = r'''
import Foundation
struct ExportProfile: Codable, Equatable {
    var id: UUID
    var name: String
    var target: String = "googleDrive"
    var settings: [String: String] = [:]
}
struct ScheduledExportEntry: Codable, Equatable {
    var id: UUID
    var profileID: UUID
}
enum ScheduledExportEntryStore { static let maximumScheduledEntries = 100 }
struct SharedSetupV2 {
    static let maximumProfiles = 100
    struct AndroidExtension: Codable, Equatable, Sendable {}
    struct Destination: Codable, Equatable, Sendable { var kind: String }
    struct Profile: Codable, Equatable, Sendable {
        var bundleID: String
        var name: String
        var destination = Destination(kind: "cloud")
        var platformExtensions = Extensions()
        var schedule: String? = nil
        struct Extensions: Codable, Equatable, Sendable { var android: AndroidExtension? = nil }
    }
    var profiles: [Profile]
}
struct SharedSetupV2ImportPlan {
    var document: SharedSetupV2
    var activeBundleID: String
}
struct SharedSetupV2ProfileImportPlan {
    var bundleID: String
    var scheduleCanApplyExactly = false
    var unsupportedPreservedSemanticIDs: [String] = []
}
enum SharedSetupV2Validation {
    static func isIdentifier(_ value: String) -> Bool { !value.isEmpty }
    static func isNonEmptyShortString(_ value: String) -> Bool { !value.isEmpty && value.unicodeScalars.count <= 256 }
}
enum SharedSetupV2AppleProfileMaterializer {
    static func normalizedSelection(from plan: SharedSetupV2ImportPlan, selectedBundleIDs: [String]) throws -> [SharedSetupV2ProfileImportPlan] {
        plan.document.profiles.filter { selectedBundleIDs.contains($0.bundleID) }.map { .init(bundleID: $0.bundleID, scheduleCanApplyExactly: $0.schedule != nil) }
    }
    static func profile(source: SharedSetupV2.Profile, plan: SharedSetupV2ProfileImportPlan, nativeID: UUID, name: String, now: Date) -> ExportProfile {
        ExportProfile(id: nativeID, name: name, target: "unbound")
    }
    static func schedule(source: SharedSetupV2.Profile, plan: SharedSetupV2ProfileImportPlan, nativeProfileID: UUID, nativeScheduleID: UUID, calendar: Calendar) throws -> ScheduledExportEntry? {
        source.schedule == nil ? nil : ScheduledExportEntry(id: nativeScheduleID, profileID: nativeProfileID)
    }
}
final class RecordingDefaults: UserDefaults {
    var writes: [String] = []
    override func set(_ value: Any?, forKey key: String) { writes.append(key); super.set(value, forKey: key) }
    override func removeObject(forKey key: String) { writes.append(key); super.removeObject(forKey: key) }
}
'''

CHECKS = r'''
@MainActor
func runChecks() throws {
    let suite = "HealthMd.Synthetic.DrivePersistence.\(UUID().uuidString)"
    let defaults = RecordingDefaults(suiteName: suite)!
    defer { defaults.removePersistentDomain(forName: suite) }
    let legacy = ExportProfile(id: UUID(), name: "Legacy", target: "localIPhoneFolder")
    let drive = ExportProfile(id: UUID(), name: "Drive")
    let plan = SharedSetupV2ImportPlan(document: .init(profiles: [.init(bundleID: "profile-001", name: "Imported")]), activeBundleID: "profile-001")
    func transaction(_ verify: (() -> Bool)? = nil) -> SharedSetupV2ProfileTransaction {
        SharedSetupV2ProfileTransaction(userDefaults: defaults, verificationOverride: verify)
    }
    func snapshot() -> NSDictionary { defaults.dictionaryRepresentation() as NSDictionary }
    func assertNoWrites(_ body: () throws -> Void) throws {
        let before = snapshot()
        defaults.writes = []
        do { try body(); fatalError("expected rejection") } catch {}
        precondition(defaults.writes.isEmpty, "rejection wrote defaults: \(defaults.writes)")
        precondition(snapshot() == before, "rejection changed bytes")
    }
    func clear() { defaults.removePersistentDomain(forName: suite) }
    func seedLegacy() throws {
        defaults.set(try ExportProfilePersistence.encode([legacy], envelope: false), forKey: ExportProfilePersistence.legacyListKey)
        defaults.set(legacy.id.uuidString, forKey: ExportProfilePersistence.legacyActiveIDKey)
    }
    func seedEnvelope() throws {
        defaults.set(try ExportProfilePersistence.encode([drive], envelope: true), forKey: ExportProfilePersistence.envelopeKey)
    }

    // Authoritative envelope Add/Replace and exact Undo, including absent active key.
    try seedLegacy(); try seedEnvelope()
    defaults.set(Data("synthetic secure authority".utf8), forKey: "untouched.authority")
    for mode in [SharedSetupV2TransactionMode.add, .replace] {
        let before = snapshot()
        let tx = transaction()
        defaults.writes = []
        let result = try tx.apply(plan, selectedBundleIDs: ["profile-001"], mode: mode)
        precondition(!defaults.writes.contains(ExportProfilePersistence.legacyListKey))
        precondition(!defaults.writes.contains(ExportProfilePersistence.legacyActiveIDKey))
        precondition(!defaults.writes.contains("untouched.authority"))
        let records = try ExportProfilePersistence.transactionProfiles(defaults.data(forKey: ExportProfilePersistence.envelopeKey), envelope: true)
        precondition(records.count == (mode == .add ? 2 : 1))
        if mode == .add { precondition(records[0] == drive) }
        precondition(result.activeProfileID != legacy.id)
        _ = try tx.undo()
        precondition(snapshot() == before)
        try assertNoWrites { _ = try tx.undo() }
    }

    // Successful Add preserves actual noncanonical record slices, not merely DTOs.
    for envelope in [false, true] {
        clear()
        // Use a raw Swift string to make JSON escapes unambiguous.
        let escapedRecord = #"{ "id" : "ID", "name" : "slash \/ quote \" brackets ][ backslash \\" , "target" : "localIPhoneFolder", "settings" : {} }"#
            .replacingOccurrences(of: "ID", with: legacy.id.uuidString)
        let profileRaw = Data((envelope ? "{ \"records\" : [\n" + escapedRecord + "\n ], \"version\" : 2 }" : "[\n" + escapedRecord + "\n ]").utf8)
        let scheduleRecord = #"{ "id" : "SCHEDULE", "profileID" : "PROFILE" }"#
            .replacingOccurrences(of: "SCHEDULE", with: UUID().uuidString)
            .replacingOccurrences(of: "PROFILE", with: legacy.id.uuidString)
        let scheduleRaw = Data(("[\n" + scheduleRecord + "\n ]").utf8)
        let key = envelope ? ExportProfilePersistence.envelopeKey : ExportProfilePersistence.legacyListKey
        defaults.set(profileRaw, forKey: key)
        defaults.set(scheduleRaw, forKey: SharedSetupV2ProfileTransaction.scheduledEntriesKey)
        let before = snapshot()
        let tx = transaction()
        var scheduledPlan = plan
        scheduledPlan.document.profiles[0].schedule = "synthetic inert schedule"
        _ = try tx.apply(scheduledPlan, selectedBundleIDs: ["profile-001"], mode: .add)
        precondition(defaults.data(forKey: key)!.range(of: Data(escapedRecord.utf8)) != nil)
        let addedScheduleBytes = defaults.data(forKey: SharedSetupV2ProfileTransaction.scheduledEntriesKey)!
        precondition(addedScheduleBytes.range(of: Data(scheduleRecord.utf8)) != nil)
        let addedSchedules = try JSONDecoder().decode([ScheduledExportEntry].self, from: addedScheduleBytes)
        precondition(addedSchedules.count == 2)
        _ = try tx.undo()
        precondition(snapshot() == before)
    }
    // Scanner preserves numeric spelling and escaped container/key delimiters.
    let numeric = Data(#"{ "ver\u0073ion":2, "rec\u006frds":[ { "number": 1.000e+3, "text":"[\"}]\\\/" } ] }"#.utf8)
    let numericAdded = try ExportProfilePersistence.appending([legacy], to: numeric, envelope: true)
    precondition(numericAdded.range(of: Data(#"{ "number": 1.000e+3, "text":"[\"}]\\\/" }"#.utf8)) != nil)
    _ = try JSONSerialization.jsonObject(with: numericAdded)
    clear()
    let duplicateArrays = Data(("{\"version\":2,\"records\":[],\"rec\\u006frds\":" + String(decoding: try JSONEncoder().encode([drive]), as: UTF8.self) + "}").utf8)
    defaults.set(duplicateArrays, forKey: ExportProfilePersistence.envelopeKey)
    try assertNoWrites { _ = try transaction().apply(plan, selectedBundleIDs: ["profile-001"], mode: .add) }

    // Validated preservation rejects corruption instead of returning empty meaning.
    clear()
    let preservationTx = transaction()
    _ = try preservationTx.apply(plan, selectedBundleIDs: ["profile-001"], mode: .replace)
    let preservation = try preservationTx.preservationSnapshot()
    precondition(preservation.pendingDestinations.values.first!.kind == "cloud")
    let healthySidecar = defaults.data(forKey: SharedSetupV2ProfileTransaction.profileStateKey)!
    let healthyBlocked = defaults.data(forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey)!
    for key in [SharedSetupV2ProfileTransaction.profileStateKey, SharedSetupV2ProfileTransaction.blockedProfileIDsKey] {
        for corrupt: Any in [Data("corrupt".utf8), "wrong type", Data("{\"version\":99,\"profiles\":[]}".utf8)] {
            defaults.set(corrupt, forKey: key)
            try assertNoWrites { _ = try preservationTx.preservationSnapshot() }
            defaults.set(healthySidecar, forKey: SharedSetupV2ProfileTransaction.profileStateKey)
            defaults.set(healthyBlocked, forKey: SharedSetupV2ProfileTransaction.blockedProfileIDsKey)
        }
    }

    // Verified rollback restores every key, absence, and the previous Undo bytes.
    let previousUndo = Data("synthetic previous Undo".utf8)
    defaults.set(previousUndo, forKey: SharedSetupV2ProfileTransaction.undoKey)
    let beforeFailure = snapshot()
    do { _ = try transaction({ false }).apply(plan, selectedBundleIDs: ["profile-001"], mode: .add); fatalError("expected failure") } catch {}
    precondition(snapshot() == beforeFailure)
    defaults.removeObject(forKey: SharedSetupV2ProfileTransaction.undoKey)
    let tx = transaction()
    _ = try tx.apply(plan, selectedBundleIDs: ["profile-001"], mode: .replace)
    let applied = snapshot()
    do { _ = try transaction({ false }).undo(); fatalError("expected Undo failure") } catch {}
    precondition(snapshot() == applied && tx.canUndo)
    _ = try tx.undo()

    // Lazy migration after a legacy transaction must not mask its Undo.
    clear(); try seedLegacy()
    let priorLegacy = snapshot()
    let legacyTx = transaction()
    _ = try legacyTx.apply(plan, selectedBundleIDs: ["profile-001"], mode: .add)
    let importedLegacy = defaults.data(forKey: ExportProfilePersistence.legacyListKey)!
    let all = try ExportProfilePersistence.transactionProfiles(importedLegacy, envelope: false)
    defaults.set(try ExportProfilePersistence.encode(all, envelope: true), forKey: ExportProfilePersistence.envelopeKey)
    defaults.set(all[0].id.uuidString, forKey: ExportProfilePersistence.activeIDKey)
    _ = try legacyTx.undo()
    precondition(snapshot() == priorLegacy)
    precondition(!ExportProfilePersistence.hasEnvelope(in: defaults))

    // Historical local Undo v1 is safe and consumes once, without public v1 grammar.
    _ = try legacyTx.apply(plan, selectedBundleIDs: ["profile-001"], mode: .add)
    var old = try JSONSerialization.jsonObject(with: defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey)!) as! [String: Any]
    old["version"] = 1; old.removeValue(forKey: "profileEnvelope"); old.removeValue(forKey: "activeProfileIDV2")
    defaults.set(try JSONSerialization.data(withJSONObject: old), forKey: SharedSetupV2ProfileTransaction.undoKey)
    try seedEnvelope()
    precondition(legacyTx.canUndo)
    _ = try legacyTx.undo()
    precondition(snapshot() == priorLegacy)

    // Native tolerant decode retains opaque records; strict transactions never erase them.
    let known = try JSONSerialization.jsonObject(with: JSONEncoder().encode(drive))
    var future = known as! [String: Any]; future["futureAuthority"] = "synthetic"
    let mixed = try JSONSerialization.data(withJSONObject: ["version": 2, "records": [known, future]])
    let tolerant = ExportProfilePersistence.decode(mixed, envelope: true)!
    precondition(tolerant.profiles == [drive] && tolerant.opaque.count == 1)
    let resaved = try ExportProfilePersistence.encode(tolerant.profiles, opaque: tolerant.opaque, envelope: true)
    precondition(ExportProfilePersistence.decode(resaved, envelope: true)!.opaque == tolerant.opaque)
    let invalid: [Any] = [
        Data("corrupt".utf8), "wrong type", mixed,
        try JSONSerialization.data(withJSONObject: ["version": 99, "records": [known]]),
        Data(("{\"version\":2.0,\"records\":" + String(decoding: try JSONEncoder().encode([drive]), as: UTF8.self) + "}").utf8),
        try JSONSerialization.data(withJSONObject: ["version": true, "records": [known]]),
        try JSONSerialization.data(withJSONObject: ["version": 2, "records": [known, known]]),
        try JSONSerialization.data(withJSONObject: ["version": 2, "records": [known, "corrupt record"]])
    ]
    for value in invalid {
        clear(); try seedLegacy()
        let testTx = transaction()
        _ = try testTx.apply(plan, selectedBundleIDs: ["profile-001"], mode: .add)
        defaults.set(value, forKey: ExportProfilePersistence.envelopeKey)
        precondition(ExportProfilePersistence.hasEnvelope(in: defaults))
        for mode in [SharedSetupV2TransactionMode.add, .replace] {
            try assertNoWrites { _ = try testTx.apply(plan, selectedBundleIDs: ["profile-001"], mode: mode) }
        }
        try assertNoWrites { _ = try testTx.undo() }
    }
    clear(); try seedLegacy()
    let futureStateTx = transaction()
    _ = try futureStateTx.apply(plan, selectedBundleIDs: ["profile-001"], mode: .add)
    var sidecar = try JSONSerialization.jsonObject(with: defaults.data(forKey: SharedSetupV2ProfileTransaction.profileStateKey)!) as! [String: Any]
    sidecar["version"] = 99
    defaults.set(try JSONSerialization.data(withJSONObject: sidecar), forKey: SharedSetupV2ProfileTransaction.profileStateKey)
    try assertNoWrites { _ = try futureStateTx.apply(plan, selectedBundleIDs: ["profile-001"], mode: .replace) }
    try assertNoWrites { _ = try futureStateTx.undo() }
    sidecar["version"] = 1
    sidecar["futureField"] = "synthetic"
    defaults.set(try JSONSerialization.data(withJSONObject: sidecar), forKey: SharedSetupV2ProfileTransaction.profileStateKey)
    try assertNoWrites { _ = try futureStateTx.apply(plan, selectedBundleIDs: ["profile-001"], mode: .replace) }
    try assertNoWrites { _ = try futureStateTx.undo() }
    clear(); try seedLegacy()
    let futureUndoTx = transaction()
    _ = try futureUndoTx.apply(plan, selectedBundleIDs: ["profile-001"], mode: .add)
    var unknownUndo = try JSONSerialization.jsonObject(with: defaults.data(forKey: SharedSetupV2ProfileTransaction.undoKey)!) as! [String: Any]
    unknownUndo["futureField"] = "synthetic"
    defaults.set(try JSONSerialization.data(withJSONObject: unknownUndo), forKey: SharedSetupV2ProfileTransaction.undoKey)
    precondition(!futureUndoTx.canUndo)
    try assertNoWrites { _ = try futureUndoTx.undo() }
    print("PASS: production codec/transaction authority, raw-slice profile/schedule Add, numeric/escape scanning, validated retention, rollback, absence-exact Undo, lazy migration, old Undo, tolerant records and no-write rejection")
}
try runChecks()
'''


class DriveProfilePersistenceTests(unittest.TestCase):
    def test_production_codec_and_transaction_with_synthetic_collaborators(self):
        transaction = (APPLE / "HealthMd/Shared/SharedSetup/SharedSetupV2ProfileTransaction.swift").read_text()
        declarations = transaction.split("/// Pure selection and materialization helpers.")[0]
        implementation = transaction.split("@MainActor\nfinal class SharedSetupV2ProfileTransaction", 1)[1]
        implementation = "@MainActor\nfinal class SharedSetupV2ProfileTransaction" + implementation.split("\nprivate extension MarkdownTemplateConfig", 1)[0]
        codec = (APPLE / "HealthMd/Shared/Models/ExportProfilePersistence.swift").read_text()
        with tempfile.TemporaryDirectory(prefix=".drive-persistence-test-", dir=APPLE) as temp:
            source = Path(temp) / "main.swift"
            source.write_text(STUBS + declarations + codec + implementation + CHECKS)
            binary = Path(temp) / "checks"
            subprocess.run(["swiftc", "-swift-version", "6", str(source), "-o", str(binary)], check=True, timeout=60)
            subprocess.run([str(binary)], check=True, timeout=30)


if __name__ == "__main__":
    unittest.main()
