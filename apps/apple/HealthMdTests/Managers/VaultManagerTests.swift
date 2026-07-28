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

final class FakeBookmarkResolver: BookmarkResolving {
    var resolvedURL: URL?
    var resolvedIsStale = false
    var resolveError: Error?
    var createdBookmarkData: Data?
    var createError: Error?
    var accessGranted = true
    var startAccessCalls: [URL] = []
    var stopAccessCalls: [URL] = []

    func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool) {
        if let error = resolveError { throw error }
        guard let url = resolvedURL else {
            throw NSError(domain: "FakeBookmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "No URL configured"])
        }
        return (url, resolvedIsStale)
    }

    func createBookmarkData(for url: URL) throws -> Data {
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
    private var bookmarkResolver: FakeBookmarkResolver!

    override func setUp() {
        super.setUp()
        defaults = FakeUserDefaults()
        fileSystem = FakeFileSystem()
        bookmarkResolver = FakeBookmarkResolver()
    }

    private func makeManager() -> VaultManager {
        let manager = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver
        )
        Self.retainedManagers.append(manager)
        return manager
    }

    private func makeSettings() -> AdvancedExportSettings {
        let settings = AdvancedExportSettings()
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeIsolatedSettings() -> AdvancedExportSettings {
        let suiteName = "VaultManagerTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: userDefaults)
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd_vault_manager_test_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func makeRealFileSystemManager(vaultURL: URL) -> VaultManager {
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = VaultManager(
            defaults: defaults,
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        Self.retainedManagers.append(manager)
        return manager
    }

    // MARK: - Init / Load Settings

    func testInit_noBookmark_vaultURLIsNil() {
        let manager = makeManager()
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.vaultName, "No vault selected")
    }

    func testInit_savedSubfolder_isRestored() {
        defaults.storage["healthSubfolder"] = "MyHealth"
        let manager = makeManager()
        XCTAssertEqual(manager.healthSubfolder, "MyHealth")
    }

    func testInit_savedBookmark_resolvesVaultURL() {
        let vaultURL = URL(fileURLWithPath: "/tmp/TestVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        bookmarkResolver.resolvedURL = vaultURL

        let manager = makeManager()
        XCTAssertEqual(manager.vaultURL, vaultURL)
        XCTAssertEqual(manager.vaultName, "TestVault")
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

    func testInit_bookmarkResolutionFails_preservesBookmarkForTransientFileProviderFailures() {
        defaults.storage["obsidianVaultBookmark"] = Data("bad-bookmark".utf8)
        defaults.storage["obsidianVaultName"] = "NetworkVault"
        bookmarkResolver.resolveError = NSError(domain: "test", code: 42, userInfo: nil)

        let manager = makeManager()
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.vaultName, "NetworkVault")
        XCTAssertNotNil(defaults.storage["obsidianVaultBookmark"])
        XCTAssertTrue(manager.hasSavedVaultFolder)
        XCTAssertEqual(
            manager.lastExportStatus,
            "Saved folder unavailable. Reconnect the location in Files or re-select the folder."
        )
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
        XCTAssertNil(manager.lastExportStatus)
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

    func testSetVaultFolder_bookmarkCreationFails_setsErrorStatus() {
        bookmarkResolver.accessGranted = true
        bookmarkResolver.createError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])
        let manager = makeManager()

        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/FailVault"))

        XCTAssertNil(manager.vaultURL)
        XCTAssertNotNil(manager.lastExportStatus)
        XCTAssertTrue(manager.lastExportStatus!.contains("Failed to save folder access"))
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

        manager.startVaultAccess()
        XCTAssertEqual(bookmarkResolver.startAccessCalls.count, 1)

        manager.stopVaultAccess()
        XCTAssertEqual(bookmarkResolver.stopAccessCalls.count, 1)
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

    // MARK: - Export Guard Tests

    func testAsyncExportKeepsMainActorResponsiveAndSecurityScopeOpenThroughWrite() async throws {
        let vaultURL = URL(fileURLWithPath: "/tmp/SlowWriteVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let slowFileSystem = SlowRecordingFileSystem()
        let manager = VaultManager(
            defaults: defaults,
            fileSystem: slowFileSystem,
            bookmarkResolver: bookmarkResolver
        )
        Self.retainedManagers.append(manager)
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
        secondDefaults.storage["obsidianVaultBookmark"] = Data("second".utf8)
        let firstManager = VaultManager(
            defaults: firstDefaults,
            fileSystem: sharedFileSystem,
            bookmarkResolver: firstResolver
        )
        let secondManager = VaultManager(
            defaults: secondDefaults,
            fileSystem: sharedFileSystem,
            bookmarkResolver: secondResolver
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

        let result = try await manager.finalizeCorpusDerivedOutputs(
            recordPayloadFiles: [payloadURL],
            recordSourceDates: [ExportFixtures.referenceDate],
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

    func testExportHealthData_emptySubfolder_writesDirectlyToVault() {
        let vaultURL = URL(fileURLWithPath: "/tmp/TestVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        manager.healthSubfolder = ""

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
        let dailyFilename = settings.dailyNoteInjection.formatFilename(for: ExportFixtures.referenceDate) + ".md"
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
        settings.generateWeeklyRollups = true
        settings.generateMonthlyRollups = true
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
            date: ExportFixtures.referenceDate
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

        let dailyRelativePath = settings.dailyNoteInjection.previewPath(for: ExportFixtures.referenceDate)
        let dailyNoteURL = ExportPathPlanner.dailyNoteURL(
            vaultURL: vaultURL,
            settings: settings.dailyNoteInjection,
            date: ExportFixtures.referenceDate
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
        let expectedPath = settings.dailyNoteInjection.previewPath(for: ExportFixtures.referenceDate)

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
            date: ExportFixtures.referenceDate
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
