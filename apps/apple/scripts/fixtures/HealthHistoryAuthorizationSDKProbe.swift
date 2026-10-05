// Compilation-only SDK probe. Never executed and never requests authorization.
// Public declaration verified against Apple's OS 27 API documentation:
// https://developer.apple.com/documentation/healthkit/hkhealthstore/earliestauthorizedsampledate(for:)
import Foundation
import HealthKit

@available(iOS 27.0, macOS 27.0, watchOS 27.0, visionOS 27.0, *)
func probeHistoryAuthorizationSDK(
    store: HKHealthStore,
    types: Set<HKObjectType>
) async throws -> [HKObjectType: Date] {
    try await store.earliestAuthorizedSampleDate(for: types)
}
