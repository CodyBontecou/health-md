import Foundation
import HealthKit

// Shared by the real HealthKit callback and host regression tests. This adapter
// keeps native empty-query semantics separate from genuine capture failures.
enum WatchExportHealthKitResult {
    nonisolated static func quantity(_ value: Double?, error: Error?) throws -> Double? {
        guard let error else { return value }
        let nativeError = error as NSError
        // Statistics queries report an empty result as errorNoData. HealthKit
        // read privacy means this must not distinguish absent from denied data.
        if nativeError.domain == HKError.errorDomain,
           nativeError.code == HKError.Code.errorNoData.rawValue {
            return nil
        }
        throw error
    }
}
