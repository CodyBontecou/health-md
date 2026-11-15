import Foundation
import HealthKit
import XCTest
@testable import HealthMdWatchExport

final class WatchExportHealthKitResultTests: XCTestCase {
    func testNativeNoDataErrorExportsUnknownWithoutAValue() async throws {
        let error = NSError(domain: HKError.errorDomain, code: HKError.Code.errorNoData.rawValue)
        let payload = try await capture(error: error)
        XCTAssertEqual(payload.observations.map(\.status), [.noData, .noData, .noData])
        XCTAssertTrue(payload.observations.allSatisfy { $0.value == nil })
        XCTAssertEqual(payload.captureStatus, "observed")
    }

    func testNativeAccessAndArgumentErrorsRemainQueryFailures() async throws {
        for code in [HKError.Code.errorDatabaseInaccessible, .errorInvalidArgument, .errorAuthorizationNotDetermined] {
            let payload = try await capture(error: NSError(domain: HKError.errorDomain, code: code.rawValue))
            XCTAssertTrue(payload.observations.allSatisfy { $0.status == .failed && $0.value == nil })
            XCTAssertEqual(payload.captureStatus, "partial")
        }
    }

    func testUnrelatedErrorWithSameNumericCodeRemainsFailure() async throws {
        let payload = try await capture(error: NSError(domain: "synthetic.other", code: HKError.Code.errorNoData.rawValue))
        XCTAssertTrue(payload.observations.allSatisfy { $0.status == .failed && $0.value == nil })
    }

    func testSuccessfulZeroAndMissingQuantityStayDistinct() throws {
        XCTAssertEqual(try WatchExportHealthKitResult.quantity(0, error: nil), 0)
        XCTAssertNil(try WatchExportHealthKitResult.quantity(nil, error: nil))
    }

    private func capture(error: Error) async throws -> WatchExportPayload {
        let now = Date(timeIntervalSince1970: 1_783_965_600)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return try await WatchExportCapture.capture(at: now, calendar: calendar,
                                                    earliestPermittedSampleDate: now) { _, _, _ in
            try WatchExportHealthKitResult.quantity(nil, error: error)
        }
    }
}
