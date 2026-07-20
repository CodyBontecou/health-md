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
        vaultManager.setVaultFolder(URL(fileURLWithPath: "/tmp/CorpusVault"))
        sessionRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("mac-corpus-tests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let sessionRoot { try? FileManager.default.removeItem(at: sessionRoot) }
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
        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
        XCTAssertTrue(manager.consumeAdmission(for: partition.descriptor))
        XCTAssertFalse(manager.consumeAdmission(for: partition.descriptor))

        XCTAssertEqual(manager.open(open, vaultManager: vaultManager).disposition, .accept)
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
        let exportedPath = "/tmp/CorpusVault/Health/2026-01-02.md"
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
        XCTAssertNotNil(fileSystem.files["/tmp/CorpusVault/Health/2026-01-02.md"])
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
        XCTAssertEqual(result?.completedDates, [firstDate])
        XCTAssertEqual(result?.totalCount, 2)
    }

    private func makeContext(
        requestedDates: [Date],
        settings suppliedSettings: AdvancedExportSettings? = nil,
        sourceTimeZoneIdentifier: String? = nil,
        transferDates suppliedTransferDates: [Date]? = nil
    ) throws -> (
        manifest: ConnectedCorpusExportManifest,
        session: ConnectedCorpusTransferSession
    ) {
        let settings = suppliedSettings ?? makeSettings()
        let manifest = ConnectedCorpusExportManifest(
            mode: .writeFiles,
            createdAt: Date(),
            sourceDeviceName: "Test iPhone",
            sourceTimeZoneIdentifier: sourceTimeZoneIdentifier,
            dateRangeStart: requestedDates.first!,
            dateRangeEnd: requestedDates.last!,
            requestedDates: requestedDates,
            transferDates: suppliedTransferDates ?? requestedDates,
            settingsSnapshot: .from(settings, healthSubfolder: "Health"),
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: "Connected Mac",
                destinationDisplayName: "CorpusVault"
            )
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
#endif
