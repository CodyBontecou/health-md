#if DEBUG
import Foundation
import os.log

/// Debug-only wall-clock timer for local export profiling.
///
/// This file is excluded from non-Debug builds. Call sites are also compile-time
/// gated so App Store builds contain no export instrumentation implementation.
nonisolated struct ExportPerformanceTimer: Sendable {
    private let startedAt = ContinuousClock.now

    func elapsedMilliseconds() -> Int64 {
        Self.milliseconds(from: startedAt.duration(to: .now))
    }

    static func milliseconds(from duration: Duration) -> Int64 {
        let components = duration.components
        return components.seconds * 1_000
            + Int64(components.attoseconds / 1_000_000_000_000_000)
    }
}

nonisolated struct ExportPerformanceQueryKey: Hashable, Sendable {
    let operation: String
    let typeIdentifier: String
}

nonisolated struct ExportPerformanceQueryMeasurement: Equatable, Sendable {
    let count: Int
    let totalElapsedMilliseconds: Int64
    let maximumElapsedMilliseconds: Int64
    let maximumConcurrentQueries: Int
}

nonisolated struct ExportPerformanceQuerySnapshot: Equatable, Sendable {
    let measurements: [ExportPerformanceQueryKey: ExportPerformanceQueryMeasurement]
    let totalQueries: Int
    let totalElapsedMilliseconds: Int64
    let maximumConcurrentQueries: Int
    let activeQueries: Int

    static let empty = ExportPerformanceQuerySnapshot(
        measurements: [:],
        totalQueries: 0,
        totalElapsedMilliseconds: 0,
        maximumConcurrentQueries: 0,
        activeQueries: 0
    )
}

/// One task-local HealthKit capture session. Short lock sections protect counters
/// inherited by child tasks; the lock is never held while HealthKit work awaits.
nonisolated final class ExportPerformanceQuerySession: @unchecked Sendable {
    private struct MutableMeasurement {
        var count = 0
        var totalElapsedMilliseconds: Int64 = 0
        var maximumElapsedMilliseconds: Int64 = 0
        var activeQueries = 0
        var maximumConcurrentQueries = 0
    }

    private let lock = NSLock()
    private var measurements: [ExportPerformanceQueryKey: MutableMeasurement] = [:]
    private var activeQueries = 0
    private var maximumConcurrentQueries = 0

    func begin(
        operation: String,
        typeIdentifier: String
    ) -> ContinuousClock.Instant {
        let key = ExportPerformanceQueryKey(
            operation: operation,
            typeIdentifier: typeIdentifier
        )
        lock.lock()
        activeQueries += 1
        maximumConcurrentQueries = max(maximumConcurrentQueries, activeQueries)
        var measurement = measurements[key] ?? MutableMeasurement()
        measurement.activeQueries += 1
        measurement.maximumConcurrentQueries = max(
            measurement.maximumConcurrentQueries,
            measurement.activeQueries
        )
        measurements[key] = measurement
        lock.unlock()
        return .now
    }

    func finish(
        operation: String,
        typeIdentifier: String,
        startedAt: ContinuousClock.Instant
    ) {
        let elapsed = ExportPerformanceTimer.milliseconds(from: startedAt.duration(to: .now))
        let key = ExportPerformanceQueryKey(
            operation: operation,
            typeIdentifier: typeIdentifier
        )

        lock.lock()
        var measurement = measurements[key] ?? MutableMeasurement()
        measurement.count += 1
        measurement.totalElapsedMilliseconds += elapsed
        measurement.maximumElapsedMilliseconds = max(
            measurement.maximumElapsedMilliseconds,
            elapsed
        )
        measurement.activeQueries -= 1
        measurements[key] = measurement
        activeQueries -= 1
        lock.unlock()
    }

    func snapshot() -> ExportPerformanceQuerySnapshot {
        lock.lock()
        let frozenMeasurements = measurements.mapValues {
            ExportPerformanceQueryMeasurement(
                count: $0.count,
                totalElapsedMilliseconds: $0.totalElapsedMilliseconds,
                maximumElapsedMilliseconds: $0.maximumElapsedMilliseconds,
                maximumConcurrentQueries: $0.maximumConcurrentQueries
            )
        }
        let active = activeQueries
        let maximumConcurrent = maximumConcurrentQueries
        lock.unlock()

        return ExportPerformanceQuerySnapshot(
            measurements: frozenMeasurements,
            totalQueries: frozenMeasurements.values.reduce(0) { $0 + $1.count },
            totalElapsedMilliseconds: frozenMeasurements.values.reduce(0) {
                $0 + $1.totalElapsedMilliseconds
            },
            maximumConcurrentQueries: maximumConcurrent,
            activeQueries: active
        )
    }
}

nonisolated final class ExportPerformanceRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var requestCount = 0

    func increment() {
        lock.lock()
        requestCount += 1
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        let value = requestCount
        lock.unlock()
        return value
    }
}

/// Debug-only export measurements emitted to Console under the
/// `ExportPerformance` category.
///
/// Labels deliberately exclude dates, values, record counts, UUIDs, predicates,
/// filenames, paths, endpoint URLs, and error descriptions.
nonisolated enum ExportPerformanceInstrumentation {
    @TaskLocal static var currentQuerySession: ExportPerformanceQuerySession?
    @TaskLocal static var currentRequestCounter: ExportPerformanceRequestCounter?

    private static let logger = Logger(
        subsystem: "com.healthexporter",
        category: "ExportPerformance"
    )

    static func completed(
        pipeline: String,
        phase: String,
        timer: ExportPerformanceTimer,
        itemCount: Int = 0,
        byteCount: Int64 = 0,
        querySnapshot: ExportPerformanceQuerySnapshot? = nil
    ) {
        let elapsedMilliseconds = timer.elapsedMilliseconds()
        if let querySnapshot {
            logger.debug(
                "kind=phase pipeline=\(pipeline, privacy: .public) phase=\(phase, privacy: .public) elapsed_ms=\(elapsedMilliseconds) items=\(itemCount) bytes=\(byteCount) queries_total=\(querySnapshot.totalQueries) queries_elapsed_ms=\(querySnapshot.totalElapsedMilliseconds) queries_max_concurrent=\(querySnapshot.maximumConcurrentQueries) queries_active=\(querySnapshot.activeQueries)"
            )
            for key in querySnapshot.measurements.keys.sorted(by: {
                if $0.operation == $1.operation {
                    return $0.typeIdentifier < $1.typeIdentifier
                }
                return $0.operation < $1.operation
            }) {
                guard let measurement = querySnapshot.measurements[key] else { continue }
                logger.debug(
                    "kind=healthkit_query operation=\(key.operation, privacy: .public) type=\(key.typeIdentifier, privacy: .public) count=\(measurement.count) elapsed_ms=\(measurement.totalElapsedMilliseconds) max_elapsed_ms=\(measurement.maximumElapsedMilliseconds) max_concurrent=\(measurement.maximumConcurrentQueries)"
                )
            }
        } else {
            logger.debug(
                "kind=phase pipeline=\(pipeline, privacy: .public) phase=\(phase, privacy: .public) elapsed_ms=\(elapsedMilliseconds) items=\(itemCount) bytes=\(byteCount)"
            )
        }
    }

    static func measureHealthKitCapture<T>(
        phase: String,
        itemCount: Int,
        operation: () async throws -> T
    ) async rethrows -> T {
        let timer = ExportPerformanceTimer()
        if currentQuerySession != nil {
            defer {
                completed(
                    pipeline: "healthkit",
                    phase: phase,
                    timer: timer,
                    itemCount: itemCount
                )
            }
            return try await operation()
        }

        let session = ExportPerformanceQuerySession()
        return try await $currentQuerySession.withValue(session) {
            defer {
                completed(
                    pipeline: "healthkit",
                    phase: phase,
                    timer: timer,
                    itemCount: itemCount,
                    querySnapshot: session.snapshot()
                )
            }
            return try await operation()
        }
    }

    static func measureHealthKitQuery<T>(
        operation: String,
        typeIdentifier: String,
        query: () async throws -> T
    ) async rethrows -> T {
        guard let session = currentQuerySession else {
            return try await query()
        }
        let startedAt = session.begin()
        defer {
            session.finish(
                operation: operation,
                typeIdentifier: typeIdentifier,
                startedAt: startedAt
            )
        }
        return try await query()
    }

    static func measureSynchronousHealthKitQuery<T>(
        operation: String,
        typeIdentifier: String,
        query: () throws -> T
    ) rethrows -> T {
        guard let session = currentQuerySession else {
            return try query()
        }
        let startedAt = session.begin()
        defer {
            session.finish(
                operation: operation,
                typeIdentifier: typeIdentifier,
                startedAt: startedAt
            )
        }
        return try query()
    }

    /// Test support for deterministic counter/concurrency assertions without
    /// enabling any production or Release instrumentation path.
    static func withRequestCounter<T>(
        _ counter: ExportPerformanceRequestCounter,
        operation: () async throws -> T
    ) async rethrows -> T {
        try await $currentRequestCounter.withValue(counter) {
            try await operation()
        }
    }

    static func recordRequest() {
        currentRequestCounter?.increment()
    }

    static func withQuerySession<T>(
        _ operation: () async throws -> T
    ) async rethrows -> (value: T, snapshot: ExportPerformanceQuerySnapshot) {
        let session = ExportPerformanceQuerySession()
        let value = try await $currentQuerySession.withValue(session) {
            try await operation()
        }
        return (value, session.snapshot())
    }
}
#endif
