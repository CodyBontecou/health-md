import Foundation
import HealthMdConnectionCore
import XCTest
@testable import HealthMd

@MainActor
final class AppleDirectJobStorageTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings observation teardown is unsafe
    // on older runtimes. Follow the existing policy in docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testNamespaceUsesCompleteFrozenAuthorityAndDiscoveryCreatesNothing() async throws {
        let storage = try fixture()
        XCTAssertNil(try storage.existingNamespace(jobID: UUID()))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: storage.support.path), [])
        let historical = try await snapshot(.nightBegins)
        XCTAssertEqual(try storage.namespace(for: historical), .historical)
        var wake = try await snapshot(.morningEnds)
        XCTAssertEqual(try storage.namespace(for: wake), .wakeDate)
        wake.appleExportEnginePin = nil
        XCTAssertThrowsError(try storage.namespace(for: wake))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: storage.support.path), [])
    }

    func testHistoricalCleanupAndWholeHistoricalTreeRemovalPreserveSuccessor() async throws {
        let storage = try fixture()
        let wake = try await snapshot(.morningEnds)
        let old = try await snapshot(.nightBegins)
        let wakeID = UUID(), oldID = UUID()
        let admission = try storage.beginAdmission()
        let wakeDirectory = try storage.prepareDirectory(jobID: wakeID, kind: .files, snapshot: wake).1
        let oldDirectory = try storage.prepareDirectory(jobID: oldID, kind: .raw, snapshot: old).1
        let retained = Data("synthetic successor checkpoint".utf8)
        try retained.write(to: wakeDirectory.appendingPathComponent("journal.json"))
        try Data("{\"request\":{\"createdAt\":\"2000-01-01T00:00:00Z\"}}".utf8)
            .write(to: oldDirectory.appendingPathComponent("journal.json"))
        admission.close()
        let removed = try AppleExportJournalRecovery.cleanupExpiredDirectJobs(at: storage.root(.historical),
            lockURL: storage.lock(.historical), durabilityRoot: storage.support,
            now: Date(timeIntervalSince1970: 1_800_000_000), lifetime: 100)
        XCTAssertEqual(removed, [oldID])
        try FileManager.default.removeItem(at: storage.root(.historical).deletingLastPathComponent())
        XCTAssertEqual(try Data(contentsOf: wakeDirectory.appendingPathComponent("journal.json")), retained)
        XCTAssertEqual(try storage.existingNamespace(jobID: wakeID), .wakeDate)
        XCTAssertTrue(FileManager.default.fileExists(atPath:
            storage.support.appendingPathComponent("Health.md/.direct-job-namespaces.lock").path))
    }

    func testConflictingNamespaceCannotAdmitOrRewriteAnotherJob() async throws {
        let storage = try fixture()
        let id = UUID()
        let wake = try await snapshot(.morningEnds)
        let old = try await snapshot(.nightBegins)
        let admission = try storage.beginAdmission()
        defer { admission.close() }
        let directory = try storage.prepareDirectory(jobID: id, kind: .raw, snapshot: wake).1
        let bytes = Data("synthetic accepted successor".utf8)
        try bytes.write(to: directory.appendingPathComponent("journal.json"))
        XCTAssertThrowsError(try storage.prepareDirectory(jobID: id, kind: .files, snapshot: old))
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.root(.historical).path))
        let duplicate = storage.job(id, namespace: .historical, kind: .raw)
        try FileManager.default.createDirectory(at: duplicate, withIntermediateDirectories: true)
        try Data("synthetic duplicate".utf8).write(to: duplicate.appendingPathComponent("journal.json"))
        XCTAssertThrowsError(try storage.existingNamespace(jobID: id))
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("journal.json")), bytes)
        XCTAssertEqual(try String(contentsOf: duplicate.appendingPathComponent("journal.json"), encoding: .utf8), "synthetic duplicate")
    }

    func testBoundReceiptCannotRedirectToOtherNamespaceAfterRemoval() async throws {
        let storage = try fixture()
        let id = UUID()
        let wake = try await snapshot(.morningEnds)
        let admission = try storage.beginAdmission()
        let directory = try storage.prepareDirectory(jobID: id, kind: .files, snapshot: wake).1
        var checkpoint = AppleExportJournalCheckpoint()
        let bytes = Data("synthetic bound successor".utf8)
        try checkpoint.publish(bytes, to: directory.appendingPathComponent("journal.json"), freshAdmission: true,
            lockURL: storage.lock(.wakeDate), durabilityRoot: storage.support)
        admission.close()
        XCTAssertEqual(try storage.boundDirectory(jobID: id, kind: .files, snapshot: wake, checkpoint: checkpoint).1, directory)
        try FileManager.default.removeItem(at: storage.job(id, namespace: .wakeDate, kind: .raw))
        let replacement = storage.job(id, namespace: .historical, kind: .files)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try bytes.write(to: replacement.appendingPathComponent("journal.json"))
        XCTAssertThrowsError(try storage.boundDirectory(jobID: id, kind: .files, snapshot: wake, checkpoint: checkpoint))
        XCTAssertEqual(try Data(contentsOf: replacement.appendingPathComponent("journal.json")), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testMixedRawAndFileJobsExpireOnlyAfterEveryJournalIsValidatedAndExpired() async throws {
        let storage = try fixture()
        let wake = try await snapshot(.morningEnds)
        let id = UUID()
        let admission = try storage.beginAdmission()
        var checkpoints: [AppleExportJournalCheckpoint] = []
        for kind in [AppleDirectJobKind.raw, .files] {
            let directory = try storage.prepareDirectory(jobID: id, kind: kind, snapshot: wake).1
            var checkpoint = AppleExportJournalCheckpoint()
            try checkpoint.publish(Data("synthetic mixed job".utf8), to: directory.appendingPathComponent("journal.json"),
                freshAdmission: true, lockURL: storage.lock(.wakeDate), durabilityRoot: storage.support)
            checkpoints.append(checkpoint)
        }
        admission.close()
        var examined: [AppleDirectJobKind] = []
        let kept = try storage.cleanupExpiredWakeDateJobs(now: Date(timeIntervalSince1970: 200), lifetime: 100,
            validatedCreationDate: { _, candidateID, kind in
                XCTAssertEqual(candidateID, id)
                examined.append(kind)
                return Date(timeIntervalSince1970: kind == .files ? 200 : 0)
            })
        XCTAssertTrue(kept.isEmpty)
        XCTAssertEqual(examined, [.raw, .files])
        for checkpoint in checkpoints { try checkpoint.validateGeneration() }
        let rejected = try storage.cleanupExpiredWakeDateJobs(now: Date(timeIntervalSince1970: 200), lifetime: 100,
            validatedCreationDate: { _, _, kind in
                if kind == .files { throw POSIXError(.EAGAIN) }
                return Date(timeIntervalSince1970: 0)
            })
        XCTAssertTrue(rejected.isEmpty)
        for checkpoint in checkpoints { try checkpoint.validateGeneration() }
        let removed = try storage.cleanupExpiredWakeDateJobs(now: Date(timeIntervalSince1970: 200), lifetime: 100,
            validatedCreationDate: { _, _, _ in Date(timeIntervalSince1970: 0) })
        XCTAssertEqual(removed, [id])
        for checkpoint in checkpoints { XCTAssertThrowsError(try checkpoint.validateGeneration()) }
    }

    func testExpiryRequiresDirectoryDurabilityBeforeValidationAndAfterRemoval() async throws {
        let storage = try fixture()
        let wake = try await snapshot(.morningEnds)
        let id = UUID()
        let admission = try storage.beginAdmission()
        let directory = try storage.prepareDirectory(jobID: id, kind: .raw, snapshot: wake).1
        var checkpoint = AppleExportJournalCheckpoint()
        try checkpoint.publish(Data("synthetic owned expiry".utf8), to: directory.appendingPathComponent("journal.json"),
            freshAdmission: true, lockURL: storage.lock(.wakeDate), durabilityRoot: storage.support)
        admission.close()
        var validated = 0
        XCTAssertThrowsError(try storage.cleanupExpiredWakeDateJobs(now: Date(timeIntervalSince1970: 200), lifetime: 100,
            directorySync: { _ in throw POSIXError(.EIO) }, validatedCreationDate: { _, _, _ in
                validated += 1
                return Date(timeIntervalSince1970: 0)
            }))
        XCTAssertEqual(validated, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path))
        var rootSyncs = 0
        XCTAssertThrowsError(try storage.cleanupExpiredWakeDateJobs(now: Date(timeIntervalSince1970: 200), lifetime: 100,
            directorySync: { url in
                if url == storage.root(.wakeDate) {
                    rootSyncs += 1
                    if rootSyncs == 2 { throw POSIXError(.EIO) }
                }
                try AtomicFileWriter.synchronizeDirectory(url)
            }, validatedCreationDate: { _, _, _ in
                validated += 1
                return Date(timeIntervalSince1970: 0)
            }))
        XCTAssertEqual(validated, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        var retryRootSyncs = 0
        let removed = try storage.cleanupExpiredWakeDateJobs(now: Date(timeIntervalSince1970: 200), lifetime: 100,
            directorySync: { url in
                if url == storage.root(.wakeDate) { retryRootSyncs += 1 }
                try AtomicFileWriter.synchronizeDirectory(url)
            }, validatedCreationDate: { _, _, _ in
                XCTFail("An ambiguous removal must not be recreated for validation")
                return Date(timeIntervalSince1970: 0)
            })
        XCTAssertTrue(removed.isEmpty)
        XCTAssertEqual(retryRootSyncs, 1)
        XCTAssertThrowsError(try checkpoint.validateGeneration())
    }

    #if os(iOS)
    func testActualRawAndFileCancellationFindSuccessorWithoutCreatingHistoricalStorage() async throws {
        for files in [false, true] {
            let storage = try fixture()
            let id = UUID()
            let bytes = try await cancellationJournal(jobID: id, files: files)
            let directory = storage.job(id, namespace: .wakeDate, kind: files ? .files : .raw)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent("journal.json")
            try bytes.write(to: url)
            let manager = NamespaceSupportFileManager(support: storage.support)
            let producer = IPhoneDirectFileExportProducer(fileManager: manager)
            let coordinator = IPhoneDirectExportCoordinator(fileManager: manager, fileProducer: producer)
            let receipt = try XCTUnwrap(coordinator.cancelWithReceipt(jobID: id,
                protocolAuthority: AppleDirectProtocolAuthority(defaultMode: .legacy)))
            let ownership = try XCTUnwrap(receipt.durableOwnership)
            try ownership.validateGeneration()
            XCTAssertEqual(ownership.journalURL, url)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            XCTAssertEqual(object["state"] as? String, "cancelled")
            XCTAssertFalse(FileManager.default.fileExists(atPath: storage.root(.historical).deletingLastPathComponent().path))
        }
    }

    func testActualCancellationRetainsWrongNamespaceAndDuplicateJobsWithoutMigration() async throws {
        for files in [false, true] {
            for duplicate in [false, true] {
                let storage = try fixture()
                let id = UUID()
                let bytes = try await cancellationJournal(jobID: id, files: files)
                var directories = [storage.job(id, namespace: .historical, kind: files ? .files : .raw)]
                if duplicate { directories.append(storage.job(id, namespace: .wakeDate, kind: files ? .files : .raw)) }
                for directory in directories {
                    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                    try bytes.write(to: directory.appendingPathComponent("journal.json"))
                }
                let manager = NamespaceSupportFileManager(support: storage.support)
                let producer = IPhoneDirectFileExportProducer(fileManager: manager)
                let coordinator = IPhoneDirectExportCoordinator(fileManager: manager, fileProducer: producer)
                XCTAssertNil(coordinator.cancelWithReceipt(jobID: id,
                    protocolAuthority: AppleDirectProtocolAuthority(defaultMode: .legacy)))
                for directory in directories {
                    XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("journal.json")), bytes)
                    XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["journal.json"],
                        "Reject namespace authority before creating a generation marker")
                }
            }
        }
    }

    func testActualFileRecoveryRejectsConflictingRendererPinWithoutMigration() async throws {
        let storage = try fixture()
        let id = UUID()
        let encoded = try await cancellationJournal(jobID: id, files: true)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let historical = try IPhoneDirectFileJournalTests.makeJournal(jobID: id)
        let encoder = JSONEncoder()
        object["appleExportEnginePin"] = try JSONSerialization.jsonObject(with:
            encoder.encode(try XCTUnwrap(historical.appleExportEnginePin)))
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        let directory = storage.job(id, namespace: .wakeDate, kind: .files)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("journal.json")
        try bytes.write(to: url)
        let producer = IPhoneDirectFileExportProducer(fileManager: NamespaceSupportFileManager(support: storage.support))
        XCTAssertThrowsError(try producer.cancel(jobID: id))
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["journal.json"])
    }

    func testActualExpiryRemovesOnlyCompleteExpiredSuccessorJobs() async throws {
        for files in [false, true] {
            let storage = try fixture()
            let id = UUID()
            let bytes = try await cancellationJournal(jobID: id, files: files)
            let directory = storage.job(id, namespace: .wakeDate, kind: files ? .files : .raw)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var checkpoint = AppleExportJournalCheckpoint()
            try checkpoint.publish(bytes, to: directory.appendingPathComponent("journal.json"), freshAdmission: true,
                lockURL: storage.lock(.wakeDate), durabilityRoot: storage.support)
            let manager = NamespaceSupportFileManager(support: storage.support)
            let producer = IPhoneDirectFileExportProducer(fileManager: manager)
            let coordinator = IPhoneDirectExportCoordinator(fileManager: manager, fileProducer: producer)
            coordinator.cleanupExpiredJobs(now: Date(timeIntervalSince1970: 1_800_000_000 + HealthMdDirectProtocol.jobLifetime + 1))
            XCTAssertFalse(FileManager.default.fileExists(atPath: storage.job(id, namespace: .wakeDate, kind: .raw).path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: storage.root(.historical).path))
            XCTAssertThrowsError(try checkpoint.validateGeneration())
        }
    }

    func testActualSuccessorExpiryRetainsUnknownIncompleteAndAmbiguousJobs() async throws {
        for files in [false, true] {
            for invalid in ["missing-owner", "bad-owner", "version", "missing-history", "rebound-history", "pre-successor", "identity", "clock", "capture", "renderer", "protocol", "fingerprint", "transfer", "missing-journal", "corrupt", "symlink", "duplicate", "unexpired"] {
                let storage = try fixture()
                let id = UUID()
                let encoded = try await cancellationJournal(jobID: id, files: files)
                var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
                if invalid == "version" { object["version"] = 999 }
                if invalid == "missing-history" {
                    object["version"] = files ? IPhoneDirectFileJournal.historyObservationVersion : 4
                }
                if invalid == "rebound-history" {
                    object["version"] = files ? IPhoneDirectFileJournal.historyObservationVersion : 4
                    var accepted = try XCTUnwrap(object["accepted"] as? [String: Any])
                    let observation = try XCTUnwrap(makeObservedContextTestFixture().manifest.historyObservation)
                    accepted["historyObservation"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(observation))
                    object["accepted"] = accepted
                }
                if invalid == "pre-successor" {
                    object["version"] = files ? IPhoneDirectFileJournal.immutableRangeRequestVersion : 2
                }
                if invalid == "identity" {
                    var accepted = try XCTUnwrap(object["accepted"] as? [String: Any])
                    accepted["jobID"] = UUID().uuidString
                    object["accepted"] = accepted
                }
                if invalid == "clock" {
                    var accepted = try XCTUnwrap(object["accepted"] as? [String: Any])
                    accepted["sourceTimeZoneIdentifier"] = "America/Los_Angeles"
                    object["accepted"] = accepted
                }
                if invalid == "capture" {
                    var snapshot = try XCTUnwrap(object["settingsSnapshot"] as? [String: Any])
                    snapshot["sleepCaptureContext"] = nil
                    object["settingsSnapshot"] = snapshot
                }
                if invalid == "renderer" {
                    var snapshot = try XCTUnwrap(object["settingsSnapshot"] as? [String: Any])
                    var pin = try XCTUnwrap(snapshot["appleExportEnginePin"] as? [String: Any])
                    pin[AppleExportEnginePin.CodingKeys.registrySHA256.rawValue] = String(repeating: "0", count: 64)
                    snapshot["appleExportEnginePin"] = pin
                    object["settingsSnapshot"] = snapshot
                }
                if invalid == "protocol" {
                    let base = try IPhoneDirectFileJournalTests.makeJournal(jobID: id)
                    var pin = try XCTUnwrap(JSONSerialization.jsonObject(with:
                        JSONEncoder().encode(try XCTUnwrap(base.appleDirectProtocolPin))) as? [String: Any])
                    pin["coreAPIVersion"] = 999
                    object["appleDirectProtocolPin"] = pin
                }
                if invalid == "fingerprint" || invalid == "transfer" {
                    var session = try XCTUnwrap(object["session"] as? [String: Any])
                    if invalid == "transfer" { session["protocolVersion"] = 999 }
                    else {
                        var fingerprint = try XCTUnwrap(session["requestFingerprint"] as? [String: Any])
                        fingerprint["sha256"] = String(repeating: "0", count: 64)
                        session["requestFingerprint"] = fingerprint
                    }
                    object["session"] = session
                }
                let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
                let directory = storage.job(id, namespace: .wakeDate, kind: files ? .files : .raw)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let url = directory.appendingPathComponent("journal.json")
                var checkpoint = AppleExportJournalCheckpoint()
                try checkpoint.publish(bytes, to: url, freshAdmission: true,
                    lockURL: storage.lock(.wakeDate), durabilityRoot: storage.support)
                let marker = directory.appendingPathComponent(".journal-generation")
                if invalid == "missing-owner" { try FileManager.default.removeItem(at: marker) }
                if invalid == "bad-owner" { try Data("unknown marker".utf8).write(to: marker) }
                if invalid == "missing-journal" { try FileManager.default.removeItem(at: url) }
                if invalid == "corrupt" { try Data("{".utf8).write(to: url) }
                if invalid == "symlink" {
                    let target = storage.support.appendingPathComponent("retained.json")
                    try bytes.write(to: target)
                    try FileManager.default.removeItem(at: url)
                    try FileManager.default.createSymbolicLink(at: url, withDestinationURL: target)
                }
                if invalid == "duplicate" {
                    let duplicate = storage.job(id, namespace: .historical, kind: .raw)
                    try FileManager.default.createDirectory(at: duplicate, withIntermediateDirectories: true)
                    // A current timestamp keeps historical cleanup from removing this separate job.
                    try Data("{\"request\":{\"createdAt\":\"2099-01-01T00:00:00Z\"}}".utf8)
                        .write(to: duplicate.appendingPathComponent("journal.json"))
                }
                let before = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
                let markerBytes = try? Data(contentsOf: marker)
                let journalBytes = try? Data(contentsOf: url)
                let journalType = try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType
                let manager = NamespaceSupportFileManager(support: storage.support)
                let coordinator = IPhoneDirectExportCoordinator(fileManager: manager,
                    fileProducer: IPhoneDirectFileExportProducer(fileManager: manager))
                let now = Date(timeIntervalSince1970: 1_800_000_000 + (invalid == "unexpired" ? 0 : HealthMdDirectProtocol.jobLifetime + 1))
                coordinator.cleanupExpiredJobs(now: now)
                XCTAssertEqual(try? Data(contentsOf: url), journalBytes, invalid)
                XCTAssertEqual(try? FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType, journalType, invalid)
                XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), before, invalid)
                XCTAssertEqual(try? Data(contentsOf: marker), markerBytes, invalid)
            }
        }
    }

    private func cancellationJournal(jobID: UUID, files: Bool) async throws -> Data {
        let model = try IPhoneDirectFileJournalTests.makeJournal(jobID: jobID)
        let wake = try await snapshot(.morningEnds)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(model)) as? [String: Any])
        object["settingsSnapshot"] = try JSONSerialization.jsonObject(with: encoder.encode(wake))
        object["appleExportEnginePin"] = try JSONSerialization.jsonObject(with: encoder.encode(try XCTUnwrap(wake.appleExportEnginePin)))
        object["appleDirectProtocolPin"] = nil
        object["state"] = "paused"
        var accepted = try XCTUnwrap(object["accepted"] as? [String: Any])
        accepted["sourceTimeZoneIdentifier"] = try XCTUnwrap(wake.sleepCaptureContext).calendarTimeZoneIdentifier
        object["accepted"] = accepted
        object["originalCalendarTimeZoneIdentifier"] = try XCTUnwrap(wake.sleepCaptureContext).calendarTimeZoneIdentifier
        if !files {
            let keys: Set<String> = ["settingsSnapshot", "accepted", "updatedAt", "state", "partitions",
                "committedPartitionCount", "committedBytes", "completionRecorded", "request", "session"]
            object = object.filter { keys.contains($0.key) }
            let request = DirectExportRequest(jobID: jobID, createdAt: model.request.createdAt,
                dateSelection: model.request.dateSelection, responseMode: .rawJSON,
                rawProfile: .healthDataProjection,
                canonicalSelection: DirectCanonicalSelection(metricIDs: ["sleep_total"]))
            let session = try DirectTransferSession(sessionID: model.session.sessionID, jobID: jobID,
                requestFingerprint: DirectRequestFingerprint.make(for: request), peerBinding: model.session.peerBinding,
                partitionTargetBytes: model.session.partitionTargetBytes, createdAt: model.session.createdAt)
            object["request"] = try JSONSerialization.jsonObject(with: encoder.encode(request))
            object["session"] = try JSONSerialization.jsonObject(with: encoder.encode(session))
            object["days"] = []
        }
        // This fixture has no history observation and retains its original successor grammar.
        object["version"] = files ? IPhoneDirectFileJournal.derivedOutputReconciliationVersion : 3
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
    #endif

    private func fixture() throws -> AppleDirectJobStorage {
        let candidate = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        let support = candidate.standardizedFileURL.resolvingSymlinksInPath()
        addTeardownBlock { try? FileManager.default.removeItem(at: support) }
        return AppleDirectJobStorage(support: support, fileManager: .default)
    }

    private func snapshot(_ attribution: SleepDayAttribution) async throws -> ExportSettingsSnapshot {
        let suite = "AppleDirectJobStorageTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.json]
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.summaryOnlyExport = false
        settings.includeGranularData = false
        settings.generateRangeSummary = false
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(
            timeZone: TimeZone(identifier: "America/New_York")!, sleepDayAttribution: attribution)
        settings.executionSleepCaptureContextIsFrozen = true
        let result = await ExportSettingsSnapshot.forNewAppleOperation(settings, healthSubfolder: "Health",
            surface: .localVaultWithoutSideEffects,
            policyResolver: AppleExportEnginePolicyResolver(injectedOverride: "legacy", userDefaults: nil, environment: [:]))
        if attribution == .morningEnds { XCTAssertTrue(try XCTUnwrap(result.appleExportEnginePin).isWakeDate) }
        return result
    }
}

#if os(iOS)
nonisolated private final class NamespaceSupportFileManager: FileManager, @unchecked Sendable {
    let support: URL
    init(support: URL) { self.support = support; super.init() }
    override func url(for directory: SearchPathDirectory, in domain: SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        guard directory == .applicationSupportDirectory else { throw CocoaError(.fileReadNoSuchFile) }
        return support
    }
}
#endif
