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

// MARK: - Tests

@MainActor
final class VaultManagerTests: XCTestCase {

    // Retain VaultManager and AdvancedExportSettings to avoid macOS 26 deinit crash.
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

    func testInit_bookmarkResolutionFails_clearsBookmark() {
        defaults.storage["obsidianVaultBookmark"] = Data("bad-bookmark".utf8)
        bookmarkResolver.resolveError = NSError(domain: "test", code: 42, userInfo: nil)

        let manager = makeManager()
        XCTAssertNil(manager.vaultURL)
        XCTAssertNil(defaults.storage["obsidianVaultBookmark"])
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
        XCTAssertNil(manager.lastExportStatus)
    }

    func testSetVaultFolder_accessDenied_setsErrorStatus() {
        bookmarkResolver.accessGranted = false
        let manager = makeManager()

        manager.setVaultFolder(URL(fileURLWithPath: "/tmp/Denied"))

        XCTAssertNil(manager.vaultURL)
        XCTAssertEqual(manager.lastExportStatus, "Failed to access folder")
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

    // MARK: - Export Guard Tests

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

    func testExportHealthData_writesFileToExpectedPath() {
        let vaultURL = URL(fileURLWithPath: "/tmp/TestVault")
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL
        let manager = makeManager()
        manager.healthSubfolder = "Health"

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: makeSettings()
        )

        XCTAssertTrue(result)
        let writtenPaths = fileSystem.files.keys
        let healthPathFiles = writtenPaths.filter { $0.hasPrefix("/tmp/TestVault/Health") }
        XCTAssertFalse(healthPathFiles.isEmpty, "Should write file under vault/Health/")
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
            settings: makeSettings()
        )

        XCTAssertTrue(result)
        let writtenPaths = fileSystem.files.keys
        let vaultRootFiles = writtenPaths.filter { $0.hasPrefix("/tmp/TestVault/") }
        XCTAssertFalse(vaultRootFiles.isEmpty, "Should write file directly under vault root")
    }
}
