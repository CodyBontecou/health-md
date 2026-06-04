import XCTest
@testable import HealthMd

final class ExportPluginTests: XCTestCase {
    private final class CallLog {
        var validations = 0
        var plans = 0
        var sideEffects = 0
    }

    private struct NoteRecord: ExportRecord {
        let exportRecordID: String
        let exportDate: Date
    }

    func testPluginRunnerInvokesPluginOncePerRecordRegardlessOfAggregateFormatCount() throws {
        let log = CallLog()
        let record = NoteRecord(exportRecordID: "2026-03-27", exportDate: Self.testDate)
        let aggregateFiles = [
            PlannedExportFile(id: "markdown", role: .aggregate(formatID: "markdown"), relativePath: "Reports/2026-03-27.md"),
            PlannedExportFile(id: "json", role: .aggregate(formatID: "json"), relativePath: "Reports/2026-03-27.json"),
            PlannedExportFile(id: "csv", role: .aggregate(formatID: "csv"), relativePath: "Reports/2026-03-27.csv")
        ]
        let plugin = AnyExportPlugin<NoteRecord>(
            id: "notes.side-effect",
            validate: { _, _ in
                log.validations += 1
                return []
            },
            planFiles: { record, _ in
                log.plans += 1
                return ExportPluginPlan(files: [PlannedExportFile(
                    id: "\(record.exportRecordID)-side-effect",
                    role: .supplemental(pluginID: "notes.side-effect"),
                    relativePath: "SideEffects/\(record.exportRecordID).md",
                    content: "side effect"
                )])
            },
            performSideEffects: { _, _ in
                log.sideEffects += 1
                return ExportPluginRunResult(pluginID: "notes.side-effect", filesWritten: 1)
            }
        )
        let runner = ExportPluginRunner(plugins: [plugin])
        let context = ExportPluginContext(
            record: record,
            operation: .write,
            aggregateFiles: aggregateFiles,
            writeMode: .overwrite
        )

        _ = try runner.validate(record: record, context: context)
        let plan = try runner.planFiles(record: record, context: context)
        let results = try runner.performSideEffects(record: record, context: context)

        XCTAssertEqual(log.validations, 1)
        XCTAssertEqual(log.plans, 1)
        XCTAssertEqual(log.sideEffects, 1)
        XCTAssertEqual(plan.files.count, 1)
        XCTAssertEqual(results.first?.filesWritten, 1)
    }

    func testMutationCollisionDetectorMatchesMutationTargetsAgainstAggregateFiles() {
        let aggregateFiles = [
            PlannedExportFile(id: "aggregate", role: .aggregate(formatID: "markdown"), relativePath: "Daily/2026-03-27.md")
        ]
        let pluginFiles = [
            PlannedExportFile(id: "daily", role: .mutation(pluginID: "daily-note"), relativePath: "Daily/2026-03-27.md"),
            PlannedExportFile(id: "entry", role: .supplemental(pluginID: "entries"), relativePath: "Daily/entries/weight.md")
        ]

        let collisions = ExportPluginCollisionDetector.mutationCollisions(
            pluginFiles: pluginFiles,
            aggregateFiles: aggregateFiles
        )

        XCTAssertEqual(collisions.count, 1)
        XCTAssertEqual(collisions.first?.pluginID, "daily-note")
        XCTAssertEqual(collisions.first?.mutationRelativePath, "Daily/2026-03-27.md")
    }

    func testExportPluginSourceDoesNotReferenceAppSpecificExportDomains() throws {
        let source = try exportKitSource(named: "ExportPlugins.swift")
        for forbidden in ["HealthData", "HealthKit", "MetricSelectionState", "HealthMetricsDictionary", "Obsidian", "Vault"] {
            XCTAssertFalse(source.contains(forbidden), "Generic plugin code must not reference \(forbidden)")
        }
    }

    private func exportKitSource(named filename: String) throws -> String {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<8 {
            let candidate = directory
                .appendingPathComponent("HealthMd")
                .appendingPathComponent("Shared")
                .appendingPathComponent("ExportKit")
                .appendingPathComponent(filename)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
            directory.deleteLastPathComponent()
        }
        throw NSError(
            domain: "ExportPluginTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate \(filename) from \(#filePath)."]
        )
    }

    private static let testDate: Date = {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.year = 2026
        components.month = 3
        components.day = 27
        components.hour = 12
        return components.date!
    }()
}
