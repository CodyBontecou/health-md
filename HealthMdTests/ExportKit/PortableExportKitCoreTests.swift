import XCTest
@testable import HealthMd

final class PortableExportKitCoreTests: XCTestCase {
    private let calendar = Calendar(identifier: .gregorian)

    private var referenceDate: Date {
        var comps = DateComponents()
        comps.calendar = calendar
        comps.timeZone = TimeZone(secondsFromGMT: 0)
        comps.year = 2026
        comps.month = 6
        comps.day = 3
        comps.hour = 9
        comps.minute = 15
        return comps.date!
    }

    func testPathPlannerExpandsBuiltInAndRecordPlaceholders() throws {
        let root = URL(fileURLWithPath: "/tmp/ExportRoot", isDirectory: true)
        let record = SampleExportRecord(
            id: "abc123",
            date: referenceDate,
            values: ["category": "running"]
        )
        let format = PortableExportFormat(id: "markdown", displayName: "Markdown", fileExtension: "md")
        let configuration = PortableExportConfiguration(
            formats: [format],
            templates: PortableExportPathTemplates(
                baseFolderTemplate: "Exports",
                folderTemplate: "{year}/{month}/{category}",
                filenameTemplate: "{date}-{id}-{format}"
            ),
            writeMode: .overwrite,
            timezone: TimeZone(secondsFromGMT: 0)!
        )

        let plan = try PortableExportPathPlanner.planFile(
            rootURL: root,
            record: record,
            format: format,
            configuration: configuration
        )

        XCTAssertEqual(plan.relativePath, "Exports/2026/06/running/2026-06-03-abc123-markdown.md")
        XCTAssertEqual(plan.url.path, "/tmp/ExportRoot/Exports/2026/06/running/2026-06-03-abc123-markdown.md")
    }

    func testPathPlannerAddsCollisionSuffixForSameExtensionFormats() throws {
        let root = URL(fileURLWithPath: "/tmp/ExportRoot", isDirectory: true)
        let record = SampleExportRecord(id: "abc123", date: referenceDate, values: [:])
        let markdown = PortableExportFormat(id: "markdown", displayName: "Markdown", fileExtension: "md")
        let bases = PortableExportFormat(id: "bases", displayName: "Obsidian Bases", fileExtension: "md", collisionSuffix: "-bases")
        let configuration = PortableExportConfiguration(
            formats: [markdown, bases],
            templates: PortableExportPathTemplates(filenameTemplate: "{date}"),
            writeMode: .overwrite,
            timezone: TimeZone(secondsFromGMT: 0)!
        )

        let markdownPlan = try PortableExportPathPlanner.planFile(rootURL: root, record: record, format: markdown, configuration: configuration)
        let basesPlan = try PortableExportPathPlanner.planFile(rootURL: root, record: record, format: bases, configuration: configuration)

        XCTAssertEqual(markdownPlan.relativePath, "2026-06-03.md")
        XCTAssertEqual(basesPlan.relativePath, "2026-06-03-bases.md")
    }

    func testPathPlannerRejectsPathTraversalSegments() throws {
        let root = URL(fileURLWithPath: "/tmp/ExportRoot", isDirectory: true)
        let record = SampleExportRecord(id: "abc123", date: referenceDate, values: [:])
        let format = PortableExportFormat(id: "json", displayName: "JSON", fileExtension: "json")
        let configuration = PortableExportConfiguration(
            formats: [format],
            templates: PortableExportPathTemplates(folderTemplate: "../Secrets", filenameTemplate: "{date}"),
            writeMode: .overwrite,
            timezone: TimeZone(secondsFromGMT: 0)!
        )

        XCTAssertThrowsError(
            try PortableExportPathPlanner.planFile(rootURL: root, record: record, format: format, configuration: configuration)
        ) { error in
            guard case PortableExportPathError.unsafePathSegment("..") = error else {
                return XCTFail("Expected unsafePathSegment, got \(error)")
            }
        }
    }

    func testFileWriterHonorsOverwriteAppendAndUpdateMergeStrategy() throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let fileURL = tempDir.appendingPathComponent("entry.md")
        let writer = PortableExportFileWriter()

        let overwrite = try writer.write(
            PortableRenderedExportFile(url: fileURL, relativePath: "entry.md", content: "first", mergeStrategy: nil),
            mode: .overwrite
        )
        XCTAssertEqual(overwrite.action, .created)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "first")

        let append = try writer.write(
            PortableRenderedExportFile(url: fileURL, relativePath: "entry.md", content: "second", mergeStrategy: nil),
            mode: .append
        )
        XCTAssertEqual(append.action, .appended)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "first\n\nsecond")

        let update = try writer.write(
            PortableRenderedExportFile(url: fileURL, relativePath: "entry.md", content: "third", mergeStrategy: TestMergeStrategy()),
            mode: .update
        )
        XCTAssertEqual(update.action, .updated)
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "merged(first\n\nsecond -> third)")
    }

    func testOrchestratorWritesMultipleFormatsAndPluginFiles() async throws {
        let tempDir = makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let record = SampleExportRecord(
            id: "abc123",
            date: referenceDate,
            values: ["category": "running"]
        )
        let markdown = PortableExportFormat(id: "markdown", displayName: "Markdown", fileExtension: "md")
        let json = PortableExportFormat(id: "json", displayName: "JSON", fileExtension: "json")
        let configuration = PortableExportConfiguration(
            formats: [markdown, json],
            templates: PortableExportPathTemplates(
                baseFolderTemplate: "Exports",
                folderTemplate: "{category}",
                filenameTemplate: "{date}-{format}"
            ),
            writeMode: .overwrite,
            timezone: TimeZone(secondsFromGMT: 0)!
        )
        let dataSource = AnyPortableExportDataSource<SampleExportRecord> { _ in [record] }
        let markdownRenderer = AnyPortableExportRenderer<SampleExportRecord>(format: markdown) { record, context in
            "markdown \(record.portableExportID) -> \(context.relativePath)"
        }
        let jsonRenderer = AnyPortableExportRenderer<SampleExportRecord>(format: json) { record, _ in
            "{\"id\":\"\(record.portableExportID)\"}"
        }
        let plugin = AnyPortableExportPlugin<SampleExportRecord>(additionalFiles: { record, context in
            [try context.renderedFile(relativePath: "sidecars/{id}.txt", content: "sidecar \(record.portableExportID)")]
        })
        let orchestrator = PortableExportOrchestrator(
            dataSource: dataSource,
            renderers: [markdownRenderer, jsonRenderer],
            plugins: [plugin]
        )

        let result = await orchestrator.export(
            request: PortableExportRequest(dates: [referenceDate], trigger: .manual),
            destinationRoot: tempDir,
            configuration: configuration
        )

        XCTAssertTrue(result.isFullSuccess)
        XCTAssertEqual(result.successfulRecordCount, 1)
        XCTAssertEqual(result.filesWritten, 3)
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("Exports/running/2026-06-03-markdown.md"), encoding: .utf8),
            "markdown abc123 -> Exports/running/2026-06-03-markdown.md"
        )
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("Exports/running/2026-06-03-json.json"), encoding: .utf8),
            "{\"id\":\"abc123\"}"
        )
        XCTAssertEqual(
            try String(contentsOf: tempDir.appendingPathComponent("sidecars/abc123.txt"), encoding: .utf8),
            "sidecar abc123"
        )
    }

    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("portable-export-kit-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

private struct SampleExportRecord: PortableExportRecord, Equatable {
    let id: String
    let date: Date
    let values: [String: String]

    var portableExportID: String { id }
    var portableExportDate: Date { date }
    var hasPortableExportableData: Bool { true }

    func exportTemplateValue(for key: String) -> String? {
        values[key]
    }
}

private struct TestMergeStrategy: PortableExportMergeStrategy {
    func merge(existing: String, new: String) throws -> String {
        "merged(\(existing) -> \(new))"
    }
}
