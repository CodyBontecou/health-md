import Foundation
import XCTest
@testable import HealthMd

@MainActor
final class AppleSleepCaptureContextTests: XCTestCase {
    private let zone = TimeZone(identifier: "America/Los_Angeles")!

    func testBothPreferenceMutationDirectionsRetainOperationAuthorityAtEveryDailyResolution() async throws {
        let changes: [(SleepDayAttribution, SleepDayAttribution)] = [(.nightBegins, .morningEnds), (.morningEnds, .nightBegins)]
        for (initial, changed) in changes {
            var preference = initial
            let context = AppleSleepCaptureContext.resolve(timeZone: zone, attribution: preference)
            try await AppleSleepCaptureContext.pinned.withValue(context) {
                let first = AppleSleepCaptureContext.resolve(attribution: preference)
                await Task.yield()
                preference = changed
                let second = AppleSleepCaptureContext.resolve(attribution: preference)
                XCTAssertEqual(first, context)
                XCTAssertEqual(second, context, "A daily fetch must not shadow the operation pin")
                if initial == .nightBegins {
                    XCTAssertNoThrow(try second.requireShippedProfile())
                } else {
                    XCTAssertThrowsError(try second.requireShippedProfile()) {
                        XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .unapprovedAttribution)
                    }
                }
            }
        }
    }

    func testConcurrentOperationsDoNotBorrowEachOthersContext() async {
        let first = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
        let second = AppleSleepCaptureContext(timeZone: TimeZone(identifier: "Europe/Berlin")!, sleepDayAttribution: .morningEnds)
        async let a = resolveRepeatedly(in: first)
        async let b = resolveRepeatedly(in: second)
        let results = await (a, b)
        XCTAssertTrue(results.0.allSatisfy { $0 == first })
        XCTAssertTrue(results.1.allSatisfy { $0 == second })
    }

    func testDurableRoundTripPreservesUnavailableAttributionAndMissingAuthorityNeverUsesPreference() throws {
        let pending = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let bytes = try encoder.encode(pending)
        let restored = try JSONDecoder().decode(AppleSleepCaptureContext.self, from: bytes)
        XCTAssertEqual(restored, pending)
        XCTAssertThrowsError(try AppleSleepCaptureContext.recovered(restored))
        XCTAssertEqual(try encoder.encode(restored), bytes, "Do not coerce or rewrite pending authority")
        let night = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins)
        XCTAssertThrowsError(try AppleSleepCaptureContext.pinned.withValue(night) {
            try AppleSleepCaptureContext.recovered(nil)
        }) {
            XCTAssertEqual($0 as? AppleSleepCaptureContext.AvailabilityError, .missingDurableAttribution)
        }
        XCTAssertEqual(try AppleSleepCaptureContext.recovered(night), night)
    }

    func testCurrentWriterProfilesRejectMorningEndsWithoutCoercingContext() {
        let context = AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .morningEnds)
        XCTAssertThrowsError(try context.requireShippedProfile())
        XCTAssertEqual(context.sleepDayAttribution, .morningEnds)
        XCTAssertNoThrow(try AppleSleepCaptureContext(timeZone: zone, sleepDayAttribution: .nightBegins).requireShippedProfile())
    }

    private func resolveRepeatedly(in context: AppleSleepCaptureContext) async -> [AppleSleepCaptureContext] {
        await AppleSleepCaptureContext.pinned.withValue(context) {
            var values: [AppleSleepCaptureContext] = []
            for _ in 0..<20 {
                await Task.yield()
                values.append(AppleSleepCaptureContext.resolve(attribution: .nightBegins))
            }
            return values
        }
    }
}
