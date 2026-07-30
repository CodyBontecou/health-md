import Foundation
import os.log

nonisolated enum HealthKitQueryExecutionError {
    static let domain = "com.healthexporter.HealthKitQueryExecution"

    enum Code: Int {
        case timedOut = 1
        case circuitOpen = 2
        case unresolvedQueryBudgetExceeded = 3
    }

    static func isExecutionFailure(_ error: Error) -> Bool {
        let nsError = error as NSError
        return nsError.domain == domain && Code(rawValue: nsError.code) != nil
    }

    static func make(_ code: Code) -> NSError {
        let description: String
        switch code {
        case .timedOut:
            description = "The HealthKit query did not finish in time."
        case .circuitOpen:
            description = "The HealthKit query was skipped after an earlier timeout."
        case .unresolvedQueryBudgetExceeded:
            description = "The HealthKit query was skipped because earlier queries are still finishing."
        }
        return NSError(
            domain: domain,
            code: code.rawValue,
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }
}

nonisolated struct HealthKitQueryExecutionConfiguration: Sendable {
    let deadline: Duration
    let slowQueryThreshold: Duration
    let maximumOutstandingQueries: Int

    static let production = HealthKitQueryExecutionConfiguration(
        deadline: .seconds(30),
        slowQueryThreshold: .seconds(5),
        maximumOutstandingQueries: 4
    )

    init(
        deadline: Duration,
        slowQueryThreshold: Duration,
        maximumOutstandingQueries: Int
    ) {
        self.deadline = deadline
        self.slowQueryThreshold = slowQueryThreshold
        self.maximumOutstandingQueries = max(1, maximumOutstandingQueries)
    }
}

nonisolated struct HealthKitQueryExecutionKey: Hashable, Sendable {
    let operation: String
    let typeIdentifier: String
}

nonisolated struct HealthKitQueryExecutionSnapshot: Equatable, Sendable {
    let activeQueries: Int
    let unresolvedQueries: Int
    let waitingQueries: Int
    let openCircuits: Set<HealthKitQueryExecutionKey>
}

nonisolated private final class HealthKitQueryAdmissionWaiter: @unchecked Sendable {
    let key: HealthKitQueryExecutionKey

    private let lock = NSLock()
    private var continuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var result: Result<Void, Error>?

    init(key: HealthKitQueryExecutionKey) {
        self.key = key
    }

    var isResolved: Bool {
        lock.lock()
        let value = result != nil
        lock.unlock()
        return value
    }

    func wait() async -> Result<Void, Error> {
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

    @discardableResult
    func resolve(_ result: Result<Void, Error>) -> Bool {
        let continuation: CheckedContinuation<Result<Void, Error>, Never>?
        lock.lock()
        guard self.result == nil else {
            lock.unlock()
            return false
        }
        self.result = result
        continuation = self.continuation
        self.continuation = nil
        lock.unlock()
        continuation?.resume(returning: result)
        return true
    }
}

/// One export/capture-scoped query controller. It bounds physical workers, keeps
/// timed-out workers accounted for until their actual completion, and opens a
/// per-operation/type circuit after the first timeout.
nonisolated final class HealthKitQueryExecutionController: @unchecked Sendable {
    private enum AdmissionResolution {
        case admitted(HealthKitQueryAdmissionWaiter)
        case failed(HealthKitQueryAdmissionWaiter, NSError)
    }

    let configuration: HealthKitQueryExecutionConfiguration

    private let lock = NSLock()
    private var activeQueries = 0
    private var unresolvedQueries = 0
    private var waiters: [HealthKitQueryAdmissionWaiter] = []
    private var openCircuits: Set<HealthKitQueryExecutionKey> = []

    init(configuration: HealthKitQueryExecutionConfiguration = .production) {
        self.configuration = configuration
    }

    static func withController<T>(
        configuration: HealthKitQueryExecutionConfiguration = .production,
        operation: () async throws -> T
    ) async rethrows -> T {
        if HealthKitQueryExecutionScope.current != nil {
            return try await operation()
        }
        return try await withController(
            HealthKitQueryExecutionController(configuration: configuration),
            operation: operation
        )
    }

    /// Internal test seam for inspecting the same controller after late physical
    /// completion. Production captures use the configuration-based overload.
    static func withController<T>(
        _ controller: HealthKitQueryExecutionController,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await HealthKitQueryExecutionScope.$current.withValue(controller) {
            try await operation()
        }
    }

    fileprivate func enqueue(_ waiter: HealthKitQueryAdmissionWaiter) {
        var resolutions: [AdmissionResolution] = []
        lock.lock()
        if waiter.isResolved {
            lock.unlock()
            return
        }
        if openCircuits.contains(waiter.key) {
            resolutions.append(.failed(
                waiter,
                HealthKitQueryExecutionError.make(.circuitOpen)
            ))
        } else if unresolvedQueries >= configuration.maximumOutstandingQueries {
            resolutions.append(.failed(
                waiter,
                HealthKitQueryExecutionError.make(.unresolvedQueryBudgetExceeded)
            ))
        } else if activeQueries + unresolvedQueries < configuration.maximumOutstandingQueries {
            activeQueries += 1
            resolutions.append(.admitted(waiter))
        } else {
            waiters.append(waiter)
        }
        lock.unlock()
        apply(resolutions)
    }

    fileprivate func cancel(_ waiter: HealthKitQueryAdmissionWaiter) {
        lock.lock()
        if let index = waiters.firstIndex(where: { $0 === waiter }) {
            waiters.remove(at: index)
        }
        lock.unlock()
        waiter.resolve(.failure(CancellationError()))
    }

    func workerTimedOut(for key: HealthKitQueryExecutionKey) {
        var resolutions: [AdmissionResolution] = []
        lock.lock()
        activeQueries -= 1
        unresolvedQueries += 1
        openCircuits.insert(key)
        resolutions = drainWaitersLocked()
        lock.unlock()
        apply(resolutions)
    }

    func workerBecameUnresolvedAfterCancellation() {
        var resolutions: [AdmissionResolution] = []
        lock.lock()
        activeQueries -= 1
        unresolvedQueries += 1
        resolutions = drainWaitersLocked()
        lock.unlock()
        apply(resolutions)
    }

    func workerCompleted(wasUnresolved: Bool) {
        var resolutions: [AdmissionResolution] = []
        lock.lock()
        if wasUnresolved {
            unresolvedQueries -= 1
        } else {
            activeQueries -= 1
        }
        resolutions = drainWaitersLocked()
        lock.unlock()
        apply(resolutions)
    }

    func snapshot() -> HealthKitQueryExecutionSnapshot {
        lock.lock()
        let snapshot = HealthKitQueryExecutionSnapshot(
            activeQueries: activeQueries,
            unresolvedQueries: unresolvedQueries,
            waitingQueries: waiters.count,
            openCircuits: openCircuits
        )
        lock.unlock()
        return snapshot
    }

    private func releaseUnlaunchedAdmission() {
        var resolutions: [AdmissionResolution] = []
        lock.lock()
        activeQueries -= 1
        resolutions = drainWaitersLocked()
        lock.unlock()
        apply(resolutions)
    }

    private func drainWaitersLocked() -> [AdmissionResolution] {
        var resolutions: [AdmissionResolution] = []
        waiters.removeAll(where: { $0.isResolved })

        var index = 0
        while index < waiters.count {
            let waiter = waiters[index]
            if openCircuits.contains(waiter.key) {
                waiters.remove(at: index)
                resolutions.append(.failed(
                    waiter,
                    HealthKitQueryExecutionError.make(.circuitOpen)
                ))
            } else {
                index += 1
            }
        }

        if unresolvedQueries >= configuration.maximumOutstandingQueries {
            let pending = waiters
            waiters.removeAll()
            resolutions.append(contentsOf: pending.map {
                .failed(
                    $0,
                    HealthKitQueryExecutionError.make(.unresolvedQueryBudgetExceeded)
                )
            })
            return resolutions
        }

        while activeQueries + unresolvedQueries < configuration.maximumOutstandingQueries,
              !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            activeQueries += 1
            resolutions.append(.admitted(waiter))
        }
        return resolutions
    }

    private func apply(_ resolutions: [AdmissionResolution]) {
        for resolution in resolutions {
            switch resolution {
            case .admitted(let waiter):
                if !waiter.resolve(.success(())) {
                    releaseUnlaunchedAdmission()
                }
            case .failed(let waiter, let error):
                waiter.resolve(.failure(error))
            }
        }
    }
}

nonisolated private enum HealthKitQueryExecutionScope {
    @TaskLocal static var current: HealthKitQueryExecutionController?
}

nonisolated private enum HealthKitQueryLiveDiagnostics {
    private static let logger = Logger(
        subsystem: "com.healthexporter",
        category: "HealthKitQueryLifecycle"
    )

    static func emit(
        operation: String,
        typeIdentifier: String,
        elapsedMilliseconds: Int64,
        outcome: String
    ) {
        switch outcome {
        case "slow":
            logger.info(
                "operation=\(operation, privacy: .public) type=\(typeIdentifier, privacy: .public) elapsed_ms=\(elapsedMilliseconds) outcome=slow"
            )
        case "timeout":
            logger.error(
                "operation=\(operation, privacy: .public) type=\(typeIdentifier, privacy: .public) elapsed_ms=\(elapsedMilliseconds) outcome=timeout"
            )
        case "start":
            logger.debug(
                "operation=\(operation, privacy: .public) type=\(typeIdentifier, privacy: .public) elapsed_ms=\(elapsedMilliseconds) outcome=start"
            )
        case "completion":
            logger.debug(
                "operation=\(operation, privacy: .public) type=\(typeIdentifier, privacy: .public) elapsed_ms=\(elapsedMilliseconds) outcome=completion"
            )
        default:
            break
        }
    }
}

/// An unchecked generic box is intentional: HealthKit returns framework values
/// that are not uniformly annotated Sendable. Every mutable lifecycle field is
/// protected by `lock`, and the value crosses only through the one-shot result.
nonisolated private final class HealthKitQueryLifecycle<T>: @unchecked Sendable {
    private let lock = NSLock()
    private let controller: HealthKitQueryExecutionController
    private let key: HealthKitQueryExecutionKey
    private let query: () async throws -> T
    private let startedAt = ContinuousClock.now

    private var continuation: CheckedContinuation<Result<T, Error>, Never>?
    private var callerResult: Result<T, Error>?
    private var callerResolved = false
    private var workerFinished = false
    private var workerIsUnresolved = false
    private var workerTask: Task<Void, Never>?
    private var deadlineTask: Task<Void, Never>?
    private var slowTask: Task<Void, Never>?

    init(
        controller: HealthKitQueryExecutionController,
        key: HealthKitQueryExecutionKey,
        query: @escaping () async throws -> T
    ) {
        self.controller = controller
        self.key = key
        self.query = query
    }

    func launch() {
        HealthKitQueryLiveDiagnostics.emit(
            operation: key.operation,
            typeIdentifier: key.typeIdentifier,
            elapsedMilliseconds: 0,
            outcome: "start"
        )

        let worker = Task { [lifecycle = self] in
            await lifecycle.runQuery()
        }
        installWorker(worker)

        let deadline = controller.configuration.deadline
        let deadlineTask = Task { [lifecycle = self] in
            do {
                try await ContinuousClock().sleep(for: deadline)
            } catch {
                return
            }
            lifecycle.deadlineReached()
        }
        installDeadlineTask(deadlineTask)

        let slowThreshold = controller.configuration.slowQueryThreshold
        let slowTask = Task { [lifecycle = self] in
            do {
                try await ContinuousClock().sleep(for: slowThreshold)
            } catch {
                return
            }
            lifecycle.slowThresholdReached()
        }
        installSlowTask(slowTask)
    }

    func value() async throws -> T {
        let result = await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                installContinuation(continuation)
            }
        } onCancel: {
            self.callerCancelled()
        }
        return try result.get()
    }

    private func runQuery() async {
        let result: Result<T, Error>
        do {
            result = .success(try await query())
        } catch {
            result = .failure(error)
        }
        workerCompleted(with: result)
    }

    private func installContinuation(
        _ continuation: CheckedContinuation<Result<T, Error>, Never>
    ) {
        lock.lock()
        if let callerResult {
            lock.unlock()
            continuation.resume(returning: callerResult)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    private func installWorker(_ task: Task<Void, Never>) {
        lock.lock()
        workerTask = task
        let shouldCancel = callerResolved
        if workerFinished { workerTask = nil }
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    private func installDeadlineTask(_ task: Task<Void, Never>) {
        lock.lock()
        deadlineTask = task
        let shouldCancel = callerResolved || workerFinished
        if shouldCancel { deadlineTask = nil }
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    private func installSlowTask(_ task: Task<Void, Never>) {
        lock.lock()
        slowTask = task
        let shouldCancel = callerResolved || workerFinished
        if shouldCancel { slowTask = nil }
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    private func slowThresholdReached() {
        lock.lock()
        guard !callerResolved, !workerFinished else {
            lock.unlock()
            return
        }
        HealthKitQueryLiveDiagnostics.emit(
            operation: key.operation,
            typeIdentifier: key.typeIdentifier,
            elapsedMilliseconds: elapsedMilliseconds(),
            outcome: "slow"
        )
        lock.unlock()
    }

    private func deadlineReached() {
        let continuation: CheckedContinuation<Result<T, Error>, Never>?
        let worker: Task<Void, Never>?
        let slow: Task<Void, Never>?
        let result = Result<T, Error>.failure(
            HealthKitQueryExecutionError.make(.timedOut)
        )

        lock.lock()
        guard !callerResolved, !workerFinished else {
            lock.unlock()
            return
        }
        callerResolved = true
        workerIsUnresolved = true
        callerResult = result
        continuation = self.continuation
        self.continuation = nil
        worker = workerTask
        slow = slowTask
        controller.workerTimedOut(for: key)
        // The lifecycle lock prevents physical completion until this event has
        // been emitted, so timeout is observable while the worker is outstanding.
        HealthKitQueryLiveDiagnostics.emit(
            operation: key.operation,
            typeIdentifier: key.typeIdentifier,
            elapsedMilliseconds: elapsedMilliseconds(),
            outcome: "timeout"
        )
        lock.unlock()

        worker?.cancel()
        slow?.cancel()
        continuation?.resume(returning: result)
    }

    private func callerCancelled() {
        let continuation: CheckedContinuation<Result<T, Error>, Never>?
        let worker: Task<Void, Never>?
        let deadline: Task<Void, Never>?
        let slow: Task<Void, Never>?
        let result = Result<T, Error>.failure(CancellationError())

        lock.lock()
        guard !callerResolved, !workerFinished else {
            lock.unlock()
            return
        }
        callerResolved = true
        workerIsUnresolved = true
        callerResult = result
        continuation = self.continuation
        self.continuation = nil
        worker = workerTask
        deadline = deadlineTask
        slow = slowTask
        controller.workerBecameUnresolvedAfterCancellation()
        lock.unlock()

        worker?.cancel()
        deadline?.cancel()
        slow?.cancel()
        continuation?.resume(returning: result)
    }

    private func workerCompleted(with result: Result<T, Error>) {
        let continuation: CheckedContinuation<Result<T, Error>, Never>?
        let resultForCaller: Result<T, Error>?
        let deadline: Task<Void, Never>?
        let slow: Task<Void, Never>?
        let wasUnresolved: Bool

        lock.lock()
        guard !workerFinished else {
            lock.unlock()
            return
        }
        workerFinished = true
        wasUnresolved = workerIsUnresolved
        controller.workerCompleted(wasUnresolved: wasUnresolved)
        if callerResolved {
            continuation = nil
            resultForCaller = nil
        } else {
            callerResolved = true
            callerResult = result
            continuation = self.continuation
            self.continuation = nil
            resultForCaller = result
        }
        deadline = deadlineTask
        slow = slowTask
        workerTask = nil
        deadlineTask = nil
        slowTask = nil
        HealthKitQueryLiveDiagnostics.emit(
            operation: key.operation,
            typeIdentifier: key.typeIdentifier,
            elapsedMilliseconds: elapsedMilliseconds(),
            outcome: "completion"
        )
        lock.unlock()

        deadline?.cancel()
        slow?.cancel()
        if let resultForCaller {
            continuation?.resume(returning: resultForCaller)
        }
    }

    private func elapsedMilliseconds() -> Int64 {
        let components = startedAt.duration(to: .now).components
        return components.seconds * 1_000
            + Int64(components.attoseconds / 1_000_000_000_000_000)
    }
}

/// Executes one physical HealthKit or WorkoutKit read with a finite deadline.
/// The physical worker is deliberately unstructured so caller return never
/// awaits a descriptor that ignores cooperative Task cancellation.
nonisolated func executeHealthKitQuery<T>(
    operation: String,
    typeIdentifier: String,
    _ query: @escaping () async throws -> T
) async throws -> T {
    if let controller = HealthKitQueryExecutionScope.current {
        return try await executeBoundedHealthKitQuery(
            controller: controller,
            operation: operation,
            typeIdentifier: typeIdentifier,
            query
        )
    }

    return try await HealthKitQueryExecutionController.withController {
        guard let controller = HealthKitQueryExecutionScope.current else {
            preconditionFailure("HealthKit query controller was not installed")
        }
        return try await executeBoundedHealthKitQuery(
            controller: controller,
            operation: operation,
            typeIdentifier: typeIdentifier,
            query
        )
    }
}

nonisolated private func executeBoundedHealthKitQuery<T>(
    controller: HealthKitQueryExecutionController,
    operation: String,
    typeIdentifier: String,
    _ query: @escaping () async throws -> T
) async throws -> T {
    let key = HealthKitQueryExecutionKey(
        operation: operation,
        typeIdentifier: typeIdentifier
    )
    let waiter = HealthKitQueryAdmissionWaiter(key: key)

    let admissionResult = await withTaskCancellationHandler {
        controller.enqueue(waiter)
        return await waiter.wait()
    } onCancel: {
        controller.cancel(waiter)
    }
    try admissionResult.get()
    if Task.isCancelled {
        controller.workerCompleted(wasUnresolved: false)
        throw CancellationError()
    }

    let measuredQuery: () async throws -> T = {
        #if DEBUG
        return try await ExportPerformanceInstrumentation.measureHealthKitQuery(
            operation: operation,
            typeIdentifier: typeIdentifier,
            query: query
        )
        #else
        return try await query()
        #endif
    }
    let lifecycle = HealthKitQueryLifecycle(
        controller: controller,
        key: key,
        query: measuredQuery
    )
    lifecycle.launch()
    return try await lifecycle.value()
}

/// Synchronous counterpart for HealthKit characteristic reads. Synchronous
/// behavior is intentionally unchanged and does not use the async controller.
@inline(__always)
nonisolated func executeSynchronousHealthKitQuery<T>(
    operation: String,
    typeIdentifier: String,
    _ query: () throws -> T
) rethrows -> T {
    #if DEBUG
    return try ExportPerformanceInstrumentation.measureSynchronousHealthKitQuery(
        operation: operation,
        typeIdentifier: typeIdentifier,
        query: query
    )
    #else
    return try query()
    #endif
}
