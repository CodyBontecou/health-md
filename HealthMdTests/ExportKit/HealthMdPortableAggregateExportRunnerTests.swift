import XCTest
@testable import HealthMd

@MainActor
final class HealthMdPortableAggregateExportRunnerTests: XCTestCase {
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testRunnerWritesAllSelectedAggregateFormatsToExportPathPlannerTargets() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.filenameFormat = "health-{date}"
        settings.folderStructure = "Daily/{year}"
        settings.writeMode = .overwrite
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health Data",
            settings: settings,
            trigger: .manual
        )

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(result.filesWritten, settings.exportFormats.count)

        let expectedTargets = ExportPathPlanner.aggregateOutputTargets(
            vaultURL: vaultURL,
            healthSubfolder: "Health Data",
            settings: settings,
            date: ExportFixtures.fullDay.date
        )
        XCTAssertEqual(result.writtenRelativePaths.sorted(), expectedTargets.map(\.relativePath).sorted())

        for target in expectedTargets {
            XCTAssertTrue(FileManager.default.fileExists(atPath: target.url.path), "Expected aggregate file at \(target.relativePath)")
            let actual = try String(contentsOf: target.url, encoding: .utf8)
            let expected = ExportFixtures.fullDay.export(format: target.format, settings: settings)
            if target.format == .json {
                XCTAssertEqual(try canonicalJSONObject(from: actual), try canonicalJSONObject(from: expected))
            } else {
                XCTAssertEqual(actual, expected)
            }
        }
    }

    func testResultProvidesVaultManagerStyleAggregateStatusAndExportResultMapping() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = [.markdown, .json]
        settings.filenameFormat = "health-{date}"
        settings.folderStructure = "Daily/{year}"

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health",
            settings: settings
        )

        XCTAssertEqual(
            result.legacyAggregateStatusMessage,
            "Exported to Health/Daily/2026/\(result.writtenFilenames.joined(separator: ", "))"
        )
        XCTAssertTrue(result.exportResult.isFullSuccess)
        XCTAssertEqual(result.exportResult.totalFilesWritten, 2)
    }

    func testOverwriteModeReplacesExistingAggregateFile() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = [.markdown]
        settings.writeMode = .overwrite

        let target = aggregateTarget(vaultURL: vaultURL, settings: settings, format: .markdown)
        try createFile(at: target.url, contents: "old content")

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health",
            settings: settings
        )

        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(try String(contentsOf: target.url, encoding: .utf8), ExportFixtures.fullDay.export(format: .markdown, settings: settings))
    }

    func testAppendModeAppendsWithExactlyTwoNewlines() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = [.markdown]
        settings.writeMode = .append

        let target = aggregateTarget(vaultURL: vaultURL, settings: settings, format: .markdown)
        try createFile(at: target.url, contents: "existing content")

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health",
            settings: settings
        )

        let newContent = ExportFixtures.fullDay.export(format: .markdown, settings: settings)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(try String(contentsOf: target.url, encoding: .utf8), "existing content\n\n\(newContent)")
    }

    func testUpdateModeUsesMarkdownMergerForMarkdown() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = [.markdown]
        settings.writeMode = .update

        let target = aggregateTarget(vaultURL: vaultURL, settings: settings, format: .markdown)
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
        try createFile(at: target.url, contents: existing)

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health",
            settings: settings
        )

        let newContent = ExportFixtures.fullDay.export(format: .markdown, settings: settings)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(try String(contentsOf: target.url, encoding: .utf8), MarkdownMerger.merge(existing: existing, new: newContent))
    }

    func testUpdateModeOverwritesNonMarkdownFormats() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = [.json]
        settings.writeMode = .update

        let target = aggregateTarget(vaultURL: vaultURL, settings: settings, format: .json)
        try createFile(at: target.url, contents: "{\"stale\":true}")

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health",
            settings: settings
        )

        let expected = ExportFixtures.fullDay.export(format: .json, settings: settings)
        XCTAssertTrue(result.isSuccess)
        XCTAssertEqual(try canonicalJSONObject(from: try String(contentsOf: target.url, encoding: .utf8)), try canonicalJSONObject(from: expected))
    }

    func testEmptyHealthDataReturnsNoDataFailureAndWritesNoFiles() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = [.markdown]

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.emptyDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health",
            settings: settings
        )

        XCTAssertEqual(result.outcome, .failed(.noData))
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.filesWritten, 0)
        XCTAssertEqual(regularFiles(in: vaultURL), [])
    }

    func testEmptySelectedFormatsReturnsNoFormatsFailureAndWritesNoFiles() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = []

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health",
            settings: settings
        )

        XCTAssertEqual(result.outcome, .failed(.noFormats))
        XCTAssertFalse(result.isSuccess)
        XCTAssertEqual(result.filesWritten, 0)
        XCTAssertEqual(regularFiles(in: vaultURL), [])
    }

    func testRunnerDoesNotCreateDailyNoteInjectionOutputWhenEnabled() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = [.markdown]
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = "Daily"
        settings.dailyNoteInjection.filenamePattern = "{date}"

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health",
            settings: settings
        )

        let dailyNoteURL = ExportPathPlanner.dailyNoteURL(
            vaultURL: vaultURL,
            settings: settings.dailyNoteInjection,
            date: ExportFixtures.fullDay.date
        )
        XCTAssertTrue(result.isSuccess)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dailyNoteURL.path), "Runner must not run Daily Note Injection")
    }

    func testRunnerDoesNotCreateIndividualEntryTrackingOutputWhenEnabled() async throws {
        let vaultURL = makeTempDir()
        defer { try? FileManager.default.removeItem(at: vaultURL) }
        let settings = makeSettings()
        settings.exportFormats = [.markdown]
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.setTrackIndividually("workouts", enabled: true)
        settings.individualTracking.entriesFolder = "entries"

        let result = await HealthMdPortableAggregateExportRunner().export(
            healthData: ExportFixtures.fullDay,
            vaultURL: vaultURL,
            healthSubfolder: "Health",
            settings: settings
        )

        let individualEntriesURL = vaultURL
            .appendingPathComponent("Health", isDirectory: true)
            .appendingPathComponent("entries", isDirectory: true)
        XCTAssertTrue(result.isSuccess)
        XCTAssertFalse(FileManager.default.fileExists(atPath: individualEntriesURL.path), "Runner must not run Individual Entry Tracking")
    }

    private func aggregateTarget(
        vaultURL: URL,
        healthSubfolder: String = "Health",
        settings: AdvancedExportSettings,
        format: ExportFormat
    ) -> ExportPathPlanner.AggregateOutputTarget {
        ExportPathPlanner.aggregateOutputTargets(
            vaultURL: vaultURL,
            healthSubfolder: healthSubfolder,
            settings: settings,
            date: ExportFixtures.fullDay.date
        ).first { $0.format == format }!
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suiteName = "HealthMdPortableAggregateExportRunnerTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: userDefaults)
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        settings.writeMode = .overwrite
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd-portable-aggregate-runner-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func createFile(at url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
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

        return enumerator.compactMap { item -> String? in
            guard let url = item as? URL else { return nil }
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { return nil }
            return String(url.path.dropFirst(root.path.count + 1))
        }.sorted()
    }
}
