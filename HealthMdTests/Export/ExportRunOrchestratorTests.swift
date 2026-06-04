import XCTest
@testable import HealthMd

final class ExportRunOrchestratorTests: XCTestCase {
    private struct NoteRecord: ExportRecord, Equatable {
        let id: String
        let date: Date
        let body: String

        var exportRecordID: String { id }
        var exportDate: Date { date }
    }

    private enum TestError: LocalizedError {
        case dataSourceFailed
        case writeFailed

        var errorDescription: String? {
            switch self {
            case .dataSourceFailed:
                return "Data source failed"
            case .writeFailed:
                return "Write failed"
            }
        }
    }

    func testRun_noDestinationFailsAllInputsBeforeFetching() async {
        var fetchCount = 0
        var writeCount = 0
        let orchestrator = makeOrchestrator(
            fetch: { input in
                fetchCount += 1
                return ExportFetchedRecord(record: self.record(input))
            },
            write: { _, _ in
                writeCount += 1
                return ExportRecordWriteSummary(filesWritten: 1)
            }
        )
        let request = makeRequest(inputs: [1, 2], destination: nil)

        let result = await orchestrator.run(request)

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.totalCount, 2)
        XCTAssertEqual(result.failedRecords.map(\.failure.reason), [.noDestination, .noDestination])
        XCTAssertEqual(fetchCount, 0)
        XCTAssertEqual(writeCount, 0)
    }

    func testRun_noFormatsFailsAllInputsBeforeFetching() async {
        var fetchCount = 0
        let orchestrator = makeOrchestrator(fetch: { input in
            fetchCount += 1
            return ExportFetchedRecord(record: self.record(input))
        })
        let request = makeRequest(inputs: [1], formatIDs: [])

        let result = await orchestrator.run(request)

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.failedRecords.first?.failure.reason, .noFormatsSelected)
        XCTAssertEqual(result.failedRecords.first?.failure.errorDescription, "At least one export format must be selected")
        XCTAssertEqual(fetchCount, 0)
    }

    func testRun_noDataRecordsFailureAndDoesNotWrite() async {
        var writeCount = 0
        let orchestrator = makeOrchestrator(
            fetch: { _ in ExportFetchedRecord<NoteRecord>(record: nil) },
            write: { _, _ in
                writeCount += 1
                return ExportRecordWriteSummary(filesWritten: 1)
            }
        )
        let request = makeRequest(inputs: [1])

        let result = await orchestrator.run(request)

        XCTAssertEqual(result.status, .failure)
        XCTAssertEqual(result.failedRecords.first?.failure.reason, .noData)
        XCTAssertEqual(result.filesWritten, 0)
        XCTAssertEqual(writeCount, 0)
    }

    func testRun_partialDataSourceFailureKeepsSuccessfulRecordsAndFileCounts() async {
        let orchestrator = makeOrchestrator(
            fetch: { input in
                if input == 2 { throw TestError.dataSourceFailed }
                return ExportFetchedRecord(record: self.record(input))
            },
            failureMapper: { error in
                ExportRunFailure(reason: .dataSourceError, errorDescription: error.localizedDescription)
            }
        )
        let request = makeRequest(inputs: [1, 2, 3], formatIDs: ["markdown", "json"])

        let result = await orchestrator.run(request)

        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertEqual(result.successCount, 2)
        XCTAssertEqual(result.totalCount, 3)
        XCTAssertEqual(result.filesWritten, 4)
        XCTAssertEqual(result.failedRecords.count, 1)
        XCTAssertEqual(result.failedRecords.first?.record.id, "2")
        XCTAssertEqual(result.failedRecords.first?.failure.reason, .dataSourceError)
        XCTAssertEqual(result.failedRecords.first?.failure.errorDescription, "Data source failed")
    }

    func testRun_reportsPlanningFetchingRenderingWritingAndCompletedProgress() async {
        let orchestrator = makeOrchestrator(fetch: { input in
            ExportFetchedRecord(record: self.record(input))
        })
        let request = makeRequest(inputs: [1], formatIDs: ["markdown", "json"])
        var progressEvents: [ExportProgress] = []

        let result = await orchestrator.run(request) { progress in
            progressEvents.append(progress)
        }

        XCTAssertTrue(result.isFullSuccess)
        XCTAssertEqual(progressEvents.map(\.phase), [.planning, .fetching, .rendering, .rendering, .writing, .completed])
        XCTAssertEqual(progressEvents.filter { $0.phase == .rendering }.map(\.currentFormatID), ["markdown", "json"])
        XCTAssertEqual(progressEvents.last?.successCount, 1)
        XCTAssertEqual(progressEvents.last?.filesWritten, 2)
    }

    func testRun_cancellationDuringFetchReturnsCancelledPartialResult() async {
        let probe = CancellationProbe()
        let orchestrator = makeOrchestrator(fetch: { input in
            if input == 2 {
                await probe.markSecondFetchStarted()
                try await Task.sleep(nanoseconds: 5_000_000_000)
            }
            return ExportFetchedRecord(record: self.record(input))
        })
        let request = makeRequest(inputs: [1, 2], formatIDs: ["markdown"])

        let task = Task { await orchestrator.run(request) }
        await probe.waitForSecondFetch()
        task.cancel()
        let result = await task.value

        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertEqual(result.successCount, 1)
        XCTAssertEqual(result.totalCount, 2)
        XCTAssertTrue(result.failedRecords.isEmpty)
        XCTAssertEqual(result.filesWritten, 1)
    }

    func testGenericOrchestrationSourceDoesNotReferenceAppSpecificExportDomains() throws {
        let source = try exportKitSource(named: "ExportOrchestration.swift")
        for forbidden in ["HealthData", "HealthKit", "MetricSelectionState", "HealthMetricsDictionary", "Obsidian", "Vault"] {
            XCTAssertFalse(source.contains(forbidden), "Generic orchestration code must not reference \(forbidden)")
        }
    }

    private func makeOrchestrator(
        fetch: @escaping (Int) async throws -> ExportFetchedRecord<NoteRecord>,
        write: @escaping (NoteRecord, ExportRunWriteContext) async throws -> ExportRecordWriteSummary = { _, context in
            ExportRecordWriteSummary(filesWritten: context.formatIDs.count)
        },
        failureMapper: @escaping (Error) -> ExportRunFailure = { error in
            ExportRunFailure(reason: .writeError, errorDescription: error.localizedDescription)
        }
    ) -> ExportRunOrchestrator<Int, NoteRecord> {
        ExportRunOrchestrator(
            dataSource: AnyExportRecordDataSource(fetch: fetch),
            writer: AnyExportRecordWriter(write: write),
            failureMapper: failureMapper
        )
    }

    private func makeRequest(
        inputs: [Int],
        formatIDs: [String] = ["markdown"],
        destination: ExportDestination? = ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/ExportRunOrchestratorTests"))
    ) -> ExportRunRequest<Int> {
        ExportRunRequest(
            recordInputs: inputs,
            formatIDs: formatIDs,
            destination: destination,
            recordReference: { input in
                ExportRecordReference(id: "\(input)", date: self.date(day: input))
            }
        )
    }

    private func record(_ input: Int) -> NoteRecord {
        NoteRecord(id: "\(input)", date: date(day: input), body: "Record \(input)")
    }

    private func date(day: Int) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = day
        return Calendar.current.date(from: components)!
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
            domain: "ExportRunOrchestratorTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate \(filename) from \(#filePath)."]
        )
    }
}

private actor CancellationProbe {
    private var secondFetchStarted = false
    private var continuation: CheckedContinuation<Void, Never>?

    func waitForSecondFetch() async {
        if secondFetchStarted { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func markSecondFetchStarted() {
        secondFetchStarted = true
        continuation?.resume()
        continuation = nil
    }
}
