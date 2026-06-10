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
