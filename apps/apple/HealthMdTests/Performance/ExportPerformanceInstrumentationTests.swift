#if DEBUG
import XCTest
@testable import HealthMd

final class ExportPerformanceInstrumentationTests: XCTestCase {
    private enum ExpectedError: Error {
        case failure
    }

    nonisolated private final class SampleSequence: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [UInt64]
        private let fallback: UInt64

        init(values: [UInt64], fallback: UInt64) {
            self.values = values
            self.fallback = fallback
        }

        func next() -> UInt64 {
            lock.lock()
            defer { lock.unlock() }
            guard !values.isEmpty else { return fallback }
            return values.removeFirst()
        }
    }

    nonisolated private final class SampleCallState: @unchecked Sendable {
        private let lock = NSLock()
        private var callCount = 0
        private var stopReturned = false

        func nextCall() -> Int {
            lock.lock()
            defer { lock.unlock() }
            callCount += 1
            return callCount
        }

        func markStopReturned() {
            lock.lock()
            stopReturned = true
            lock.unlock()
        }

        var didStopReturn: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopReturned
        }
    }

    private actor TwoTaskBarrier {
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            await withCheckedContinuation { continuation in
                waiters.append(continuation)
                guard waiters.count == 2 else { return }
                let ready = waiters
                waiters.removeAll()
                ready.forEach { $0.resume() }
            }
        }
    }

    func testQuerySessionAggregatesCountsByOperationAndType() async throws {
        let (_, snapshot) = try await ExportPerformanceInstrumentation.withQuerySession {
            _ = try await executeHealthKitQuery(
                operation: "queryAverage",
                typeIdentifier: "heartRate"
            ) { 1 }
            _ = try await executeHealthKitQuery(
                operation: "queryAverage",
                typeIdentifier: "heartRate"
            ) { 2 }
            _ = try await executeHealthKitQuery(
                operation: "queryMax",
                typeIdentifier: "oxygenSaturation"
            ) { 3 }
        }

        XCTAssertEqual(snapshot.totalQueries, 3)
        XCTAssertEqual(snapshot.activeQueries, 0)
        XCTAssertEqual(
            snapshot.measurements[
                ExportPerformanceQueryKey(
                    operation: "queryAverage",
                    typeIdentifier: "heartRate"
                )
            ]?.count,
            2
        )
        XCTAssertEqual(
            snapshot.measurements[
                ExportPerformanceQueryKey(
                    operation: "queryMax",
                    typeIdentifier: "oxygenSaturation"
                )
            ]?.count,
            1
        )
        XCTAssertEqual(
            snapshot.totalQueries,
            snapshot.measurements.values.reduce(0) { $0 + $1.count }
        )
    }

    func testQuerySessionObservesInheritedTaskConcurrency() async {
        let barrier = TwoTaskBarrier()
        let (_, snapshot) = await ExportPerformanceInstrumentation.withQuerySession {
            async let first: Int = ExportPerformanceInstrumentation.measureHealthKitQuery(
                operation: "queryQuantityRecords",
                typeIdentifier: "steps"
            ) {
                await barrier.wait()
                return 1
            }
            async let second: Int = ExportPerformanceInstrumentation.measureHealthKitQuery(
                operation: "queryQuantityRecords",
                typeIdentifier: "steps"
            ) {
                await barrier.wait()
                return 2
            }
            _ = await (first, second)
        }

        XCTAssertEqual(snapshot.totalQueries, 2)
        XCTAssertEqual(snapshot.maximumConcurrentQueries, 2)
        XCTAssertEqual(
            snapshot.measurements[
                ExportPerformanceQueryKey(
                    operation: "queryQuantityRecords",
                    typeIdentifier: "steps"
                )
            ]?.maximumConcurrentQueries,
            2
        )
        XCTAssertEqual(snapshot.activeQueries, 0)
    }

    func testSynchronousHealthKitQueryUsesCurrentSession() async {
        let (_, snapshot) = await ExportPerformanceInstrumentation.withQuerySession {
            _ = executeSynchronousHealthKitQuery(
                operation: "queryCharacteristicRecord",
                typeIdentifier: "biologicalSex"
            ) { 1 }
        }

        XCTAssertEqual(snapshot.totalQueries, 1)
        XCTAssertEqual(
            snapshot.measurements[
                ExportPerformanceQueryKey(
                    operation: "queryCharacteristicRecord",
                    typeIdentifier: "biologicalSex"
                )
            ]?.count,
            1
        )
    }

    func testHealthKitCaptureInstallsTaskLocalQuerySession() async {
        let snapshot = await ExportPerformanceInstrumentation.measureHealthKitCapture(
            phase: "test-capture",
            itemCount: 1
        ) {
            _ = await ExportPerformanceInstrumentation.measureHealthKitQuery(
                operation: "querySum",
                typeIdentifier: "stepCount"
            ) { 42 }
            return ExportPerformanceInstrumentation.currentQuerySession?.snapshot()
        }

        XCTAssertEqual(snapshot?.totalQueries, 1)
        XCTAssertEqual(snapshot?.activeQueries, 0)
    }

    func testRequestCounterIsInheritedByChildTasks() async {
        let counter = ExportPerformanceRequestCounter()
        await ExportPerformanceInstrumentation.withRequestCounter(counter) {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        ExportPerformanceInstrumentation.recordRequest()
                    }
                }
            }
        }

        XCTAssertEqual(counter.count, 4)
    }

    func testLabTelemetryPersistsStructuredRestrictedSpan() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-performance-telemetry-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let runID = "physical-run_01"
        let telemetryURL = try ExportPerformanceInstrumentation.beginLabRun(
            runID: runID,
            target: .directFiles,
            rootDirectory: root
        )
        defer { ExportPerformanceInstrumentation.endLabRun(runID: runID) }

        let result = await ExportPerformanceInstrumentation.measureSpan(
            pipeline: "direct-file",
            phase: "render"
        ) { 42 }

        XCTAssertEqual(result, 42)
        let attributes = try FileManager.default.attributesOfItem(atPath: telemetryURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        let lines = try String(contentsOf: telemetryURL, encoding: .utf8)
            .split(separator: "\n")
        XCTAssertEqual(lines.count, 1)
        let decoder = JSONDecoder()
        let record = try decoder.decode(
            ExportPerformanceSpanRecord.self,
            from: Data(lines[0].utf8)
        )
        XCTAssertEqual(record.telemetryVersion, 1)
        XCTAssertEqual(record.sequence, 0)
        XCTAssertEqual(record.runID, runID)
        XCTAssertEqual(record.target, ExportPerformanceLabTarget.directFiles.rawValue)
        XCTAssertEqual(record.pipeline, "direct-file")
        XCTAssertEqual(record.phase, "render")
        XCTAssertEqual(record.outcome, ExportPerformanceSpanOutcome.success.rawValue)
        XCTAssertGreaterThanOrEqual(record.footprintPeakBytes ?? 0, 1)
    }

    func testLabTelemetryPersistsHealthKitOperationBreakdownWithoutTypes() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-performance-query-breakdown-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let runID = "query-breakdown"
        let telemetryURL = try ExportPerformanceInstrumentation.beginLabRun(
            runID: runID,
            target: .directFiles,
            rootDirectory: root
        )
        defer { ExportPerformanceInstrumentation.endLabRun(runID: runID) }
        let attachment = ExportPerformanceQueryMeasurement(
            count: 3,
            totalElapsedMilliseconds: 12,
            maximumElapsedMilliseconds: 7,
            maximumConcurrentQueries: 2
        )
        let quantity = ExportPerformanceQueryMeasurement(
            count: 1,
            totalElapsedMilliseconds: 5,
            maximumElapsedMilliseconds: 5,
            maximumConcurrentQueries: 1
        )
        ExportPerformanceInstrumentation.completed(
            pipeline: "healthkit",
            phase: "daily-capture-granular",
            timer: ExportPerformanceTimer(),
            querySnapshot: ExportPerformanceQuerySnapshot(
                measurements: [
                    ExportPerformanceQueryKey(
                        operation: "queryAttachmentMetadata",
                        typeIdentifier: "private-type-a"
                    ): attachment,
                    ExportPerformanceQueryKey(
                        operation: "queryQuantityRecords",
                        typeIdentifier: "private-type-b"
                    ): quantity,
                ],
                totalQueries: 4,
                totalElapsedMilliseconds: 17,
                maximumConcurrentQueries: 2,
                activeQueries: 0
            )
        )

        let decoder = JSONDecoder()
        let records = try String(contentsOf: telemetryURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(ExportPerformanceSpanRecord.self, from: Data($0.utf8)) }
        XCTAssertEqual(records.map(\.sequence), [0, 1, 2])
        let queryRecords = records.filter { $0.pipeline == "healthkit-query" }
        XCTAssertEqual(queryRecords.map(\.phase), [
            "query-attachment-metadata", "query-quantity-records"
        ])
        XCTAssertEqual(queryRecords.map(\.queryCount), [3, 1])
        XCTAssertFalse(try String(contentsOf: telemetryURL).contains("private-type"))
        XCTAssertEqual(
            ExportPerformanceInstrumentation.telemetryQueryPhase(operation: "unsafe/value"),
            "other-query"
        )
    }

    func testLabTelemetryMarksFailedHealthKitCaptureAndQueriesAsFailure() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-performance-query-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let runID = "query-failure"
        let telemetryURL = try ExportPerformanceInstrumentation.beginLabRun(
            runID: runID,
            target: .directFiles,
            rootDirectory: root
        )
        defer { ExportPerformanceInstrumentation.endLabRun(runID: runID) }

        do {
            _ = try await ExportPerformanceInstrumentation.measureHealthKitCapture(
                phase: "daily-capture-granular",
                itemCount: 1
            ) {
                _ = try await ExportPerformanceInstrumentation.measureHealthKitQuery(
                    operation: "queryAttachmentMetadata",
                    typeIdentifier: "private-type"
                ) {
                    throw ExpectedError.failure
                }
            }
            XCTFail("Expected capture to fail")
        } catch ExpectedError.failure {
            // Expected.
        }

        let decoder = JSONDecoder()
        let records = try String(contentsOf: telemetryURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(ExportPerformanceSpanRecord.self, from: Data($0.utf8)) }
        XCTAssertEqual(records.map(\.outcome), ["failure", "failure"])
        XCTAssertEqual(records.map(\.pipeline), ["healthkit", "healthkit-query"])
    }

    func testLabTelemetryResumeContinuesSequence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-performance-resume-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let runID = "resumed-run"
        let telemetryURL = try ExportPerformanceInstrumentation.beginLabRun(
            runID: runID,
            target: .directFiles,
            rootDirectory: root
        )
        ExportPerformanceInstrumentation.beginSpan(
            pipeline: "direct-file",
            phase: "capture"
        ).finish(outcome: .success)
        ExportPerformanceInstrumentation.endLabRun(runID: runID)

        _ = try ExportPerformanceInstrumentation.beginLabRun(
            runID: runID,
            target: .directFiles,
            rootDirectory: root
        )
        ExportPerformanceInstrumentation.beginSpan(
            pipeline: "direct-file",
            phase: "transfer"
        ).finish(outcome: .success)
        ExportPerformanceInstrumentation.endLabRun(runID: runID)

        let decoder = JSONDecoder()
        let records = try String(contentsOf: telemetryURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(ExportPerformanceSpanRecord.self, from: Data($0.utf8)) }
        XCTAssertEqual(records.map(\.sequence), [0, 1])
    }

    func testLabTelemetryRejectsUnsafeRunIDsAndLabels() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-performance-invalid-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertThrowsError(
            try ExportPerformanceInstrumentation.beginLabRun(
                runID: "../../private",
                target: .directRaw,
                rootDirectory: root
            )
        ) { error in
            XCTAssertEqual(
                error as? ExportPerformanceLabTelemetryError,
                .invalidRunID
            )
        }

        let runID = "safe-run"
        let telemetryURL = try ExportPerformanceInstrumentation.beginLabRun(
            runID: runID,
            target: .directRaw,
            rootDirectory: root
        )
        let span = ExportPerformanceInstrumentation.beginSpan(
            pipeline: "direct-file",
            phase: "private/date"
        )
        span.finish(outcome: .success)
        ExportPerformanceInstrumentation.endLabRun(runID: runID)
        XCTAssertEqual(try Data(contentsOf: telemetryURL), Data())
    }

    func testLabTelemetryRejectsSymlinkedRunStorage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-performance-symlink-\(UUID().uuidString)")
        let outside = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-performance-outside-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outside)
        }
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("Runs"),
            withDestinationURL: outside
        )
        XCTAssertThrowsError(
            try ExportPerformanceInstrumentation.beginLabRun(
                runID: "symlink-run",
                target: .directFiles,
                rootDirectory: root
            )
        ) { error in
            XCTAssertEqual(
                error as? ExportPerformanceLabTelemetryError,
                .unsafeRoot
            )
        }
    }

    func testLabTelemetrySequencesConcurrentNestedSpans() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("export-performance-concurrent-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let runID = "concurrent-run"
        let telemetryURL = try ExportPerformanceInstrumentation.beginLabRun(
            runID: runID,
            target: .apiEndpoint,
            rootDirectory: root
        )
        defer { ExportPerformanceInstrumentation.endLabRun(runID: runID) }

        let context = ExportPerformanceRunContext(
            runID: runID,
            target: .apiEndpoint
        )
        await ExportPerformanceInstrumentation.withRunContext(context) {
            await withTaskGroup(of: Void.self) { group in
                for _ in 0..<4 {
                    group.addTask {
                        await ExportPerformanceInstrumentation.measureSpan(
                            pipeline: "api-endpoint",
                            phase: "upload"
                        ) { await Task.yield() }
                    }
                }
            }
        }

        let decoder = JSONDecoder()
        let records = try String(contentsOf: telemetryURL, encoding: .utf8)
            .split(separator: "\n")
            .map { try decoder.decode(ExportPerformanceSpanRecord.self, from: Data($0.utf8)) }
        XCTAssertEqual(records.count, 4)
        XCTAssertEqual(records.map(\.sequence).sorted(), [0, 1, 2, 3])
        XCTAssertTrue(records.allSatisfy { $0.outcome == "success" })
    }

    func testFootprintSamplerReportsUnavailableInsteadOfZero() {
        let sampler = ExportPerformanceFootprintSampler(sample: { nil })
        sampler.startSampling()
        XCTAssertNil(sampler.stopSampling())
    }

    func testFootprintSamplerTracksPeriodicPeakWithoutBlockingStop() {
        let values = SampleSequence(values: [10, 30, 20], fallback: 20)
        let sampledPeak = expectation(description: "sampled periodic peak")
        let sampler = ExportPerformanceFootprintSampler {
            let value = values.next()
            if value == 30 { sampledPeak.fulfill() }
            return value
        }

        sampler.startSampling()
        wait(for: [sampledPeak], timeout: 1)
        let footprint = sampler.stopSampling()

        XCTAssertEqual(footprint?.startBytes, 10)
        XCTAssertEqual(footprint?.peakBytes, 30)
        XCTAssertEqual(footprint?.endBytes, 20)
    }

    func testFootprintSamplerCanBeAbandonedWithoutOccupyingAWorker() {
        weak var releasedSampler: ExportPerformanceFootprintSampler?
        autoreleasepool {
            let sampler = ExportPerformanceFootprintSampler(sample: { 10 })
            releasedSampler = sampler
            sampler.startSampling()
        }
        XCTAssertNil(releasedSampler)
    }

    func testFootprintSamplerDrainsInFlightSampleBeforeReturning() {
        let sampleStarted = expectation(description: "periodic sample started")
        let allowSampleToFinish = DispatchSemaphore(value: 0)
        let stopReturned = expectation(description: "stop returned")
        let state = SampleCallState()
        let sampler = ExportPerformanceFootprintSampler {
            let currentCall = state.nextCall()
            if currentCall == 2 {
                sampleStarted.fulfill()
                allowSampleToFinish.wait()
            }
            return UInt64(currentCall * 10)
        }

        sampler.startSampling()
        wait(for: [sampleStarted], timeout: 1)
        DispatchQueue.global().async {
            _ = sampler.stopSampling()
            state.markStopReturned()
            stopReturned.fulfill()
        }
        Thread.sleep(forTimeInterval: 0.05)
        XCTAssertFalse(state.didStopReturn)
        allowSampleToFinish.signal()
        wait(for: [stopReturned], timeout: 1)
    }

    func testThrowingQueryIsCountedAndClosesActiveMeasurement() async {
        let session = ExportPerformanceQuerySession()

        do {
            _ = try await ExportPerformanceInstrumentation.$currentQuerySession.withValue(session) {
                try await ExportPerformanceInstrumentation.measureHealthKitQuery(
                    operation: "queryFailure",
                    typeIdentifier: "testType"
                ) {
                    throw ExpectedError.failure
                }
            }
            XCTFail("Expected the measured query to throw")
        } catch ExpectedError.failure {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        let snapshot = session.snapshot()
        XCTAssertEqual(snapshot.totalQueries, 1)
        XCTAssertEqual(snapshot.maximumConcurrentQueries, 1)
        XCTAssertEqual(snapshot.activeQueries, 0)
    }
}
#endif
