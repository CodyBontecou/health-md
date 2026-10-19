import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class ConnectedCorpusNamespaceTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: Combine observation teardown follows
    // the policy in docs/testing/lifecycle-audit.md on older native runtimes.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testMissingConnectedInspectionCreatesNoStorage() async throws {
        let base = try temporaryBase()
        let root = base.appendingPathComponent("ConnectedCorpusOutbound", isDirectory: true)
        let store = ConnectedCorpusOutboundStore(rootURL: root)
        XCTAssertNil(try store.load(jobID: UUID()))
        XCTAssertTrue(store.resumableJournals().isEmpty)
        XCTAssertTrue(store.cleanupExpired().isEmpty)
        XCTAssertEqual(store.totalInternalSpoolBytes(jobID: UUID()), 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: base.path), [])
    }

    func testSuccessorUsesSiblingAndSurvivesHistoricalTreeRemoval() async throws {
        let base = try temporaryBase()
        let root = base.appendingPathComponent("ConnectedCorpusOutbound", isDirectory: true)
        let successor = base.appendingPathComponent("ConnectedCorpusOutboundSleepAttribution", isDirectory: true)
        let store = ConnectedCorpusOutboundStore(rootURL: root, now: { Self.clock })
        let wake = try await operation(.morningEnds)
        let journal = try store.createOrRestore(origin: .interactiveIPhone, session: wake.session, manifest: wake.manifest)
        let directory = successor.appendingPathComponent(journal.jobID.uuidString.lowercased())
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("journal.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
        let item = try makeItem(date: wake.manifest.transferDates[0])
        let spooled = try store.adoptItem(item, expectedIndex: 0, jobID: journal.jobID)
        let bytes = try Data(contentsOf: directory.appendingPathComponent(try XCTUnwrap(spooled.items.first).relativePath))
        let old = try await operation(.nightBegins)
        _ = try store.createOrRestore(origin: .interactiveIPhone, session: old.session, manifest: old.manifest)
        try FileManager.default.removeItem(at: root)
        let relaunched = ConnectedCorpusOutboundStore(rootURL: root, now: { Self.clock })
        let restored = try XCTUnwrap(relaunched.load(jobID: journal.jobID))
        XCTAssertEqual(restored, spooled)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(try XCTUnwrap(restored.items.first).relativePath)), bytes)
        try relaunched.cancel(jobID: journal.jobID)
        XCTAssertEqual(try relaunched.load(jobID: journal.jobID)?.state, .cancelled)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testSuccessorExpiryAndResumableDiscoveryPreserveUnexpiredHistoricalJob() async throws {
        let base = try temporaryBase()
        let root = base.appendingPathComponent("ConnectedCorpusOutbound", isDirectory: true)
        let successor = base.appendingPathComponent("ConnectedCorpusOutboundSleepAttribution", isDirectory: true)
        let store = ConnectedCorpusOutboundStore(rootURL: root, now: { Self.clock })
        let wake = try await operation(.morningEnds)
        let old = try await operation(.nightBegins)
        _ = try store.createOrRestore(origin: .interactiveIPhone, session: wake.session, manifest: wake.manifest)
        _ = try store.createOrRestore(origin: .interactiveIPhone, session: old.session, manifest: old.manifest,
            expiresAt: Self.clock.addingTimeInterval(30 * 24 * 60 * 60))
        let spooled = try store.adoptItem(makeItem(date: Self.clock), expectedIndex: 0, jobID: wake.session.jobID)
        let directory = successor.appendingPathComponent(wake.session.jobID.uuidString.lowercased())
        let item = directory.appendingPathComponent(try XCTUnwrap(spooled.items.first).relativePath)
        let oldURL = root.appendingPathComponent(old.session.jobID.uuidString.lowercased()).appendingPathComponent("journal.json")
        let oldBytes = try Data(contentsOf: oldURL)
        let fresh = ConnectedCorpusOutboundStore(rootURL: root, now: { Self.clock })
        XCTAssertEqual(Set(fresh.resumableJournals().map(\.jobID)), [wake.session.jobID, old.session.jobID])
        let expiry = Self.clock.addingTimeInterval(ConnectedCorpusOutboundStore.retentionInterval + 1)
        XCTAssertEqual(fresh.cleanupExpired(now: expiry), [wake.session.jobID])
        XCTAssertEqual(try fresh.load(jobID: wake.session.jobID, allowExpired: true)?.state, .expired)
        XCTAssertFalse(FileManager.default.fileExists(atPath: item.path))
        XCTAssertEqual(Set(fresh.resumableJournals().map(\.jobID)), [old.session.jobID])
        XCTAssertEqual(try Data(contentsOf: oldURL), oldBytes)
        _ = fresh.cleanupExpired(now: expiry.addingTimeInterval(24 * 60 * 60 + 1))
        XCTAssertNil(try fresh.load(jobID: wake.session.jobID, allowExpired: true))
        XCTAssertEqual(try Data(contentsOf: oldURL), oldBytes)
    }

    func testMisplacedAndDuplicateJobsRetainBytesBeforeMigrationOrCleanup() async throws {
        for duplicate in [false, true] {
            let base = try temporaryBase()
            let root = base.appendingPathComponent("ConnectedCorpusOutbound", isDirectory: true)
            let successor = base.appendingPathComponent("ConnectedCorpusOutboundSleepAttribution", isDirectory: true)
            let wake = try await operation(.morningEnds)
            let writer = ConnectedCorpusOutboundStore(rootURL: root, now: { Self.clock })
            let journal = try writer.createOrRestore(origin: .interactiveIPhone, session: wake.session, manifest: wake.manifest)
            let source = successor.appendingPathComponent(journal.jobID.uuidString.lowercased())
            let wrong = root.appendingPathComponent(journal.jobID.uuidString.lowercased())
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            if duplicate { try FileManager.default.copyItem(at: source, to: wrong) }
            else { try FileManager.default.moveItem(at: source, to: wrong) }
            let url = wrong.appendingPathComponent("journal.json")
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
            object["version"] = 1
            let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            try bytes.write(to: url)
            let orphan = wrong.appendingPathComponent("items/retain.bin")
            try Data("synthetic unrecognized spool".utf8).write(to: orphan)
            let marker = try Data(contentsOf: wrong.appendingPathComponent(".journal-generation"))
            let fresh = ConnectedCorpusOutboundStore(rootURL: root, now: { Self.clock })
            XCTAssertThrowsError(try fresh.load(jobID: journal.jobID, allowExpired: true))
            XCTAssertThrowsError(try fresh.createOrRestore(origin: .interactiveIPhone, session: wake.session, manifest: wake.manifest))
            XCTAssertTrue(fresh.resumableJournals().isEmpty)
            XCTAssertTrue(fresh.cleanupExpired(now: Self.clock.addingTimeInterval(2 * ConnectedCorpusOutboundStore.retentionInterval)).isEmpty)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
            XCTAssertEqual(try Data(contentsOf: orphan), Data("synthetic unrecognized spool".utf8))
            XCTAssertEqual(try Data(contentsOf: wrong.appendingPathComponent(".journal-generation")), marker)
        }
    }

    func testSenderSuspensionCannotBorrowReplacementNamespaceOrIdenticalBytesGeneration() async throws {
        for sameAuthority in [false, true] {
            let base = try temporaryBase()
            let root = base.appendingPathComponent("ConnectedCorpusOutbound", isDirectory: true)
            let successor = base.appendingPathComponent("ConnectedCorpusOutboundSleepAttribution", isDirectory: true)
            let wake = try await operation(.morningEnds)
            let replacement = sameAuthority ? wake : try await operation(.nightBegins, jobID: wake.session.jobID)
            let store = ConnectedCorpusOutboundStore(rootURL: root, now: { Self.clock })
            _ = try store.createOrRestore(origin: .interactiveIPhone, session: wake.session, manifest: wake.manifest)
            let newStore = ConnectedCorpusOutboundStore(rootURL: root, now: { Self.clock })
            let oldDirectory = successor.appendingPathComponent(wake.session.jobID.uuidString.lowercased())
            let newDirectory = (sameAuthority ? successor : root).appendingPathComponent(wake.session.jobID.uuidString.lowercased())
            var transportCalls = 0
            let transport = ConnectedCorpusSender.Transport(
                open: { _ in transportCalls += 1; XCTFail("A superseded sender cannot open a partition"); return nil },
                sendPartition: { file, _, transferID, _ in
                    transportCalls += 1; XCTFail("A superseded sender cannot transfer bytes")
                    return .success(ConnectedTransferFinalAck(transferID: transferID, accepted: false, sha256: file.sha256, message: nil))
                },
                finalize: { _, _ in transportCalls += 1; XCTFail("A superseded sender cannot finalize"); return nil },
                cancel: { _ in transportCalls += 1; XCTFail("A superseded sender cannot cancel the replacement"); return nil })
            var winner: Data?
            var produced: URL?
            do {
                _ = try await ConnectedCorpusDurableSender.send(configuration: .init(jobID: wake.session.jobID, retryDelayNanoseconds: 0),
                    store: store, transport: transport, produceItem: { _, date in
                        await Task.yield()
                        _ = try XCTUnwrap(store.load(jobID: wake.session.jobID))
                        let oldBytes = try Data(contentsOf: oldDirectory.appendingPathComponent("journal.json"))
                        let oldGeneration = try Data(contentsOf: oldDirectory.appendingPathComponent(".journal-generation"))
                        try FileManager.default.removeItem(at: oldDirectory)
                        _ = try newStore.createOrRestore(origin: .interactiveIPhone, session: replacement.session, manifest: replacement.manifest)
                        if sameAuthority {
                            let destination = newDirectory.appendingPathComponent("journal.json")
                            let replacementBytes = try Data(contentsOf: destination)
                            try AtomicFileWriter.writeData(oldBytes, to: destination,
                                commitPolicy: .replaceIfUnchanged(replacementBytes),
                                transactionLockURL: base.appendingPathComponent(".ConnectedCorpusOutboundSleepAttribution.journal.lock"),
                                directoryDurability: .required(upTo: base))
                            _ = try newStore.load(jobID: replacement.session.jobID)
                        }
                        winner = try Data(contentsOf: newDirectory.appendingPathComponent("journal.json"))
                        if sameAuthority {
                            XCTAssertEqual(winner, oldBytes, "Only the private generation distinguishes this replacement")
                            XCTAssertNotEqual(try Data(contentsOf: newDirectory.appendingPathComponent(".journal-generation")), oldGeneration)
                        }
                        let item = try self.makeItem(date: date)
                        produced = item.file.url
                        return item
                    })
                XCTFail("The suspended sender must reject a replacement")
            } catch {
                XCTAssertEqual(error as? ConnectedCorpusOutboundStoreError, .requestChanged)
            }
            XCTAssertEqual(transportCalls, 0)
            XCTAssertEqual(try Data(contentsOf: newDirectory.appendingPathComponent("journal.json")), try XCTUnwrap(winner))
            XCTAssertEqual(try newStore.load(jobID: wake.session.jobID)?.nextItemIndex, 0)
            XCTAssertFalse(FileManager.default.fileExists(atPath: try XCTUnwrap(produced).path))
            XCTAssertThrowsError(try store.load(jobID: wake.session.jobID))
            XCTAssertThrowsError(try store.cancel(jobID: wake.session.jobID))
            XCTAssertThrowsError(try store.remove(jobID: wake.session.jobID))
            XCTAssertTrue(store.cleanupExpired(now: Self.clock.addingTimeInterval(2 * ConnectedCorpusOutboundStore.retentionInterval)).isEmpty)
            XCTAssertEqual(try Data(contentsOf: newDirectory.appendingPathComponent("journal.json")), try XCTUnwrap(winner))
        }
    }

    private static var clock: Date { Date(timeIntervalSince1970: 1_800_000_000) }

    private func temporaryBase() throws -> URL {
        let candidate = FileManager.default.temporaryDirectory.appendingPathComponent("connected-namespace-\(UUID())")
        try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: true)
        let base = candidate.standardizedFileURL.resolvingSymlinksInPath()
        addTeardownBlock { try? FileManager.default.removeItem(at: base) }
        return base
    }

    private func operation(_ attribution: SleepDayAttribution, jobID: UUID = UUID()) async throws
        -> (session: ConnectedCorpusTransferSession, manifest: ConnectedCorpusExportManifest) {
        let suite = "ConnectedCorpusNamespaceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.json]
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.includeGranularData = false
        settings.generateRangeSummary = false
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(
            timeZone: TimeZone(identifier: "America/New_York")!, sleepDayAttribution: attribution)
        settings.executionSleepCaptureContextIsFrozen = true
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(settings, healthSubfolder: "Health",
            surface: .localVaultWithoutSideEffects,
            policyResolver: AppleExportEnginePolicyResolver(injectedOverride: "legacy", userDefaults: nil, environment: [:]))
        let manifest = ConnectedCorpusExportManifest(mode: .writeFiles, createdAt: Self.clock,
            sourceDeviceName: "Synthetic iPhone", sourceTimeZoneIdentifier: "America/New_York",
            dateRangeStart: Self.clock, dateRangeEnd: Self.clock, requestedDates: [Self.clock],
            requestedDateIdentifiers: ["2027-01-15"], transferDates: [Self.clock],
            settingsSnapshot: snapshot, requestedTarget: nil)
        let session = ConnectedCorpusTransferSession(sessionID: UUID(), jobID: jobID,
            requestFingerprint: try ConnectedCorpusRequestFingerprint.make(for: manifest), protocolVersion: 2,
            partitionTargetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes,
            createdAt: Self.clock,
            peerBinding: ConnectedCorpusPeerBinding(sourceInstallationID: UUID(), destinationInstallationID: UUID()))
        return (session, manifest)
    }

    private func makeItem(date: Date) throws -> ConnectedCorpusSpoolItem {
        try ConnectedCorpusSpoolItem.encode(ConnectedCorpusHealthDayPayload(sourceDate: date,
            isRequestedDate: true, record: HealthData(date: date, activity: ActivityData(steps: 456)),
            externalDailyRecords: [], failure: nil), kind: .macHealthDay, sourceDate: date,
            isRequestedDate: true, protocolVersion: 2)
    }
}
