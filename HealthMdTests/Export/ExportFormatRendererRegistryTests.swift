import XCTest
@testable import HealthMd

final class ExportFormatRendererRegistryTests: XCTestCase {
    private struct NoteRecord: ExportRecord {
        let exportRecordID: String
        let exportDate: Date
        let body: String
    }

    private struct NoteRenderer: ExportRenderer {
        let descriptor: ExportFormatDescriptor

        func render(record: NoteRecord, context: ExportRenderContext) throws -> RenderedExport {
            RenderedExport(content: "\(descriptor.id):\(record.body)", contentType: descriptor.contentType)
        }
    }

    func testRegistryDefinesCustomFormatsWithoutCentralEnum() throws {
        let record = NoteRecord(exportRecordID: "note-1", exportDate: ExportFixtures.referenceDate, body: "hello")
        let descriptor = ExportFormatDescriptor(
            id: "plainText",
            displayName: "Plain Text",
            fileExtension: "txt",
            contentType: "text/plain",
            defaultSortKey: "Plain Text"
        )
        let registry = try ExportRendererRegistry(renderers: [
            AnyExportRenderer(NoteRenderer(descriptor: descriptor))
        ])

        let rendered = try registry.render(record: record, formatID: "plainText")

        XCTAssertEqual(registry.registeredFormatIDs, ["plainText"])
        XCTAssertEqual(rendered, RenderedExport(content: "plainText:hello", contentType: "text/plain"))
    }

    func testRegistryUsesDeterministicDescriptorOrdering() throws {
        let beta = ExportFormatDescriptor(
            id: "beta",
            displayName: "Beta",
            fileExtension: "beta",
            contentType: "text/beta",
            defaultSortKey: "20-Beta"
        )
        let alpha = ExportFormatDescriptor(
            id: "alpha",
            displayName: "Alpha",
            fileExtension: "alpha",
            contentType: "text/alpha",
            defaultSortKey: "10-Alpha"
        )
        let registry = try ExportRendererRegistry(renderers: [
            AnyExportRenderer(NoteRenderer(descriptor: beta)),
            AnyExportRenderer(NoteRenderer(descriptor: alpha))
        ])

        XCTAssertEqual(registry.registeredFormatIDs, ["alpha", "beta"])
        XCTAssertEqual(try registry.descriptors(for: ["beta", "alpha"]).map(\.id), ["alpha", "beta"])
    }

    func testResolvedFilenamesApplyCollisionSuffixForDuplicateExtensions() throws {
        let markdown = ExportFormatDescriptor(
            id: "markdown",
            displayName: "Markdown",
            fileExtension: "md",
            contentType: "text/markdown",
            defaultSortKey: "Markdown"
        )
        let bases = ExportFormatDescriptor(
            id: "obsidianBases",
            displayName: "Obsidian Bases",
            fileExtension: "md",
            collisionSuffix: "-bases",
            contentType: "text/markdown",
            defaultSortKey: "Obsidian Bases"
        )
        let registry = try ExportRendererRegistry(renderers: [
            AnyExportRenderer(NoteRenderer(descriptor: bases)),
            AnyExportRenderer(NoteRenderer(descriptor: markdown))
        ])

        let filenames = try registry.resolvedFilenames(baseName: "2026-03-15").map(\.filename)

        XCTAssertEqual(filenames, ["2026-03-15.md", "2026-03-15-bases.md"])
    }

    func testResolvedFilenamesUsesStableFallbackWhenCollisionSuffixIsMissing() throws {
        let first = ExportFormatDescriptor(
            id: "first",
            displayName: "First",
            fileExtension: ".md",
            contentType: "text/markdown",
            defaultSortKey: "10-First"
        )
        let second = ExportFormatDescriptor(
            id: "second format",
            displayName: "Second",
            fileExtension: "md",
            contentType: "text/markdown",
            defaultSortKey: "20-Second"
        )
        let registry = try ExportRendererRegistry(renderers: [
            AnyExportRenderer(NoteRenderer(descriptor: second)),
            AnyExportRenderer(NoteRenderer(descriptor: first))
        ])

        let filenames = try registry.resolvedFilenames(baseName: "entry").map(\.filename)

        XCTAssertEqual(filenames, ["entry.md", "entry-second-format.md"])
    }
}

final class HealthExportRendererAdapterTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested
    // ObservableObjects; retaining avoids the macOS 26 / Swift 6 deinit crash.
    // See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testHealthDescriptorsPreserveHistoricalRawValueOrdering() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]

        XCTAssertEqual(settings.sortedExportFormats, [.csv, .json, .markdown, .obsidianBases])
        XCTAssertEqual(
            HealthExportRendererAdapter.registry(settings: settings).registeredFormatIDs,
            ["csv", "json", "markdown", "obsidianBases"]
        )
    }

    func testHealthFilenamesPreserveDuplicateMarkdownExtensionBehavior() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.filenameFormat = "{date}"

        let baseName = settings.formatFilename(for: ExportFixtures.referenceDate)

        settings.exportFormats = [.markdown, .obsidianBases]
        XCTAssertEqual(settings.filename(for: ExportFixtures.referenceDate, format: .markdown), "\(baseName).md")
        XCTAssertEqual(settings.filename(for: ExportFixtures.referenceDate, format: .obsidianBases), "\(baseName)-bases.md")

        settings.exportFormats = [.obsidianBases]
        XCTAssertEqual(settings.filename(for: ExportFixtures.referenceDate, format: .obsidianBases), "\(baseName).md")
    }

    func testHealthResolvedFilenamesMatchCurrentMultiFormatExtensions() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.filenameFormat = "Health-{date}"
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]

        let baseName = settings.formatFilename(for: ExportFixtures.referenceDate)
        let resolved = HealthExportRendererAdapter.resolvedFilenames(
            baseName: baseName,
            formats: settings.exportFormats
        )

        XCTAssertEqual(resolved.map(\.format), [.csv, .json, .markdown, .obsidianBases])
        XCTAssertEqual(resolved.map(\.filename), [
            "\(baseName).csv",
            "\(baseName).json",
            "\(baseName).md",
            "\(baseName)-bases.md"
        ])
    }

    func testHealthRendererRegistryMatchesExistingRendererOutput() throws {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.includeMetadata = true
        settings.groupByCategory = true

        let data = ExportFixtures.fullDayGranular
        let filteredData = data.filtered(by: settings.metricSelection)
        let record = HealthExportRecord(healthData: data)
        let registry = HealthExportRendererAdapter.registry(settings: settings)

        XCTAssertEqual(
            try registry.render(record: record, formatID: ExportFormat.markdown.exportKitFormatID).content,
            filteredData.toMarkdown(
                includeMetadata: settings.includeMetadata,
                groupByCategory: settings.groupByCategory,
                customization: settings.formatCustomization
            )
        )
        XCTAssertEqual(
            try registry.render(record: record, formatID: ExportFormat.obsidianBases.exportKitFormatID).content,
            filteredData.toObsidianBases(customization: settings.formatCustomization)
        )
        XCTAssertEqual(
            try jsonObject(from: registry.render(record: record, formatID: ExportFormat.json.exportKitFormatID).content),
            try jsonObject(from: filteredData.toJSON(customization: settings.formatCustomization))
        )
        XCTAssertEqual(
            try registry.render(record: record, formatID: ExportFormat.csv.exportKitFormatID).content,
            filteredData.toCSV(customization: settings.formatCustomization)
        )
    }

    func testHealthAggregatePlanPreservesCurrentPathsFilenamesOrderingAndContents() throws {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.markdown, .obsidianBases, .json, .csv]
        settings.filenameFormat = "daily/{date}"
        settings.folderStructure = "{year}//{month}"
        settings.includeMetadata = true
        settings.groupByCategory = true

        let record = HealthExportRecord(healthData: ExportFixtures.fullDay)
        let plan = try HealthAggregateExportAdapter.planAggregateFiles(
            record: record,
            settings: settings,
            healthSubfolder: "Health",
            safetyPolicy: .preserveCurrentBehavior
        )

        XCTAssertEqual(plan.files.map { file in
            guard case .aggregate(let formatID) = file.role else { return "" }
            return formatID
        }, settings.sortedExportFormats.map(\.exportKitFormatID))
        XCTAssertEqual(
            plan.displayFilenames,
            settings.sortedExportFormats.map { settings.filename(for: ExportFixtures.referenceDate, format: $0) }
        )
        XCTAssertEqual(
            plan.files.map(\.relativePath),
            settings.sortedExportFormats.map {
                ExportPathPlanner.aggregateRelativePath(
                    healthSubfolder: "Health",
                    settings: settings,
                    date: ExportFixtures.referenceDate,
                    format: $0
                )
            }
        )

        for (file, format) in zip(plan.files, settings.sortedExportFormats) {
            XCTAssertEqual(file.format, format.exportFormatDescriptor)
            XCTAssertEqual(file.contentType, format.exportFormatDescriptor.contentType)
            XCTAssertEqual(file.displayName, format.rawValue)
            let expectedContent = ExportFixtures.fullDay.export(format: format, settings: settings)
            if format == .json {
                XCTAssertEqual(try jsonObject(from: file.content), try jsonObject(from: expectedContent))
            } else {
                XCTAssertEqual(file.content, expectedContent)
            }
        }
    }

    private func jsonObject(from string: String) throws -> NSDictionary {
        let data = try XCTUnwrap(string.data(using: .utf8))
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? NSDictionary)
    }

    private func makeSettings() -> (AdvancedExportSettings, UserDefaults, String) {
        let suiteName = "healthmd.tests.export-renderer-registry.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        return (settings, defaults, suiteName)
    }
}
