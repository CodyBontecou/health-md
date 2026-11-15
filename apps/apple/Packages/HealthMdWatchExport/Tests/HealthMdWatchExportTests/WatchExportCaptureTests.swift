import Foundation
import XCTest
@testable import HealthMdWatchExport

final class WatchExportCaptureTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }

    func testCaptureUsesFrozenLocalDayAndKeepsZeroDistinctFromMissingAndFailure() async throws {
        let now = Date(timeIntervalSince1970: 1_783_965_600)
        var queried: [WatchExportMetric] = []
        let payload = try await WatchExportCapture.capture(at: now, calendar: calendar,
                                                          earliestPermittedSampleDate: now.addingTimeInterval(-86400)) { metric, start, end in
            queried.append(metric)
            XCTAssertEqual(start, self.calendar.startOfDay(for: now))
            XCTAssertEqual(end, now)
            switch metric {
            case .steps: return 0
            case .activeEnergy: return nil
            case .exercise: throw WatchExportError.unavailable
            }
        }
        XCTAssertEqual(queried, WatchExportMetric.allCases)
        XCTAssertEqual(payload.observations.map(\.status), [.value, .noData, .failed])
        XCTAssertEqual(payload.observations[0].value, 0)
        XCTAssertNil(payload.observations[1].value)
        XCTAssertNil(payload.observations[2].value)
        XCTAssertEqual(payload.captureStatus, "partial")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload.encoded()) as? [String: Any])
        XCTAssertEqual(object["schema"] as? String, "healthmd.watch_snapshot")
        XCTAssertEqual(object["schema_version"] as? Int, 1)
        XCTAssertEqual(object["source"] as? String, "watch_local_healthkit")
        XCTAssertEqual(object["workouts_status"] as? String, "not_requested")
        XCTAssertEqual(object["history_availability"] as? String, "unknown_local_store_may_be_purged")
        XCTAssertEqual(object["calendar_timezone"] as? String, calendar.timeZone.identifier)
        XCTAssertNil(object["records"])
        let rows = try XCTUnwrap(object["observations"] as? [[String: Any]])
        XCTAssertNil(rows[1]["value"])
        XCTAssertNil(rows[2]["value"])
        XCTAssertEqual(rows.map { $0["unit"] as? String }, ["count", "kcal", "min"])
    }

    func testEmptyQueriesAreObservedNotCompleteHistoryOrDeniedAuthorization() async throws {
        let payload = try await WatchExportCapture.capture(at: Date(), calendar: calendar,
                                                          earliestPermittedSampleDate: Date()) { _, _, _ in nil }
        XCTAssertEqual(payload.captureStatus, "observed")
        XCTAssertTrue(payload.observations.allSatisfy { $0.status == .noData && $0.value == nil })
    }

    func testInvalidValuesNeverBecomeFabricatedMeasurements() async throws {
        for invalid in [Double.nan, .infinity, -1] {
            XCTAssertThrowsError(try WatchExportObservation(metric: .steps, value: invalid))
        }
        XCTAssertThrowsError(try WatchExportObservation(metric: .steps, value: 1, status: .noData))
        let payload = try await WatchExportCapture.capture(at: Date(), calendar: calendar,
                                                          earliestPermittedSampleDate: Date()) { _, _, _ in .nan }
        XCTAssertEqual(payload.captureStatus, "partial")
        XCTAssertTrue(payload.observations.allSatisfy { $0.status == .failed && $0.value == nil })
    }

    func testCancelledCaptureDoesNotConvertCancellationToMissingData() async {
        do {
            _ = try await WatchExportCapture.capture(at: Date(), calendar: calendar,
                                                    earliestPermittedSampleDate: Date()) { _, _, _ in throw CancellationError() }
            XCTFail("Expected cancellation")
        } catch { XCTAssertTrue(error is CancellationError) }
    }

    func testPublicSyntheticFixtureMatchesProductionEncoder() throws {
        let formatter = ISO8601DateFormatter()
        let now = try XCTUnwrap(formatter.date(from: "2026-07-13T12:00:00Z"))
        let start = try XCTUnwrap(formatter.date(from: "2026-07-13T00:00:00Z"))
        let earliest = try XCTUnwrap(formatter.date(from: "2026-07-12T00:00:00Z"))
        let id = try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000171"))
        let payload = try WatchExportPayload(uploadID: id, capturedAt: now, intervalStart: start, intervalEnd: now,
                                            calendarTimezone: "UTC", earliestPermittedSampleDate: earliest,
                                            observations: [
                                                WatchExportObservation(metric: .steps, value: 0),
                                                WatchExportObservation(metric: .activeEnergy, value: nil),
                                                WatchExportObservation(metric: .exercise, value: nil, status: .failed)
                                            ])
        let url = try XCTUnwrap(Bundle.module.url(forResource: "watch-snapshot-v1", withExtension: "json"))
        let expected = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? NSDictionary)
        let actual = try XCTUnwrap(JSONSerialization.jsonObject(with: payload.encoded()) as? NSDictionary)
        XCTAssertEqual(actual, expected)
    }

    func testPayloadRejectsMissingOrDuplicateMetricRowsAndInvalidWindow() throws {
        let now = Date()
        let rows = try WatchExportMetric.allCases.map { try WatchExportObservation(metric: $0, value: nil) }
        for invalidRows in [[], [rows[0], rows[0], rows[0]], Array(rows.reversed())] {
            XCTAssertThrowsError(try WatchExportPayload(capturedAt: now, intervalStart: now, intervalEnd: now,
                                                        calendarTimezone: "UTC", earliestPermittedSampleDate: now, observations: invalidRows))
        }
        XCTAssertThrowsError(try WatchExportPayload(capturedAt: now, intervalStart: now, intervalEnd: now.addingTimeInterval(1),
                                                    calendarTimezone: "UTC", earliestPermittedSampleDate: now, observations: rows))
    }
}
