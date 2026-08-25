//
//  VaultManagerTests.swift
//  HealthMdTests
//
//  Tests for VaultManager bookmark management, vault selection,
//  export path construction, and write modes using injected fakes.
//

import XCTest
@testable import HealthMd

// MARK: - FakeBookmarkResolver

final class FakeVaultFolderIdentityProbe: VaultFolderIdentityProbing {
    var identitiesByPath: [String: VaultFolderIdentity?] = [:]
    var defaultIdentity: VaultFolderIdentity?
    var error: Error?
    var calls: [URL] = []

    func persistentIdentity(for url: URL) throws -> VaultFolderIdentity? {
        calls.append(url)
        if let error { throw error }
        if let configured = identitiesByPath[url.standardizedFileURL.path] {
            return configured
        }
        return defaultIdentity
    }
}

final class FakeBookmarkResolver: BookmarkResolving {
    var resolvedURL: URL?
    var resolvedIsStale = false
    var resolveError: Error?
    var resolutionResults: [Result<(url: URL, isStale: Bool), Error>] = []
    var resolveCalls: [Data] = []
    var createdBookmarkData: Data?
    var createError: Error?
    var createBookmarkCalls: [URL] = []
    var accessGranted = true
    var startAccessCalls: [URL] = []
    var stopAccessCalls: [URL] = []

    func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool) {
        resolveCalls.append(data)
        if !resolutionResults.isEmpty {
            return try resolutionResults.removeFirst().get()
        }
        if let error = resolveError { throw error }
        guard let url = resolvedURL else {
            throw NSError(domain: "FakeBookmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "No URL configured"])
        }
        return (url, resolvedIsStale)
    }

    func createBookmarkData(for url: URL) throws -> Data {
        createBookmarkCalls.append(url)
        if let error = createError { throw error }
        return createdBookmarkData ?? Data("fake-bookmark-\(url.lastPathComponent)".utf8)
    }

    func startAccessing(_ url: URL) -> Bool {
        startAccessCalls.append(url)
        return accessGranted
    }

    func stopAccessing(_ url: URL) {
        stopAccessCalls.append(url)
    }
}

nonisolated private final class SlowRecordingFileSystem: FileSystemAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: String] = [:]
    private var directories: Set<String> = []
    private var writeStartedStorage = false
    private var writeFinishedStorage = false
    private var writeWasOnMainThreadStorage = false
    private var activeWrites = 0
    private var maximumConcurrentWritesStorage = 0

    var writeStarted: Bool {
        lock.withLock { writeStartedStorage }
    }

    var writeFinished: Bool {
        lock.withLock { writeFinishedStorage }
    }

    var writeWasOnMainThread: Bool {
        lock.withLock { writeWasOnMainThreadStorage }
    }

    var maximumConcurrentWrites: Int {
        lock.withLock { maximumConcurrentWritesStorage }
    }

    func fileExists(atPath path: String) -> Bool {
        lock.withLock { files[path] != nil || directories.contains(path) }
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        lock.withLock { _ = directories.insert(url.path) }
    }

    func contentsOfFile(at url: URL) throws -> String {
        try lock.withLock {
            guard let content = files[url.path] else {
                throw CocoaError(.fileReadNoSuchFile)
            }
            return content
        }
    }

    func writeString(_ string: String, to url: URL, atomically: Bool) throws {
        lock.withLock {
            writeStartedStorage = true
            writeWasOnMainThreadStorage = Thread.isMainThread
            activeWrites += 1
            maximumConcurrentWritesStorage = max(maximumConcurrentWritesStorage, activeWrites)
        }
        Thread.sleep(forTimeInterval: 0.3)
        lock.withLock {
            files[url.path] = string
            activeWrites -= 1
            writeFinishedStorage = true
        }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] { [] }

    func removeItem(at url: URL) throws {
        lock.withLock {
            files.removeValue(forKey: url.path)
            directories.remove(url.path)
        }
    }
}

nonisolated private final class SecureCommitHookProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var executionCountStorage = 0
    private var cancellationRequestedStorage = false

    var executionCount: Int { lock.withLock { executionCountStorage } }
    var cancellationRequested: Bool { lock.withLock { cancellationRequestedStorage } }

    func record() {
        lock.withLock { executionCountStorage += 1 }
    }

    func requestCancellation() {
        lock.withLock { cancellationRequestedStorage = true }
    }
}

// MARK: - Tests

@MainActor
final class VaultManagerTests: XCTestCase {

    // STATIC RETENTION JUSTIFICATION: VaultManager and AdvancedExportSettings are
    // ObservableObjects with nested observable properties. Static retention avoids
    // macOS 26 / Swift 6 deinit crash. See docs/testing/lifecycle-audit.md.
    private static var retainedManagers: [VaultManager] = []
    private static var retainedSettings: [AdvancedExportSettings] = []

    private var defaults: FakeUserDefaults!
    private var fileSystem: FakeFileSystem!
    private var fileCoordinator: RecordingFileCoordinator!
    private var bookmarkResolver: FakeBookmarkResolver!
    private var identityProbe: FakeVaultFolderIdentityProbe!

    override func setUp() {
        super.setUp()
        defaults = FakeUserDefaults()
        fileSystem = FakeFileSystem()
        fileCoordinator = RecordingFileCoordinator()
        bookmarkResolver = FakeBookmarkResolver()
        identityProbe = FakeVaultFolderIdentityProbe()
    }

    private func seedLegacySelection(for url: URL) {
        defaults.storage["obsidianVaultPath"] = url.path
        defaults.storage["obsidianVaultName"] = url.lastPathComponent
    }

    private func identity(_ value: String, volume: String = "volume") -> VaultFolderIdentity {
        let fileIdentifier = value.utf8.reduce(UInt64(0)) { partial, byte in
            partial &* 257 &+ UInt64(byte)
        }
        return VaultFolderIdentity(
            volumeUUIDString: volume,
            fileIdentifier: fileIdentifier
        )
    }

    private func seedV1Selection(for url: URL, name: String? = nil) throws {
        defaults.storage["obsidianVaultSelectionV1"] = try JSONSerialization.data(withJSONObject: [
            "version": 1,
            "standardizedPath": url.standardizedFileURL.path,
            "displayName": name ?? url.lastPathComponent
        ])
        defaults.storage["obsidianVaultPath"] = url.standardizedFileURL.path
        defaults.storage["obsidianVaultName"] = name ?? url.lastPathComponent
    }

    private func seedV2Selection(
        for url: URL,
        identity: VaultFolderIdentity?,
        name: String? = nil
    ) throws {
        var selection: [String: Any] = [
            "version": 2,
            "standardizedPath": url.standardizedFileURL.path,
            "displayName": name ?? url.lastPathComponent
        ]
        if let identity {
            selection["identity"] = [
                "volumeUUIDString": identity.volumeUUIDString,
                "fileIdentifier": identity.fileIdentifier
            ]
        }
        defaults.storage["obsidianVaultSelectionV2"] = try JSONSerialization.data(withJSONObject: selection)
        defaults.storage["obsidianVaultPath"] = url.standardizedFileURL.path
        defaults.storage["obsidianVaultName"] = name ?? url.lastPathComponent
    }

    private func makeManager(seedLegacySelectionIfNeeded: Bool = true) -> VaultManager {
        if seedLegacySelectionIfNeeded,
           defaults.data(forKey: "obsidianVaultBookmark") != nil,
           defaults.string(forKey: "obsidianVaultPath") == nil,
           let resolvedURL = bookmarkResolver.resolvedURL {
            seedLegacySelection(for: resolvedURL)
        }
        let manager = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            fileCoordinator: fileCoordinator,
            bookmarkResolver: bookmarkResolver,
            identityProbe: identityProbe
        )
        Self.retainedManagers.append(manager)
        return manager
    }

    private func makeSettings() -> AdvancedExportSettings {
        let settings = AdvancedExportSettings()
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")!
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeIsolatedSettings() -> AdvancedExportSettings {
        let suiteName = "VaultManagerTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: userDefaults)
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")!
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd_vault_manager_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeRealFileSystemManager(
        vaultURL: URL,
        fileCoordinator: FileCoordinating? = nil
    ) -> VaultManager {
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        defaults.storage.removeValue(forKey: "obsidianVaultSelectionV1")
        defaults.storage.removeValue(forKey: "obsidianVaultSelectionV2")
        defaults.storage["obsidianVaultPath"] = vaultURL.path
        defaults.storage["obsidianVaultName"] = vaultURL.lastPathComponent
        bookmarkResolver.resolvedURL = vaultURL
        let manager = VaultManager(
            defaults: defaults,
            fileSystem: SystemFileSystem(),
            fileCoordinator: fileCoordinator,
            bookmarkResolver: bookmarkResolver,
            identityProbe: identityProbe
        )
        Self.retainedManagers.append(manager)
        return manager
    }

    private func installParentSwap(
        on manager: VaultManager,
        parent: URL,
        movedParent: URL,
        outside: URL,
        probe: SecureCommitHookProbe,
        afterFinalValidation: Bool = false
    ) {
        let hook: @Sendable () throws -> Void = {
            probe.record()
            try FileManager.default.moveItem(at: parent, to: movedParent)
            try FileManager.default.createSymbolicLink(at: parent, withDestinationURL: outside)
        }
        if afterFinalValidation {
            manager.productionDestinationDidValidateForTesting = hook
        } else {
            manager.productionDestinationWillCommitForTesting = hook
        }
    }

    private func assertRaceWroteNothing(
        filename: String,
        movedParent: URL,
        outside: URL,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: movedParent.appendingPathComponent(filename).path),
            file: file,
            line: line
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: outside.appendingPathComponent(filename).path),
            file: file,
            line: line
        )
    }

    func testProductionAggregateWriteFailsClosedOnParentSymlinkSwap() throws {
        try assertAggregateRaceFailsClosed(afterFinalValidation: false)
    }

    func testProductionAggregateCommitWindowFailsClosedAfterFinalValidation() throws {
        try assertAggregateRaceFailsClosed(afterFinalValidation: true)
    }

    private func assertAggregateRaceFailsClosed(afterFinalValidation: Bool) throws {
        let root = makeTempDir()
        let outside = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let parent = root.appendingPathComponent("Health", isDirectory: true)
        let moved = root.appendingPathComponent("Health-original", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let coordinator = RecordingFileCoordinator()
        let manager = makeRealFileSystemManager(vaultURL: root, fileCoordinator: coordinator)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.markdown]
        settings.includeDataDictionary = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        let probe = SecureCommitHookProbe()
        installParentSwap(
            on: manager,
            parent: parent,
            movedParent: moved,
            outside: outside,
            probe: probe,
            afterFinalValidation: afterFinalValidation
        )

        XCTAssertThrowsError(try manager.exportHealthDataResult(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        )) { error in
            XCTAssertEqual(error as? ExportError, .destinationChanged)
        }
        XCTAssertEqual(probe.executionCount, 1)
        let filename = settings.filename(for: ExportFixtures.referenceDate, format: .markdown)
        XCTAssertEqual(
            coordinator.calls,
            [.init(url: parent.appendingPathComponent(filename), intent: .replace)],
            "The secure aggregate route must use the coordinated destination accessor"
        )
        assertRaceWroteNothing(filename: filename, movedParent: moved, outside: outside)
    }

    func testProductionDailyNoteWriteFailsClosedOnParentSymlinkSwap() throws {
        let root = makeTempDir()
        let outside = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let parent = root.appendingPathComponent("Daily", isDirectory: true)
        let moved = root.appendingPathComponent("Daily-original", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let coordinator = RecordingFileCoordinator()
        let manager = makeRealFileSystemManager(vaultURL: root, fileCoordinator: coordinator)
        let settings = makeIsolatedSettings()
        settings.exportFormats = []
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"
        let probe = SecureCommitHookProbe()
        installParentSwap(
            on: manager,
            parent: parent,
            movedParent: moved,
            outside: outside,
            probe: probe
        )

        let result = try manager.exportHealthDataResult(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        )
        guard case .failed(let error) = result.dailyNoteResult else {
            return XCTFail("Expected bound daily-note publication to fail closed")
        }
        XCTAssertEqual(error as? ExportError, .destinationChanged)
        XCTAssertEqual(probe.executionCount, 1)
        let filename = settings.dailyNoteInjection.formatFilename(
            for: ExportFixtures.referenceDate,
            timeZone: settings.exportTimeZoneOverride ?? .current
        ) + ".md"
        XCTAssertEqual(
            coordinator.calls,
            [.init(url: parent.appendingPathComponent(filename), intent: .replace)],
            "The secure daily-note route must use the coordinated destination accessor"
        )
        assertRaceWroteNothing(filename: filename, movedParent: moved, outside: outside)
    }

    func testProductionArchiveWriteFailsClosedOnParentSymlinkSwap() async throws {
        try await assertArchiveRaceFailsClosed(summaryOnly: false)
    }

    func testProductionSummaryOnlyArchiveWriteFailsClosedOnParentSymlinkSwap() async throws {
        try await assertArchiveRaceFailsClosed(summaryOnly: true)
    }

    private func assertArchiveRaceFailsClosed(summaryOnly: Bool) async throws {
        let root = makeTempDir()
        let outside = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: outside) }
        let parent = root.appendingPathComponent("Health", isDirectory: true)
        let moved = root.appendingPathComponent("Health-original", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let coordinator = RecordingFileCoordinator()
        let manager = makeRealFileSystemManager(vaultURL: root, fileCoordinator: coordinator)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = true
        settings.summaryOnlyExport = summaryOnly
        settings.exportFormats = [.markdown]
        settings.includeDataDictionary = false
        settings.generateWeeklyRollups = true
        let probe = SecureCommitHookProbe()
        installParentSwap(
            on: manager,
            parent: parent,
            movedParent: moved,
            outside: outside,
            probe: probe
        )

        let start = ExportFixtures.referenceDate
        let formatter = DateFormatter()
        formatter.timeZone = settings.exportTimeZoneOverride
        formatter.dateFormat = "yyyy-MM-dd"
        let archiveName = "Health.md Export \(formatter.string(from: start)).zip"
        do {
            _ = try await manager.exportArchive(
                from: summaryOnly ? [] : [ExportFixtures.fullDay],
                rollupHealthData: [ExportFixtures.fullDay],
                settings: settings,
                startDate: start,
                endDate: start
            )
            XCTFail("Expected bound ZIP publication to fail closed")
        } catch {
            XCTAssertEqual(error as? ExportError, .destinationChanged)
        }
        XCTAssertEqual(probe.executionCount, 1)
        XCTAssertEqual(
            coordinator.calls,
            [.init(url: parent.appendingPathComponent(archiveName), intent: .replace)],
            "The secure ZIP route must use the coordinated destination accessor"
        )
        assertRaceWroteNothing(filename: archiveName, movedParent: moved, outside: outside)
    }

    // MARK: - Export path admission

    func testArchiveRejectsParentTraversalBeforeCreatingDestination() async throws {
        let root = makeTempDir()
        let outside = root.deletingLastPathComponent()
            .appendingPathComponent("healthmd_archive_escape_\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let manager = makeRealFileSystemManager(vaultURL: root)
        manager.healthSubfolder = "../\(outside.lastPathComponent)"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.archiveExportFiles = true

        do {
            _ = try await manager.exportArchive(
                from: [ExportFixtures.fullDay],
                settings: settings,
                startDate: ExportFixtures.referenceDate,
                endDate: ExportFixtures.referenceDate
            )
            XCTFail("Archive traversal must be rejected")
        } catch let error as ExportError {
            guard case .invalidExportPath = error else {
                return XCTFail("Expected invalidExportPath, got \(error)")
            }
        }

        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(try FileManager.default.subpathsOfDirectory(atPath: root.path).isEmpty)
    }

    func testRangePreflightRejectsFixedFilenameAcrossDatesWithZeroWrites() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = makeRealFileSystemManager(vaultURL: root)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.filenameFormat = "health"
        let secondDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 1, to: ExportFixtures.referenceDate)
        )

        XCTAssertThrowsError(try manager.preflightExportDestinations(
            settings: settings,
            dates: [ExportFixtures.referenceDate, secondDate]
        )) { error in
            guard case ExportError.invalidExportPath = error else {
                return XCTFail("Expected invalidExportPath, got \(error)")
            }
        }
        XCTAssertTrue(try FileManager.default.subpathsOfDirectory(atPath: root.path).isEmpty)
    }

    func testRangePreflightKeepsTenThousandOneDailyDestinationsWhenSummaryIsUnavailable() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = makeRealFileSystemManager(vaultURL: root)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.generateRangeSummary = true
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2000,
            month: 1,
            day: 1
        )))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(
            year: 2027,
            month: 5,
            day: 19
        )))
        let dates = ExportOrchestrator.dateRange(from: start, to: end, calendar: calendar)
        XCTAssertEqual(dates.count, 10_001)

        XCTAssertNoThrow(try manager.preflightExportDestinations(
            settings: settings,
            dates: dates
        ))
        XCTAssertTrue(try FileManager.default.subpathsOfDirectory(atPath: root.path).isEmpty)
    }

    func testPreflightRejectsCaseWidthUnicodeAndAncestorAliases() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = makeRealFileSystemManager(vaultURL: root)

        let unsafePlans = [
            ["Health/A.json", "health/a.JSON"],
            ["Health/Ａ.json", "Health/A.json"],
            ["Health/café.json", "Health/cafe\u{301}.json"],
            ["Health/output", "Health/output/day.json"],
            ["Health/output", "Health/output-a", "Health/output/day.json"],
            ["Health/CON.json"],
            ["Health/COM¹.json"],
            ["Health/LPT³.txt"],
            ["Health/day.json."],
            ["Health/file:stream.json"]
        ]
        for paths in unsafePlans {
            XCTAssertThrowsError(try manager.preflightExportArtifactPaths(paths)) { error in
                guard case ExportError.invalidExportPath = error else {
                    return XCTFail("Expected invalidExportPath for \(paths), got \(error)")
                }
            }
        }
        XCTAssertTrue(try FileManager.default.subpathsOfDirectory(atPath: root.path).isEmpty)
    }

    func testPreflightRejectsSymlinkEscapeAndHardLinkAlias() throws {
        let root = makeTempDir()
        let outside = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let manager = makeRealFileSystemManager(vaultURL: root)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Escaped"),
            withDestinationURL: outside
        )
        XCTAssertThrowsError(try manager.preflightExportArtifactPaths([
            "Escaped/day.json"
        ]))

        let health = root.appendingPathComponent("Health", isDirectory: true)
        try FileManager.default.createDirectory(at: health, withIntermediateDirectories: true)
        let first = health.appendingPathComponent("first.json")
        let second = health.appendingPathComponent("second.json")
        try Data("{}".utf8).write(to: first)
        try FileManager.default.linkItem(at: first, to: second)
        XCTAssertThrowsError(try manager.preflightExportArtifactPaths([
            "Health/first.json",
            "Health/second.json"
        ]))
    }

    func testSummaryOnlyArchivePreflightOmitsUnusedDailyEntryPaths() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = makeRealFileSystemManager(vaultURL: root)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.archiveExportFiles = true
        settings.summaryOnlyExport = true
        settings.filenameFormat = "health"
        settings.generateWeeklyRollups = true
        let secondDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 1, to: ExportFixtures.referenceDate)
        )

        XCTAssertNoThrow(try manager.preflightExportDestinations(
            settings: settings,
            dates: [ExportFixtures.referenceDate, secondDate],
            rollupDates: [ExportFixtures.referenceDate, secondDate]
        ))
        XCTAssertTrue(try FileManager.default.subpathsOfDirectory(atPath: root.path).isEmpty)
    }

    func testArchivePreflightRejectsCrossDateDailyNoteCollision() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = makeRealFileSystemManager(vaultURL: root)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.archiveExportFiles = true
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.filenamePattern = "health"
        let secondDate = try XCTUnwrap(
            Calendar.current.date(byAdding: .day, value: 1, to: ExportFixtures.referenceDate)
        )

        XCTAssertThrowsError(try manager.preflightExportDestinations(
            settings: settings,
            dates: [ExportFixtures.referenceDate, secondDate]
        )) { error in
            guard case ExportError.invalidExportPath = error else {
                return XCTFail("Expected invalidExportPath, got \(error)")
            }
        }
        XCTAssertTrue(try FileManager.default.subpathsOfDirectory(atPath: root.path).isEmpty)
    }

    func testPreflightAcceptsNormalNestedPortablePaths() throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = makeRealFileSystemManager(vaultURL: root)

        bookmarkResolver.startAccessCalls = []
        bookmarkResolver.stopAccessCalls = []
        XCTAssertNoThrow(try manager.preflightExportArtifactPaths([
            "Health/JSON/2026/08/10.json",
            "Health/Markdown/2026/08/10.md",
            "Daily/2026-08-10.md"
        ]))
        XCTAssertEqual(bookmarkResolver.startAccessCalls, [root])
        XCTAssertEqual(bookmarkResolver.stopAccessCalls, [root])
        XCTAssertTrue(try FileManager.default.subpathsOfDirectory(atPath: root.path).isEmpty)
    }

    // MARK: - Durable exact artifact I/O

    func testExactArtifactIOUsesRawBytesAndAtomicDescriptorRelativeWrite() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = makeRealFileSystemManager(vaultURL: root)
        let binding = try manager.exactDestinationBinding()
        let relativePath = "Health/exact.json"
        let expected = Data("{\"exact\":true}\n".utf8)

        try await manager.overwriteExactUTF8Artifact(
            relativePath: relativePath,
            data: expected,
            binding: binding
        )
        let outputURL = root.appendingPathComponent(relativePath)
        XCTAssertEqual(try Data(contentsOf: outputURL), expected)
        let exactState = try await manager.inspectExactUTF8Artifact(
            relativePath: relativePath,
            expectedData: expected,
            binding: binding
        )
        XCTAssertEqual(exactState, .exact)

        try Data([0xff, 0xfe]).write(to: outputURL, options: .atomic)
        let driftState = try await manager.inspectExactUTF8Artifact(
            relativePath: relativePath,
            expectedData: expected,
            binding: binding
        )
        XCTAssertEqual(
            driftState,
            .different,
            "Readable non-UTF-8 bytes are drift, not transient destination unavailability"
        )
    }

    func testExactArtifactIORejectsSymlinkComponentWithoutWritingOutsideRoot() async throws {
        let root = makeTempDir()
        let outside = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        let manager = makeRealFileSystemManager(vaultURL: root)
        let binding = try manager.exactDestinationBinding()
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Health"),
            withDestinationURL: outside
        )

        do {
            try await manager.overwriteExactUTF8Artifact(
                relativePath: "Health/escaped.json",
                data: Data("{}\n".utf8),
                binding: binding
            )
            XCTFail("Symlink traversal must fail closed")
        } catch let error as AppleExactDestinationError {
            XCTAssertEqual(error, .unsafeRelativePath)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: outside.appendingPathComponent("escaped.json").path
        ))
    }

    func testExactArtifactIORejectsSamePathRootReplacement() async throws {
        let root = makeTempDir()
        defer { try? FileManager.default.removeItem(at: root) }
        let manager = makeRealFileSystemManager(vaultURL: root)
        let binding = try manager.exactDestinationBinding()
        try FileManager.default.removeItem(at: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        do {
            _ = try await manager.inspectExactUTF8Artifact(
                relativePath: "Health/exact.json",
                expectedData: Data("{}\n".utf8),
                binding: binding
            )
            XCTFail("Replacing a selected root at the same path must fail closed")
        } catch let error as AppleExactDestinationError {
            XCTAssertEqual(error, .destinationRebound)
        }
    }

    func testExactArtifactIORejectsRootRenameAfterParentOpenBeforeCommit() async throws {
        let root = makeTempDir()
        let movedRoot = root.deletingLastPathComponent()
            .appendingPathComponent("moved-selected-root-\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: movedRoot)
        }
        let manager = makeRealFileSystemManager(vaultURL: root)
        let binding = try manager.exactDestinationBinding()
        manager.exactDestinationWillCommitForTesting = {
            try FileManager.default.moveItem(at: root, to: movedRoot)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        do {
            try await manager.overwriteExactUTF8Artifact(
                relativePath: "Health/exact.json",
                data: Data("{}\n".utf8),
                binding: binding
            )
            XCTFail("Renaming the selected root after opening its parent must fail closed")
        } catch let error as AppleExactDestinationError {
            XCTAssertEqual(error, .destinationRebound)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: movedRoot.appendingPathComponent("Health/exact.json").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("Health/exact.json").path
        ))
    }

    // MARK: - Init / Load Settings

    func testInit_noBookmark_vaultURLIsNilAndSubfolderDefaultsToSelectedFolder() {
        let manager = makeManager()
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.vaultName, "No vault selected")
        XCTAssertFalse(manager.hasVaultSelection)
        XCTAssertFalse(manager.isVaultConfigured)
        XCTAssertEqual(manager.vaultAvailabilityText, "Choose Folder")
        XCTAssertEqual(manager.healthSubfolder, "")
    }

    func testInit_savedSubfolder_isRestored() {
        defaults.storage["healthSubfolder"] = "MyHealth"
        let manager = makeManager()
        XCTAssertEqual(manager.healthSubfolder, "MyHealth")
    }

    func testInit_savedBookmark_resolvesVaultURLAndMigratesLegacyMetadata() throws {
        let vaultURL = URL(fileURLWithPath: "/tmp/TestVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        seedLegacySelection(for: vaultURL)
        bookmarkResolver.resolvedURL = vaultURL

        let manager = makeManager()
        XCTAssertEqual(manager.vaultURL, vaultURL)
        XCTAssertEqual(manager.vaultName, "TestVault")
        XCTAssertEqual(manager.destinationState, .available)
        let selectionData = try XCTUnwrap(defaults.data(forKey: "obsidianVaultSelectionV2"))
        let selection = try JSONSerialization.jsonObject(with: selectionData) as? [String: Any]
        XCTAssertEqual(selection?["version"] as? Int, 2)
        XCTAssertEqual(selection?["standardizedPath"] as? String, vaultURL.standardizedFileURL.path)
        XCTAssertEqual(selection?["displayName"] as? String, "TestVault")
    }

    func testInit_acceptsStandardizedEquivalentResolvedPath() {
        let expectedURL = URL(fileURLWithPath: "/tmp/Parent/../EquivalentVault")
        let resolvedURL = URL(fileURLWithPath: "/tmp/EquivalentVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        defaults.storage["obsidianVaultPath"] = expectedURL.path
        defaults.storage["obsidianVaultName"] = "EquivalentVault"
        bookmarkResolver.resolvedURL = resolvedURL

        let manager = makeManager()

        XCTAssertEqual(manager.vaultURL, resolvedURL)
        XCTAssertEqual(manager.destinationState, .available)
    }

    func testInit_rejectsResolvedDestinationChangeAndPreservesSavedSelection() throws {
        let expectedURL = URL(fileURLWithPath: "/tmp/Healthmd")
        let reboundURL = URL(fileURLWithPath: "/tmp/Healthmd(1)")
        let bookmark = Data("original-bookmark".utf8)
        defaults.storage["obsidianVaultBookmark"] = bookmark
        try seedV2Selection(for: expectedURL, identity: identity("original"))
        bookmarkResolver.resolvedURL = reboundURL
        bookmarkResolver.resolvedIsStale = true
        identityProbe.defaultIdentity = identity("replacement")

        let manager = makeManager()
        let selectionData = try XCTUnwrap(defaults.data(forKey: "obsidianVaultSelectionV2"))

        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.vaultName, "Healthmd")
        XCTAssertEqual(manager.destinationState, .requiresReselectionDestinationChanged)
        XCTAssertTrue(manager.requiresVaultReselection)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), bookmark)
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultPath"), expectedURL.path)
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultName"), "Healthmd")
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), selectionData)
        XCTAssertTrue(bookmarkResolver.createBookmarkCalls.isEmpty)
        XCTAssertEqual(bookmarkResolver.startAccessCalls, [reboundURL])
        XCTAssertTrue(fileCoordinator.calls.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)
        XCTAssertTrue(fileSystem.directories.isEmpty)

        manager.refreshVaultAccess()
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.destinationState, .requiresReselectionDestinationChanged)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), bookmark)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), selectionData)
    }

    func testInit_bookmarkWithoutTrustedExpectedPathRequiresReselection() {
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        bookmarkResolver.resolvedURL = URL(fileURLWithPath: "/tmp/Untrusted")

        let manager = makeManager(seedLegacySelectionIfNeeded: false)

        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.destinationState, .requiresReselectionMissingExpectedPath)
        XCTAssertTrue(manager.requiresVaultReselection)
        XCTAssertTrue(bookmarkResolver.resolveCalls.isEmpty)
    }

    func testInit_staleBookmark_refreshesByResaving() {
        let vaultURL = URL(fileURLWithPath: "/tmp/StaleVault")
        defaults.storage["obsidianVaultBookmark"] = Data("old-bookmark".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        bookmarkResolver.resolvedIsStale = true

        let manager = makeManager()

        XCTAssertEqual(manager.vaultURL, vaultURL)
        XCTAssertEqual(bookmarkResolver.startAccessCalls.count, 1)
        XCTAssertEqual(bookmarkResolver.stopAccessCalls.count, 1)
        XCTAssertNotNil(defaults.storage["obsidianVaultBookmark"] as? Data)
    }

    func testInit_bookmarkResolutionFails_preservesBookmarkAndCanRecover() {
        let vaultURL = URL(fileURLWithPath: "/tmp/NetworkVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bad-bookmark".utf8)
        seedLegacySelection(for: vaultURL)
        bookmarkResolver.resolutionResults = [
            .failure(NSError(domain: "test", code: 42, userInfo: nil)),
            .success((vaultURL, false))
        ]

        let manager = makeManager()
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.vaultName, "NetworkVault")
        XCTAssertEqual(manager.destinationState, .temporarilyUnavailable)
        XCTAssertNotNil(defaults.storage["obsidianVaultBookmark"])
        XCTAssertTrue(manager.hasSavedVaultFolder)
        XCTAssertTrue(manager.hasVaultSelection)
        XCTAssertTrue(manager.isVaultConfigured)
        XCTAssertEqual(manager.pathForDisplay, vaultURL.path)
        XCTAssertEqual(
            manager.lastExportStatus,
            "Saved folder unavailable. Reconnect the location in Files or re-select the folder."
        )

        manager.refreshVaultAccess()
        XCTAssertEqual(manager.vaultURL, vaultURL)
        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertFalse(manager.requiresVaultReselection)
    }

    func testInit_startAccessFailureIsTemporaryAndPreservesDurableSelection() throws {
        let url = URL(fileURLWithPath: "/tmp/ProviderVault")
        let bookmark = Data("bookmark".utf8)
        defaults.storage["obsidianVaultBookmark"] = bookmark
        try seedV2Selection(for: url, identity: identity("folder"))
        let selection = defaults.data(forKey: "obsidianVaultSelectionV2")
        bookmarkResolver.resolvedURL = url
        bookmarkResolver.accessGranted = false

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .temporarilyUnavailable)
        XCTAssertEqual(manager.vaultName, "ProviderVault")
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), bookmark)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), selection)
        XCTAssertTrue(identityProbe.calls.isEmpty)
    }

    func testInit_identityProbeFailureIsTemporaryAndPreservesDurableSelection() throws {
        let url = URL(fileURLWithPath: "/tmp/ProviderVault")
        let bookmark = Data("bookmark".utf8)
        defaults.storage["obsidianVaultBookmark"] = bookmark
        try seedV2Selection(for: url, identity: identity("folder"))
        let selection = defaults.data(forKey: "obsidianVaultSelectionV2")
        bookmarkResolver.resolvedURL = url
        identityProbe.error = CocoaError(.fileReadUnknown)

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .temporarilyUnavailable)
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), bookmark)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), selection)
    }

    func testInit_samePathWithEqualIdentityRemainsAvailable() throws {
        let url = URL(fileURLWithPath: "/tmp/SameVault")
        let stableIdentity = identity("same")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV2Selection(for: url, identity: stableIdentity)
        let selection = defaults.data(forKey: "obsidianVaultSelectionV2")
        bookmarkResolver.resolvedURL = url
        identityProbe.defaultIdentity = stableIdentity

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(manager.vaultURL, url)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), selection)
        XCTAssertTrue(bookmarkResolver.createBookmarkCalls.isEmpty)
    }

    func testInit_samePathWithoutCurrentIdentityPreservesSavedIdentity() throws {
        let url = URL(fileURLWithPath: "/tmp/SameProviderVault")
        let stableIdentity = identity("saved")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV2Selection(for: url, identity: stableIdentity)
        let selection = defaults.data(forKey: "obsidianVaultSelectionV2")
        bookmarkResolver.resolvedURL = url
        identityProbe.defaultIdentity = nil

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(manager.vaultURL, url)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), selection)
        XCTAssertTrue(bookmarkResolver.createBookmarkCalls.isEmpty)
    }

    func testInit_movedPathWithEqualIdentityIsAcceptedAndDurableMetadataUpdated() throws {
        let oldURL = URL(fileURLWithPath: "/tmp/OldVault")
        let movedURL = URL(fileURLWithPath: "/tmp/MovedVault")
        let stableIdentity = identity("same")
        defaults.storage["obsidianVaultBookmark"] = Data("old-bookmark".utf8)
        try seedV2Selection(for: oldURL, identity: stableIdentity)
        bookmarkResolver.resolvedURL = movedURL
        bookmarkResolver.createdBookmarkData = Data("moved-bookmark".utf8)
        identityProbe.defaultIdentity = stableIdentity

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(manager.vaultURL, movedURL)
        XCTAssertEqual(manager.vaultName, "MovedVault")
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), Data("moved-bookmark".utf8))
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultPath"), movedURL.path)
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultName"), "MovedVault")
        XCTAssertEqual(bookmarkResolver.createBookmarkCalls, [movedURL])
    }

    func testInit_movedPathWithDifferentIdentityFailsClosedWithZeroWrites() throws {
        let oldURL = URL(fileURLWithPath: "/tmp/Dropbox/Healthmd")
        let changedURL = URL(fileURLWithPath: "/tmp/Dropbox/Healthmd(1)")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV2Selection(for: oldURL, identity: identity("old"))
        let before = defaults.storage
        bookmarkResolver.resolvedURL = changedURL
        identityProbe.defaultIdentity = identity("new")

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .requiresReselectionDestinationChanged)
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(defaults.storage as NSDictionary, before as NSDictionary)
        XCTAssertTrue(bookmarkResolver.createBookmarkCalls.isEmpty)
    }

    func testInit_samePathWithDifferentIdentityFailsClosed() throws {
        let url = URL(fileURLWithPath: "/tmp/ReplacedVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV2Selection(for: url, identity: identity("old"))
        let before = defaults.storage
        bookmarkResolver.resolvedURL = url
        identityProbe.defaultIdentity = identity("new")

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .requiresReselectionDestinationChanged)
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(defaults.storage as NSDictionary, before as NSDictionary)
    }

    func testInit_movedPathWithoutComparableIdentityNeedsReviewWithZeroWrites() throws {
        let oldURL = URL(fileURLWithPath: "/tmp/OldProviderVault")
        let movedURL = URL(fileURLWithPath: "/tmp/NewProviderVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV2Selection(for: oldURL, identity: identity("old"))
        let before = defaults.storage
        bookmarkResolver.resolvedURL = movedURL
        identityProbe.defaultIdentity = nil

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .requiresReviewIdentityUnavailable)
        XCTAssertTrue(manager.hasVaultSelection)
        XCTAssertTrue(manager.isVaultConfigured)
        XCTAssertEqual(manager.vaultAvailabilityText, "Needs Access")
        XCTAssertEqual(manager.vaultName, "OldProviderVault")
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(defaults.storage as NSDictionary, before as NSDictionary)
        XCTAssertTrue(bookmarkResolver.createBookmarkCalls.isEmpty)
    }

    func testInit_identitylessProviderMovedPathRebindsAndRefreshesDurableSelection() throws {
        // Cloud file-provider volumes (iCloud Drive, Dropbox, and similar) never
        // report persistent IDs, so both the trusted selection and the resolved
        // URL carry nil identity. A bookmark that resolves with acquired security
        // scope is the strongest same-resource evidence such providers offer;
        // the destination must rebind across provider path drift instead of
        // demanding reselection on every launch (issue #140).
        let savedURL = URL(fileURLWithPath: "/tmp/Provider/Healthmd")
        let movedURL = URL(fileURLWithPath: "/private/tmp/Provider/Healthmd")
        defaults.storage["obsidianVaultBookmark"] = Data("old-bookmark".utf8)
        try seedV2Selection(for: savedURL, identity: nil)
        bookmarkResolver.resolvedURL = movedURL
        bookmarkResolver.createdBookmarkData = Data("refreshed-bookmark".utf8)
        identityProbe.defaultIdentity = nil

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(manager.vaultURL, movedURL)
        XCTAssertEqual(manager.vaultName, "Healthmd")
        XCTAssertFalse(manager.requiresVaultReselection)
        XCTAssertTrue(manager.isVaultDestinationUsable)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), Data("refreshed-bookmark".utf8))
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultPath"), movedURL.standardizedFileURL.path)
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultName"), "Healthmd")
        XCTAssertEqual(bookmarkResolver.createBookmarkCalls, [movedURL])

        // The rebound selection is durable: the next launch resolves the same
        // path and needs no further bookmark refresh.
        manager.refreshVaultAccess()
        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(manager.vaultURL, movedURL)
        XCTAssertEqual(bookmarkResolver.createBookmarkCalls, [movedURL])
    }

    func testInit_identityEvidenceAppearingAcrossMovedPathStillRequiresReview() throws {
        // A selection saved without identity evidence that later resolves with
        // identity evidence at a moved path keeps one-sided verification: the
        // volume became identity-capable, so the move cannot be proven safe.
        let savedURL = URL(fileURLWithPath: "/tmp/Provider/Healthmd")
        let movedURL = URL(fileURLWithPath: "/tmp/Provider/Healthmd-moved")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV2Selection(for: savedURL, identity: nil)
        let before = defaults.storage
        bookmarkResolver.resolvedURL = movedURL
        identityProbe.defaultIdentity = identity("newly-visible")

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .requiresReviewIdentityUnavailable)
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(defaults.storage as NSDictionary, before as NSDictionary)
        XCTAssertTrue(bookmarkResolver.createBookmarkCalls.isEmpty)
    }

    func testInit_v1SamePathUpgradesIdentity() throws {
        let url = URL(fileURLWithPath: "/tmp/LegacyVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV1Selection(for: url)
        bookmarkResolver.resolvedURL = url
        identityProbe.defaultIdentity = identity("legacy-folder")

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .available)
        let data = try XCTUnwrap(defaults.data(forKey: "obsidianVaultSelectionV2"))
        let selection = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(selection?["version"] as? Int, 2)
        XCTAssertNotNil(selection?["identity"])
    }

    func testInit_v1MovedPathNeverSilentlyAccepted() throws {
        let oldURL = URL(fileURLWithPath: "/tmp/LegacyVault")
        let movedURL = URL(fileURLWithPath: "/tmp/MovedLegacyVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV1Selection(for: oldURL)
        let before = defaults.storage
        bookmarkResolver.resolvedURL = movedURL
        identityProbe.defaultIdentity = identity("resolved-only")

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .requiresReviewIdentityUnavailable)
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(defaults.storage as NSDictionary, before as NSDictionary)
    }

    func testInit_v2SelectionTakesPrecedenceOverLegacyV1() throws {
        let v2URL = URL(fileURLWithPath: "/tmp/CurrentVault")
        let v1URL = URL(fileURLWithPath: "/tmp/LegacyVault")
        let stableIdentity = identity("current")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV1Selection(for: v1URL)
        try seedV2Selection(for: v2URL, identity: stableIdentity)
        bookmarkResolver.resolvedURL = v2URL
        identityProbe.defaultIdentity = stableIdentity

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(manager.vaultURL, v2URL)
        XCTAssertEqual(manager.vaultName, "CurrentVault")
    }

    func testInit_staleMovedBookmarkRefreshesOnlyAfterIdentityEquality() throws {
        let oldURL = URL(fileURLWithPath: "/tmp/OldVault")
        let movedURL = URL(fileURLWithPath: "/tmp/MovedVault")
        let stableIdentity = identity("same")
        defaults.storage["obsidianVaultBookmark"] = Data("old".utf8)
        try seedV2Selection(for: oldURL, identity: stableIdentity)
        bookmarkResolver.resolvedURL = movedURL
        bookmarkResolver.resolvedIsStale = true
        bookmarkResolver.createdBookmarkData = Data("fresh".utf8)
        identityProbe.defaultIdentity = stableIdentity

        _ = makeManager()

        XCTAssertEqual(identityProbe.calls, [movedURL])
        XCTAssertEqual(bookmarkResolver.createBookmarkCalls, [movedURL])
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), Data("fresh".utf8))
    }

    func testInit_refreshFailurePreservesPriorBookmarkAndSelection() throws {
        let oldURL = URL(fileURLWithPath: "/tmp/OldVault")
        let movedURL = URL(fileURLWithPath: "/tmp/MovedVault")
        let stableIdentity = identity("same")
        let oldBookmark = Data("old".utf8)
        defaults.storage["obsidianVaultBookmark"] = oldBookmark
        try seedV2Selection(for: oldURL, identity: stableIdentity)
        let oldSelection = defaults.data(forKey: "obsidianVaultSelectionV2")
        bookmarkResolver.resolvedURL = movedURL
        bookmarkResolver.resolvedIsStale = true
        bookmarkResolver.createError = CocoaError(.fileWriteUnknown)
        identityProbe.defaultIdentity = stableIdentity

        let manager = makeManager()

        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(manager.vaultURL, movedURL)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), oldBookmark)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), oldSelection)
        XCTAssertNotNil(manager.lastExportStatus)

        bookmarkResolver.createError = nil
        bookmarkResolver.createdBookmarkData = Data("fresh".utf8)
        manager.refreshVaultAccess()

        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), Data("fresh".utf8))
        XCTAssertNotEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), oldSelection)
        XCTAssertNil(manager.lastExportStatus)
    }

    func testPresentationRetainsSavedNameForUnavailableAndReviewStates() throws {
        let url = URL(fileURLWithPath: "/tmp/SavedVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        try seedV2Selection(for: url, identity: identity("folder"))
        bookmarkResolver.resolveError = CocoaError(.fileReadUnknown)

        let manager = makeManager()

        XCTAssertTrue(manager.hasVaultSelection)
        XCTAssertEqual(manager.vaultName, "SavedVault")
        XCTAssertEqual(manager.vaultAvailabilityText, "Unavailable")
    }

    // MARK: - Vault Selection

    func testSetVaultFolder_savesBookmarkAndUpdatesState() {
        let vaultURL = URL(fileURLWithPath: "/tmp/NewVault")
        bookmarkResolver.accessGranted = true
        let manager = makeManager()

        manager.setVaultFolder(vaultURL)

        XCTAssertEqual(manager.vaultURL, vaultURL)
        XCTAssertEqual(manager.vaultName, "NewVault")
        XCTAssertNotNil(defaults.storage["obsidianVaultBookmark"])
        XCTAssertEqual(defaults.storage["obsidianVaultName"] as? String, "NewVault")
        XCTAssertEqual(defaults.storage["obsidianVaultPath"] as? String, "/tmp/NewVault")
        XCTAssertNotNil(defaults.storage["obsidianVaultSelectionV2"] as? Data)
        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertNil(manager.lastExportStatus)
    }

    func testSetVaultFolder_storesRoundTrippedSelectionMetadata() throws {
        // File-provider destinations can normalize the picker URL differently
        // from the bookmark-resolved URL. The trusted path and identity must be
        // captured through the same resolution pipeline that verifies them on
        // later launches, so the next cold start matches instead of failing
        // verification (issue #140).
        let pickedURL = URL(fileURLWithPath: "/tmp/Picked/Healthmd")
        let canonicalURL = URL(fileURLWithPath: "/private/tmp/Picked/Healthmd")
        let canonicalIdentity = identity("canonical")
        bookmarkResolver.resolvedURL = canonicalURL
        identityProbe.identitiesByPath[canonicalURL.standardizedFileURL.path] = canonicalIdentity
        let manager = makeManager()

        manager.setVaultFolder(pickedURL)

        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultPath"), canonicalURL.standardizedFileURL.path)
        let selectionData = try XCTUnwrap(defaults.data(forKey: "obsidianVaultSelectionV2"))
        let selection = try JSONSerialization.jsonObject(with: selectionData) as? [String: Any]
        XCTAssertEqual(selection?["standardizedPath"] as? String, canonicalURL.standardizedFileURL.path)
        let identityObject = try XCTUnwrap(selection?["identity"] as? [String: Any])
        XCTAssertEqual(identityObject["volumeUUIDString"] as? String, canonicalIdentity.volumeUUIDString)
        XCTAssertTrue(identityProbe.calls.contains(canonicalURL))

        // The stored selection already describes the bookmark-resolved URL, so
        // the next launch accepts it without any launch-time bookmark refresh
        // (only the selection-time creation is recorded).
        manager.refreshVaultAccess()
        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(manager.vaultURL, canonicalURL)
        XCTAssertEqual(bookmarkResolver.createBookmarkCalls, [pickedURL])
    }

    func testRecordSuccessfulExportStatusMarksOutcomeUntilReassigned() {
        let manager = makeManager()
        XCTAssertFalse(manager.lastExportStatusIsSuccess)

        // The local-export full-success status carries no success prefix;
        // only the recorded outcome may mark it successful.
        manager.recordSuccessfulExportStatus("≥ 1 generated file(s) · 1 of 1 data day(s)")
        XCTAssertTrue(manager.lastExportStatusIsSuccess)

        // Re-recording an identical success keeps the marking.
        manager.recordSuccessfulExportStatus("≥ 1 generated file(s) · 1 of 1 data day(s)")
        XCTAssertTrue(manager.lastExportStatusIsSuccess)

        // Any direct status assignment resets the outcome flag so a stale
        // success cannot recolor a later destination-error status.
        manager.lastExportStatus = "Saved folder unavailable. Reconnect the location in Files or re-select the folder."
        XCTAssertFalse(manager.lastExportStatusIsSuccess)
    }

    func testSetVaultFolder_accessDenied_setsErrorStatus() {
        bookmarkResolver.accessGranted = false
        let manager = makeManager()

        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/Denied"))

        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.lastExportStatus, "Failed to access folder")
    }

    func testCanAccessSelectedVaultFolder_reflectsSecurityScopedAccess() {
        bookmarkResolver.accessGranted = true
        let manager = makeManager()
        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/AccessibleVault"))

        XCTAssertTrue(manager.canAccessSelectedVaultFolder())

        bookmarkResolver.accessGranted = false
        XCTAssertFalse(manager.canAccessSelectedVaultFolder())
    }

    func testSetVaultFolder_bookmarkCreationFails_preservesPreviousValidSelection() {
        let originalURL = URL(fileURLWithPath: "/tmp/OriginalVault")
        let manager = makeManager()
        manager.setVaultFolder(originalURL)
        let originalBookmark = defaults.data(forKey: "obsidianVaultBookmark")
        let originalSelection = defaults.data(forKey: "obsidianVaultSelectionV2")
        bookmarkResolver.createError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])

        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/FailVault"))

        XCTAssertEqual(manager.vaultURL, originalURL)
        XCTAssertEqual(manager.vaultName, "OriginalVault")
        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), originalBookmark)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), originalSelection)
        XCTAssertTrue(manager.lastExportStatus?.contains("Failed to save folder access") == true)
    }

    func testSetVaultFolder_identityProbeFailurePreservesPreviousValidSelection() {
        let originalURL = URL(fileURLWithPath: "/tmp/OriginalVault")
        let manager = makeManager()
        manager.setVaultFolder(originalURL)
        let originalBookmark = defaults.data(forKey: "obsidianVaultBookmark")
        let originalSelection = defaults.data(forKey: "obsidianVaultSelectionV2")
        identityProbe.error = CocoaError(.fileReadUnknown)

        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/FailVault"))

        XCTAssertEqual(manager.vaultURL, originalURL)
        XCTAssertEqual(manager.vaultName, "OriginalVault")
        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), originalBookmark)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV2"), originalSelection)
        XCTAssertTrue(manager.lastExportStatus?.contains("Failed to save folder access") == true)
    }

    func testExplicitReselectionAuthorizesChangedPathAndClearsIssue() throws {
        let originalURL = URL(fileURLWithPath: "/tmp/Healthmd")
        let changedURL = URL(fileURLWithPath: "/tmp/Healthmd(1)")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        // A confirmed identity mismatch is what forces reselection under the
        // identity-evidence contract; identity-less provider drift now rebinds.
        try seedV2Selection(for: originalURL, identity: identity("original"))
        bookmarkResolver.resolvedURL = changedURL
        identityProbe.defaultIdentity = identity("replacement")
        let manager = makeManager()
        XCTAssertTrue(manager.requiresVaultReselection)

        manager.setVaultFolder(changedURL)

        XCTAssertEqual(manager.vaultURL, changedURL)
        XCTAssertEqual(manager.vaultName, "Healthmd(1)")
        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertFalse(manager.requiresVaultReselection)
        XCTAssertNil(manager.lastExportStatus)
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultPath"), changedURL.standardizedFileURL.path)
    }

    func testClearVaultFolder_removesBookmarkAndResetsState() {
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        bookmarkResolver.resolvedURL = URL(fileURLWithPath: "/tmp/Vault")
        let manager = makeManager()
        XCTAssertNotNil(manager.vaultURL)

        manager.clearVaultFolder()

        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.vaultName, "No vault selected")
        XCTAssertNil(defaults.storage["obsidianVaultBookmark"])
        XCTAssertNil(defaults.storage["obsidianVaultName"])
        XCTAssertNil(defaults.storage["obsidianVaultPath"])
        XCTAssertNil(defaults.storage["obsidianVaultSelectionV1"])
        XCTAssertNil(defaults.storage["obsidianVaultSelectionV2"])
        XCTAssertEqual(manager.destinationState, .notSelected)
    }

    // MARK: - Subfolder Setting

    func testSaveSubfolderSetting_persistsToDefaults() {
        let manager = makeManager()
        manager.healthSubfolder = "CustomHealth"
        manager.saveSubfolderSetting()

        XCTAssertEqual(defaults.storage["healthSubfolder"] as? String, "CustomHealth")
    }

    // MARK: - Background Access

    func testHasVaultAccess_trueWhenVaultSet() {
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = URL(fileURLWithPath: "/tmp/V")
        let manager = makeManager()

        XCTAssertTrue(manager.hasVaultAccess)
    }

    func testHasVaultAccess_falseWhenNoVault() {
        let manager = makeManager()
        XCTAssertFalse(manager.hasVaultAccess)
    }

    func testStartStopVaultAccess_callsBookmarkResolver() {
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        let vaultURL = URL(fileURLWithPath: "/tmp/V")
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        bookmarkResolver.startAccessCalls = []
        bookmarkResolver.stopAccessCalls = []

        let lease = manager.beginVaultAccess()
        XCTAssertEqual(bookmarkResolver.startAccessCalls.count, 1)

        lease?.stop()
        XCTAssertEqual(bookmarkResolver.stopAccessCalls.count, 1)
    }

    func testStopVaultAccessUsesURLCapturedBeforeReselection() {
        let originalURL = URL(fileURLWithPath: "/tmp/Original")
        let replacementURL = URL(fileURLWithPath: "/tmp/Replacement")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        seedLegacySelection(for: originalURL)
        bookmarkResolver.resolvedURL = originalURL
        let manager = makeManager()
        bookmarkResolver.startAccessCalls = []
        bookmarkResolver.stopAccessCalls = []

        let lease = try? XCTUnwrap(manager.beginVaultAccess())
        manager.setVaultFolder(replacementURL)
        bookmarkResolver.stopAccessCalls = []
        lease?.stop()
        lease?.stop()

        XCTAssertEqual(bookmarkResolver.stopAccessCalls, [originalURL])
    }

    func testStopVaultAccessBalancesCapturedURLAfterRefreshMakesDestinationUnavailable() {
        let vaultURL = URL(fileURLWithPath: "/tmp/V")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        seedLegacySelection(for: vaultURL)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        bookmarkResolver.startAccessCalls = []
        bookmarkResolver.stopAccessCalls = []

        let lease = try? XCTUnwrap(manager.beginVaultAccess())
        bookmarkResolver.resolveError = CocoaError(.fileReadUnknown)
        manager.refreshVaultAccess()
        bookmarkResolver.stopAccessCalls = []
        lease?.stop()

        XCTAssertEqual(manager.destinationState, .temporarilyUnavailable)
        XCTAssertEqual(bookmarkResolver.stopAccessCalls, [vaultURL])
    }

    func testExportPresentationAccessUsesCapturedSecurityScopeRoot() throws {
        let vaultURL = URL(fileURLWithPath: "/tmp/PresentationVault")
        let fileURL = vaultURL.appendingPathComponent("Health/2026/07/2026-07-19.md")
        let manager = makeManager()
        manager.recordExportPresentationTarget(
            fileURL: fileURL,
            securityScopedRootURL: vaultURL
        )
        let target = try XCTUnwrap(manager.lastExportPresentationTarget)

        XCTAssertTrue(manager.startAccessingExportPresentationTarget(target))
        manager.stopAccessingExportPresentationTarget(target)

        XCTAssertEqual(bookmarkResolver.startAccessCalls, [vaultURL])
        XCTAssertEqual(bookmarkResolver.stopAccessCalls, [vaultURL])
        XCTAssertEqual(target.fileURL, fileURL)
        XCTAssertEqual(target.folderURL, fileURL.deletingLastPathComponent())
    }

    #if os(iOS)
    func testExportFolderBrowserUsesExactInitialDirectory() {
        let folderURL = URL(fileURLWithPath: "/tmp/V/Health/Markdown/2026")

        let picker = ExportFolderBrowser.makeDocumentPicker(
            initialDirectoryURL: folderURL
        )

        XCTAssertEqual(picker.directoryURL, folderURL)
        XCTAssertFalse(picker.allowsMultipleSelection)
    }
    #endif

    func testClearVaultFolderClearsExportPresentationTarget() {
        let manager = makeManager()
        manager.recordExportPresentationTarget(
            fileURL: URL(fileURLWithPath: "/tmp/V/Health/day.md"),
            securityScopedRootURL: URL(fileURLWithPath: "/tmp/V")
        )

        manager.clearVaultFolder()

        XCTAssertNil(manager.lastExportPresentationTarget)
    }

    // MARK: - Coordinated Export I/O

    func testAggregateWriteUsesCoordinatorAccessorURLForAtomicCommit() throws {
        let manager = makeManager()
        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/SelectedVault"))
        let redirectedURL = URL(fileURLWithPath: "/tmp/ProviderAccessor/coordinated.json")
        fileCoordinator.redirectedURL = redirectedURL
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]

        let result = try manager.exportHealthDataResult(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings,
            writeDataDictionary: false
        )

        XCTAssertEqual(result.aggregateFileCount, 1)
        XCTAssertEqual(fileCoordinator.calls.count, 1)
        XCTAssertEqual(fileCoordinator.calls.first?.intent, .replace)
        XCTAssertNotNil(fileSystem.files[redirectedURL.path])
        XCTAssertEqual(fileSystem.files.count, 1)
    }

    func testCoordinatorDestinationChangeMapsToDestinationChangedExportError() {
        let manager = makeManager()
        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/SelectedVault"))
        fileCoordinator.injectedError = FileCoordinationError.destinationChanged
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]

        XCTAssertThrowsError(try manager.exportHealthDataResult(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings,
            writeDataDictionary: false
        )) { error in
            XCTAssertEqual(error as? ExportError, .destinationChanged)
        }
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testSystemFileCoordinatorCreatesNestedProviderStyleExportPath() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health/Nested"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]

        let result = try await manager.exportHealthData(
            ExportFixtures.fullDay,
            settings: settings,
            writeDataDictionary: false
        )

        XCTAssertEqual(result.aggregateFileCount, 1)
        let nestedFolder = vaultURL.appendingPathComponent("Health/Nested")
        let files = try FileManager.default.contentsOfDirectory(
            at: nestedFolder,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.filter { $0.pathExtension == "json" }.count, 1)
    }

    func testAggregateCoordinationFailurePerformsNoDirectoryOrWriteSideEffects() {
        let manager = makeManager()
        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/SelectedVault"))
        fileCoordinator.injectedError = NSError(
            domain: NSCocoaErrorDomain,
            code: CocoaError.Code.fileWriteNoPermission.rawValue
        )
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]

        XCTAssertThrowsError(try manager.exportHealthDataResult(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings,
            writeDataDictionary: false
        ))
        XCTAssertEqual(fileCoordinator.calls.count, 1)
        XCTAssertTrue(fileSystem.directories.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    // MARK: - Export Guard Tests

    func testAsyncExportKeepsMainActorResponsiveAndSecurityScopeOpenThroughWrite() async throws {
        let vaultURL = URL(fileURLWithPath: "/tmp/SlowWriteVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        seedLegacySelection(for: vaultURL)
        bookmarkResolver.resolvedURL = vaultURL
        let slowFileSystem = SlowRecordingFileSystem()
        let manager = VaultManager(
            defaults: defaults,
            fileSystem: slowFileSystem,
            bookmarkResolver: bookmarkResolver,
            identityProbe: identityProbe
        )
        Self.retainedManagers.append(manager)
        bookmarkResolver.startAccessCalls = []
        bookmarkResolver.stopAccessCalls = []
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]

        let exportTask = Task {
            try await manager.exportHealthData(
                ExportFixtures.fullDay,
                settings: settings,
                writeDataDictionary: false
            )
        }

        while !slowFileSystem.writeStarted {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertFalse(slowFileSystem.writeWasOnMainThread)
        XCTAssertFalse(slowFileSystem.writeFinished)
        XCTAssertTrue(bookmarkResolver.stopAccessCalls.isEmpty)

        let result = try await exportTask.value
        XCTAssertEqual(result.aggregateFileCount, 1)
        XCTAssertTrue(slowFileSystem.writeFinished)
        XCTAssertEqual(bookmarkResolver.stopAccessCalls, [vaultURL])
    }

    func testAsyncExportPreservesRequestScopedSourceTimeZone() async throws {
        let vaultURL = URL(fileURLWithPath: "/tmp/SourceTimeZoneVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.filenameFormat = "{date}"

        let referenceDate = ExportFixtures.fullDay.date
        let localOffset = TimeZone.current.secondsFromGMT(for: referenceDate)
        let sourceTimeZone = try XCTUnwrap(TimeZone(
            secondsFromGMT: localOffset >= 0 ? -12 * 3_600 : 14 * 3_600
        ))
        settings.exportTimeZoneOverride = sourceTimeZone
        let expectedFormatter = DateFormatter()
        expectedFormatter.calendar = Calendar(identifier: .gregorian)
        expectedFormatter.locale = Locale(identifier: "en_US_POSIX")
        expectedFormatter.timeZone = sourceTimeZone
        expectedFormatter.dateFormat = "yyyy-MM-dd"
        let expectedDate = expectedFormatter.string(from: referenceDate)
        let localFormatter = DateFormatter()
        localFormatter.calendar = Calendar(identifier: .gregorian)
        localFormatter.locale = Locale(identifier: "en_US_POSIX")
        localFormatter.timeZone = .current
        localFormatter.dateFormat = "yyyy-MM-dd"
        XCTAssertNotEqual(localFormatter.string(from: referenceDate), expectedDate)

        _ = try await manager.exportHealthData(
            ExportFixtures.fullDay,
            settings: settings,
            writeDataDictionary: false
        )

        XCTAssertNotNil(fileSystem.files.keys.first {
            $0.hasSuffix("/\(expectedDate).json")
        })
    }

    func testAggregateWritesRemainSerializedAcrossVaultManagerInstances() async throws {
        let sharedFileSystem = SlowRecordingFileSystem()
        let firstVault = URL(fileURLWithPath: "/tmp/SerializedVaultA")
        let secondVault = URL(fileURLWithPath: "/tmp/SerializedVaultB")
        let firstResolver = FakeBookmarkResolver()
        let secondResolver = FakeBookmarkResolver()
        firstResolver.resolvedURL = firstVault
        secondResolver.resolvedURL = secondVault
        let firstDefaults = FakeUserDefaults()
        let secondDefaults = FakeUserDefaults()
        firstDefaults.storage["obsidianVaultBookmark"] = Data("first".utf8)
        firstDefaults.storage["obsidianVaultPath"] = firstVault.path
        firstDefaults.storage["obsidianVaultName"] = firstVault.lastPathComponent
        secondDefaults.storage["obsidianVaultBookmark"] = Data("second".utf8)
        secondDefaults.storage["obsidianVaultPath"] = secondVault.path
        secondDefaults.storage["obsidianVaultName"] = secondVault.lastPathComponent
        let firstManager = VaultManager(
            defaults: firstDefaults,
            fileSystem: sharedFileSystem,
            bookmarkResolver: firstResolver,
            identityProbe: identityProbe
        )
        let secondManager = VaultManager(
            defaults: secondDefaults,
            fileSystem: sharedFileSystem,
            bookmarkResolver: secondResolver,
            identityProbe: identityProbe
        )
        Self.retainedManagers.append(contentsOf: [firstManager, secondManager])
        let firstSettings = makeIsolatedSettings()
        let secondSettings = makeIsolatedSettings()
        firstSettings.exportFormats = [.json]
        secondSettings.exportFormats = [.json]

        async let firstResult = firstManager.exportHealthData(
            ExportFixtures.fullDay,
            settings: firstSettings,
            writeDataDictionary: false
        )
        async let secondResult = secondManager.exportHealthData(
            ExportFixtures.fullDay,
            settings: secondSettings,
            writeDataDictionary: false
        )
        _ = try await (firstResult, secondResult)

        XCTAssertEqual(sharedFileSystem.maximumConcurrentWrites, 1)
    }

    func testDirectExportReportsDestinationChangedWithoutFilesystemWork() throws {
        let expectedURL = URL(fileURLWithPath: "/tmp/Healthmd")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        // Confirmed identity mismatch (not identity-less provider drift, which
        // now rebinds) is what must stop an export before any filesystem work.
        try seedV2Selection(for: expectedURL, identity: identity("original"))
        bookmarkResolver.resolvedURL = URL(fileURLWithPath: "/tmp/Healthmd(1)")
        identityProbe.defaultIdentity = identity("replacement")
        let manager = makeManager()

        XCTAssertThrowsError(try manager.exportHealthDataResult(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: makeSettings()
        )) { error in
            XCTAssertEqual(error as? ExportError, .destinationChanged)
        }
        XCTAssertTrue(fileSystem.files.isEmpty)
        XCTAssertTrue(fileSystem.directories.isEmpty)
    }

    func testExportHealthData_noVault_returnsFalse() {
        let manager = makeManager()
        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: makeSettings()
        )
        XCTAssertFalse(result)
    }

    func testExportHealthData_noData_returnsFalse() {
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = URL(fileURLWithPath: "/tmp/V")
        let manager = makeManager()
        let result = manager.exportHealthData(
            ExportFixtures.emptyDay,
            for: ExportFixtures.referenceDate,
            settings: makeSettings()
        )
        XCTAssertFalse(result)
    }

    #if os(macOS)
    func testDiskBackedLocalArchiveMatchesInMemoryArchiveBytes() async throws {
        let firstVault = makeTempDir()
        let secondVault = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: firstVault)
            try? FileManager.default.removeItem(at: secondVault)
        }
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = true
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        let record = ExportFixtures.fullDay

        let inMemoryManager = makeRealFileSystemManager(vaultURL: firstVault)
        let optionalInMemoryURL = try await inMemoryManager.exportArchive(
            from: [record],
            settings: settings,
            startDate: ExportFixtures.referenceDate,
            endDate: ExportFixtures.referenceDate
        )
        let inMemoryURL = try XCTUnwrap(optionalInMemoryURL)

        let spool = LocalArchiveSpool()
        defer { spool.cleanup() }
        try await spool.append(record, settings: settings)
        let diskBackedManager = makeRealFileSystemManager(vaultURL: secondVault)
        let optionalDiskBackedURL = try await diskBackedManager.exportArchive(
            fromRenderedFiles: spool.files,
            settings: settings,
            startDate: ExportFixtures.referenceDate,
            endDate: ExportFixtures.referenceDate
        )
        let diskBackedURL = try XCTUnwrap(optionalDiskBackedURL)

        XCTAssertEqual(
            inMemoryManager.lastExportPresentationTarget,
            ExportPresentationTarget(
                fileURL: inMemoryURL,
                securityScopedRootURL: firstVault
            )
        )
        XCTAssertEqual(
            diskBackedManager.lastExportPresentationTarget,
            ExportPresentationTarget(
                fileURL: diskBackedURL,
                securityScopedRootURL: secondVault
            )
        )

        let firstExtracted = makeTempDir()
        let secondExtracted = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: firstExtracted)
            try? FileManager.default.removeItem(at: secondExtracted)
        }
        try extractZIP(inMemoryURL, to: firstExtracted)
        try extractZIP(diskBackedURL, to: secondExtracted)
        let firstPaths = try FileManager.default.subpathsOfDirectory(atPath: firstExtracted.path).sorted()
        let secondPaths = try FileManager.default.subpathsOfDirectory(atPath: secondExtracted.path).sorted()
        XCTAssertEqual(secondPaths, firstPaths)
        for path in firstPaths {
            let firstURL = firstExtracted.appendingPathComponent(path)
            let secondURL = secondExtracted.appendingPathComponent(path)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: firstURL.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { continue }
            let secondData = try Data(contentsOf: secondURL)
            let firstData = try Data(contentsOf: firstURL)
            let firstDifference = zip(secondData, firstData).enumerated().first {
                $0.element.0 != $0.element.1
            }?.offset
            let context: String
            if let firstDifference {
                let lower = max(0, firstDifference - 80)
                let upper = min(firstData.count, firstDifference + 160)
                context = "in-memory=\(String(data: firstData[lower..<upper], encoding: .utf8) ?? "<binary>") disk-backed=\(String(data: secondData[lower..<upper], encoding: .utf8) ?? "<binary>")"
            } else {
                context = "sizes \(firstData.count) and \(secondData.count)"
            }
            XCTAssertEqual(
                secondData,
                firstData,
                "Disk-backed archive content differs for \(path): \(context)"
            )
        }
    }
    #endif

    #if os(macOS)
    func testArchiveCancellationAfterFinalValidationPreservesPriorZIPAndRecordsNoSuccess() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = true
        settings.exportFormats = [.json]
        settings.includeDataDictionary = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        settings.generateRangeSummary = false

        let healthURL = vaultURL.appendingPathComponent("Health", isDirectory: true)
        try FileManager.default.createDirectory(at: healthURL, withIntermediateDirectories: true)
        let archiveURL = healthURL.appendingPathComponent("Health.md Export 2026-03-15.zip")
        let priorArchive = Data("prior archive remains authoritative".utf8)
        try priorArchive.write(to: archiveURL)

        let probe = SecureCommitHookProbe()
        manager.productionDestinationDidValidateForTesting = {
            probe.record()
            probe.requestCancellation()
        }

        do {
            _ = try await manager.exportArchive(
                from: [ExportFixtures.fullDay],
                settings: settings,
                startDate: ExportFixtures.referenceDate,
                endDate: ExportFixtures.referenceDate,
                cancellationCheck: { probe.cancellationRequested }
            )
            XCTFail("Cancellation at the final pre-rename boundary must stop archive publication")
        } catch is CancellationError {
            // Expected: the prior archive remains authoritative.
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }

        XCTAssertEqual(probe.executionCount, 1)
        XCTAssertEqual(try Data(contentsOf: archiveURL), priorArchive)
        XCTAssertNil(manager.lastExportPresentationTarget)
        XCTAssertNil(manager.lastExportStatus)
    }

    func testArchiveDictionaryDisabledKeepsSelectedArtifactsWithoutDictionaryEntry() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = true
        settings.exportFormats = [.markdown]
        settings.includeDataDictionary = false
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)

        let optionalArchiveURL = try await manager.exportArchive(
            from: [ExportFixtures.fullDay],
            settings: settings,
            startDate: ExportFixtures.referenceDate,
            endDate: ExportFixtures.referenceDate
        )
        let archiveURL = try XCTUnwrap(optionalArchiveURL)
        let extracted = makeTempDir()
        defer { try? FileManager.default.removeItem(at: extracted) }
        try extractZIP(archiveURL, to: extracted)
        let paths = try FileManager.default.subpathsOfDirectory(atPath: extracted.path)

        XCTAssertTrue(paths.contains { $0.hasSuffix(".md") })
        XCTAssertFalse(paths.contains(HealthMdExportSchema.dataDictionaryFilename))
    }
    #endif

    func testFinalizeCorpusDerivedOutputs_withoutDerivedOutputsSkipsPayloadsAndVaultAccess() async throws {
        let manager = makeManager()
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        let nonexistentPayload = URL(fileURLWithPath: "/tmp/should-not-be-decoded.json")

        let result = try await manager.finalizeCorpusDerivedOutputs(
            recordPayloadFiles: [nonexistentPayload],
            settings: settings,
            requestedDates: [ExportFixtures.referenceDate],
            startDate: ExportFixtures.referenceDate,
            endDate: ExportFixtures.referenceDate
        )

        XCTAssertEqual(result.rollupFileCount, 0)
        XCTAssertEqual(result.archiveFileCount, 0)
        XCTAssertTrue(bookmarkResolver.startAccessCalls.isEmpty)
    }

    func testFinalizeCorpusDerivedOutputsUsesJournalDatesAndCleansCompactProjections() async throws {
        let vaultURL = makeTempDir()
        let workURL = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: vaultURL)
            try? FileManager.default.removeItem(at: workURL)
        }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = false
        settings.exportFormats = [.json]
        settings.generateWeeklyRollups = true
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        let payloadURL = workURL.appendingPathComponent("dense-day.json")
        let payload = ConnectedCorpusHealthDayPayload(
            sourceDate: ExportFixtures.referenceDate,
            isRequestedDate: true,
            record: ExportFixtures.fullDay,
            externalDailyRecords: [],
            failure: nil
        )
        try JSONEncoder().encode(payload).write(to: payloadURL)
        let streamablePayload = try ConnectedCorpusApplicationItemCodec.encode(
            payload,
            kind: .macHealthDay
        )
        defer { streamablePayload.remove() }

        let result = try await manager.finalizeCorpusDerivedOutputs(
            recordPayloadFiles: [payloadURL, streamablePayload.url],
            recordSourceDates: [ExportFixtures.referenceDate, ExportFixtures.referenceDate],
            settings: settings,
            requestedDates: [ExportFixtures.referenceDate],
            startDate: ExportFixtures.referenceDate,
            endDate: ExportFixtures.referenceDate,
            archiveWorkDirectoryURL: workURL
        )

        XCTAssertGreaterThan(result.rollupFileCount, 0)
        let workEntries = try FileManager.default.contentsOfDirectory(
            at: workURL,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(workEntries.contains {
            $0.lastPathComponent.hasPrefix(".healthmd-rollup-projections-")
        })
    }

    func testRollupSummaryPreflightUsesAuthoritativeRangeWhenBoundaryRecordIsUnavailable() throws {
        let vaultURL = makeTempDir()
        let outsideURL = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: vaultURL)
            try? FileManager.default.removeItem(at: outsideURL)
        }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.generateRangeSummary = true
        settings.includeDataDictionary = true
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let endDate = ExportFixtures.referenceDate
        let startDate = endDate.addingTimeInterval(-86_400)
        let requestedRange = try HealthRollupRangeRequest(
            startDate: startDate,
            endDate: endDate,
            calendarTimeZoneIdentifier: "UTC"
        )
        let rollupFolder = vaultURL.appendingPathComponent(
            "Health/Rollups/Range",
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: rollupFolder, withIntermediateDirectories: true)
        let outsideFile = outsideURL.appendingPathComponent("escaped.json")
        let originalOutsideData = Data("must remain unchanged".utf8)
        try originalOutsideData.write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: rollupFolder.appendingPathComponent("2026-03-14_to_2026-03-15.json"),
            withDestinationURL: outsideFile
        )

        XCTAssertThrowsError(try manager.exportRollupSummaries(
            from: [ExportFixtures.fullDay],
            requestedRange: requestedRange,
            settings: settings
        ))

        XCTAssertEqual(try Data(contentsOf: outsideFile), originalOutsideData)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent(
                "Health/\(HealthMdExportSchema.dataDictionaryFilename)"
            ).path
        ), "authoritative range admission must fail before the first export write")
    }

    func testLegacyCorpusFinalizationUsesOriginalRangeIdentityAndTimezone() async throws {
        let vaultURL = makeTempDir()
        let workURL = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: vaultURL)
            try? FileManager.default.removeItem(at: workURL)
        }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.generateRangeSummary = true
        settings.exportTimeZoneOverride = TimeZone(identifier: "Asia/Tokyo")
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let record = ExportFixtures.fullDay
        let originalEnd = record.date
        let originalStart = try XCTUnwrap(utc.date(byAdding: .day, value: -1, to: originalEnd))
        let payload = ConnectedCorpusHealthDayPayload(
            sourceDate: originalEnd,
            isRequestedDate: true,
            record: record,
            externalDailyRecords: [],
            failure: nil
        )
        let streamablePayload = try ConnectedCorpusApplicationItemCodec.encode(
            payload,
            kind: .macHealthDay
        )
        defer { streamablePayload.remove() }

        let result = try await manager.finalizeCorpusDerivedOutputs(
            recordPayloadFiles: [streamablePayload.url],
            recordSourceDates: [originalEnd],
            settings: settings,
            requestedDates: [originalEnd],
            rollupRequestedDates: [originalStart, originalEnd],
            rollupCalendarTimeZoneIdentifier: "UTC",
            startDate: originalEnd,
            endDate: originalEnd,
            archiveWorkDirectoryURL: workURL
        )

        XCTAssertEqual(result.rollupFileCount, 1)
        let rollupURL = vaultURL
            .appendingPathComponent("Rollups/Range/2026-03-14_to_2026-03-15.json")
        let rollup = try String(contentsOf: rollupURL, encoding: .utf8)
        XCTAssertTrue(rollup.contains("\"period_id\" : \"2026-03-14_to_2026-03-15\""))
        XCTAssertTrue(rollup.contains("\"days_expected\" : 2"))
        XCTAssertTrue(rollup.contains("\"days_counted\" : 1"))
    }

    func testDirectResidualRetryUsesOriginalRangeZipNameAndCompleteArchiveScopeInFrozenTimezone() async throws {
        let vaultURL = makeTempDir()
        let workURL = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: vaultURL)
            try? FileManager.default.removeItem(at: workURL)
        }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = true
        settings.exportFormats = [.json]
        settings.includeDataDictionary = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        settings.generateRangeSummary = true
        let frozenIdentifier = TimeZone.current.identifier == "America/Los_Angeles"
            ? "Asia/Tokyo"
            : "America/Los_Angeles"
        let frozenTimeZone = try XCTUnwrap(TimeZone(identifier: frozenIdentifier))
        settings.exportTimeZoneOverride = frozenTimeZone
        var frozenCalendar = Calendar(identifier: .gregorian)
        frozenCalendar.timeZone = frozenTimeZone
        let originalEnd = try XCTUnwrap(frozenCalendar.date(from: DateComponents(
            timeZone: frozenTimeZone,
            year: 2026,
            month: 3,
            day: 15
        )))
        let originalStart = try XCTUnwrap(
            frozenCalendar.date(byAdding: .day, value: -1, to: originalEnd)
        )
        let firstRecord = HealthData(
            date: originalStart,
            timeContext: ExportFixtures.fullDay.timeContext
        )
        var residualRecord = HealthData(
            date: originalEnd,
            timeContext: ExportFixtures.fullDay.timeContext
        )
        residualRecord.activity = ActivityData(steps: 1_234)
        let payloads = [
            ConnectedCorpusHealthDayPayload(
                sourceDate: originalStart,
                isRequestedDate: false,
                record: firstRecord,
                externalDailyRecords: [],
                failure: nil
            ),
            ConnectedCorpusHealthDayPayload(
                sourceDate: originalEnd,
                isRequestedDate: true,
                record: residualRecord,
                externalDailyRecords: [],
                failure: nil
            ),
        ]
        let payloadURLs = try payloads.enumerated().map { index, payload in
            let url = workURL.appendingPathComponent("direct-\(index).json")
            try JSONEncoder().encode(payload).write(to: url)
            return url
        }
        let startIdentifier = HealthRollupDateFormatting.dayString(
            originalStart,
            timeZone: frozenTimeZone
        )
        let endIdentifier = HealthRollupDateFormatting.dayString(
            originalEnd,
            timeZone: frozenTimeZone
        )
        let periodID = "\(startIdentifier)_to_\(endIdentifier)"

        let result = try await manager.finalizeCorpusDerivedOutputs(
            recordPayloadFiles: payloadURLs,
            recordSourceDates: [originalStart, originalEnd],
            settings: settings,
            requestedDates: [originalEnd],
            rollupRequestedDates: [originalStart, originalEnd],
            rollupCalendarTimeZoneIdentifier: frozenIdentifier,
            startDate: originalStart,
            endDate: originalEnd,
            healthSubfolder: "Health",
            archiveWorkDirectoryURL: workURL
        )

        XCTAssertEqual(result.archiveFileCount, 1)
        let archiveURL = vaultURL.appendingPathComponent(
            "Health/Health.md Export \(periodID).zip"
        )
        XCTAssertEqual(manager.lastExportPresentationTarget?.fileURL, archiveURL)
        let archiveData = try Data(contentsOf: archiveURL)
        XCTAssertNotNil(archiveData.range(of: Data("\(startIdentifier).json".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("\(endIdentifier).json".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data(
            "Rollups/Range/\(periodID).json".utf8
        )))
    }

    func testDirectResidualArchiveCollisionFailsBeforeAnyWrite() async throws {
        let vaultURL = makeTempDir()
        let workURL = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: vaultURL)
            try? FileManager.default.removeItem(at: workURL)
        }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = true
        settings.exportFormats = [.json]
        settings.filenameFormat = "health"
        settings.includeDataDictionary = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        settings.generateRangeSummary = false
        let frozenTimeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        settings.exportTimeZoneOverride = frozenTimeZone
        var frozenCalendar = Calendar(identifier: .gregorian)
        frozenCalendar.timeZone = frozenTimeZone
        let originalEnd = ExportFixtures.referenceDate
        let originalStart = try XCTUnwrap(
            frozenCalendar.date(byAdding: .day, value: -1, to: originalEnd)
        )
        let payloads = [
            ConnectedCorpusHealthDayPayload(
                sourceDate: originalStart,
                isRequestedDate: false,
                record: HealthData(
                    date: originalStart,
                    timeContext: ExportFixtures.fullDay.timeContext
                ),
                externalDailyRecords: [],
                failure: nil
            ),
            ConnectedCorpusHealthDayPayload(
                sourceDate: originalEnd,
                isRequestedDate: true,
                record: ExportFixtures.fullDay,
                externalDailyRecords: [],
                failure: nil
            ),
        ]
        let payloadURLs = try payloads.enumerated().map { index, payload in
            let url = workURL.appendingPathComponent("collision-\(index).json")
            try JSONEncoder().encode(payload).write(to: url)
            return url
        }

        do {
            _ = try await manager.finalizeCorpusDerivedOutputs(
                recordPayloadFiles: payloadURLs,
                recordSourceDates: [originalStart, originalEnd],
                settings: settings,
                requestedDates: [originalEnd],
                rollupRequestedDates: [originalStart, originalEnd],
                rollupCalendarTimeZoneIdentifier: frozenTimeZone.identifier,
                startDate: originalStart,
                endDate: originalEnd,
                healthSubfolder: "Health",
                archiveWorkDirectoryURL: workURL
            )
            XCTFail("Original archive entry collisions must fail preflight")
        } catch let error as ExportError {
            guard case .invalidExportPath = error else {
                return XCTFail("Expected invalidExportPath, got \(error)")
            }
        }
        XCTAssertTrue(try FileManager.default.subpathsOfDirectory(atPath: vaultURL.path).isEmpty)
        XCTAssertNil(manager.lastExportPresentationTarget)
    }

    #if os(macOS)
    func testFinalizeCorpusDerivedArchiveRetainsStreamedArtifactsThroughZIPAppend() async throws {
        let vaultURL = makeTempDir()
        let workURL = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: vaultURL)
            try? FileManager.default.removeItem(at: workURL)
        }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = true
        settings.exportFormats = [.json, .csv]
        settings.includeDataDictionary = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        let payload = ConnectedCorpusHealthDayPayload(
            sourceDate: ExportFixtures.referenceDate,
            isRequestedDate: true,
            record: ExportFixtures.fullDay,
            externalDailyRecords: [],
            failure: nil
        )
        let streamablePayload = try ConnectedCorpusApplicationItemCodec.encode(
            payload,
            kind: .macHealthDay
        )
        defer { streamablePayload.remove() }

        let result = try await manager.finalizeCorpusDerivedOutputs(
            recordPayloadFiles: [streamablePayload.url],
            recordSourceDates: [ExportFixtures.referenceDate],
            settings: settings,
            requestedDates: [ExportFixtures.referenceDate],
            startDate: ExportFixtures.referenceDate,
            endDate: ExportFixtures.referenceDate,
            archiveWorkDirectoryURL: workURL
        )

        XCTAssertEqual(result.archiveFileCount, 1)
        let archiveURL = try XCTUnwrap(manager.lastExportPresentationTarget?.fileURL)
        let extracted = makeTempDir()
        defer { try? FileManager.default.removeItem(at: extracted) }
        try extractZIP(archiveURL, to: extracted)
        let files = try FileManager.default.subpathsOfDirectory(atPath: extracted.path)
        XCTAssertTrue(files.contains { $0.hasSuffix(".json") })
        XCTAssertTrue(files.contains { $0.hasSuffix(".csv") })
        XCTAssertFalse(files.contains(HealthMdExportSchema.dataDictionaryFilename))
    }

    func testFinalizeCorpusArchiveResidualRetryUsesImmutableOriginalDailyEntryScope() async throws {
        let vaultURL = makeTempDir()
        let workURL = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: vaultURL)
            try? FileManager.default.removeItem(at: workURL)
        }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = true
        settings.exportFormats = [.json]
        settings.includeDataDictionary = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        settings.generateRangeSummary = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let secondDate = ExportFixtures.referenceDate
        let firstDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: secondDate))
        let firstRecord = HealthData(
            date: firstDate,
            timeContext: ExportFixtures.fullDay.timeContext
        )
        let payloads = [
            ConnectedCorpusHealthDayPayload(
                sourceDate: firstDate,
                isRequestedDate: false,
                record: firstRecord,
                externalDailyRecords: [],
                failure: nil
            ),
            ConnectedCorpusHealthDayPayload(
                sourceDate: secondDate,
                isRequestedDate: true,
                record: ExportFixtures.fullDay,
                externalDailyRecords: [],
                failure: nil
            ),
        ]
        let payloadURLs = try payloads.enumerated().map { index, payload in
            let url = workURL.appendingPathComponent("\(index).json")
            try JSONEncoder().encode(payload).write(to: url)
            return url
        }

        let result = try await manager.finalizeCorpusDerivedOutputs(
            recordPayloadFiles: payloadURLs,
            recordSourceDates: [firstDate, secondDate],
            settings: settings,
            requestedDates: [secondDate],
            rollupRequestedDates: [firstDate, secondDate],
            rollupCalendarTimeZoneIdentifier: "UTC",
            startDate: secondDate,
            endDate: secondDate,
            healthSubfolder: "Health",
            archiveWorkDirectoryURL: workURL
        )

        XCTAssertEqual(result.archiveFileCount, 1)
        let archiveURL = try XCTUnwrap(manager.lastExportPresentationTarget?.fileURL)
        let extracted = makeTempDir()
        defer { try? FileManager.default.removeItem(at: extracted) }
        try extractZIP(archiveURL, to: extracted)
        let paths = try FileManager.default.subpathsOfDirectory(atPath: extracted.path)
        XCTAssertTrue(paths.contains("2026-03-14.json"), paths.joined(separator: "\n"))
        XCTAssertTrue(paths.contains("2026-03-15.json"), paths.joined(separator: "\n"))
    }

    func testFinalizeCorpusArchiveMissingOriginalSourcePreservesExistingZIP() async throws {
        let vaultURL = makeTempDir()
        let workURL = makeTempDir()
        defer {
            try? FileManager.default.removeItem(at: vaultURL)
            try? FileManager.default.removeItem(at: workURL)
        }
        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.archiveExportFiles = true
        settings.exportFormats = [.json]
        settings.includeDataDictionary = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        settings.generateRangeSummary = false
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let secondDate = ExportFixtures.referenceDate
        let firstDate = try XCTUnwrap(calendar.date(byAdding: .day, value: -1, to: secondDate))
        let payload = ConnectedCorpusHealthDayPayload(
            sourceDate: secondDate,
            isRequestedDate: true,
            record: ExportFixtures.fullDay,
            externalDailyRecords: [],
            failure: nil
        )
        let payloadURL = workURL.appendingPathComponent("residual.json")
        try JSONEncoder().encode(payload).write(to: payloadURL)
        let healthURL = vaultURL.appendingPathComponent("Health", isDirectory: true)
        try FileManager.default.createDirectory(at: healthURL, withIntermediateDirectories: true)
        let archiveURL = healthURL.appendingPathComponent(
            "Health.md Export 2026-03-14_to_2026-03-15.zip"
        )
        let originalArchive = Data("existing archive must survive".utf8)
        try originalArchive.write(to: archiveURL)

        do {
            _ = try await manager.finalizeCorpusDerivedOutputs(
                recordPayloadFiles: [payloadURL],
                recordSourceDates: [secondDate],
                settings: settings,
                requestedDates: [secondDate],
                rollupRequestedDates: [firstDate, secondDate],
                rollupCalendarTimeZoneIdentifier: "UTC",
                startDate: secondDate,
                endDate: secondDate,
                healthSubfolder: "Health",
                archiveWorkDirectoryURL: workURL
            )
            XCTFail("Archive rebuild must fail when an immutable original source is unavailable")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("existing ZIP preserved"))
        }
        XCTAssertEqual(try Data(contentsOf: archiveURL), originalArchive)
    }
    #endif

    func testExportHealthData_writesFileToExpectedPath() {
        let vaultURL = URL(fileURLWithPath: "/tmp/TestVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        manager.healthSubfolder = "Health"

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: makeIsolatedSettings()
        )

        XCTAssertTrue(result)
        let writtenPaths = fileSystem.files.keys
        let expectedHealthPrefix = vaultURL.appendingPathComponent("Health").path
        let healthPathFiles = writtenPaths.filter { $0.hasPrefix(expectedHealthPrefix) }
        XCTAssertFalse(healthPathFiles.isEmpty, "Should write file under vault/Health/")
    }

    func testAsyncExportAppendRetryDoesNotDuplicateIdenticalAggregate() async throws {
        let vaultURL = URL(fileURLWithPath: "/tmp/AsyncAppendVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.markdown]
        settings.writeMode = .append

        _ = try await manager.exportHealthData(
            ExportFixtures.fullDay,
            settings: settings,
            writeDataDictionary: false
        )
        let markdownPath = try XCTUnwrap(fileSystem.files.keys.first { $0.hasSuffix(".md") })
        let firstContent = try XCTUnwrap(fileSystem.files[markdownPath])

        _ = try await manager.exportHealthData(
            ExportFixtures.fullDay,
            settings: settings,
            writeDataDictionary: false
        )

        XCTAssertEqual(fileSystem.files[markdownPath], firstContent)
        XCTAssertEqual(manager.lastExportStatus?.hasPrefix("Already present in"), true)
    }

    func testExportHealthData_appendRetryDoesNotDuplicateIdenticalAggregate() throws {
        let vaultURL = URL(fileURLWithPath: "/tmp/TestVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.markdown]
        settings.writeMode = .append
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false

        XCTAssertTrue(manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        ))
        let markdownPath = try XCTUnwrap(fileSystem.files.keys.first { $0.hasSuffix(".md") })
        let firstContent = try XCTUnwrap(fileSystem.files[markdownPath])

        XCTAssertTrue(manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        ))

        XCTAssertEqual(fileSystem.files[markdownPath], firstContent)
    }

    func testExportHealthData_defaultSubfolder_writesDirectlyToSelectedFolder() {
        let vaultURL = URL(fileURLWithPath: "/tmp/TestVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: makeIsolatedSettings()
        )

        XCTAssertTrue(result)
        let writtenPaths = fileSystem.files.keys
        let vaultRootPrefix = vaultURL.path.hasSuffix("/") ? vaultURL.path : vaultURL.path + "/"
        let vaultRootFiles = writtenPaths.filter { $0.hasPrefix(vaultRootPrefix) }
        XCTAssertFalse(vaultRootFiles.isEmpty, "Should write file directly under vault root")
    }

    func testExportHealthData_organizeFormatsIntoFileTypeFolders() {
        let vaultURL = URL(fileURLWithPath: "/tmp/TestVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        manager.healthSubfolder = "Health"

        let settings = makeIsolatedSettings()
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.folderStructure = "{year}"
        settings.organizeFormatsIntoFolders = true

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        )

        XCTAssertTrue(result)
        let filename = settings.formatFilename(for: ExportFixtures.referenceDate)
        let dictionaryPath = "/tmp/TestVault/Health/\(HealthMdExportSchema.dataDictionaryFilename)"
        let expectedPaths: Set<String> = [
            "/tmp/TestVault/Health/Markdown/2026/\(filename).md",
            "/tmp/TestVault/Health/Bases/2026/\(filename).md",
            "/tmp/TestVault/Health/JSON/2026/\(filename).json",
            "/tmp/TestVault/Health/CSV/2026/\(filename).csv",
            dictionaryPath
        ]
        XCTAssertEqual(Set(fileSystem.files.keys), expectedPaths)
        XCTAssertTrue(fileSystem.files[dictionaryPath]?.contains("active_calories") == true)
        XCTAssertEqual(
            manager.lastExportPresentationTarget,
            ExportPresentationTarget(
                fileURL: URL(fileURLWithPath: "/tmp/TestVault/Health/Markdown/2026/\(filename).md"),
                securityScopedRootURL: vaultURL
            )
        )
    }

    func testExportHealthData_dictionaryDisabledKeepsMarkdownWithoutJSONSidecar() {
        let vaultURL = URL(fileURLWithPath: "/tmp/TestVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.markdown]
        settings.includeDataDictionary = false

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        )

        XCTAssertTrue(result)
        XCTAssertTrue(fileSystem.files.keys.contains { $0.hasSuffix(".md") })
        XCTAssertFalse(fileSystem.files.keys.contains {
            $0.hasSuffix(HealthMdExportSchema.dataDictionaryFilename)
        })
        XCTAssertFalse(fileSystem.files.keys.contains { $0.hasSuffix(".json") })
    }

    func testExportHealthData_runsIndividualEntrySideEffectsForEveryAggregateFormat() throws {
        for format in ExportFormat.allCases {
            let vaultURL = makeTempDir()
            defer { try? FileManager.default.removeItem(at: vaultURL) }

            let manager = makeRealFileSystemManager(vaultURL: vaultURL)
            manager.healthSubfolder = "Health"

            let settings = makeIsolatedSettings()
            settings.exportFormats = [format]
            settings.individualTracking.globalEnabled = true
            settings.individualTracking.setTrackIndividually("weight", enabled: true)

            let result = manager.exportHealthData(
                ExportFixtures.fullDay,
                for: ExportFixtures.referenceDate,
                settings: settings
            )

            XCTAssertTrue(result, "Expected \(format.rawValue) aggregate export to succeed")

            let entriesFolder = vaultURL
                .appendingPathComponent("Health")
                .appendingPathComponent("entries")
                .appendingPathComponent("body_measurements")
            let files = try FileManager.default.contentsOfDirectory(
                at: entriesFolder,
                includingPropertiesForKeys: nil
            )
            XCTAssertEqual(files.count, 1, "Expected \(format.rawValue) export to also write individual entry files")
            XCTAssertTrue(files[0].lastPathComponent.contains("weight"))
        }
    }

    func testExportHealthData_doesNotWriteWorkoutEntriesWhenIndividualTrackingDisabled() throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"

        let settings = makeIsolatedSettings()
        settings.exportFormats = [.markdown]
        settings.individualTracking.globalEnabled = false

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        )

        XCTAssertTrue(result)
        let workoutFolder = vaultURL
            .appendingPathComponent("Health")
            .appendingPathComponent("entries")
            .appendingPathComponent("workouts")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: workoutFolder.path),
            "Workout entry files should only be written when Individual Entry Tracking → Workouts is enabled"
        )
    }

    func testExportHealthData_writesWorkoutEntriesWhenIndividualTrackingWorkoutsEnabled() throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"

        let settings = makeIsolatedSettings()
        settings.exportFormats = [.markdown]
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.setTrackIndividually("workouts", enabled: true)

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        )

        XCTAssertTrue(result)
        let workoutFolder = vaultURL
            .appendingPathComponent("Health")
            .appendingPathComponent("entries")
            .appendingPathComponent("workouts")
        let files = try FileManager.default.contentsOfDirectory(
            at: workoutFolder,
            includingPropertiesForKeys: nil
        )
        XCTAssertEqual(files.count, 1, "Expected exactly one workout entry file")
        let content = try String(contentsOf: files[0], encoding: .utf8)
        XCTAssertTrue(content.contains("type: workout"), "Workout note frontmatter missing: \(content)")
        XCTAssertTrue(content.contains("# Running"), "Workout note body missing: \(content)")
    }

    func testExportHealthData_dailyNoteInjectionResolvesFromVaultRoot() throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"

        let settings = makeIsolatedSettings()
        settings.exportFormats = [.markdown]
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"
        settings.dailyNoteInjection.filenamePattern = "{date}"

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        )

        XCTAssertTrue(result)
        let dailyFilename = settings.dailyNoteInjection.formatFilename(
            for: ExportFixtures.referenceDate,
            timeZone: settings.exportTimeZoneOverride ?? .current
        ) + ".md"
        let rootDailyNote = vaultURL
            .appendingPathComponent("Daily")
            .appendingPathComponent(dailyFilename)
        let legacyHealthDailyNote = vaultURL
            .appendingPathComponent("Health")
            .appendingPathComponent("Daily")
            .appendingPathComponent(dailyFilename)
        let aggregate = vaultURL
            .appendingPathComponent("Health")
            .appendingPathComponent(settings.filename(for: ExportFixtures.referenceDate, format: .markdown))

        XCTAssertTrue(FileManager.default.fileExists(atPath: aggregate.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootDailyNote.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyHealthDailyNote.path))
    }

    func testDailyNotesOnlyWritesExactlyTheDailyNoteAndPreservesOtherPreferences() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"

        let settings = makeIsolatedSettings()
        settings.exportFormats = Set(ExportFormat.allCases)
        settings.archiveExportFiles = true
        settings.generateRangeSummary = true
        settings.summaryOnlyExport = true
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.setTrackIndividually("weight", enabled: true)
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"
        settings.dailyNoteInjection.filenamePattern = "{date}"

        let result = try await manager.exportHealthData(ExportFixtures.fullDay, settings: settings)
        let dailyNoteURL = ExportPathPlanner.dailyNoteURL(
            vaultURL: vaultURL,
            settings: settings.dailyNoteInjection,
            date: ExportFixtures.referenceDate,
            timeZone: settings.exportTimeZoneOverride ?? .current
        )
        let rootItems = try FileManager.default.contentsOfDirectory(atPath: vaultURL.path)
        let dailyItems = try FileManager.default.contentsOfDirectory(
            atPath: vaultURL.appendingPathComponent("Daily").path
        )

        XCTAssertEqual(result.aggregateFileCount, 0)
        XCTAssertEqual(result.individualEntryFileCount, 0)
        XCTAssertEqual(result.dailyNoteUpdatedCount, 1)
        XCTAssertEqual(rootItems, ["Daily"])
        XCTAssertEqual(dailyItems, [dailyNoteURL.lastPathComponent])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Health/\(HealthMdExportSchema.dataDictionaryFilename)").path
        ))
        XCTAssertEqual(settings.exportFormats, Set(ExportFormat.allCases))
        XCTAssertTrue(settings.archiveExportFiles)
        XCTAssertTrue(settings.summaryOnlyExport)
        XCTAssertEqual(
            manager.lastExportPresentationTarget,
            ExportPresentationTarget(
                fileURL: dailyNoteURL,
                securityScopedRootURL: vaultURL
            )
        )
    }

    func testDailyNotesOnlyMissingNoteReturnsTerminalSkipResultWithoutOtherFiles() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        let settings = makeIsolatedSettings()
        settings.exportFormats = []
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true
        settings.dailyNoteInjection.createIfMissing = false
        settings.dailyNoteInjection.folderPath = "Daily"

        let result = try await manager.exportHealthData(ExportFixtures.fullDay, settings: settings)

        XCTAssertEqual(result.dailyNoteUpdatedCount, 0)
        XCTAssertEqual(result.dailyNoteSkippedCount, 1)
        if case .skipped(let reason) = result.dailyNoteResult {
            XCTAssertTrue(reason.contains("not found"))
        } else {
            XCTFail("Expected a missing-note skip")
        }
        XCTAssertTrue(try FileManager.default.subpathsOfDirectory(atPath: vaultURL.path).isEmpty)
        XCTAssertNil(manager.lastExportPresentationTarget)
    }

    func testManualExportRunsDailyNoteInjectionWhenEnabled() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"

        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"
        settings.dailyNoteInjection.filenamePattern = "{date}"

        try await manager.exportHealthData(ExportFixtures.fullDay, settings: settings)

        let dailyRelativePath = settings.dailyNoteInjection.previewPath(
            for: ExportFixtures.referenceDate,
            timeZone: settings.exportTimeZoneOverride ?? .current
        )
        let dailyNoteURL = ExportPathPlanner.dailyNoteURL(
            vaultURL: vaultURL,
            settings: settings.dailyNoteInjection,
            date: ExportFixtures.referenceDate,
            timeZone: settings.exportTimeZoneOverride ?? .current
        )
        let aggregateURL = vaultURL
            .appendingPathComponent("Health")
            .appendingPathComponent(settings.filename(for: ExportFixtures.referenceDate, format: .json))

        XCTAssertTrue(FileManager.default.fileExists(atPath: aggregateURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dailyNoteURL.path))
        let dailyContent = try String(contentsOf: dailyNoteURL, encoding: .utf8)
        XCTAssertTrue(dailyContent.contains("steps:"))
        XCTAssertTrue(manager.lastExportStatus?.contains("injected into \(dailyRelativePath)") == true)
    }

    func testManualExport_dailyNoteCollisionBlocksMarkdownOverwriteAndPreservesNote() async throws {
        try await assertDailyNoteCollisionBlocksAggregateOverwrite(format: .markdown)
    }

    func testManualExport_dailyNoteCollisionBlocksObsidianBasesOverwriteAndPreservesNote() async throws {
        try await assertDailyNoteCollisionBlocksAggregateOverwrite(format: .obsidianBases)
    }

    func testBackgroundExport_dailyNoteCollisionReturnsFalseWithClearStatus() throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = ""

        let settings = makeCollidingDailyNoteSettings(format: .markdown)
        let dailyNoteURL = try precreateCollidingDailyNote(in: vaultURL, settings: settings)
        let originalContent = try String(contentsOf: dailyNoteURL, encoding: .utf8)

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        )

        XCTAssertFalse(result)
        XCTAssertEqual(try String(contentsOf: dailyNoteURL, encoding: .utf8), originalContent)
        XCTAssertTrue(manager.lastExportStatus?.contains("Daily Note Injection target conflicts") == true)
    }

    #if os(macOS)
    private func extractZIP(_ archiveURL: URL, to destinationURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-qq", archiveURL.path, "-d", destinationURL.path]
        let errors = Pipe()
        process.standardOutput = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let message = String(
                data: errors.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? "Unknown unzip failure"
            XCTFail(message)
        }
    }
    #endif

    private func assertDailyNoteCollisionBlocksAggregateOverwrite(format: ExportFormat) async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = ""

        let settings = makeCollidingDailyNoteSettings(format: format)
        let dailyNoteURL = try precreateCollidingDailyNote(in: vaultURL, settings: settings)
        let originalContent = try String(contentsOf: dailyNoteURL, encoding: .utf8)
        let expectedPath = settings.dailyNoteInjection.previewPath(
            for: ExportFixtures.referenceDate,
            timeZone: settings.exportTimeZoneOverride ?? .current
        )

        do {
            try await manager.exportHealthData(ExportFixtures.fullDay, settings: settings)
            XCTFail("Expected export to fail because \(format.rawValue) output collides with Daily Note Injection")
        } catch let error as ExportError {
            guard case .dailyNotePathConflict(let path) = error else {
                XCTFail("Expected dailyNotePathConflict, got \(error)")
                return
            }
            XCTAssertEqual(path, expectedPath)
            XCTAssertTrue(error.localizedDescription.contains("Daily Note Injection target conflicts"))
        }

        XCTAssertEqual(try String(contentsOf: dailyNoteURL, encoding: .utf8), originalContent)
    }

    private func makeCollidingDailyNoteSettings(format: ExportFormat) -> AdvancedExportSettings {
        let settings = makeIsolatedSettings()
        settings.exportFormats = [format]
        settings.filenameFormat = "{date}"
        settings.folderStructure = "Daily"
        settings.writeMode = .overwrite
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.createIfMissing = false
        settings.dailyNoteInjection.folderPath = "Daily"
        settings.dailyNoteInjection.filenamePattern = "{date}"
        return settings
    }

    private func precreateCollidingDailyNote(in vaultURL: URL, settings: AdvancedExportSettings) throws -> URL {
        let dailyNoteURL = ExportPathPlanner.dailyNoteURL(
            vaultURL: vaultURL,
            settings: settings.dailyNoteInjection,
            date: ExportFixtures.referenceDate,
            timeZone: settings.exportTimeZoneOverride ?? .current
        )
        try FileManager.default.createDirectory(
            at: dailyNoteURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try "# Daily note\n\nThis journal text must survive.".write(
            to: dailyNoteURL,
            atomically: true,
            encoding: .utf8
        )
        return dailyNoteURL
    }
}
