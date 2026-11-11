#if DEBUG
import XCTest
@testable import HealthMd

final class HealthKitQueryExecutionTests: XCTestCase {
    nonisolated private final class LockedCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = 0

        func increment() {
            lock.lock()
            storage += 1
            lock.unlock()
        }

        var value: Int {
            lock.lock()
            let value = storage
            lock.unlock()
            return value
        }
    }

    private actor HeldQuery {
        private var continuation: CheckedContinuation<Int, Never>?
        private var released = false

        func value() async -> Int {
            if released { return 1 }
            return await withCheckedContinuation { continuation = $0 }
        }

        func release() {
            released = true
            let pending = continuation
            continuation = nil
            pending?.resume(returning: 1)
        }
    }

    /// The test releases physical completion after observing logical timeout;
    /// scheduler delays cannot accidentally turn "still outstanding" into done.
    nonisolated private final class ControlledQuery: @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: CheckedContinuation<Int, Never>?
        private var result: Int?

        func value() async -> Int {
            await withCheckedContinuation { continuation in
                lock.lock()
                if let result {
                    lock.unlock()
                    continuation.resume(returning: result)
                } else {
                    self.continuation = continuation
                    lock.unlock()
                }
            }
        }

        func complete() {
            lock.lock()
            guard result == nil else {
                lock.unlock()
                return
            }
            result = 42
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.resume(returning: 42)
        }
    }

    private func configuration(
        deadlineMilliseconds: Int64 = 30,
        maximumOutstandingQueries: Int = 2
    ) -> HealthKitQueryExecutionConfiguration {
        HealthKitQueryExecutionConfiguration(
            deadline: .milliseconds(deadlineMilliseconds),
            slowQueryThreshold: .milliseconds(10),
            maximumOutstandingQueries: maximumOutstandingQueries
        )
    }

    private func milliseconds(
        from start: ContinuousClock.Instant,
        to end: ContinuousClock.Instant = .now
    ) -> Int64 {
        let components = start.duration(to: end).components
        return components.seconds * 1_000
            + Int64(components.attoseconds / 1_000_000_000_000_000)
    }

    private func delayedValue(
        _ value: Int,
        milliseconds: Int,
        completionCounter: LockedCounter? = nil
    ) async -> Int {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(
                deadline: .now() + .milliseconds(milliseconds)
            ) {
                completionCounter?.increment()
                continuation.resume(returning: value)
            }
        }
    }

    private func waitUntil(
        timeoutMilliseconds: Int = 1_000,
        _ condition: () -> Bool
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(timeoutMilliseconds))
        while ContinuousClock.now < deadline {
            if condition() { return true }
            try? await ContinuousClock().sleep(for: .milliseconds(2))
        }
        return condition()
    }

    func testCallerReturnsByDeadlineWhenWorkerIgnoresCancellationAndCompletesLater() async {
        let controller = HealthKitQueryExecutionController(
            configuration: configuration(deadlineMilliseconds: 25)
        )
        let physicalCompletions = LockedCounter()
        let physicalQuery = ControlledQuery()
        let startedAt = ContinuousClock.now

        do {
            _ = try await HealthKitQueryExecutionController.withController(controller) {
                try await executeHealthKitQuery(
                    operation: "testTimeout",
                    typeIdentifier: "test.type"
                ) {
                    let result = await physicalQuery.value()
                    physicalCompletions.increment()
                    return result
                }
            }
            XCTFail("Expected timeout")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, HealthKitQueryExecutionError.domain)
            XCTAssertEqual(nsError.code, HealthKitQueryExecutionError.Code.timedOut.rawValue)
        }

        XCTAssertLessThan(milliseconds(from: startedAt), 300)
        XCTAssertEqual(controller.snapshot().unresolvedQueries, 1)
        physicalQuery.complete()
        let physicalWorkerReleased = await waitUntil {
            physicalCompletions.value == 1 && controller.snapshot().unresolvedQueries == 0
        }
        XCTAssertTrue(physicalWorkerReleased)
    }

    func testLateCompletionDoesNotResumeCallerTwice() async {
        let controller = HealthKitQueryExecutionController(
            configuration: configuration(deadlineMilliseconds: 20)
        )
        let physicalCompletions = LockedCounter()
        var callerCompletions = 0

        do {
            _ = try await HealthKitQueryExecutionController.withController(controller) {
                try await executeHealthKitQuery(
                    operation: "testOneShot",
                    typeIdentifier: "test.type"
                ) {
                    await self.delayedValue(
                        1,
                        milliseconds: 100,
                        completionCounter: physicalCompletions
                    )
                }
            }
            XCTFail("Expected timeout")
        } catch {
            callerCompletions += 1
        }

        let physicalWorkerFinished = await waitUntil { physicalCompletions.value == 1 }
        XCTAssertTrue(physicalWorkerFinished)
        try? await ContinuousClock().sleep(for: .milliseconds(20))
        XCTAssertEqual(callerCompletions, 1)
        XCTAssertEqual(physicalCompletions.value, 1)
        XCTAssertEqual(controller.snapshot().activeQueries, 0)
        XCTAssertEqual(controller.snapshot().unresolvedQueries, 0)
    }

    func testBlockedDiagnosticsDoNotDelayDeadlineOrReleasePhysicalOwnership() async {
        for blockedOutcome in ["start", "slow", "timeout"] {
            let observed = LockedCounter()
            let controller = HealthKitQueryExecutionController(
                configuration: configuration(deadlineMilliseconds: 25),
                diagnosticSink: { _, _, _, outcome in
                    if outcome == blockedOutcome {
                        observed.increment()
                        Thread.sleep(forTimeInterval: 0.5)
                    }
                }
            )
            let physicalCompletions = LockedCounter()
            let physicalQuery = ControlledQuery()
            let startedAt = ContinuousClock.now
            do {
                _ = try await HealthKitQueryExecutionController.withController(controller) {
                    try await executeHealthKitQuery(operation: "blockedDiagnostic", typeIdentifier: "synthetic") {
                        let result = await physicalQuery.value()
                        physicalCompletions.increment()
                        return result
                    }
                }
                XCTFail("Expected timeout with blocked \(blockedOutcome) diagnostic")
            } catch {
                XCTAssertEqual((error as NSError).domain, HealthKitQueryExecutionError.domain)
                XCTAssertEqual((error as NSError).code, HealthKitQueryExecutionError.Code.timedOut.rawValue)
            }
            XCTAssertLessThan(milliseconds(from: startedAt), 300, "Blocked \(blockedOutcome) diagnostic")
            XCTAssertEqual(controller.snapshot().unresolvedQueries, 1)
            physicalQuery.complete()
            let finished = await waitUntil(timeoutMilliseconds: 1_500) {
                observed.value == 1 && physicalCompletions.value == 1 && controller.snapshot().unresolvedQueries == 0
            }
            XCTAssertTrue(finished, "The actual worker must complete exactly once after \(blockedOutcome)")
        }
    }

    func testBlockedCompletionDiagnosticDoesNotDelaySuccessfulCaller() async throws {
        let observed = LockedCounter()
        let controller = HealthKitQueryExecutionController(
            configuration: configuration(deadlineMilliseconds: 25),
            diagnosticSink: { _, _, _, outcome in
                if outcome == "completion" {
                    observed.increment()
                    Thread.sleep(forTimeInterval: 0.5)
                }
            }
        )
        let startedAt = ContinuousClock.now
        let value = try await HealthKitQueryExecutionController.withController(controller) {
            try await executeHealthKitQuery(operation: "blockedCompletion", typeIdentifier: "synthetic") { 42 }
        }
        XCTAssertEqual(value, 42)
        XCTAssertLessThan(milliseconds(from: startedAt), 300)
        XCTAssertEqual(controller.snapshot().activeQueries, 0)
        XCTAssertEqual(controller.snapshot().unresolvedQueries, 0)
        let emitted = await waitUntil { observed.value == 1 }
        XCTAssertTrue(emitted)
    }

    func testSameOperationAndTypeCircuitFailsFastWithoutInvokingAgain() async {
        let controller = HealthKitQueryExecutionController(
            configuration: configuration(deadlineMilliseconds: 20)
        )
        let invocations = LockedCounter()

        do {
            _ = try await HealthKitQueryExecutionController.withController(controller) {
                try await executeHealthKitQuery(
                    operation: "testCircuit",
                    typeIdentifier: "test.type"
                ) {
                    invocations.increment()
                    return await self.delayedValue(1, milliseconds: 120)
                }
            }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(
                (error as NSError).code,
                HealthKitQueryExecutionError.Code.timedOut.rawValue
            )
        }

        let secondStartedAt = ContinuousClock.now
        do {
            _ = try await HealthKitQueryExecutionController.withController(controller) {
                try await executeHealthKitQuery(
                    operation: "testCircuit",
                    typeIdentifier: "test.type"
                ) {
                    invocations.increment()
                    return 2
                }
            }
            XCTFail("Expected open circuit")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, HealthKitQueryExecutionError.domain)
            XCTAssertEqual(nsError.code, HealthKitQueryExecutionError.Code.circuitOpen.rawValue)
        }

        XCTAssertLessThan(milliseconds(from: secondStartedAt), 100)
        XCTAssertEqual(invocations.value, 1)
    }

    func testTimedOutQueryDoesNotBlockDifferentHealthyQueryWithinBudget() async throws {
        let controller = HealthKitQueryExecutionController(
            configuration: configuration(
                deadlineMilliseconds: 20,
                maximumOutstandingQueries: 2
            )
        )

        do {
            _ = try await HealthKitQueryExecutionController.withController(controller) {
                try await executeHealthKitQuery(
                    operation: "testHung",
                    typeIdentifier: "test.hung"
                ) {
                    await self.delayedValue(1, milliseconds: 120)
                }
            }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(
                (error as NSError).code,
                HealthKitQueryExecutionError.Code.timedOut.rawValue
            )
        }

        let value = try await HealthKitQueryExecutionController.withController(controller) {
            try await executeHealthKitQuery(
                operation: "testHealthy",
                typeIdentifier: "test.healthy"
            ) {
                7
            }
        }
        XCTAssertEqual(value, 7)
        XCTAssertEqual(controller.snapshot().unresolvedQueries, 1)
    }

    func testCancellationReturnsWithoutAwaitingPhysicalCompletion() async {
        let controller = HealthKitQueryExecutionController(
            configuration: configuration(deadlineMilliseconds: 500)
        )
        let invocations = LockedCounter()
        let physicalCompletions = LockedCounter()

        let task = Task {
            try await HealthKitQueryExecutionController.withController(controller) {
                try await executeHealthKitQuery(
                    operation: "testCancellation",
                    typeIdentifier: "test.type"
                ) {
                    invocations.increment()
                    return await self.delayedValue(
                        1,
                        milliseconds: 180,
                        completionCounter: physicalCompletions
                    )
                }
            }
        }

        let workerStarted = await waitUntil { invocations.value == 1 }
        XCTAssertTrue(workerStarted)
        let cancelledAt = ContinuousClock.now
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertLessThan(milliseconds(from: cancelledAt), 150)
        XCTAssertEqual(controller.snapshot().unresolvedQueries, 1)
        let physicalWorkerReleased = await waitUntil {
            physicalCompletions.value == 1 && controller.snapshot().unresolvedQueries == 0
        }
        XCTAssertTrue(physicalWorkerReleased)
    }

    func testStableNSErrorDomainAndCodesIncludingBudgetFailure() async {
        XCTAssertEqual(
            HealthKitQueryExecutionError.domain,
            "com.healthexporter.HealthKitQueryExecution"
        )
        XCTAssertEqual(HealthKitQueryExecutionError.Code.timedOut.rawValue, 1)
        XCTAssertEqual(HealthKitQueryExecutionError.Code.circuitOpen.rawValue, 2)
        XCTAssertEqual(
            HealthKitQueryExecutionError.Code.unresolvedQueryBudgetExceeded.rawValue,
            3
        )

        let controller = HealthKitQueryExecutionController(
            configuration: configuration(
                deadlineMilliseconds: 20,
                maximumOutstandingQueries: 1
            )
        )
        let physicalQuery = ControlledQuery()
        defer { physicalQuery.complete() }
        do {
            _ = try await HealthKitQueryExecutionController.withController(controller) {
                try await executeHealthKitQuery(
                    operation: "testBudgetHung",
                    typeIdentifier: "test.hung"
                ) {
                    await physicalQuery.value()
                }
            }
            XCTFail("Expected timeout")
        } catch {
            XCTAssertEqual(
                (error as NSError).code,
                HealthKitQueryExecutionError.Code.timedOut.rawValue
            )
        }

        // Exercise a caller that resumes after the former 120 ms worker fixture.
        // Budget evidence must survive delayed observation, not rely on runner speed.
        try? await ContinuousClock().sleep(for: .milliseconds(160))
        XCTAssertEqual(controller.snapshot().unresolvedQueries, 1)

        let invocations = LockedCounter()
        do {
            _ = try await HealthKitQueryExecutionController.withController(controller) {
                try await executeHealthKitQuery(
                    operation: "testBudgetHealthy",
                    typeIdentifier: "test.healthy"
                ) {
                    invocations.increment()
                    return 2
                }
            }
            XCTFail("Expected unresolved-query budget failure")
        } catch {
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, HealthKitQueryExecutionError.domain)
            XCTAssertEqual(
                nsError.code,
                HealthKitQueryExecutionError.Code.unresolvedQueryBudgetExceeded.rawValue
            )
            XCTAssertEqual(
                nsError.localizedDescription,
                "The HealthKit query was skipped because earlier queries are still finishing."
            )
        }
        XCTAssertEqual(invocations.value, 0)

        physicalQuery.complete()
        let physicalWorkerReleased = await waitUntil {
            controller.snapshot().unresolvedQueries == 0
        }
        XCTAssertTrue(physicalWorkerReleased)
        do {
            let value = try await HealthKitQueryExecutionController.withController(controller) {
                try await executeHealthKitQuery(
                    operation: "testBudgetHealthy",
                    typeIdentifier: "test.healthy"
                ) {
                    invocations.increment()
                    return 2
                }
            }
            XCTAssertEqual(value, 2)
        } catch {
            XCTFail("Expected budget to recover after physical completion: \(error)")
        }
        XCTAssertEqual(invocations.value, 1)
    }
}
#endif
