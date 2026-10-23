import Foundation
import HealthKit

// Separate from widget snapshots: no placeholders, swallowed query errors, sleep
// approximations, or cached phone values can enter this export.
enum WatchExportCaptureProvider {
    static func capture() async throws -> WatchExportPayload {
        guard HKHealthStore.isHealthDataAvailable() else { throw WatchExportError.unavailable }
        let store = HKHealthStore()
        return try await WatchExportCapture.capture(at: Date(), calendar: .current,
                                                     earliestPermittedSampleDate: store.earliestPermittedSampleDate()) { metric, start, end in
            let identifier: HKQuantityTypeIdentifier
            let unit: HKUnit
            switch metric {
            case .steps: identifier = .stepCount; unit = .count()
            case .activeEnergy: identifier = .activeEnergyBurned; unit = .kilocalorie()
            case .exercise: identifier = .appleExerciseTime; unit = .minute()
            }
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier) else { throw WatchExportError.unavailable }
            let predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate),
                NSPredicate(format: "%K < %@", HKPredicateKeyPathStartDate, end as NSDate)
            ])
            let operation = WatchExportQuantityQuery(store: store)
            return try await operation.sum(type: type, predicate: predicate, unit: unit)
        }
    }
}

// HealthKit callbacks run on a private queue. One continuation is resumed exactly
// once, including cancellation before registration and callbacks racing stop().
private final class WatchExportQuantityQuery: @unchecked Sendable {
    private let lock = NSLock()
    private let store: HKHealthStore
    private var query: HKStatisticsQuery?
    private var continuation: CheckedContinuation<Double?, Error>?
    private var finished = false

    init(store: HKHealthStore) { self.store = store }

    func sum(type: HKQuantityType, predicate: NSPredicate, unit: HKUnit) async throws -> Double? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock()
                guard !finished else {
                    lock.unlock()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                self.continuation = continuation
                let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { [self] _, statistics, error in
                    if let error {
                        finish(.failure(error))
                    } else {
                        finish(.success(statistics?.sumQuantity()?.doubleValue(for: unit)))
                    }
                }
                self.query = query
                // Register under the lock, so cancellation cannot stop a query
                // immediately before it is executed and leave it running.
                store.execute(query)
                lock.unlock()
            }
        } onCancel: {
            self.finish(.failure(CancellationError()), stop: true)
        }
    }

    private func finish(_ result: Result<Double?, Error>, stop: Bool = false) {
        lock.lock()
        guard !finished else { lock.unlock(); return }
        finished = true
        let continuation = self.continuation
        let query = self.query
        self.continuation = nil
        self.query = nil
        lock.unlock()
        if stop, let query { store.stop(query) }
        continuation?.resume(with: result)
    }
}
