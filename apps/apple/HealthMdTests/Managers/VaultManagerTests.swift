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

    override func setUp() {
        super.setUp()
        defaults = FakeUserDefaults()
        fileSystem = FakeFileSystem()
        fileCoordinator = RecordingFileCoordinator()
        bookmarkResolver = FakeBookmarkResolver()
    }

    private func seedLegacySelection(for url: URL) {
        defaults.storage["obsidianVaultPath"] = url.path
        defaults.storage["obsidianVaultName"] = url.lastPathComponent
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
        defaults.storage.removeValue(forKey: "obsidianVaultSelectionV1")
        defaults.storage["obsidianVaultPath"] = vaultURL.path
        defaults.storage["obsidianVaultName"] = vaultURL.lastPathComponent
        bookmarkResolver.resolvedURL = vaultURL
        let manager = VaultManager(
            defaults: defaults,
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        Self.retainedManagers.append(manager)
        return manager
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
        let selectionData = try XCTUnwrap(defaults.data(forKey: "obsidianVaultSelectionV1"))
        let selection = try JSONSerialization.jsonObject(with: selectionData) as? [String: Any]
        XCTAssertEqual(selection?["version"] as? Int, 1)
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
        seedLegacySelection(for: expectedURL)
        bookmarkResolver.resolvedURL = reboundURL
        bookmarkResolver.resolvedIsStale = true

        let manager = makeManager()
        let selectionData = try XCTUnwrap(defaults.data(forKey: "obsidianVaultSelectionV1"))

        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.vaultName, "Healthmd")
        XCTAssertEqual(manager.destinationState, .requiresReselectionDestinationChanged)
        XCTAssertTrue(manager.requiresVaultReselection)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), bookmark)
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultPath"), expectedURL.path)
        XCTAssertEqual(defaults.string(forKey: "obsidianVaultName"), "Healthmd")
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV1"), selectionData)
        XCTAssertTrue(bookmarkResolver.createBookmarkCalls.isEmpty)
        XCTAssertTrue(bookmarkResolver.startAccessCalls.isEmpty)
        XCTAssertTrue(fileCoordinator.calls.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)
        XCTAssertTrue(fileSystem.directories.isEmpty)

        manager.refreshVaultAccess()
        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.destinationState, .requiresReselectionDestinationChanged)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), bookmark)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV1"), selectionData)
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
        XCTAssertEqual(
            manager.lastExportStatus,
            "Saved folder unavailable. Reconnect the location in Files or re-select the folder."
        )

        manager.refreshVaultAccess()
        XCTAssertEqual(manager.vaultURL, vaultURL)
        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertFalse(manager.requiresVaultReselection)
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
        XCTAssertNotNil(defaults.storage["obsidianVaultSelectionV1"] as? Data)
        XCTAssertEqual(manager.destinationState, .available)
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

    func testSetVaultFolder_bookmarkCreationFails_preservesPreviousValidSelection() {
        let originalURL = URL(fileURLWithPath: "/tmp/OriginalVault")
        let manager = makeManager()
        manager.setVaultFolder(originalURL)
        let originalBookmark = defaults.data(forKey: "obsidianVaultBookmark")
        let originalSelection = defaults.data(forKey: "obsidianVaultSelectionV1")
        bookmarkResolver.createError = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "disk full"])

        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/FailVault"))

        XCTAssertEqual(manager.vaultURL, originalURL)
        XCTAssertEqual(manager.vaultName, "OriginalVault")
        XCTAssertEqual(manager.destinationState, .available)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultBookmark"), originalBookmark)
        XCTAssertEqual(defaults.data(forKey: "obsidianVaultSelectionV1"), originalSelection)
        XCTAssertTrue(manager.lastExportStatus?.contains("Failed to save folder access") == true)
    }

    func testExplicitReselectionAuthorizesChangedPathAndClearsIssue() {
        let originalURL = URL(fileURLWithPath: "/tmp/Healthmd")
        let changedURL = URL(fileURLWithPath: "/tmp/Healthmd(1)")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        seedLegacySelection(for: originalURL)
        bookmarkResolver.resolvedURL = changedURL
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
        firstDefaults.storage["obsidianVaultPath"] = firstVault.path
        firstDefaults.storage["obsidianVaultName"] = firstVault.lastPathComponent
        secondDefaults.storage["obsidianVaultBookmark"] = Data("second".utf8)
        secondDefaults.storage["obsidianVaultPath"] = secondVault.path
        secondDefaults.storage["obsidianVaultName"] = secondVault.lastPathComponent
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

    func testDirectExportReportsDestinationChangedWithoutFilesystemWork() {
        let expectedURL = URL(fileURLWithPath: "/tmp/Healthmd")
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        seedLegacySelection(for: expectedURL)
        bookmarkResolver.resolvedURL = URL(fileURLWithPath: "/tmp/Healthmd(1)")
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

    func testManualExport_dataDictionaryCollisionFailsBeforeCreatingAnyArtifact() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeRealFileSystemManager(vaultURL: vaultURL)
        manager.healthSubfolder = "Health"
        let settings = makeIsolatedSettings()
        settings.exportFormats = [.json]
        settings.folderStructure = ""
        settings.filenameFormat = "_healthmd_data_dictionary"
        settings.includeDataDictionary = true

        do {
            _ = try await manager.exportHealthData(ExportFixtures.fullDay, settings: settings)
            XCTFail("Expected the dictionary/artifact collision to fail")
        } catch let error as ExportError {
            guard case .dataDictionaryPathConflict(let path) = error else {
                XCTFail("Expected dataDictionaryPathConflict, got \(error)")
                return
            }
            XCTAssertEqual(path, "Health/_healthmd_data_dictionary.json")
            XCTAssertTrue(error.localizedDescription.contains("Data dictionary"))
        }

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vaultURL.path), [])
    }

    func testDataDictionaryCollisionUsesPortableCaseUnicodeAndWidthFolding() {
        let dictionary = "Health/\(HealthMdExportSchema.dataDictionaryFilename)"
        let fullWidth = dictionary.applyingTransform(.fullwidthToHalfwidth, reverse: true)
            ?? dictionary.uppercased()
        XCTAssertNotNil(ExportPathPlanner.dataDictionaryArtifactCollision(
            healthSubfolder: "Health",
            artifactRelativePaths: [dictionary.uppercased()]
        ))
        XCTAssertNotNil(ExportPathPlanner.dataDictionaryArtifactCollision(
            healthSubfolder: "Health",
            artifactRelativePaths: [fullWidth]
        ))
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
