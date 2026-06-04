import XCTest
@testable import HealthMd

@MainActor
final class HealthMdPortableAggregateVaultManagerParityTests: XCTestCase {
    private static var retainedManagers: [VaultManager] = []
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testRunnerAndVaultManagerAggregateOutputsMatchForAllFormats() async throws {
        let legacyVault = makeTempDir(name: "legacy-all-formats")
        let portableVault = makeTempDir(name: "portable-all-formats")
        defer { removeTempDirs(legacyVault, portableVault) }

        let settings = makeSettings()
        settings.exportFormats = Set(ExportFormat.allCases)
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        settings.writeMode = .overwrite
        settings.includeGranularData = true
        disableSideEffects(in: settings)

        let (_, result) = try await exportWithVaultManagerAndRunner(
            healthData: ExportFixtures.fullDayGranular,
            settings: settings,
            healthSubfolder: "Health",
            legacyVault: legacyVault,
            portableVault: portableVault
        )

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.filesWritten, settings.exportFormats.count)
        try assertAggregateFileParity(
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDayGranular.date,
            legacyVault: legacyVault,
            portableVault: portableVault,
            runnerResult: result
        )
    }

    func testParityHoldsWithFolderStructureAndFilenameFormatTemplates() async throws {
        let legacyVault = makeTempDir(name: "legacy-template")
        let portableVault = makeTempDir(name: "portable-template")
        defer { removeTempDirs(legacyVault, portableVault) }

        let settings = makeSettings()
        settings.exportFormats = [.markdown, .json, .csv]
        settings.filenameFormat = "health-{date}-{weekday}-{day}"
        settings.folderStructure = "Daily/{year}/{month}/{quarter}"
        settings.writeMode = .overwrite
        disableSideEffects(in: settings)

        let (_, result) = try await exportWithVaultManagerAndRunner(
            healthData: ExportFixtures.fullDay,
            settings: settings,
            healthSubfolder: "Health Data",
            legacyVault: legacyVault,
            portableVault: portableVault
        )

        XCTAssertTrue(result.isSuccess)
        let expectedFolder = ExportPathPlanner.aggregateFolderRelativePath(
            healthSubfolder: "Health Data",
            settings: settings,
            date: ExportFixtures.fullDay.date
        )
        XCTAssertFalse(expectedFolder.isEmpty)
        XCTAssertTrue(result.writtenRelativePaths.allSatisfy { $0.hasPrefix(expectedFolder + "/health-") })
        try assertAggregateFileParity(
            settings: settings,
            healthSubfolder: "Health Data",
            date: ExportFixtures.fullDay.date,
            legacyVault: legacyVault,
            portableVault: portableVault,
            runnerResult: result
        )
    }

    func testParityHoldsWhenMarkdownAndObsidianBasesAreBothSelected() async throws {
        let legacyVault = makeTempDir(name: "legacy-bases")
        let portableVault = makeTempDir(name: "portable-bases")
        defer { removeTempDirs(legacyVault, portableVault) }

        let settings = makeSettings()
        settings.exportFormats = [.markdown, .obsidianBases]
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        settings.writeMode = .overwrite
        disableSideEffects(in: settings)

        let (_, result) = try await exportWithVaultManagerAndRunner(
            healthData: ExportFixtures.fullDay,
            settings: settings,
            healthSubfolder: "Health",
            legacyVault: legacyVault,
            portableVault: portableVault
        )

        let markdownFilename = settings.filename(for: ExportFixtures.fullDay.date, format: .markdown)
        let basesFilename = settings.filename(for: ExportFixtures.fullDay.date, format: .obsidianBases)
        XCTAssertTrue(markdownFilename.hasSuffix(".md"))
        XCTAssertFalse(markdownFilename.hasSuffix("-bases.md"))
        XCTAssertTrue(basesFilename.hasSuffix("-bases.md"))
        XCTAssertEqual(Set(result.writtenFilenames), [markdownFilename, basesFilename])
        try assertAggregateFileParity(
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            legacyVault: legacyVault,
            portableVault: portableVault,
            runnerResult: result
        )
    }

    func testOverwriteModeParityReplacesExistingAggregateFiles() async throws {
        let legacyVault = makeTempDir(name: "legacy-overwrite")
        let portableVault = makeTempDir(name: "portable-overwrite")
        defer { removeTempDirs(legacyVault, portableVault) }

        let settings = makeSettings()
        settings.exportFormats = [.markdown]
        settings.writeMode = .overwrite
        disableSideEffects(in: settings)
        try seedExistingAggregateFile(
            format: .markdown,
            contents: "stale aggregate content",
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            vaults: [legacyVault, portableVault]
        )

        let (_, result) = try await exportWithVaultManagerAndRunner(
            healthData: ExportFixtures.fullDay,
            settings: settings,
            healthSubfolder: "Health",
            legacyVault: legacyVault,
            portableVault: portableVault
        )

        let expected = ExportFixtures.fullDay.export(format: .markdown, settings: settings)
        XCTAssertEqual(
            try aggregateContent(in: legacyVault, healthSubfolder: "Health", settings: settings, format: .markdown, date: ExportFixtures.fullDay.date),
            expected
        )
        try assertAggregateFileParity(
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            legacyVault: legacyVault,
            portableVault: portableVault,
            runnerResult: result
        )
    }

    func testAppendModeParityUsesExactlyTwoNewlines() async throws {
        let legacyVault = makeTempDir(name: "legacy-append")
        let portableVault = makeTempDir(name: "portable-append")
        defer { removeTempDirs(legacyVault, portableVault) }

        let settings = makeSettings()
        settings.exportFormats = [.markdown]
        settings.writeMode = .append
        disableSideEffects(in: settings)
        let existing = "existing aggregate content"
        try seedExistingAggregateFile(
            format: .markdown,
            contents: existing,
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            vaults: [legacyVault, portableVault]
        )

        let (_, result) = try await exportWithVaultManagerAndRunner(
            healthData: ExportFixtures.fullDay,
            settings: settings,
            healthSubfolder: "Health",
            legacyVault: legacyVault,
            portableVault: portableVault
        )

        let newContent = ExportFixtures.fullDay.export(format: .markdown, settings: settings)
        let expected = existing + "\n\n" + newContent
        XCTAssertEqual(
            try aggregateContent(in: legacyVault, healthSubfolder: "Health", settings: settings, format: .markdown, date: ExportFixtures.fullDay.date),
            expected
        )
        XCTAssertEqual(
            try aggregateContent(in: portableVault, healthSubfolder: "Health", settings: settings, format: .markdown, date: ExportFixtures.fullDay.date),
            expected
        )
        try assertAggregateFileParity(
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            legacyVault: legacyVault,
            portableVault: portableVault,
            runnerResult: result
        )
    }

    func testUpdateModeMarkdownParityUsesMarkdownMerger() async throws {
        let legacyVault = makeTempDir(name: "legacy-update-markdown")
        let portableVault = makeTempDir(name: "portable-update-markdown")
        defer { removeTempDirs(legacyVault, portableVault) }

        let settings = makeSettings()
        settings.exportFormats = [.markdown]
        settings.writeMode = .update
        disableSideEffects(in: settings)
        let existing = """
        ---
        date: 2026-03-15
        ---
        # Existing Health

        ## Activity
        Old activity content

        ## Personal Notes
        Keep this user-authored section.
        """
        try seedExistingAggregateFile(
            format: .markdown,
            contents: existing,
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            vaults: [legacyVault, portableVault]
        )

        let (_, result) = try await exportWithVaultManagerAndRunner(
            healthData: ExportFixtures.fullDay,
            settings: settings,
            healthSubfolder: "Health",
            legacyVault: legacyVault,
            portableVault: portableVault
        )

        let newContent = ExportFixtures.fullDay.export(format: .markdown, settings: settings)
        let expected = MarkdownMerger.merge(existing: existing, new: newContent)
        XCTAssertEqual(
            try aggregateContent(in: legacyVault, healthSubfolder: "Health", settings: settings, format: .markdown, date: ExportFixtures.fullDay.date),
            expected
        )
        XCTAssertTrue(expected.contains("Keep this user-authored section."))
        try assertAggregateFileParity(
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            legacyVault: legacyVault,
            portableVault: portableVault,
            runnerResult: result
        )
    }

    func testUpdateModeNonMarkdownParityFallsBackToOverwrite() async throws {
        let legacyVault = makeTempDir(name: "legacy-update-csv")
        let portableVault = makeTempDir(name: "portable-update-csv")
        defer { removeTempDirs(legacyVault, portableVault) }

        let settings = makeSettings()
        settings.exportFormats = [.csv]
        settings.writeMode = .update
        disableSideEffects(in: settings)
        try seedExistingAggregateFile(
            format: .csv,
            contents: "stale,csv\nold,value\n",
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            vaults: [legacyVault, portableVault]
        )

        let (_, result) = try await exportWithVaultManagerAndRunner(
            healthData: ExportFixtures.fullDay,
            settings: settings,
            healthSubfolder: "Health",
            legacyVault: legacyVault,
            portableVault: portableVault
        )

        let expected = ExportFixtures.fullDay.export(format: .csv, settings: settings)
        XCTAssertEqual(
            try aggregateContent(in: legacyVault, healthSubfolder: "Health", settings: settings, format: .csv, date: ExportFixtures.fullDay.date),
            expected
        )
        try assertAggregateFileParity(
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            legacyVault: legacyVault,
            portableVault: portableVault,
            runnerResult: result
        )
    }

    func testRunnerLegacyStatusMatchesVaultManagerAggregateStatusWhenSideEffectsAreDisabled() async throws {
        let legacyVault = makeTempDir(name: "legacy-status")
        let portableVault = makeTempDir(name: "portable-status")
        defer { removeTempDirs(legacyVault, portableVault) }

        let settings = makeSettings()
        settings.exportFormats = [.markdown, .json]
        settings.filenameFormat = "health-{date}"
        settings.folderStructure = "Daily/{year}"
        settings.writeMode = .overwrite
        disableSideEffects(in: settings)

        let (manager, result) = try await exportWithVaultManagerAndRunner(
            healthData: ExportFixtures.fullDay,
            settings: settings,
            healthSubfolder: "Health",
            legacyVault: legacyVault,
            portableVault: portableVault
        )

        XCTAssertEqual(result.legacyAggregateStatusMessage, manager.lastExportStatus)
        try assertAggregateFileParity(
            settings: settings,
            healthSubfolder: "Health",
            date: ExportFixtures.fullDay.date,
            legacyVault: legacyVault,
            portableVault: portableVault,
            runnerResult: result
        )
    }

    func testAggregateOnlyStatusFormatterBuildsVaultManagerStatusShape() {
        XCTAssertEqual(
            HealthMdAggregateExportStatusFormatter.aggregateOnlyStatusMessage(
                leadingAction: "Updated",
                relativeFolderPath: "Health/Daily/2026",
                writtenFilenames: ["2026-03-14.md", "2026-03-14.json"]
            ),
            "Updated Health/Daily/2026/2026-03-14.md, 2026-03-14.json"
        )
        XCTAssertEqual(
            HealthMdAggregateExportStatusFormatter.aggregateOnlyStatusMessage(
                leadingAction: "Exported to",
                relativeFolderPath: "",
                writtenFilenames: ["2026-03-14.md"]
            ),
            "Exported to 2026-03-14.md"
        )
        XCTAssertNil(
            HealthMdAggregateExportStatusFormatter.aggregateOnlyStatusMessage(
                leadingAction: "Exported to",
                relativeFolderPath: "Health",
                writtenFilenames: []
            )
        )
    }

    func testRunnerDoesNotCreateDailyNoteOrIndividualEntrySideEffectsWhenSettingsAreEnabled() async throws {
        let portableVault = makeTempDir(name: "portable-no-side-effects")
        defer { removeTempDirs(portableVault) }

        let settings = makeSettings()
        settings.exportFormats = [.markdown]
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        settings.writeMode = .overwrite
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"
        settings.dailyNoteInjection.filenamePattern = "{date}"
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.entriesFolder = "entries"
        settings.individualTracking.setTrackIndividually("weight", enabled: true)

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: portableVault,
            healthSubfolder: "Health",
            settings: settings
        )

        let dailyNoteURL = ExportPathPlanner.dailyNoteURL(
            vaultURL: portableVault,
            settings: settings.dailyNoteInjection,
            date: ExportFixtures.fullDay.date
        )
        let individualEntriesRoot = portableVault
            .appendingPathComponent("Health", isDirectory: true)
            .appendingPathComponent("entries", isDirectory: true)

        XCTAssertTrue(result.isSuccess)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dailyNoteURL.path), "Runner must not run Daily Note Injection")
        XCTAssertFalse(FileManager.default.fileExists(atPath: individualEntriesRoot.path), "Runner must not run Individual Entry Tracking")
        XCTAssertEqual(regularFiles(in: portableVault), result.writtenRelativePaths.sorted())
    }

    private func exportWithVaultManagerAndRunner(
        healthData: HealthData,
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        legacyVault: URL,
        portableVault: URL
    ) async throws -> (manager: VaultManager, runnerResult: HealthMdPortableAggregateExportResult) {
        let manager = makeVaultManager(vaultURL: legacyVault)
        manager.healthSubfolder = healthSubfolder
        try await manager.exportHealthData(healthData, settings: settings)

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: healthData,
            vaultURL: portableVault,
            healthSubfolder: healthSubfolder,
            settings: settings
        )
        return (manager, result)
    }

    private func assertAggregateFileParity(
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        date: Date,
        legacyVault: URL,
        portableVault: URL,
        runnerResult: HealthMdPortableAggregateExportResult,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let legacyTargets = ExportPathPlanner.aggregateOutputTargets(
            vaultURL: legacyVault,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date
        )
        let portableTargets = ExportPathPlanner.aggregateOutputTargets(
            vaultURL: portableVault,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date
        )

        XCTAssertEqual(legacyTargets.map(\.relativePath), portableTargets.map(\.relativePath), file: file, line: line)
        XCTAssertEqual(runnerResult.writtenRelativePaths, portableTargets.map(\.relativePath), file: file, line: line)

        for legacyTarget in legacyTargets {
            let portableTarget = try XCTUnwrap(
                portableTargets.first { $0.relativePath == legacyTarget.relativePath },
                "Missing portable target for \(legacyTarget.relativePath)",
                file: file,
                line: line
            )
            XCTAssertTrue(FileManager.default.fileExists(atPath: legacyTarget.url.path), file: file, line: line)
            XCTAssertTrue(FileManager.default.fileExists(atPath: portableTarget.url.path), file: file, line: line)
            let legacyContent = try String(contentsOf: legacyTarget.url, encoding: .utf8)
            let portableContent = try String(contentsOf: portableTarget.url, encoding: .utf8)
            // JSONSerialization does not guarantee dictionary key order across
            // separate renders; compare parsed JSON while keeping exact byte
            // parity assertions for the text formats whose ordering is stable.
            if legacyTarget.format == .json {
                XCTAssertEqual(
                    try canonicalJSONObject(from: legacyContent),
                    try canonicalJSONObject(from: portableContent),
                    "Expected canonical JSON aggregate parity for \(legacyTarget.relativePath)",
                    file: file,
                    line: line
                )
            } else {
                XCTAssertEqual(
                    legacyContent,
                    portableContent,
                    "Expected aggregate content parity for \(legacyTarget.relativePath)",
                    file: file,
                    line: line
                )
            }
        }
    }

    private func seedExistingAggregateFile(
        format: ExportFormat,
        contents: String,
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        date: Date,
        vaults: [URL]
    ) throws {
        for vault in vaults {
            let url = ExportPathPlanner.aggregateFileURL(
                vaultURL: vault,
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: date,
                format: format
            )
            try createFile(at: url, contents: contents)
        }
    }

    private func aggregateContent(
        in vault: URL,
        healthSubfolder: String,
        settings: AdvancedExportSettings,
        format: ExportFormat,
        date: Date
    ) throws -> String {
        let url = ExportPathPlanner.aggregateFileURL(
            vaultURL: vault,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: date,
            format: format
        )
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func disableSideEffects(in settings: AdvancedExportSettings) {
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suiteName = "HealthMdPortableAggregateVaultManagerParityTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: userDefaults)
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        settings.writeMode = .overwrite
        settings.includeMetadata = true
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeVaultManager(vaultURL: URL) -> VaultManager {
        let defaults = FakeUserDefaults()
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        let bookmarkResolver = FakeBookmarkResolver()
        bookmarkResolver.resolvedURL = vaultURL
        let manager = VaultManager(
            defaults: defaults,
            fileSystem: SystemFileSystem(),
            bookmarkResolver: bookmarkResolver
        )
        Self.retainedManagers.append(manager)
        return manager
    }

    private func makeTempDir(name: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd-parity-\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func removeTempDirs(_ urls: URL...) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func canonicalJSONObject(from string: String) throws -> NSObject {
        let data = Data(string.utf8)
        return try JSONSerialization.jsonObject(with: data) as! NSObject
    }

    private func regularFiles(in root: URL) -> [String] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let rootPath = root.resolvingSymlinksInPath().path
        return enumerator.compactMap { item -> String? in
            guard let url = item as? URL else { return nil }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            let path = url.resolvingSymlinksInPath().path
            guard path.hasPrefix(rootPath + "/") else { return nil }
            return String(path.dropFirst(rootPath.count + 1))
        }.sorted()
    }
}
