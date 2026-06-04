import XCTest
@testable import HealthMd
import ExportKit

final class ExportPreviewBuilderTests: XCTestCase {
    private final class FetchLog {
        var dates: [Date] = []
    }

    private struct NoteRecord: ExportRecord {
        let exportRecordID: String
        let exportDate: Date
        let body: String
    }

    private struct NoteRenderer: ExportRenderer {
        let descriptor: ExportFormatDescriptor

        func render(record: NoteRecord, context: ExportRenderContext) throws -> RenderedExport {
            RenderedExport(
                content: "\(descriptor.id):\(record.body)",
                contentType: descriptor.contentType
            )
        }
    }

    func testBuildPreviewWalksNewestFirstAndHonorsRenderAndFetchCaps() async throws {
        let oldest = date(day: 1)
        let middle = date(day: 2)
        let newest = date(day: 3)
        let records: [Date: NoteRecord?] = [
            oldest: NoteRecord(exportRecordID: "oldest", exportDate: oldest, body: "old"),
            middle: nil,
            newest: NoteRecord(exportRecordID: "newest", exportDate: newest, body: "new")
        ]
        let fetchLog = FetchLog()
        let request = try previewRequest(
            dates: [oldest, middle, newest],
            records: records,
            fetchLog: fetchLog
        )
        let builder = ExportPreviewBuilder<Date, NoteRecord>(
            maxRenderedRecords: 2,
            maxFetchAttempts: 3
        )

        let preview = try await builder.buildPreview(request)

        XCTAssertEqual(fetchLog.dates, [newest, middle, oldest])
        XCTAssertEqual(preview.records.map(\.id), ["newest", "oldest"])
        XCTAssertEqual(preview.totalRecordCount, 3)
        XCTAssertEqual(preview.renderedRecordCount, 2)
        XCTAssertEqual(preview.fetchAttemptCount, 3)
    }

    func testBuildPreviewStopsAtFetchAttemptCapBeforeOlderData() async throws {
        let oldest = date(day: 1)
        let middle = date(day: 2)
        let newest = date(day: 3)
        let records: [Date: NoteRecord?] = [
            oldest: NoteRecord(exportRecordID: "oldest", exportDate: oldest, body: "old"),
            middle: nil,
            newest: NoteRecord(exportRecordID: "newest", exportDate: newest, body: "new")
        ]
        let fetchLog = FetchLog()
        let request = try previewRequest(
            dates: [oldest, middle, newest],
            records: records,
            fetchLog: fetchLog
        )
        let builder = ExportPreviewBuilder<Date, NoteRecord>(
            maxRenderedRecords: 2,
            maxFetchAttempts: 2
        )

        let preview = try await builder.buildPreview(request)

        XCTAssertEqual(fetchLog.dates, [newest, middle])
        XCTAssertEqual(preview.records.map(\.id), ["newest"])
        XCTAssertEqual(preview.fetchAttemptCount, 2)
    }

    func testBuildPreviewReturnsEmptyWithoutFetchingWhenNoFormatsAreSelected() async throws {
        let day = date(day: 1)
        let fetchLog = FetchLog()
        let request = try previewRequest(
            dates: [day],
            selectedFormatIDs: [],
            records: [day: NoteRecord(exportRecordID: "day", exportDate: day, body: "body")],
            fetchLog: fetchLog
        )

        let preview = try await ExportPreviewBuilder<Date, NoteRecord>().buildPreview(request)

        XCTAssertTrue(preview.records.isEmpty)
        XCTAssertTrue(fetchLog.dates.isEmpty)
        XCTAssertEqual(preview.totalRecordCount, 1)
        XCTAssertEqual(preview.fetchAttemptCount, 0)
    }

    func testBuildPreviewReturnsEmptyAfterFetchingWhenRecordsHaveNoData() async throws {
        let first = date(day: 1)
        let second = date(day: 2)
        let fetchLog = FetchLog()
        let request = try previewRequest(
            dates: [first, second],
            records: [first: nil, second: nil],
            fetchLog: fetchLog
        )

        let preview = try await ExportPreviewBuilder<Date, NoteRecord>().buildPreview(request)

        XCTAssertTrue(preview.records.isEmpty)
        XCTAssertEqual(fetchLog.dates, [second, first])
        XCTAssertEqual(preview.fetchAttemptCount, 2)
    }

    func testBuildPreviewRendersMultipleFormatsIntoPlannedFiles() async throws {
        let day = date(day: 4)
        let fetchLog = FetchLog()
        let request = try previewRequest(
            dates: [day],
            selectedFormatIDs: ["markdown", "json"],
            records: [day: NoteRecord(exportRecordID: "day", exportDate: day, body: "hello")],
            fetchLog: fetchLog
        )

        let preview = try await ExportPreviewBuilder<Date, NoteRecord>().buildPreview(request)

        let files = try XCTUnwrap(preview.records.first?.files)
        XCTAssertEqual(files.map(\.filename), ["2026-03-04.json", "2026-03-04.md"])
        XCTAssertEqual(files.map(\.relativeFolderPath), ["Notes/json", "Notes/markdown"])
        XCTAssertEqual(files.map(\.content), ["json:hello", "markdown:hello"])
        XCTAssertEqual(files.map(\.format?.id), ["json", "markdown"])
        XCTAssertEqual(files.map(\.sizeLabel), ["10 B", "14 B"])
    }

    func testBuildPreviewSurfacesFetchFileAndSideEffectWarnings() async throws {
        let day = date(day: 5)
        let fetchLog = FetchLog()
        let record = NoteRecord(exportRecordID: "day", exportDate: day, body: "hello")
        let request = try previewRequest(
            dates: [day],
            records: [day: record],
            fetchLog: fetchLog,
            fetchedWarnings: [ExportWarning(id: "fetch", message: "Fetched with partial data")],
            fileWarnings: [ExportWarning(id: "file", message: "Filename adjusted")],
            supplementalPlan: ExportPreviewSupplementalPlan(
                files: [PlannedExportFile(
                    id: "daily-note",
                    role: .mutation(pluginID: "daily-note"),
                    relativePath: "Daily/2026-03-05.md",
                    content: "merged daily note",
                    displayName: "Daily Note"
                )],
                warnings: [ExportWarning(id: "side-effect", message: "Daily note missing")]
            )
        )

        let preview = try await ExportPreviewBuilder<Date, NoteRecord>().buildPreview(request)

        XCTAssertEqual(
            preview.warnings.map(\.message),
            ["Fetched with partial data", "Filename adjusted", "Daily note missing"]
        )
        XCTAssertEqual(preview.records.first?.files.count, 2)
        XCTAssertEqual(preview.records.first?.files.last?.role, .mutation(pluginID: "daily-note"))
    }

    func testDisplayContentAndPlannedFileSizeLabelsUseGenericPreviewSupport() {
        let file = PlannedExportFile(
            id: "large",
            role: .aggregate(formatID: "plain"),
            relativePath: "Reports/large.txt",
            content: String(repeating: "a", count: 2_048)
        )

        let display = file.displayContent(maximumRenderedBytes: 32, headBytes: 16, tailBytes: 8)

        XCTAssertEqual(file.filename, "large.txt")
        XCTAssertEqual(file.relativeFolderPath, "Reports")
        XCTAssertEqual(file.sizeLabel, "2.0 KB")
        XCTAssertTrue(display.isTruncated)
        XCTAssertTrue(display.text.contains("Preview truncated"))
    }

    func testGenericPreviewBuilderSourceDoesNotReferenceAppSpecificExportDomains() throws {
        let source = try exportKitSource(named: "ExportPreviewBuilding.swift")
        for forbidden in ["HealthData", "HealthKit", "MetricSelectionState", "HealthMetricsDictionary", "Obsidian", "Vault"] {
            XCTAssertFalse(source.contains(forbidden), "Generic preview builder code must not reference \(forbidden)")
        }
    }

    private func previewRequest(
        dates: [Date],
        selectedFormatIDs: [String] = ["markdown"],
        records: [Date: NoteRecord?],
        fetchLog: FetchLog,
        fetchedWarnings: [ExportWarning] = [],
        fileWarnings: [ExportWarning] = [],
        supplementalPlan: ExportPreviewSupplementalPlan = ExportPreviewSupplementalPlan()
    ) throws -> ExportPreviewRequest<Date, NoteRecord> {
        let registry = try ExportRendererRegistry(renderers: [
            AnyExportRenderer(NoteRenderer(descriptor: ExportFormatDescriptor(
                id: "markdown",
                displayName: "Markdown",
                fileExtension: "md",
                contentType: "text/markdown",
                defaultSortKey: "20-Markdown"
            ))),
            AnyExportRenderer(NoteRenderer(descriptor: ExportFormatDescriptor(
                id: "json",
                displayName: "JSON",
                fileExtension: "json",
                contentType: "application/json",
                defaultSortKey: "10-JSON"
            )))
        ])

        return ExportPreviewRequest(
            recordInputs: dates,
            selectedFormatIDs: selectedFormatIDs,
            dataSource: AnyExportRecordDataSource { date in
                fetchLog.dates.append(date)
                return ExportFetchedRecord(record: records[date] ?? nil, warnings: fetchedWarnings)
            },
            rendererRegistry: registry,
            recordReference: { date in
                ExportRecordReference(id: Self.idFormatter.string(from: date), date: date)
            },
            planAggregateFile: { record, descriptor, rendered in
                let template = ExportPathTemplate(
                    folderTemplate: "Notes/{format}",
                    filenameTemplate: "{date}",
                    fileExtension: descriptor.fileExtension
                )
                let relativePath = try template.plannedRelativePath(
                    variables: ExportPathVariables(
                        date: record.exportDate,
                        values: ["format": descriptor.id]
                    ),
                    safetyPolicy: .preserveCurrentBehavior
                )
                return PlannedExportFile(
                    id: "\(record.exportRecordID)-\(descriptor.id)",
                    role: .aggregate(formatID: descriptor.id),
                    relativePath: relativePath,
                    content: rendered.content,
                    warnings: fileWarnings,
                    format: descriptor,
                    contentType: rendered.contentType,
                    displayName: descriptor.displayName
                )
            },
            supplementalFilePlanner: { _ in supplementalPlan }
        )
    }

    private func date(day: Int) -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 3
        components.day = day
        components.hour = 12
        return components.date!
    }

    private func exportKitSource(named filename: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory
                .appendingPathComponent("ExportKit")
                .appendingPathComponent("Sources")
                .appendingPathComponent("ExportKit")
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "ExportPreviewBuilderTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate \(filename) from \(#filePath)."]
        )
    }

    private static let idFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
