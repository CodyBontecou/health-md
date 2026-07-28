#if DEBUG
import XCTest
@testable import HealthMd

final class ExportPerformanceInstrumentationTests: XCTestCase {
    private enum ExpectedError: Error {
        case failure
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

    func testQuerySessionAggregatesCountsByOperationAndType() async {
        let (_, snapshot) = await ExportPerformanceInstrumentation.withQuerySession {
            _ = await executeHealthKitQuery(
                operation: "queryAverage",
                typeIdentifier: "heartRate"
            ) { 1 }
            _ = await executeHealthKitQuery(
                operation: "queryAverage",
                typeIdentifier: "heartRate"
            ) { 2 }
            _ = await executeHealthKitQuery(
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
