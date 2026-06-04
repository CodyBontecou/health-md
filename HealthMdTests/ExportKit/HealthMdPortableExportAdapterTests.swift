import XCTest
@testable import HealthMd

@MainActor
final class HealthMdPortableExportAdapterTests: XCTestCase {
    private static var retainedSettings: [AdvancedExportSettings] = []
    private static var retainedManagers: [VaultManager] = []

    func testMapsAllHealthMdFormatsToPortableDescriptorsWithBasesCollisionSuffix() throws {
        let markdown = HealthMdPortableExportAdapter.portableFormat(for: .markdown)
        let bases = HealthMdPortableExportAdapter.portableFormat(for: .obsidianBases)
        let json = HealthMdPortableExportAdapter.portableFormat(for: .json)
        let csv = HealthMdPortableExportAdapter.portableFormat(for: .csv)

        XCTAssertEqual(markdown, PortableExportFormat(id: "markdown", displayName: "Markdown", fileExtension: "md"))
        XCTAssertEqual(bases, PortableExportFormat(id: "obsidianBases", displayName: "Obsidian Bases", fileExtension: "md", collisionSuffix: "-bases"))
        XCTAssertEqual(json, PortableExportFormat(id: "json", displayName: "JSON", fileExtension: "json"))
        XCTAssertEqual(csv, PortableExportFormat(id: "csv", displayName: "CSV", fileExtension: "csv"))

        let settings = makeSettings()
        settings.exportFormats = [.markdown, .obsidianBases]
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        let configuration = HealthMdPortableExportAdapter.configuration(
            settings: settings,
            healthSubfolder: "Health"
        )
        let record = HealthMdPortableExportRecord(healthData: ExportFixtures.partialDay, settings: settings)
        let root = URL(fileURLWithPath: "/tmp/HealthMdPortableAdapter", isDirectory: true)

        let markdownPlan = try PortableExportPathPlanner.planFile(
            rootURL: root,
            record: record,
            format: markdown,
            configuration: configuration
        )
        let basesPlan = try PortableExportPathPlanner.planFile(
            rootURL: root,
            record: record,
            format: bases,
            configuration: configuration
        )

        XCTAssertEqual(markdownPlan.relativePath, ExportPathPlanner.aggregateRelativePath(
            healthSubfolder: "Health",
            settings: settings,
            date: ExportFixtures.partialDay.date,
            format: .markdown
        ))
        XCTAssertEqual(basesPlan.relativePath, ExportPathPlanner.aggregateRelativePath(
            healthSubfolder: "Health",
            settings: settings,
            date: ExportFixtures.partialDay.date,
            format: .obsidianBases
        ))
        XCTAssertTrue(markdownPlan.relativePath.hasSuffix(".md"))
        XCTAssertTrue(basesPlan.relativePath.hasSuffix("-bases.md"))
    }

    func testAdvancedExportSettingsPathsMatchExistingExportPathPlanner() throws {
        let settings = makeSettings()
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.filenameFormat = "health-{date}-{day}"
        settings.folderStructure = "{year}/{month}/{quarter}"
        let healthSubfolder = "Health Data"
        let configuration = HealthMdPortableExportAdapter.configuration(
            settings: settings,
            healthSubfolder: healthSubfolder
        )
        let record = HealthMdPortableExportRecord(healthData: ExportFixtures.fullDay, settings: settings)
        let vaultURL = URL(fileURLWithPath: "/tmp/HealthMdPortablePathParity", isDirectory: true)

        for format in ExportFormat.allCases {
            let portableFormat = HealthMdPortableExportAdapter.portableFormat(for: format)
            let plan = try PortableExportPathPlanner.planFile(
                rootURL: vaultURL,
                record: record,
                format: portableFormat,
                configuration: configuration
            )
            let legacyRelativePath = ExportPathPlanner.aggregateRelativePath(
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: ExportFixtures.fullDay.date,
                format: format
            )
            let legacyURL = ExportPathPlanner.aggregateFileURL(
                vaultURL: vaultURL,
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: ExportFixtures.fullDay.date,
                format: format
            )

            XCTAssertEqual(plan.relativePath, legacyRelativePath, "Expected portable path parity for \(format.rawValue)")
            XCTAssertEqual(plan.url.path, legacyURL.path, "Expected portable URL parity for \(format.rawValue)")
        }
    }

    func testPortableRenderersMatchExistingHealthDataExportForEveryFormat() async throws {
        let settings = makeSettings()
        settings.exportFormats = Set(ExportFormat.allCases)
        settings.includeMetadata = true
        settings.includeGranularData = true
        let record = HealthMdPortableExportRecord(healthData: ExportFixtures.fullDay, settings: settings)
        let request = PortableExportRequest(dates: [ExportFixtures.fullDay.date], trigger: .manual)
        let configuration = HealthMdPortableExportAdapter.configuration(settings: settings, healthSubfolder: "Health")

        for format in ExportFormat.allCases {
            let portableFormat = HealthMdPortableExportAdapter.portableFormat(for: format)
            let renderer = HealthMdPortableExportAdapter.renderer(for: format)
            let context = PortableExportRenderContext(
                record: record,
                request: request,
                configuration: configuration,
                format: portableFormat,
                relativePath: "Health/fixture.\(format.fileExtension)",
                url: URL(fileURLWithPath: "/tmp/fixture.\(format.fileExtension)")
            )

            let rendered = try await renderer.render(record: record, context: context)
            let expected = ExportFixtures.fullDay.export(format: format, settings: settings)
            if format == .json {
                XCTAssertEqual(try canonicalJSONObject(from: rendered), try canonicalJSONObject(from: expected), "Expected renderer parity for \(format.rawValue)")
            } else {
                XCTAssertEqual(rendered, expected, "Expected renderer parity for \(format.rawValue)")
            }
        }
    }

    func testMarkdownRendererUsesMarkdownMergerForPortableUpdateMode() throws {
        let renderer = HealthMdPortableExportAdapter.renderer(for: .markdown)
        let mergeStrategy = try XCTUnwrap(renderer.mergeStrategy)
        let existing = """
        ---
        date: 2026-03-15
        ---
        # Existing

        ## Activity
        Old steps

        ## Personal Notes
        Keep this note.
        """
        let new = """
        ---
        date: 2026-03-15
        steps: 12500
        ---
        # New

        ## Activity
        New steps
        """

        let portableMerged = try mergeStrategy.merge(existing: existing, new: new)

        XCTAssertEqual(portableMerged, MarkdownMerger.merge(existing: existing, new: new))
        XCTAssertTrue(portableMerged.contains("New steps"))
        XCTAssertTrue(portableMerged.contains("Keep this note."))
    }

    func testPortableOrchestratorWritesSameAggregateFilesAsVaultManagerForFixtureDay() async throws {
        let legacyVault = makeTempDir(name: "healthmd-legacy-vault")
        let portableVault = makeTempDir(name: "healthmd-portable-vault")
        defer {
            try? FileManager.default.removeItem(at: legacyVault)
            try? FileManager.default.removeItem(at: portableVault)
        }

        let settings = makeSettings()
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.filenameFormat = "{date}"
        settings.folderStructure = "Daily/{year}"
        settings.writeMode = .overwrite
        settings.individualTracking.globalEnabled = false
        settings.dailyNoteInjection.enabled = false

        let manager = makeVaultManager(vaultURL: legacyVault)
        manager.healthSubfolder = "Health"
        try await manager.exportHealthData(ExportFixtures.partialDay, settings: settings)

        let record = HealthMdPortableExportRecord(healthData: ExportFixtures.partialDay, settings: settings)
        let orchestrator = PortableExportOrchestrator(
            dataSource: HealthMdPortableExportAdapter.dataSource(records: [record]),
            renderers: HealthMdPortableExportAdapter.renderers(for: settings)
        )
        let result = await orchestrator.export(
            request: PortableExportRequest(dates: [ExportFixtures.partialDay.date], trigger: .manual),
            destinationRoot: portableVault,
            configuration: HealthMdPortableExportAdapter.configuration(settings: settings, healthSubfolder: "Health")
        )

        XCTAssertTrue(result.isFullSuccess)
        XCTAssertEqual(result.filesWritten, settings.exportFormats.count)

        for target in ExportPathPlanner.aggregateOutputTargets(
            vaultURL: legacyVault,
            healthSubfolder: "Health",
            settings: settings,
            date: ExportFixtures.partialDay.date
        ) {
            let portableURL = portableVault.appendingPathComponent(target.relativePath)
            XCTAssertTrue(FileManager.default.fileExists(atPath: portableURL.path), "Expected portable file at \(target.relativePath)")
            let portableContent = try String(contentsOf: portableURL, encoding: .utf8)
            let legacyContent = try String(contentsOf: target.url, encoding: .utf8)
            if target.format == .json {
                XCTAssertEqual(
                    try canonicalJSONObject(from: portableContent),
                    try canonicalJSONObject(from: legacyContent),
                    "Expected file content parity for \(target.relativePath)"
                )
            } else {
                XCTAssertEqual(
                    portableContent,
                    legacyContent,
                    "Expected file content parity for \(target.relativePath)"
                )
            }
        }
    }

    private func canonicalJSONObject(from string: String) throws -> NSObject {
        let data = Data(string.utf8)
        return try JSONSerialization.jsonObject(with: data) as! NSObject
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suiteName = "HealthMdPortableExportAdapterTests.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: userDefaults)
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
            .appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
