import Foundation
import XCTest
@testable import HealthMd

#if os(macOS)
@MainActor
final class MacCorpusExportSessionManagerTests: XCTestCase {
    private var defaults: FakeUserDefaults!
    private var fileSystem: FakeFileSystem!
    private var bookmarkResolver: FakeBookmarkResolver!
    private var vaultManager: VaultManager!
    private var vaultRoot: URL!
    private var sessionRoot: URL!

    override func setUp() {
        super.setUp()
        defaults = FakeUserDefaults()
        fileSystem = FakeFileSystem()
        bookmarkResolver = FakeBookmarkResolver()
        bookmarkResolver.accessGranted = true
        vaultManager = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver
        )
        vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorpusVault-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(
            at: vaultRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        vaultManager.setVaultFolder(vaultRoot)
        sessionRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-corpus-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let sessionRoot { try? FileManager.default.removeItem(at: sessionRoot) }
        if let vaultRoot { try? FileManager.default.removeItem(at: vaultRoot) }
        super.tearDown()
    }

    func testOpenRejectsDestinationSymlinkOutsideSelectedVault() throws {
        let vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-symlink-vault-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-symlink-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: vaultRoot)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createSymbolicLink(
            at: vaultRoot.appendingPathComponent("Health"),
            withDestinationURL: outside
        )
        let realVault = VaultManager(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        realVault.setVaultFolder(vaultRoot)
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let disposition = MacCorpusExportSessionManager(rootURL: sessionRoot).open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: realVault
        )
        XCTAssertEqual(disposition.disposition, .reject)
    }

    func testPartitionRejectsSymlinkedProtectedRecordsDirectory() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)

        let sessionDirectory = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString, isDirectory: true)
        let recordsDirectory = sessionDirectory.appendingPathComponent("records", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-records-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.removeItem(at: recordsDirectory)
        try FileManager.default.createSymbolicLink(at: recordsDirectory, withDestinationURL: outside)

        do {
            try await manager.applyPartition(
                fileURL: partition.file.url,
                descriptor: partition.descriptor,
                vaultManager: vaultManager
            )
            XCTFail("A symlinked protected records directory must fail closed")
        } catch {
            // Expected: no source payload may be moved through the symlink.
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testPartitionRejectsReboundProtectedSessionRootBeforeWritingItems() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)

        let sessionDirectory = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString, isDirectory: true)
        let movedSession = sessionRoot
            .appendingPathComponent("moved-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-session-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: movedSession)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.moveItem(at: sessionDirectory, to: movedSession)
        try FileManager.default.createSymbolicLink(at: sessionDirectory, withDestinationURL: outside)

        do {
            try await manager.applyPartition(
                fileURL: partition.file.url,
                descriptor: partition.descriptor,
                vaultManager: vaultManager
            )
            XCTFail("A rebound protected session root must fail before source spool writes")
        } catch {
            // Expected: the persisted device/inode binding cannot follow the replacement.
        }
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testExpiredCorruptSessionIsSecurelyRemovedAfterRetention() throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
        manager.suspendForDisconnect()
        let sessionDirectory = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
        try Data("corrupt".utf8).write(
            to: sessionDirectory.appendingPathComponent("journal.json"),
            options: .atomic
        )

        manager.cleanupExpiredSessionsForTesting(
            now: Date().addingTimeInterval(ConnectedCorpusOutboundStore.retentionInterval + 60)
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDirectory.path))
    }

    func testCorruptEarlyExpiryCannotDeleteJournalAndRestartSession() throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(
            MacCorpusExportSessionManager(rootURL: sessionRoot)
                .open(open, vaultManager: vaultManager).disposition,
            .accept
        )
        let sessionDirectory = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
        let journalURL = sessionDirectory.appendingPathComponent("journal.json")
        var journal = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        let storedSession = try XCTUnwrap(journal["session"] as? [String: Any])
        journal["expiresAt"] = try XCTUnwrap(storedSession["createdAt"])
        try JSONSerialization.data(withJSONObject: journal, options: [.sortedKeys])
            .write(to: journalURL, options: .atomic)

        let restarted = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: journalURL.path))
        XCTAssertEqual(restarted.open(open, vaultManager: vaultManager).disposition, .reject)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: sessionDirectory.path),
            "invalid expiry must not make the same durable operation look new"
        )
    }

    func testRestoreRejectsTamperedProtectedSessionIdentity() throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(
            MacCorpusExportSessionManager(rootURL: sessionRoot)
                .open(open, vaultManager: vaultManager).disposition,
            .accept
        )
        let journalURL = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
            .appendingPathComponent("journal.json")
        var journal = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        let inode = try XCTUnwrap(journal["protectedSessionInode"] as? NSNumber)
        journal["protectedSessionInode"] = inode.uint64Value + 1
        try JSONSerialization.data(withJSONObject: journal, options: [.sortedKeys])
            .write(to: journalURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: journalURL.path
        )

        XCTAssertEqual(
            MacCorpusExportSessionManager(rootURL: sessionRoot)
                .open(open, vaultManager: vaultManager).disposition,
            .reject
        )
    }

    func testDailyNotesOnlyOpenIgnoresSuppressedAggregateDestination() throws {
        let vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-daily-only-vault-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-daily-only-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: vaultRoot)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createSymbolicLink(
            at: vaultRoot.appendingPathComponent("Health"),
            withDestinationURL: outside
        )
        let realVault = VaultManager(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        realVault.setVaultFolder(vaultRoot)
        let settings = makeSettings()
        settings.archiveExportFiles = true
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.entriesFolder = "Health/Entries"
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], settings: settings)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }

        let disposition = MacCorpusExportSessionManager(rootURL: sessionRoot).open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: realVault
        )

        XCTAssertEqual(disposition.disposition, .accept)
    }

    func testAcceptedOpenGrantsOneExactTransportAdmission() throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let firstOpen = manager.open(open, vaultManager: vaultManager)
        XCTAssertEqual(firstOpen.disposition, .accept, firstOpen.message ?? "")
        XCTAssertTrue(manager.consumeAdmission(for: partition.descriptor))
        XCTAssertFalse(manager.consumeAdmission(for: partition.descriptor))

        let secondOpen = manager.open(open, vaultManager: vaultManager)
        XCTAssertEqual(secondOpen.disposition, .accept, secondOpen.message ?? "")
        XCTAssertTrue(manager.consumeAdmission(for: partition.descriptor))
    }

    func testDurableOpenRejectsDifferentInstallationAndAcceptsBoundPeer() throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let sourceInstallationID = UUID()
        let destinationInstallationID = UUID()
        let boundSession = ConnectedCorpusTransferSession(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            protocolVersion: 2,
            partitionTargetBytes: context.session.partitionTargetBytes,
            createdAt: context.session.createdAt,
            peerBinding: ConnectedCorpusPeerBinding(
                sourceInstallationID: sourceInstallationID,
                destinationInstallationID: destinationInstallationID
            )
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: boundSession.sessionID,
            jobID: boundSession.jobID,
            targetBytes: boundSession.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let open = ConnectedCorpusTransferOpen(
            session: boundSession,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)

        XCTAssertEqual(manager.open(
            open,
            vaultManager: vaultManager,
            localInstallationID: destinationInstallationID,
            remoteInstallationID: UUID()
        ).disposition, .reject)
        XCTAssertEqual(manager.open(
            open,
            vaultManager: vaultManager,
            localInstallationID: destinationInstallationID,
            remoteInstallationID: sourceInstallationID
        ).disposition, .accept)
    }

    func testPartitionCommitWritesDailyOutputAndReplayIsIdempotent() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        var diskSpaceCheckCount = 0
        let manager = MacCorpusExportSessionManager(
            rootURL: sessionRoot,
            diskSpaceCheck: { _, _ in
                diskSpaceCheckCount += 1
                return true
            }
        )
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)

        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let exportedPath = vaultRoot
            .appendingPathComponent("Health/2026-01-02.md")
            .path
        let firstContent = try XCTUnwrap(fileSystem.files[exportedPath])
        XCTAssertTrue(firstContent.contains("4321"))

        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .alreadyCommitted)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        XCTAssertEqual(fileSystem.files[exportedPath], firstContent)

        let diskSpaceChecksBeforeFinalization = diskSpaceCheckCount
        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: vaultManager
        )
        guard case .files(let result, let acknowledgement) = outcome else {
            return XCTFail("Expected file result")
        }
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(
            diskSpaceCheckCount,
            diskSpaceChecksBeforeFinalization,
            "Loose-files-only finalization must not reserve space for derived outputs"
        )
        XCTAssertEqual(result.completedDates, [date])
        XCTAssertEqual(acknowledgement.completedDates, [date])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionRoot
                .appendingPathComponent(context.session.sessionID.uuidString)
                .appendingPathComponent("journal.json").path
        ))
        let replay = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: vaultManager
        )
        guard case .replay(let replayAcknowledgement, let replayResult) = replay else {
            return XCTFail("Expected terminal acknowledgement replay")
        }
        XCTAssertEqual(replayAcknowledgement, acknowledgement)
        XCTAssertEqual(replayResult?.jobID, result.jobID)
        XCTAssertEqual(replayResult?.completedDates, result.completedDates)
        XCTAssertEqual(replayResult?.successCount, result.successCount)
    }

    func testFinalizationFailureAndRejectedAcknowledgementReplayTogetherAfterRestart() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        let failure = MacExportFailure(
            jobID: context.session.jobID,
            reason: .exportWriteFailure,
            message: "Mac could not finalize the partitioned corpus export.",
            underlyingError: "simulated failure"
        )
        let acknowledgement = try XCTUnwrap(manager.recordFinalizationFailure(
            finalize,
            failure: failure,
            vaultManager: vaultManager
        ))
        XCTAssertFalse(acknowledgement.accepted)

        let replay = try await MacCorpusExportSessionManager(rootURL: sessionRoot).finalize(
            finalize,
            vaultManager: vaultManager
        )
        guard case .failed(let replayedFailure, let replayedAcknowledgement) = replay else {
            return XCTFail("Expected durable failure and rejected ACK replay")
        }
        XCTAssertEqual(replayedFailure, failure)
        XCTAssertEqual(replayedAcknowledgement, acknowledgement)
    }

    func testFinalizationFailurePersistenceFailurePublishesNoTerminalAcknowledgement() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        manager.failNextTerminalPersistForTesting = true
        XCTAssertNil(manager.recordFinalizationFailure(
            finalize,
            failure: MacExportFailure(
                jobID: context.session.jobID,
                reason: .exportWriteFailure,
                message: "simulated"
            ),
            vaultManager: vaultManager
        ))

        guard case .files = try await MacCorpusExportSessionManager(rootURL: sessionRoot).finalize(
            finalize,
            vaultManager: vaultManager
        ) else {
            return XCTFail("A failed terminal persist must leave finalization resumable")
        }
    }

    func testPartitionedPinnedRustDayUsesExactManifestSnapshotAndConnectedSurface() async throws {
        let date = Self.day(2026, 1, 2)
        let record = HealthData(date: date, activity: ActivityData(steps: 4_321))
        let settings = makeSettings()
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: record
        )
        let context = try makeContext(
            requestedDates: [date],
            settings: settings,
            settingsSnapshot: snapshot,
            sourceTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let planner = ConnectedMacPlannerProbe()
        vaultManager = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: planner
        )
        vaultManager.setVaultFolder(vaultRoot)
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)

        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )

        XCTAssertEqual(planner.calls.count, 1)
        XCTAssertEqual(planner.calls.first?.surface, .connectedReceivedFilesWithoutSideEffects)
        XCTAssertEqual(planner.calls.first?.settingsSnapshot, snapshot)
        XCTAssertEqual(
            fileSystem.files[vaultRoot.appendingPathComponent("Health/2026-01-02.json").path],
            "rust-authority-only"
        )
    }

    func testPinnedConnectedRangeRejectsAcknowledgedSourceSpoolDriftBeforePlanning() async throws {
        let requestedDate = Self.day(2026, 1, 5)
        let supportingDate = Self.day(2026, 1, 6)
        let record = HealthData(date: requestedDate, activity: ActivityData(steps: 4_321))
        let settings = makeSettings()
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        settings.generateWeeklyRollups = true
        let snapshot = try await makePinnedSnapshot(
            engine: .shadow,
            settings: settings,
            record: record
        )
        let context = try makeContext(
            requestedDates: [requestedDate],
            settings: settings,
            settingsSnapshot: snapshot,
            sourceTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier,
            transferDates: [requestedDate, supportingDate]
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: requestedDate))
        assembler.append(try healthItem(date: supportingDate, isRequestedDate: false))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        var manager: MacCorpusExportSessionManager? = MacCorpusExportSessionManager(
            rootURL: sessionRoot
        )
        XCTAssertEqual(manager?.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)
        try await manager?.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        manager = nil
        let recordsDirectory = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
            .appendingPathComponent("records", isDirectory: true)
        let recordURL = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(
                at: recordsDirectory,
                includingPropertiesForKeys: nil
            ).first
        )
        var bytes = try Data(contentsOf: recordURL)
        bytes.append(0x20)
        try bytes.write(to: recordURL, options: .atomic)

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        do {
            _ = try await MacCorpusExportSessionManager(rootURL: sessionRoot).finalize(
                finalize,
                vaultManager: resumedVault
            )
            XCTFail("Acknowledged source bytes must remain integrity-bound until planning")
        } catch let error as ConnectedCorpusTransferModelError {
            XCTAssertEqual(error, .invalidJournal)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(rejectingPlanner.callCount, 0)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testPinnedConnectedRangeDefersAllWritesUntilOneDailyAndRollupFinalizationPlan() async throws {
        let requestedDate = Self.day(2026, 1, 5)
        let supportingDate = Self.day(2026, 1, 6)
        let record = HealthData(date: requestedDate, activity: ActivityData(steps: 4_321))
        let settings = makeSettings()
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        settings.includeDataDictionary = false
        settings.generateWeeklyRollups = true
        settings.folderStructure = "Rollups/{year}"
        let snapshot = try await makePinnedSnapshot(
            engine: .shadow,
            settings: settings,
            record: record
        )
        let context = try makeContext(
            requestedDates: [requestedDate],
            settings: settings,
            settingsSnapshot: snapshot,
            sourceTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier,
            transferDates: [requestedDate, supportingDate]
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: requestedDate))
        assembler.append(try healthItem(date: supportingDate, isRequestedDate: false))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)

        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        XCTAssertTrue(fileSystem.files.isEmpty, "partition durability must not write range destinations")

        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: vaultManager
        )
        guard case .files(let result, let acknowledgement) = outcome else {
            return XCTFail("Expected connected range file result")
        }
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.totalFilesWritten, 2)
        XCTAssertEqual(result.completedDates, [requestedDate])
        XCTAssertEqual(acknowledgement.completedDates, [requestedDate])
        XCTAssertNotNil(fileSystem.files[
            vaultRoot.appendingPathComponent("Health/Rollups/2026/2026-01-05.json").path
        ])
        XCTAssertNil(fileSystem.files[
            vaultRoot
                .appendingPathComponent("Health")
                .appendingPathComponent(HealthMdExportSchema.dataDictionaryFilename).path
        ])
        let rollupPaths = fileSystem.files.keys.filter { $0.contains("/Rollups/Weekly/") }
        XCTAssertEqual(rollupPaths.count, 1)
        let rollupContent = try XCTUnwrap(rollupPaths.first.flatMap { fileSystem.files[$0] })
        XCTAssertTrue(rollupContent.contains(
            HealthRollupDateFormatting.timestampString(context.manifest.createdAt)
        ))
    }

    func testPinnedConnectedSummaryOnlyRangeFinalizesWithoutDailyArtifacts() async throws {
        let requestedDate = Self.day(2026, 2, 10)
        let supportingDate = Self.day(2026, 2, 11)
        let record = HealthData(date: requestedDate, activity: ActivityData(steps: 4_321))
        let settings = makeSettings()
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        settings.generateMonthlyRollups = true
        settings.summaryOnlyExport = true
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: record
        )
        let context = try makeContext(
            requestedDates: [requestedDate],
            settings: settings,
            settingsSnapshot: snapshot,
            sourceTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier,
            transferDates: [requestedDate, supportingDate]
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: requestedDate))
        assembler.append(try healthItem(date: supportingDate, isRequestedDate: false))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        XCTAssertTrue(fileSystem.files.isEmpty)

        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: vaultManager
        )
        guard case .files(let result, _) = outcome else {
            return XCTFail("Expected summary-only connected range result")
        }
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.totalFilesWritten, 1)
        XCTAssertEqual(result.completedDates, [requestedDate])
        XCTAssertNil(fileSystem.files[
            vaultRoot.appendingPathComponent("Health/2026-02-10.json").path
        ])
        XCTAssertEqual(
            fileSystem.files.keys.filter { $0.contains("/Rollups/Monthly/") }.count,
            1
        )
    }

    func testPinnedConnectedRangeRetainsPublishedPlanAfterPostRenameSyncFailure() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(
            failAfterDictionaryWrite: false,
            failAfterRangePlanJournalPublication: true
        )
        let artifactURL = sessionRoot
            .appendingPathComponent(interrupted.sessionID.uuidString)
            .appendingPathComponent("finalization/artifacts/0000.artifact")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifactURL.path))

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        let restored = MacCorpusExportSessionManager(rootURL: sessionRoot)
        guard case .files = try await restored.finalize(
            interrupted.finalize,
            vaultManager: resumedVault
        ) else {
            return XCTFail("A published exact range plan should resume after sync uncertainty")
        }
        XCTAssertEqual(rejectingPlanner.callCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
    }

    func testPinnedConnectedRangeReinspectsExactAdoptionInsideCommitTransaction() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: true)
        let dictionaryPath = vaultRoot
            .appendingPathComponent("Health")
            .appendingPathComponent(HealthMdExportSchema.dataDictionaryFilename).path
        var replacedAfterInitialRead = false
        fileSystem.readCompleted = { url in
            guard url.path == dictionaryPath, !replacedAfterInitialRead else { return }
            replacedAfterInitialRead = true
            self.fileSystem.files[dictionaryPath] = "concurrent replacement"
        }
        defer { fileSystem.readCompleted = nil }

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        let restored = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let outcome = try await restored.finalize(
            interrupted.finalize,
            vaultManager: resumedVault
        )
        guard case .files = outcome else {
            return XCTFail("Expected exact plan completion after transactional reinspection")
        }
        XCTAssertTrue(replacedAfterInitialRead)
        XCTAssertEqual(fileSystem.writeCounts[dictionaryPath], 2)
        XCTAssertNotEqual(fileSystem.files[dictionaryPath], "concurrent replacement")
        XCTAssertEqual(rejectingPlanner.callCount, 0)
    }

    func testPinnedConnectedRangeResumesExactBytesWithoutReplanningAfterUncertainWrite() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: true)
        let dictionaryPath = vaultRoot
            .appendingPathComponent("Health")
            .appendingPathComponent(HealthMdExportSchema.dataDictionaryFilename).path
        XCTAssertEqual(fileSystem.writeCounts[dictionaryPath], 1)

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        let restored = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(
            restored.open(interrupted.open, vaultManager: resumedVault).disposition,
            .alreadyCommitted
        )
        let outcome = try await restored.finalize(
            interrupted.finalize,
            vaultManager: resumedVault
        )
        guard case .files(let result, let acknowledgement) = outcome else {
            return XCTFail("Expected resumed range completion")
        }
        XCTAssertEqual(rejectingPlanner.callCount, 0, "resume must not invoke either renderer")
        XCTAssertEqual(fileSystem.writeCounts[dictionaryPath], 1, "exact uncertain write is adopted")
        XCTAssertEqual(result.totalFilesWritten, 2)
        XCTAssertEqual(result.completedDates, [interrupted.requestedDate])
        XCTAssertEqual(acknowledgement.completedDates, [interrupted.requestedDate])

        let leftoverFinalization = sessionRoot
            .appendingPathComponent(interrupted.sessionID.uuidString)
            .appendingPathComponent("finalization", isDirectory: true)
        try FileManager.default.createDirectory(
            at: leftoverFinalization,
            withIntermediateDirectories: true
        )
        try Data("leftover-after-terminal-checkpoint".utf8).write(
            to: leftoverFinalization.appendingPathComponent("orphan")
        )
        let replayManager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(
            replayManager.open(interrupted.open, vaultManager: resumedVault).disposition,
            .alreadyCommitted
        )
        let replay = try await replayManager.finalize(
            interrupted.finalize,
            vaultManager: resumedVault
        )
        guard case .replay(let replayAcknowledgement, let replayResult) = replay else {
            return XCTFail("Expected persisted terminal replay")
        }
        XCTAssertEqual(replayAcknowledgement, acknowledgement)
        XCTAssertEqual(replayResult?.jobID, result.jobID)
        XCTAssertEqual(rejectingPlanner.callCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: leftoverFinalization.path))

        let journalURL = sessionRoot
            .appendingPathComponent(interrupted.sessionID.uuidString)
            .appendingPathComponent("journal.json")
        var journalObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        journalObject["version"] = 3
        journalObject.removeValue(forKey: "receivedRangePlanPersisted")
        journalObject.removeValue(forKey: "receivedRangePlan")
        journalObject.removeValue(forKey: "protectedSessionDeviceID")
        journalObject.removeValue(forKey: "protectedSessionInode")
        journalObject["recordItems"] = (journalObject["recordItems"] as? [[String: Any]])?.map {
            var item = $0
            item.removeValue(forKey: "byteCount")
            item.removeValue(forKey: "sha256")
            return item
        }
        try JSONSerialization.data(withJSONObject: journalObject, options: [.sortedKeys])
            .write(to: journalURL, options: .atomic)
        let migratedTerminalReplay = try await MacCorpusExportSessionManager(
            rootURL: sessionRoot
        ).finalize(interrupted.finalize, vaultManager: resumedVault)
        guard case .replay(let migratedAcknowledgement, _) = migratedTerminalReplay else {
            return XCTFail("Expected migrated v3 terminal replay")
        }
        XCTAssertEqual(migratedAcknowledgement, acknowledgement)
        journalObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        XCTAssertEqual(journalObject["version"] as? Int, 5)

        var forgedAcknowledgement = try XCTUnwrap(
            journalObject["terminalAcknowledgement"] as? [String: Any]
        )
        forgedAcknowledgement["accepted"] = false
        journalObject["terminalAcknowledgement"] = forgedAcknowledgement
        try JSONSerialization.data(withJSONObject: journalObject, options: [.sortedKeys])
            .write(to: journalURL, options: .atomic)
        do {
            _ = try await MacCorpusExportSessionManager(rootURL: sessionRoot).finalize(
                interrupted.finalize,
                vaultManager: resumedVault
            )
            XCTFail("A forged terminal acknowledgement must not replay")
        } catch let error as ConnectedCorpusTransferModelError {
            XCTAssertEqual(error, .invalidJournal)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPinnedConnectedRangeRejectsMoreThanFourHundredSemanticOwnerDatesAtOpen() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = Self.day(2025, 1, 1)
        let dates = try (0..<401).map { offset in
            try XCTUnwrap(calendar.date(byAdding: .day, value: offset, to: start))
        }
        let record = HealthData(date: dates[0], activity: ActivityData(steps: 4_321))
        let settings = makeSettings()
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        settings.generateYearlyRollups = true
        settings.summaryOnlyExport = true
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: record
        )
        let context = try makeContext(
            requestedDates: dates,
            settings: settings,
            settingsSnapshot: snapshot,
            sourceTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier,
            transferDates: dates
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: dates[0]))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }

        let disposition = MacCorpusExportSessionManager(rootURL: sessionRoot).open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        )
        XCTAssertEqual(disposition.disposition, .reject)
        XCTAssertTrue(try XCTUnwrap(disposition.message).contains("owner-date"))
    }

    func testPinnedConnectedRangeRejectsCorruptProtectedBytesBeforeResumeWrites() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: true)
        let artifactURL = sessionRoot
            .appendingPathComponent(interrupted.sessionID.uuidString)
            .appendingPathComponent("finalization/artifacts/0000.artifact")
        try Data("corrupt".utf8).write(to: artifactURL, options: .atomic)
        let writesBeforeResume = fileSystem.writeCounts

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        let restored = MacCorpusExportSessionManager(rootURL: sessionRoot)
        do {
            _ = try await restored.finalize(interrupted.finalize, vaultManager: resumedVault)
            XCTFail("Corrupt protected bytes must fail closed")
        } catch let error as ConnectedCorpusTransferModelError {
            XCTAssertEqual(error, .invalidJournal)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(rejectingPlanner.callCount, 0)
        XCTAssertEqual(fileSystem.writeCounts, writesBeforeResume)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: artifactURL.path),
            "corrupt state is retained for diagnosis instead of looking like a new session"
        )
    }

    func testPinnedConnectedRangeRejectsProtectedSpoolSymlinkEvenWithExactBytes() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: true)
        let artifactURL = sessionRoot
            .appendingPathComponent(interrupted.sessionID.uuidString)
            .appendingPathComponent("finalization/artifacts/0000.artifact")
        let outsideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("connected-spool-outside-\(UUID().uuidString)")
        try Data(contentsOf: artifactURL).write(to: outsideURL, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: outsideURL.path
        )
        defer { try? FileManager.default.removeItem(at: outsideURL) }
        try FileManager.default.removeItem(at: artifactURL)
        try FileManager.default.createSymbolicLink(
            at: artifactURL,
            withDestinationURL: outsideURL
        )
        let writesBeforeResume = fileSystem.writeCounts

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        do {
            _ = try await MacCorpusExportSessionManager(rootURL: sessionRoot).finalize(
                interrupted.finalize,
                vaultManager: resumedVault
            )
            XCTFail("A protected spool symlink must fail closed")
        } catch let error as ConnectedCorpusTransferModelError {
            XCTAssertEqual(error, .invalidJournal)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(fileSystem.writeCounts, writesBeforeResume)
        XCTAssertEqual(rejectingPlanner.callCount, 0)
    }

    func testPinnedConnectedRangeDoesNotAcknowledgeCancellationDuringAtomicWrite() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: false)
        let dictionaryPath = vaultRoot
            .appendingPathComponent("Health")
            .appendingPathComponent(HealthMdExportSchema.dataDictionaryFilename).path
        let writeStarted = expectation(description: "dictionary write started")
        let writeBlocker = DispatchSemaphore(value: 0)
        fileSystem.writeStarted = { url in
            if url.path == dictionaryPath { writeStarted.fulfill() }
        }
        fileSystem.writeBlocker = writeBlocker
        defer {
            fileSystem.writeStarted = nil
            fileSystem.writeBlocker = nil
            writeBlocker.signal()
        }

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let finalizeTask = Task { @MainActor in
            try await manager.finalize(interrupted.finalize, vaultManager: resumedVault)
        }
        await fulfillment(of: [writeStarted], timeout: 2)

        let cancellation = manager.cancel(
            sessionID: interrupted.sessionID,
            jobID: interrupted.finalize.jobID,
            vaultManager: resumedVault
        )
        XCTAssertFalse(cancellation.0.accepted)
        XCTAssertNil(cancellation.1)
        writeBlocker.signal()
        guard case .files = try await finalizeTask.value else {
            return XCTFail("The atomic artifact boundary should finish normally")
        }
        XCTAssertEqual(fileSystem.writeCounts[dictionaryPath], 1)
        XCTAssertEqual(rejectingPlanner.callCount, 0)
    }

    func testPinnedConnectedRangeDoesNotAcknowledgeCancellationDuringReadbackCheckpoint() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: false)
        let dictionaryPath = vaultRoot
            .appendingPathComponent("Health")
            .appendingPathComponent(HealthMdExportSchema.dataDictionaryFilename).path
        let readbackStarted = expectation(description: "dictionary readback started")
        let readbackBlocker = DispatchSemaphore(value: 0)
        fileSystem.readStarted = { url in
            if url.path == dictionaryPath { readbackStarted.fulfill() }
        }
        fileSystem.readBlocker = readbackBlocker
        defer {
            fileSystem.readStarted = nil
            fileSystem.readBlocker = nil
            readbackBlocker.signal()
        }

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let finalizeTask = Task { @MainActor in
            try await manager.finalize(interrupted.finalize, vaultManager: resumedVault)
        }
        await fulfillment(of: [readbackStarted], timeout: 2)

        let cancellation = manager.cancel(
            sessionID: interrupted.sessionID,
            jobID: interrupted.finalize.jobID,
            vaultManager: resumedVault
        )
        XCTAssertFalse(cancellation.0.accepted)
        XCTAssertNil(cancellation.1)
        readbackBlocker.signal()
        guard case .files = try await finalizeTask.value else {
            return XCTFail("The exact readback and durable frontier should finish normally")
        }
        XCTAssertEqual(fileSystem.writeCounts[dictionaryPath], 1)
        XCTAssertEqual(rejectingPlanner.callCount, 0)
    }

    func testPinnedConnectedRangeRejectsAcknowledgedDestinationByteDrift() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: true)
        let dictionaryPath = vaultRoot
            .appendingPathComponent("Health")
            .appendingPathComponent(HealthMdExportSchema.dataDictionaryFilename).path
        let dailyPath = vaultRoot.appendingPathComponent("Health/2026-03-02.json").path
        fileSystem.failBeforeWritingPathOnce = dailyPath

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        let firstResume = try await MacCorpusExportSessionManager(rootURL: sessionRoot).finalize(
            interrupted.finalize,
            vaultManager: resumedVault
        )
        guard case .inProgress = firstResume else {
            return XCTFail("Expected failure after dictionary acknowledgement")
        }
        XCTAssertEqual(fileSystem.writeCounts[dictionaryPath], 1)
        fileSystem.files[dictionaryPath] = "user changed acknowledged bytes"
        let writesBeforeDriftCheck = fileSystem.writeCounts

        do {
            _ = try await MacCorpusExportSessionManager(rootURL: sessionRoot).finalize(
                interrupted.finalize,
                vaultManager: resumedVault
            )
            XCTFail("Acknowledged destination drift must fail closed")
        } catch let error as ConnectedCorpusTransferModelError {
            XCTAssertEqual(error, .invalidJournal)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(fileSystem.writeCounts, writesBeforeDriftCheck)
        XCTAssertEqual(rejectingPlanner.callCount, 0)
    }

    func testPinnedConnectedRangeRejectsSelectedFolderRebinding() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: true)
        let reboundRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorpusVault-rebound-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: reboundRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: reboundRoot) }
        let rejectingPlanner = RejectingConnectedRangePlanner()
        let reboundVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        reboundVault.setVaultFolder(reboundRoot)

        let restored = MacCorpusExportSessionManager(rootURL: sessionRoot)
        do {
            _ = try await restored.finalize(interrupted.finalize, vaultManager: reboundVault)
            XCTFail("A durable plan cannot be redirected to a different selected folder")
        } catch let error as ConnectedCorpusTransferModelError {
            XCTAssertEqual(error, .invalidJournal)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(rejectingPlanner.callCount, 0)
        XCTAssertFalse(fileSystem.files.keys.contains { $0.hasPrefix(reboundRoot.path + "/") })
    }

    func testVersionThreeFinalizingRangeJournalWithoutDurableContractFailsClosed() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: false)
        let journalURL = sessionRoot
            .appendingPathComponent(interrupted.sessionID.uuidString)
            .appendingPathComponent("journal.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        object["version"] = 3
        object.removeValue(forKey: "receivedRangePlanPersisted")
        object.removeValue(forKey: "receivedRangePlan")
        object.removeValue(forKey: "protectedSessionDeviceID")
        object.removeValue(forKey: "protectedSessionInode")
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: journalURL, options: .atomic)

        let rejectingPlanner = RejectingConnectedRangePlanner()
        let resumedVault = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: rejectingPlanner
        )
        resumedVault.setVaultFolder(vaultRoot)
        do {
            _ = try await MacCorpusExportSessionManager(rootURL: sessionRoot).finalize(
                interrupted.finalize,
                vaultManager: resumedVault
            )
            XCTFail("Old ambiguous finalization must not rerender or restart writes")
        } catch let error as ConnectedCorpusTransferModelError {
            XCTAssertEqual(error, .invalidJournal)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        XCTAssertEqual(rejectingPlanner.callCount, 0)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testPinnedConnectedRangeWithMissingSupportDayFailsBeforeDestinationWrite() async throws {
        let requestedDate = Self.day(2026, 1, 5)
        let supportingDate = Self.day(2026, 1, 6)
        let record = HealthData(date: requestedDate, activity: ActivityData(steps: 4_321))
        let settings = makeSettings()
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        settings.generateWeeklyRollups = true
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: record
        )
        let context = try makeContext(
            requestedDates: [requestedDate],
            settings: settings,
            settingsSnapshot: snapshot,
            sourceTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier,
            transferDates: [requestedDate, supportingDate]
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: requestedDate))
        assembler.append(try failedHealthItem(date: supportingDate, isRequestedDate: false))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )

        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: vaultManager
        )
        guard case .files(let result, _) = outcome else {
            return XCTFail("Expected failed connected range file result")
        }
        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.totalFilesWritten, 0)
        XCTAssertEqual(result.completedDates, [])
        XCTAssertTrue(result.failedDateDetails.contains {
            $0.date == requestedDate && $0.reason == .healthKitError
        })
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testPartitionedPinnedProviderSidecarFailsBeforePlanningOrDestinationWrite() async throws {
        let date = Self.day(2026, 1, 2)
        let record = HealthData(date: date, activity: ActivityData(steps: 4_321))
        let settings = makeSettings()
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: record
        )
        let context = try makeContext(
            requestedDates: [date],
            settings: settings,
            settingsSnapshot: snapshot,
            sourceTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier
        )
        let sidecar = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-01-02",
            payloads: [ExternalProviderPayload(
                name: "recovery",
                endpoint: "https://api.prod.whoop.com/developer/v2/recovery",
                statusCode: 200,
                data: .object(["score": .number(95)])
            )]
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date, externalDailyRecords: [sidecar]))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let planner = ConnectedMacPlannerProbe()
        vaultManager = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            appleLooseDailyPlanner: planner
        )
        vaultManager.setVaultFolder(vaultRoot)
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)

        do {
            try await manager.applyPartition(
                fileURL: partition.file.url,
                descriptor: partition.descriptor,
                vaultManager: vaultManager
            )
            XCTFail("Expected pinned provider-sidecar partition to fail safely")
        } catch {
            XCTAssertEqual(
                error as? ConnectedMacDailyExportOperation.ResolutionError,
                .unsupportedPinnedOperation
            )
        }
        XCTAssertTrue(planner.calls.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testWriteFilesPartitionDoesNotDependOnDisposableEncryptedContextStore() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], mode: .writeFiles)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }

        let keyProvider = InMemoryHealthContextEncryptionKeyProvider()
        let contextStore = EncryptedHealthContextStore(
            rootURL: sessionRoot.appendingPathComponent("unavailable-file-context", isDirectory: true),
            keyProvider: keyProvider
        )
        var seedRecord = HealthData(date: Self.day(2025, 12, 31))
        seedRecord.activity.steps = 1
        try await contextStore.upsert(HealthMdQueryContextProjector.project(seedRecord))
        keyProvider.replaceKeyData(nil)

        let sessionsRoot = sessionRoot.appendingPathComponent("file-sessions", isDirectory: true)
        let manager = MacCorpusExportSessionManager(
            rootURL: sessionsRoot,
            queryContextStore: contextStore
        )
        XCTAssertEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)

        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )

        let stored = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(contentsOf: sessionsRoot
                    .appendingPathComponent(context.session.sessionID.uuidString)
                    .appendingPathComponent("journal.json"))
            ) as? [String: Any]
        )
        XCTAssertEqual((stored["committedPartitions"] as? [[String: Any]])?.count, 1)
        XCTAssertEqual((stored["processedDates"] as? [Any])?.count, 1)
    }

    func testEncryptedContextPartitionStillFailsClosedWhenEncryptionKeyIsUnavailable() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], mode: .encryptedContext)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }

        let keyProvider = InMemoryHealthContextEncryptionKeyProvider()
        let contextStore = EncryptedHealthContextStore(
            rootURL: sessionRoot.appendingPathComponent("unavailable-agent-context", isDirectory: true),
            keyProvider: keyProvider
        )
        var seedRecord = HealthData(date: Self.day(2025, 12, 31))
        seedRecord.activity.steps = 1
        try await contextStore.upsert(HealthMdQueryContextProjector.project(seedRecord))
        keyProvider.replaceKeyData(nil)

        let manager = MacCorpusExportSessionManager(
            rootURL: sessionRoot.appendingPathComponent("agent-sessions", isDirectory: true),
            queryContextStore: contextStore
        )
        XCTAssertEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)

        do {
            try await manager.applyPartition(
                fileURL: partition.file.url,
                descriptor: partition.descriptor,
                vaultManager: vaultManager
            )
            XCTFail("Encrypted-context acquisition must fail closed without its encryption key")
        } catch {
            XCTAssertEqual(
                error as? EncryptedHealthContextStoreError,
                .missingEncryptionKey
            )
        }
    }

    func testProviderOnlyContextPartitionDoesNotProjectAppleMetricPlaceholders() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(
            requestedDates: [date],
            mode: .encryptedContext,
            selectedSourceIDs: ["whoop"]
        )
        let provider = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-01-02",
            payloads: [ExternalProviderPayload(
                name: "sleep",
                endpoint: "https://api.prod.whoop.com/developer/v2/activity/sleep",
                statusCode: 200,
                data: .object(["score": .number(88)])
            )]
        )
        let item = try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusHealthDayPayload(
                sourceDate: date,
                isRequestedDate: true,
                record: HealthData(
                    date: date,
                    healthKitRecordCaptureStatus: .notRequested
                ),
                externalDailyRecords: [provider],
                failure: nil
            ),
            kind: .macHealthDay,
            sourceDate: date,
            isRequestedDate: true
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(item)
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }

        let contextStore = EncryptedHealthContextStore(
            rootURL: sessionRoot.appendingPathComponent("provider-context", isDirectory: true),
            keyProvider: InMemoryHealthContextEncryptionKeyProvider()
        )
        let manager = MacCorpusExportSessionManager(
            rootURL: sessionRoot.appendingPathComponent("provider-sessions", isDirectory: true),
            queryContextStore: contextStore
        )
        XCTAssertEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )

        let loaded = try await contextStore.loadDay(ownerDate: "2026-01-02")
        let stored = try XCTUnwrap(loaded)
        XCTAssertTrue(stored.metrics.isEmpty)
        XCTAssertEqual(stored.status, .available)
        XCTAssertTrue(stored.evidence.contains { $0.reference.providerID == "whoop" })
    }

    func testCommittedHealthDayIsProjectedIntoEncryptedQueryContextBeforeAcknowledgement() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], mode: .encryptedContext)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }

        let contextRoot = sessionRoot.appendingPathComponent("encrypted-context", isDirectory: true)
        let contextStore = EncryptedHealthContextStore(
            rootURL: contextRoot,
            keyProvider: InMemoryHealthContextEncryptionKeyProvider()
        )
        let manager = MacCorpusExportSessionManager(
            rootURL: sessionRoot.appendingPathComponent("sessions", isDirectory: true),
            queryContextStore: contextStore
        )
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)

        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )

        let stored = try await contextStore.loadDay(ownerDate: "2026-01-02")
        XCTAssertEqual(stored?.ownerDate, "2026-01-02")
        XCTAssertEqual(
            stored?.metrics.first(where: { $0.metricID == "steps" })?.value,
            .quantity(value: 4_321, unit: "steps")
        )
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: sessionRoot
                    .appendingPathComponent("sessions", isDirectory: true)
                    .appendingPathComponent(context.session.sessionID.uuidString)
                    .appendingPathComponent("journal.json").path
            ),
            "The same application-level commit must persist its resumable journal"
        )
        XCTAssertNil(fileSystem.files[
            vaultRoot.appendingPathComponent("Health/2026-01-02.md").path
        ])

        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: vaultManager
        )
        guard case .files(let result, let acknowledgement) = outcome else {
            return XCTFail("Expected encrypted-context completion")
        }
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.totalFilesWritten, 0)
        XCTAssertEqual(acknowledgement.completedDates, [date])
    }

    func testEncryptedContextTerminalPersistFailureDoesNotExposeCompletion() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], mode: .encryptedContext)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let contextStore = EncryptedHealthContextStore(
            rootURL: sessionRoot.appendingPathComponent("terminal-context", isDirectory: true),
            keyProvider: InMemoryHealthContextEncryptionKeyProvider()
        )
        let sessionsRoot = sessionRoot.appendingPathComponent("terminal-sessions", isDirectory: true)
        let manager = MacCorpusExportSessionManager(
            rootURL: sessionsRoot,
            queryContextStore: contextStore
        )
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        manager.failNextTerminalPersistForTesting = true
        guard case .inProgress = try await manager.finalize(finalize, vaultManager: vaultManager) else {
            return XCTFail("A failed terminal journal replacement must remain resumable")
        }
        let journalURL = sessionsRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
            .appendingPathComponent("journal.json")
        let stored = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        XCTAssertEqual(stored["state"] as? String, "finalizing")
        XCTAssertNil(stored["terminalAcknowledgement"])

        guard case .files = try await manager.finalize(finalize, vaultManager: vaultManager) else {
            return XCTFail("The exact finalization must succeed after durable retry")
        }
    }

    func testStrictRawPartitionReplayReconcilesExactSpoolAfterJournalFailure() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], mode: .strictRaw)
        let item = try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusRawDayPayload(
                sourceDate: date,
                day: .missing(date: "2026-01-02")
            ),
            kind: .strictRawDay,
            sourceDate: date,
            isRequestedDate: true
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(item)
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
        manager.failNextPartitionPersistForTesting = true
        do {
            try await manager.applyPartition(
                fileURL: partition.file.url,
                descriptor: partition.descriptor,
                vaultManager: vaultManager
            )
            XCTFail("Expected the injected application-journal failure")
        } catch {
            // The exact raw spool was published before the journal replacement failed.
        }
        let rawURL = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
            .appendingPathComponent("raw/\(item.itemID.uuidString).item")
        XCTAssertTrue(FileManager.default.fileExists(atPath: rawURL.path))

        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        XCTAssertEqual(
            manager.open(open, vaultManager: vaultManager).disposition,
            .alreadyCommitted
        )
    }

    func testStrictRawPostRenameTerminalSyncFailureRetainsResultForRetry() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], mode: .strictRaw)
        let item = try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusRawDayPayload(
                sourceDate: date,
                day: .missing(date: "2026-01-02")
            ),
            kind: .strictRawDay,
            sourceDate: date,
            isRequestedDate: true
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(item)
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        manager.failNextPostRenameTerminalSyncForTesting = true
        guard case .inProgress = try await manager.finalize(finalize, vaultManager: vaultManager) else {
            return XCTFail("A post-rename strict-raw checkpoint must remain resumable")
        }
        let journalURL = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
            .appendingPathComponent("journal.json")
        let stored = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        XCTAssertEqual(stored["state"] as? String, "completed")
        XCTAssertNotNil(stored["terminalAcknowledgement"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionRoot
                .appendingPathComponent(context.session.sessionID.uuidString)
                .appendingPathComponent("raw/\(item.itemID.uuidString).item").path
        ))

        guard case .strictRaw(let spool, _) = try await MacCorpusExportSessionManager(
            rootURL: sessionRoot
        ).finalize(
            finalize,
            vaultManager: vaultManager
        ) else {
            return XCTFail("Strict raw should replay its protected terminal spool after restart")
        }
        spool.remove()
    }

    func testTerminalCleanupRejectsReboundProtectedSessionRoot() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], mode: .strictRaw)
        let item = try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusRawDayPayload(
                sourceDate: date,
                day: .missing(date: "2026-01-02")
            ),
            kind: .strictRawDay,
            sourceDate: date,
            isRequestedDate: true
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(item)
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let sessionDirectory = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString, isDirectory: true)
        let movedSession = sessionRoot
            .appendingPathComponent("terminal-moved-\(UUID().uuidString)", isDirectory: true)
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("terminal-cleanup-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outside) }
        manager.beforeProtectedCleanupForTesting = {
            try FileManager.default.moveItem(at: sessionDirectory, to: movedSession)
            try FileManager.default.createSymbolicLink(
                at: sessionDirectory,
                withDestinationURL: outside
            )
        }
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        guard case .strictRaw(let spool, _) = try await manager.finalize(
            finalize,
            vaultManager: vaultManager
        ) else {
            return XCTFail("Terminal result should remain valid even when cleanup fails closed")
        }
        spool.remove()
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testStreamableStrictRawFinalizationKeepsCanonicalDocumentDiskBackedAndExact() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], mode: .strictRaw)
        let canonical = """
        {
          "date" : "2026-01-02",
          "healthkit_record_archive" : {
            "schema" : "healthmd.healthkit_records",
            "schema_version" : 1
          },
          "schema" : "healthmd.health_data",
          "schema_version" : 8,
          "time_context" : {
            "calendar_timezone" : "UTC",
            "timestamp_timezone" : "UTC"
          },
          "type" : "health-data"
        }
        """
        let day = CanonicalRawDayResult(
            date: "2026-01-02",
            status: .complete,
            captureStatus: .complete,
            sampleCount: 1,
            recordCount: 1,
            queryStatusCounts: .init(),
            integrityWarningCount: 0,
            integrityWarningCodes: [],
            partialFailureCount: 0,
            partialFailureTypes: [],
            failureCode: nil,
            canonicalDailyJSON: canonical
        )
        let canonicalURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
            prefix: "strict-raw-production-capture-test"
        )
        try Data(canonical.utf8).write(to: canonicalURL)
        let captured = CanonicalRawCapturedDaySpool(
            day: CanonicalRawDayResult(
                date: day.date,
                status: day.status,
                captureStatus: day.captureStatus,
                sampleCount: day.sampleCount,
                recordCount: day.recordCount,
                queryStatusCounts: day.queryStatusCounts,
                integrityWarningCount: day.integrityWarningCount,
                integrityWarningCodes: day.integrityWarningCodes,
                partialFailureCount: day.partialFailureCount,
                partialFailureTypes: day.partialFailureTypes,
                failureCode: day.failureCode,
                canonicalDailyJSON: nil
            ),
            canonicalJSONFile: try ConnectedTransferFile.inspect(canonicalURL)
        )
        defer { captured.remove() }
        let item = try ConnectedCorpusSpoolItem.encodeRawDay(
            sourceDate: date,
            captured: captured,
            protocolVersion: context.session.protocolVersion
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(item)
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let sessionDirectory = sessionRoot.appendingPathComponent(
            context.session.sessionID.uuidString,
            isDirectory: true
        )
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionDirectory.appendingPathComponent(
                "raw/\(item.itemID.uuidString).health-data.json"
            ).path
        ))
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        guard case .strictRaw(let spool, let acknowledgement) = try await manager.finalize(
            finalize,
            vaultManager: vaultManager
        ) else {
            return XCTFail("Expected strict raw result")
        }
        defer { spool.remove() }
        XCTAssertEqual(acknowledgement.successCount, 1)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: spool.file.url)) as? [String: Any]
        )
        let days = try XCTUnwrap(object["days"] as? [[String: Any]])
        let healthData = try XCTUnwrap(days.first?["health_data"] as? [String: Any])
        XCTAssertEqual(healthData["schema"] as? String, HealthMdExportSchema.identifier)
        XCTAssertEqual(healthData["schema_version"] as? Int, HealthMdExportSchema.version)
        XCTAssertEqual(
            (healthData["healthkit_record_archive"] as? [String: Any])?["schema"] as? String,
            HealthKitRecordArchive.canonicalSchemaIdentifier
        )
    }

    func testStrictRawMissingDayBytesReplayAfterRestartAndLostAcknowledgement() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], mode: .strictRaw)
        let item = try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusRawDayPayload(
                sourceDate: date,
                day: .missing(date: "2026-01-02")
            ),
            kind: .strictRawDay,
            sourceDate: date,
            isRequestedDate: true
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(item)
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        let outcome = try await manager.finalize(finalize, vaultManager: vaultManager)
        guard case .strictRaw(let spool, let acknowledgement) = outcome else {
            return XCTFail("Expected strict raw completion")
        }
        XCTAssertEqual(spool.captureSummary.retainedDayCount, 0)
        XCTAssertEqual(acknowledgement.successCount, 0)
        spool.remove()

        let restarted = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let recovered = try await restarted.finalize(
            finalize,
            vaultManager: vaultManager
        )
        guard case .strictRaw(let recoveredSpool, let recoveredAcknowledgement) = recovered else {
            return XCTFail("A restart before control-response installation must replay exact raw bytes")
        }
        XCTAssertEqual(recoveredAcknowledgement, acknowledgement)
        XCTAssertEqual(recoveredSpool.file.sha256, spool.file.sha256)
        XCTAssertEqual(recoveredSpool.captureSummary, spool.captureSummary)
        recoveredSpool.remove()
        let protectedTerminalURL = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
            .appendingPathComponent("terminal/strict-raw-result.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedTerminalURL.path))

        let replay = try await MacCorpusExportSessionManager(rootURL: sessionRoot).finalize(
            finalize,
            vaultManager: vaultManager
        )
        guard case .strictRaw(let replaySpool, let replayAcknowledgement) = replay else {
            return XCTFail("A lost ACK must replay bytes so the coordinator can revalidate")
        }
        XCTAssertEqual(replayAcknowledgement, acknowledgement)
        XCTAssertEqual(replaySpool.file.sha256, recoveredSpool.file.sha256)
        replaySpool.remove()
        XCTAssertTrue(FileManager.default.fileExists(atPath: protectedTerminalURL.path))
    }

    func testDailyNotesOnlyCorpusWritesNoAdditionalFiles() async throws {
        let vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-daily-notes-only-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultRoot) }

        let realVault = VaultManager(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        realVault.setVaultFolder(vaultRoot)
        let settings = makeSettings()
        settings.exportFormats = []
        settings.archiveExportFiles = true
        settings.generateWeeklyRollups = true
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.setTrackIndividually("steps", enabled: true)
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"

        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date], settings: settings)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )

        XCTAssertEqual(manager.open(open, vaultManager: realVault).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: realVault
        )
        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: realVault
        )
        guard case .files(let result, _) = outcome else {
            return XCTFail("Expected file result")
        }

        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.totalFilesWritten, 0)
        XCTAssertEqual(result.dailyNoteUpdateCount, 1)
        XCTAssertEqual(result.formatsPerDate, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vaultRoot.path), ["Daily"])
    }

    func testArchiveIncludesRequestedDailyFilesButUsesSupportDaysOnlyForRollups() async throws {
        let vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-support-archive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultRoot) }
        let realVault = VaultManager(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        realVault.setVaultFolder(vaultRoot)
        let supportDate = Self.day(2026, 1, 1)
        let requestedDate = Self.day(2026, 1, 15)
        let settings = makeSettings()
        settings.archiveExportFiles = true
        settings.generateMonthlyRollups = true
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"
        settings.dailyNoteInjection.filenamePattern = "{date}"
        let context = try makeContext(
            requestedDates: [requestedDate],
            settings: settings,
            transferDates: [supportDate, requestedDate]
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        let externalRecord = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-01-15",
            payloads: [ExternalProviderPayload(
                name: "recovery",
                endpoint: "https://api.prod.whoop.com/developer/v2/recovery",
                statusCode: 200,
                data: .object(["score": .number(95)])
            )]
        )
        assembler.append(try healthItem(date: supportDate, isRequestedDate: false))
        assembler.append(try healthItem(date: requestedDate, externalDailyRecords: [externalRecord]))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertNotEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: realVault
        ).disposition, .reject)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: realVault
        )
        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: realVault
        )
        guard case .files(let result, _) = outcome else { return XCTFail("Expected file result") }
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.externalRecordFileCount, 1)
        let dailyNoteURL = ExportPathPlanner.dailyNoteURL(
            vaultURL: vaultRoot,
            settings: settings.dailyNoteInjection,
            date: requestedDate
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: dailyNoteURL.path))
        let archiveURL = vaultRoot
            .appendingPathComponent("Health")
            .appendingPathComponent("Health.md Export 2026-01-15.zip")
        let listing = try unzipListing(archiveURL)
        XCTAssertTrue(listing.contains("2026-01-15.md"), listing)
        XCTAssertFalse(listing.contains("2026-01-01.md"), listing)
        XCTAssertTrue(listing.contains("2026-01.md"), listing)
    }

    func testFailedSupportingDaySuppressesRollupAndKeepsRequestedDateRetryable() async throws {
        let supportDate = Self.day(2026, 1, 1)
        let requestedDate = Self.day(2026, 1, 15)
        let settings = makeSettings()
        settings.generateMonthlyRollups = true
        let context = try makeContext(
            requestedDates: [requestedDate],
            settings: settings,
            transferDates: [supportDate, requestedDate]
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusHealthDayPayload(
                sourceDate: supportDate,
                isRequestedDate: false,
                record: nil,
                externalDailyRecords: [],
                failure: FailedDateDetail(date: supportDate, reason: .healthKitError)
            ),
            kind: .macHealthDay,
            sourceDate: supportDate,
            isRequestedDate: false
        ))
        assembler.append(try healthItem(date: requestedDate))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertNotEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .reject)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: vaultManager
        )
        guard case .files(let result, _) = outcome else { return XCTFail("Expected file result") }
        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertEqual(result.failedDateDetails.map(\.date), [requestedDate])
        XCTAssertEqual(result.completedDates, [])
        XCTAssertFalse(fileSystem.files.keys.contains { $0.contains("/Rollups/") })
    }

    func testFailedRequestedDaySuppressesSharedRollupWindow() async throws {
        let failedDate = Self.day(2026, 1, 1)
        let successfulDate = Self.day(2026, 1, 15)
        let settings = makeSettings()
        settings.generateMonthlyRollups = true
        let context = try makeContext(
            requestedDates: [failedDate, successfulDate],
            settings: settings
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusHealthDayPayload(
                sourceDate: failedDate,
                isRequestedDate: true,
                record: nil,
                externalDailyRecords: [],
                failure: FailedDateDetail(date: failedDate, reason: .healthKitError)
            ),
            kind: .macHealthDay,
            sourceDate: failedDate,
            isRequestedDate: true
        ))
        assembler.append(try healthItem(date: successfulDate))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertNotEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .reject)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 1,
                totalByteCount: partition.descriptor.byteCount,
                finalPartitionSHA256: partition.descriptor.sha256
            ),
            vaultManager: vaultManager
        )
        guard case .files(let result, _) = outcome else { return XCTFail("Expected file result") }
        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertEqual(Set(result.failedDateDetails.map(\.date)), Set([failedDate, successfulDate]))
        XCTAssertEqual(result.completedDates, [])
        XCTAssertFalse(fileSystem.files.keys.contains { $0.contains("/Rollups/") })
    }

    func testSourceTimeZoneOwnsDailyFilenameOnMac() async throws {
        let sourceTimeZone = TimeZone(identifier: "Pacific/Kiritimati")!
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let sourceDate = sourceCalendar.date(from: DateComponents(year: 2026, month: 1, day: 2))!
        let context = try makeContext(
            requestedDates: [sourceDate],
            sourceTimeZoneIdentifier: sourceTimeZone.identifier
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: sourceDate))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertNotEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .reject)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        XCTAssertNotNil(fileSystem.files[
            vaultRoot.appendingPathComponent("Health/2026-01-02.md").path
        ])
    }

    func testNewManagerResumesAtNextDurablyCommittedPartition() async throws {
        let firstDate = Self.day(2026, 1, 2)
        let secondDate = Self.day(2026, 1, 3)
        let context = try makeContext(requestedDates: [firstDate, secondDate])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: firstDate))
        let first = try XCTUnwrap(assembler.makeNextPartition(force: true))
        assembler.append(try healthItem(date: secondDate))
        let second = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { first.remove(); second.remove() }

        var manager: MacCorpusExportSessionManager? = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(manager?.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: first.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .accept)
        try await manager?.applyPartition(
            fileURL: first.file.url,
            descriptor: first.descriptor,
            vaultManager: vaultManager
        )
        manager = nil

        let journalURL = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
            .appendingPathComponent("journal.json")
        var legacyJournal = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        legacyJournal["version"] = 3
        legacyJournal.removeValue(forKey: "receivedRangePlanPersisted")
        legacyJournal.removeValue(forKey: "receivedRangePlan")
        legacyJournal.removeValue(forKey: "protectedSessionDeviceID")
        legacyJournal.removeValue(forKey: "protectedSessionInode")
        legacyJournal["recordItems"] = (legacyJournal["recordItems"] as? [[String: Any]])?.map {
            var item = $0
            item.removeValue(forKey: "byteCount")
            item.removeValue(forKey: "sha256")
            return item
        }
        legacyJournal["rawItems"] = (legacyJournal["rawItems"] as? [[String: Any]])?.map {
            var item = $0
            item.removeValue(forKey: "byteCount")
            item.removeValue(forKey: "sha256")
            return item
        }
        legacyJournal["partialItems"] = (legacyJournal["partialItems"] as? [[String: Any]])?.map {
            var item = $0
            item.removeValue(forKey: "prefixSHA256")
            return item
        }
        try JSONSerialization.data(withJSONObject: legacyJournal, options: [.sortedKeys])
            .write(to: journalURL, options: .atomic)

        let restored = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let disposition = restored.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: second.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        )
        XCTAssertEqual(disposition.disposition, .resume)
        XCTAssertEqual(disposition.nextPartitionIndex, 1)
        let migratedJournal = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        XCTAssertEqual(migratedJournal["version"] as? Int, 5)
        XCTAssertEqual(migratedJournal["receivedRangePlanPersisted"] as? Bool, false)
        try await restored.applyPartition(
            fileURL: second.file.url,
            descriptor: second.descriptor,
            vaultManager: vaultManager
        )
        let outcome = try await restored.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: 2,
                totalByteCount: first.descriptor.byteCount + second.descriptor.byteCount,
                finalPartitionSHA256: second.descriptor.sha256
            ),
            vaultManager: vaultManager
        )
        guard case .files(let result, _) = outcome else { return XCTFail("Expected file result") }
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.completedDates, [firstDate, secondDate])
    }

    func testArchiveAndMonthlyRollupFinalizeAcrossPartitionBoundaries() async throws {
        let vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-archive-vault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultRoot) }
        let realVault = VaultManager(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        realVault.setVaultFolder(vaultRoot)
        let firstDate = Self.day(2026, 1, 1)
        let secondDate = Self.day(2026, 1, 31)
        let settings = makeSettings()
        settings.archiveExportFiles = true
        settings.generateMonthlyRollups = true
        let context = try makeContext(requestedDates: [firstDate, secondDate], settings: settings)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        var partitions: [ConnectedCorpusPreparedPartition] = []
        for date in [firstDate, secondDate] {
            assembler.append(try healthItem(date: date))
            let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
            partitions.append(partition)
            let disposition = manager.open(
                ConnectedCorpusTransferOpen(
                    session: context.session,
                    partition: partition.descriptor,
                    exportManifest: context.manifest
                ),
                vaultManager: realVault
            )
            XCTAssertNotEqual(disposition.disposition, .reject)
            try await manager.applyPartition(
                fileURL: partition.file.url,
                descriptor: partition.descriptor,
                vaultManager: realVault
            )
        }
        defer { partitions.forEach { $0.remove() } }

        let outcome = try await manager.finalize(
            ConnectedCorpusTransferFinalize(
                sessionID: context.session.sessionID,
                jobID: context.session.jobID,
                requestFingerprint: context.session.requestFingerprint,
                partitionCount: partitions.count,
                totalByteCount: partitions.reduce(0) { $0 + $1.descriptor.byteCount },
                finalPartitionSHA256: partitions.last?.descriptor.sha256
            ),
            vaultManager: realVault
        )
        guard case .files(let result, _) = outcome else { return XCTFail("Expected file result") }
        XCTAssertEqual(result.status, .success)
        XCTAssertEqual(result.completedDates, [firstDate, secondDate])
        XCTAssertEqual(result.totalFilesWritten, 1)
        let archiveURL = vaultRoot
            .appendingPathComponent("Health")
            .appendingPathComponent("Health.md Export 2026-01-01_to_2026-01-31.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        let listing = try unzipListing(archiveURL)
        XCTAssertTrue(listing.contains("2026-01-01.md"))
        XCTAssertTrue(listing.contains("2026-01-31.md"))
        XCTAssertTrue(listing.contains("2026-01.md"), listing)
    }

    func testCancellationDuringFinalizationCannotBeOverwrittenBySuccess() async throws {
        let vaultRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("corpus-finalize-cancel-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultRoot) }
        let realVault = VaultManager(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        realVault.setVaultFolder(vaultRoot)
        let date = Self.day(2026, 1, 15)
        let settings = makeSettings()
        settings.archiveExportFiles = true
        let context = try makeContext(requestedDates: [date], settings: settings)
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertNotEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: realVault
        ).disposition, .reject)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: realVault
        )
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        var cancellationTask: Task<MacExportResultPayload?, Never>?
        do {
            _ = try await manager.finalize(
                finalize,
                vaultManager: realVault,
                progress: { processed, _, _ in
                    guard processed == 1, cancellationTask == nil else { return }
                    cancellationTask = Task { @MainActor in
                        manager.cancel(
                            sessionID: context.session.sessionID,
                            jobID: context.session.jobID,
                            vaultManager: realVault
                        ).1
                    }
                }
            )
            XCTFail("Cancellation must not be overwritten by a successful final acknowledgement")
        } catch is CancellationError {
            // Expected: cancellation wins the race at the final cooperative yield.
        }
        let cancelledResult = await cancellationTask?.value
        XCTAssertEqual(cancelledResult?.status, .cancelled)
        XCTAssertEqual(cancelledResult?.completedDates, [])
        do {
            _ = try await manager.finalize(finalize, vaultManager: realVault)
            XCTFail("A cancelled journal must not replay a successful finalization")
        } catch {}
    }

    func testCompletedItemIDCannotBeReusedInLaterPartition() async throws {
        let date = Self.day(2026, 1, 1)
        let context = try makeContext(requestedDates: [date])
        let reusedItemID = UUID()
        let firstAssembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
        )
        firstAssembler.append(try healthItem(date: date, itemID: reusedItemID))
        let first = try XCTUnwrap(firstAssembler.makeNextPartition(force: true))
        defer { first.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertNotEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: first.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .reject)
        try await manager.applyPartition(
            fileURL: first.file.url,
            descriptor: first.descriptor,
            vaultManager: vaultManager
        )

        let secondAssembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes,
            nextPartitionIndex: 1,
            previousPartitionSHA256: first.descriptor.sha256
        )
        secondAssembler.append(try healthItem(date: date, itemID: reusedItemID))
        let second = try XCTUnwrap(secondAssembler.makeNextPartition(force: true))
        defer { second.remove() }
        XCTAssertNotEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: second.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .reject)
        do {
            try await manager.applyPartition(
                fileURL: second.file.url,
                descriptor: second.descriptor,
                vaultManager: vaultManager
            )
            XCTFail("Expected completed item identity reuse to be rejected")
        } catch {}
    }

    func testFailedPartitionRollsBackInMemoryCompletionBeforeCancellation() async throws {
        let firstDate = Self.day(2026, 1, 1)
        let secondDate = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [firstDate, secondDate])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
        )
        assembler.append(try healthItem(date: firstDate))
        let invalidURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "invalid-corpus-item")
        try Data("not-json".utf8).write(to: invalidURL)
        defer { try? FileManager.default.removeItem(at: invalidURL) }
        assembler.append(ConnectedCorpusSpoolItem(
            itemID: UUID(),
            kind: .macHealthDay,
            sourceDate: secondDate,
            isRequestedDate: true,
            file: try ConnectedTransferFile.inspect(invalidURL)
        ))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertNotEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .reject)
        do {
            try await manager.applyPartition(
                fileURL: partition.file.url,
                descriptor: partition.descriptor,
                vaultManager: vaultManager
            )
            XCTFail("Expected invalid second item to reject the whole partition")
        } catch {}
        let (_, result) = manager.cancel(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            vaultManager: vaultManager
        )
        XCTAssertEqual(result?.completedDates, [])
        XCTAssertEqual(result?.successCount, 0)
    }

    func testDisconnectDuringPartitionWriteDefersSuspensionUntilJournalCommit() async throws {
        let date = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [date])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: date))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
        let outputPath = vaultRoot.appendingPathComponent("Health/2026-01-02.md").path
        let writeStarted = expectation(description: "partition destination write started")
        writeStarted.assertForOverFulfill = false
        let blocker = DispatchSemaphore(value: 0)
        fileSystem.writeStarted = { _ in writeStarted.fulfill() }
        fileSystem.writeBlocker = blocker
        defer {
            fileSystem.writeStarted = nil
            fileSystem.writeBlocker = nil
            blocker.signal()
        }
        let applyTask = Task { @MainActor in
            try await manager.applyPartition(
                fileURL: partition.file.url,
                descriptor: partition.descriptor,
                vaultManager: vaultManager
            )
        }
        await fulfillment(of: [writeStarted], timeout: 2)
        manager.suspendForDisconnect()
        XCTAssertTrue(manager.isBusy, "in-flight partition ownership must not detach early")
        blocker.signal()
        try await applyTask.value
        XCTAssertFalse(manager.isBusy)
        XCTAssertEqual(fileSystem.writeCounts[outputPath], 1)

        let restored = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertEqual(restored.open(open, vaultManager: vaultManager).disposition, .alreadyCommitted)
        try await restored.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        XCTAssertEqual(fileSystem.writeCounts[outputPath], 1)
    }

    func testSuspendedDisconnectJournalCanBeCancelledWithExactProgress() async throws {
        let firstDate = Self.day(2026, 1, 1)
        let secondDate = Self.day(2026, 1, 2)
        let context = try makeContext(requestedDates: [firstDate, secondDate])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
        )
        assembler.append(try healthItem(date: firstDate))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertNotEqual(manager.open(
            ConnectedCorpusTransferOpen(
                session: context.session,
                partition: partition.descriptor,
                exportManifest: context.manifest
            ),
            vaultManager: vaultManager
        ).disposition, .reject)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        manager.suspendForDisconnect()
        XCTAssertFalse(manager.isBusy)
        let (acknowledgement, result) = manager.cancel(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            vaultManager: vaultManager
        )
        XCTAssertTrue(acknowledgement.accepted)
        XCTAssertEqual(result?.completedDates, [firstDate])
    }

    func testPinnedRangePlanCancellationDoesNotCountCapturedDateBeforeDestinationWrite() async throws {
        let interrupted = try await prepareInterruptedPinnedRange(failAfterDictionaryWrite: false)
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)

        let (acknowledgement, result) = manager.cancel(
            sessionID: interrupted.sessionID,
            jobID: interrupted.finalize.jobID,
            vaultManager: vaultManager
        )

        XCTAssertTrue(acknowledgement.accepted)
        XCTAssertEqual(result?.status, .cancelled)
        XCTAssertEqual(result?.successCount, 0)
        XCTAssertEqual(result?.completedDates, [])
        XCTAssertEqual(result?.formatsPerDate, 1)
        XCTAssertEqual(result?.totalFilesWritten, 0)
        XCTAssertEqual(result?.hasConsistentFileAccounting, true)
        XCTAssertNil(
            fileSystem.writeCounts[
                vaultRoot.appendingPathComponent("Health/2026-03-02.json").path
            ]
        )
    }

    func testCancellationReturnsExactDurablyCompletedDates() async throws {
        let firstDate = Self.day(2026, 1, 2)
        let secondDate = Self.day(2026, 1, 3)
        let context = try makeContext(requestedDates: [firstDate, secondDate])
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: firstDate))
        let first = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { first.remove() }

        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        XCTAssertNotEqual(
            manager.open(
                ConnectedCorpusTransferOpen(
                    session: context.session,
                    partition: first.descriptor,
                    exportManifest: context.manifest
                ),
                vaultManager: vaultManager
            ).disposition,
            .reject
        )
        try await manager.applyPartition(
            fileURL: first.file.url,
            descriptor: first.descriptor,
            vaultManager: vaultManager
        )

        let (acknowledgement, result) = manager.cancel(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            vaultManager: vaultManager
        )
        XCTAssertTrue(acknowledgement.accepted)
        XCTAssertEqual(result?.status, .cancelled)
        XCTAssertEqual(result?.successCount, 1)
        XCTAssertEqual(result?.completedDates, [firstDate])
        XCTAssertEqual(result?.totalCount, 2)
        XCTAssertEqual(result?.totalFilesWritten, 1)
        XCTAssertEqual(result?.dailyNoteUpdateCount, 0)
        XCTAssertEqual(result?.dailyNoteSkipCount, 0)
        XCTAssertEqual(result?.hasConsistentFileAccounting, true)
    }

    private func prepareInterruptedPinnedRange(
        failAfterDictionaryWrite: Bool,
        failAfterRangePlanJournalPublication: Bool = false
    ) async throws -> (
        finalize: ConnectedCorpusTransferFinalize,
        sessionID: UUID,
        requestedDate: Date,
        open: ConnectedCorpusTransferOpen
    ) {
        let requestedDate = Self.day(2026, 3, 2)
        let supportingDate = Self.day(2026, 3, 3)
        let record = HealthData(date: requestedDate, activity: ActivityData(steps: 4_321))
        let settings = makeSettings()
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        settings.generateWeeklyRollups = true
        let snapshot = try await makePinnedSnapshot(
            engine: .shadow,
            settings: settings,
            record: record
        )
        let context = try makeContext(
            requestedDates: [requestedDate],
            settings: settings,
            settingsSnapshot: snapshot,
            sourceTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier,
            transferDates: [requestedDate, supportingDate]
        )
        let assembler = try ConnectedCorpusPartitionAssembler(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            targetBytes: context.session.partitionTargetBytes
        )
        assembler.append(try healthItem(date: requestedDate))
        assembler.append(try healthItem(date: supportingDate, isRequestedDate: false))
        let partition = try XCTUnwrap(assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: sessionRoot)
        let open = ConnectedCorpusTransferOpen(
            session: context.session,
            partition: partition.descriptor,
            exportManifest: context.manifest
        )
        XCTAssertEqual(manager.open(
            open,
            vaultManager: vaultManager
        ).disposition, .accept)
        try await manager.applyPartition(
            fileURL: partition.file.url,
            descriptor: partition.descriptor,
            vaultManager: vaultManager
        )
        let dictionaryPath = vaultRoot
            .appendingPathComponent("Health")
            .appendingPathComponent(HealthMdExportSchema.dataDictionaryFilename).path
        if failAfterRangePlanJournalPublication {
            manager.failNextPostRenameRangePlanSyncForTesting = true
        } else if failAfterDictionaryWrite {
            fileSystem.failAfterWritingPathOnce = dictionaryPath
        } else {
            fileSystem.failBeforeWritingPathOnce = dictionaryPath
        }
        let finalize = ConnectedCorpusTransferFinalize(
            sessionID: context.session.sessionID,
            jobID: context.session.jobID,
            requestFingerprint: context.session.requestFingerprint,
            partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount,
            finalPartitionSHA256: partition.descriptor.sha256
        )
        let outcome = try await manager.finalize(finalize, vaultManager: vaultManager)
        guard case .inProgress = outcome else {
            throw NSError(
                domain: "MacCorpusExportSessionManagerTests",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Expected interrupted durable finalization"]
            )
        }
        let journalURL = sessionRoot
            .appendingPathComponent(context.session.sessionID.uuidString)
            .appendingPathComponent("journal.json")
        let journalObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        XCTAssertEqual(journalObject["receivedRangePlanPersisted"] as? Bool, true)
        XCTAssertNotNil(journalObject["receivedRangePlan"])
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: sessionRoot
                .appendingPathComponent(context.session.sessionID.uuidString)
                .appendingPathComponent("finalization/artifacts/0000.artifact").path
        ))
        return (finalize, context.session.sessionID, requestedDate, open)
    }

    private func makeContext(
        requestedDates: [Date],
        mode: ConnectedCorpusExportMode = .writeFiles,
        settings suppliedSettings: AdvancedExportSettings? = nil,
        settingsSnapshot suppliedSettingsSnapshot: ExportSettingsSnapshot? = nil,
        sourceTimeZoneIdentifier: String? = nil,
        transferDates suppliedTransferDates: [Date]? = nil,
        selectedSourceIDs: [String]? = nil
    ) throws -> (
        manifest: ConnectedCorpusExportManifest,
        session: ConnectedCorpusTransferSession
    ) {
        let settings = suppliedSettings ?? makeSettings()
        let scopedSourceIDs = selectedSourceIDs ?? ["apple_health"]
        let canonicalSelection = mode == .encryptedContext
            ? CanonicalHealthDataSelection(
                metricIDs: Array(settings.metricSelection.enabledMetrics),
                sourceIDs: scopedSourceIDs
            )
            : nil
        let requestedDateIdentifiers: [String]? = mode == .strictRaw
            ? requestedDates.map {
                let formatter = DateFormatter()
                formatter.calendar = Calendar(identifier: .gregorian)
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = .current
                formatter.dateFormat = "yyyy-MM-dd"
                return formatter.string(from: $0)
            }
            : nil
        let manifest = ConnectedCorpusExportManifest(
            mode: mode,
            createdAt: Date(),
            sourceDeviceName: "Test iPhone",
            sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
            dateRangeStart: requestedDates.first!,
            dateRangeEnd: requestedDates.last!,
            requestedDates: requestedDates,
            requestedDateIdentifiers: requestedDateIdentifiers,
            transferDates: suppliedTransferDates ?? requestedDates,
            settingsSnapshot: suppliedSettingsSnapshot
                ?? .from(settings, healthSubfolder: "Health"),
            rawProfile: mode == .strictRaw ? .canonicalSourceRecordsV1 : nil,
            canonicalSelection: canonicalSelection,
            selectedSourceIDs: mode == .encryptedContext ? scopedSourceIDs : selectedSourceIDs,
            requestedTarget: mode == .writeFiles ? ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: "Connected Mac",
                destinationDisplayName: "CorpusVault"
            ) : nil
        )
        let session = ConnectedCorpusTransferSession(
            sessionID: UUID(),
            jobID: UUID(),
            requestFingerprint: try .make(for: manifest),
            partitionTargetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes,
            createdAt: Date()
        )
        return (manifest, session)
    }

    private func makePinnedSnapshot(
        engine: ExportEngineMode,
        settings: AdvancedExportSettings,
        record: HealthData
    ) async throws -> ExportSettingsSnapshot {
        let calendarTimeZoneIdentifier = record.timeContext.calendarTimeZoneIdentifier
        let pin = await AppleExportEnginePolicyResolver(
            injectedOverride: engine.rawValue,
            userDefaults: nil,
            environment: [:]
        ).pinForNewOperation(calendarTimeZoneIdentifier: calendarTimeZoneIdentifier)
        return ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEnginePin: try XCTUnwrap(pin),
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
        )
    }

    private func healthItem(
        date: Date,
        isRequestedDate: Bool = true,
        itemID: UUID = UUID(),
        externalDailyRecords: [ExternalDailyRecord] = []
    ) throws -> ConnectedCorpusSpoolItem {
        var record = HealthData(date: date)
        record.activity.steps = 4_321
        return try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusHealthDayPayload(
                sourceDate: date,
                isRequestedDate: isRequestedDate,
                record: record,
                externalDailyRecords: externalDailyRecords,
                failure: nil
            ),
            kind: .macHealthDay,
            sourceDate: date,
            isRequestedDate: isRequestedDate,
            itemID: itemID
        )
    }

    private func failedHealthItem(
        date: Date,
        isRequestedDate: Bool
    ) throws -> ConnectedCorpusSpoolItem {
        try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusHealthDayPayload(
                sourceDate: date,
                isRequestedDate: isRequestedDate,
                record: nil,
                externalDailyRecords: [],
                failure: FailedDateDetail(date: date, reason: .healthKitError)
            ),
            kind: .macHealthDay,
            sourceDate: date,
            isRequestedDate: isRequestedDate,
            itemID: UUID()
        )
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suite = "MacCorpusExportSessionManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.markdown]
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        settings.writeMode = .overwrite
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        return settings
    }

    private func unzipListing(_ archiveURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-Z1", archiveURL.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        ) ?? ""
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day))!
    }
}

@MainActor
private final class RejectingConnectedRangePlanner: AppleLooseDailyRangeExportPlanning {
    private(set) var callCount = 0

    func plan(
        healthData: HealthData,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) async throws -> AppleLooseDailyPlanResolution {
        callCount += 1
        throw NSError(
            domain: "RejectingConnectedRangePlanner",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Renderer must not run during durable resume"]
        )
    }

    func planRange(
        healthData: [HealthData],
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) async throws -> AppleLooseDailyPlanResolution {
        callCount += 1
        throw NSError(
            domain: "RejectingConnectedRangePlanner",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Renderer must not run during durable resume"]
        )
    }

    func planRange(
        healthData: [HealthData],
        dailyOutputOwnerDates: Set<String>,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface,
        operationIdentity: AppleExportOperationIdentity?
    ) async throws -> AppleLooseDailyPlanResolution {
        callCount += 1
        throw NSError(
            domain: "RejectingConnectedRangePlanner",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Renderer must not run during durable resume"]
        )
    }
}
#endif
