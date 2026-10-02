import XCTest
@testable import HealthMd

final class ScheduledExportTargetScheduleTests: XCTestCase {
    func testDefaultScheduleTargetsLocalIPhoneFolder() {
        XCTAssertEqual(ExportSchedule().target, .localIPhoneFolder)
    }

    func testDecodesLegacyScheduleWithoutTargetAsLocalIPhoneFolder() throws {
        let payload: [String: Any] = [
            "isEnabled": true,
            "frequency": ScheduleFrequency.daily.rawValue,
            "preferredHour": 8,
            "preferredMinute": 0,
            "weekday": 1,
            "lookbackDays": 1
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        let decoded = try JSONDecoder().decode(ExportSchedule.self, from: data)

        XCTAssertEqual(decoded.target, .localIPhoneFolder)
    }

    // Issue #9 investigation: these characterize the legacy hour grammar, not
    // acceptance of new minute intervals. Never use zero as a half-hour sentinel.
    func testLegacyHourReaderClampsZeroAndOneRatherThanRepresentingRequestedCadence() throws {
        for hours in [0, 1] {
            let payload: [String: Any] = [
                "isEnabled": true,
                "frequency": ScheduleFrequency.daily.rawValue,
                "preferredHour": 8,
                "preferredMinute": 0,
                "todayRefreshEnabled": true,
                "todayRefreshIntervalHours": hours
            ]
            let data = try JSONSerialization.data(withJSONObject: payload)
            let decoded = try JSONDecoder().decode(ExportSchedule.self, from: data)
            XCTAssertEqual(decoded.todayRefreshIntervalHours, 3)
            XCTAssertTrue(decoded.todayRefreshEnabled)
        }
    }

    func testLegacyReaderIgnoresUnrecognizedMinuteIntentAndDropsItOnReencode() throws {
        // A hypothetical additive field alone cannot safely change old-reader semantics.
        let payload: [String: Any] = [
            "isEnabled": true,
            "frequency": ScheduleFrequency.daily.rawValue,
            "preferredHour": 8,
            "preferredMinute": 0,
            "todayRefreshEnabled": true,
            "todayRefreshIntervalHours": 3,
            "todayRefreshIntervalMinutes": 30
        ]
        let decoded = try JSONDecoder().decode(ExportSchedule.self, from:
            JSONSerialization.data(withJSONObject: payload))
        XCTAssertEqual(decoded.todayRefreshIntervalHours, 3)
        let reencoded = try XCTUnwrap(JSONSerialization.jsonObject(with:
            JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertNil(reencoded["todayRefreshIntervalMinutes"])
    }

    func testLegacyHourReaderRejectsFractionalHours() throws {
        let payload: [String: Any] = [
            "isEnabled": true,
            "frequency": ScheduleFrequency.daily.rawValue,
            "preferredHour": 8,
            "preferredMinute": 0,
            "todayRefreshEnabled": true,
            "todayRefreshIntervalHours": 0.5
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        XCTAssertThrowsError(try JSONDecoder().decode(ExportSchedule.self, from: data)) { error in
            XCTAssertTrue(error is DecodingError)
        }
    }

    func testLegacySupportedRefreshIntervalsRoundTripWithoutChangingCompletedScheduleOrProgress() throws {
        let enabled = Date(timeIntervalSince1970: 1_700_000_000)
        let completed = enabled.addingTimeInterval(86_400)
        let refreshed = completed.addingTimeInterval(3_600)
        for frequency in [ScheduleFrequency.daily, .weekly] {
            for hours in [3, 6, 12] {
                let schedule = ExportSchedule(
                    isEnabled: true, frequency: frequency,
                    preferredHour: 8, preferredMinute: 15, weekday: 4,
                    target: .apiEndpoint, lookbackDays: 7,
                    todayRefreshEnabled: true, todayRefreshIntervalHours: hours,
                    lastExportDate: completed, lastTodayRefreshDate: refreshed,
                    enabledAt: enabled
                )
                let decoded = try JSONDecoder().decode(ExportSchedule.self, from: JSONEncoder().encode(schedule))
                XCTAssertEqual(decoded, schedule)
            }
        }
    }

    func testEncodesAndDecodesScheduledAPITarget() throws {
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 7,
            preferredMinute: 30,
            target: .apiEndpoint,
            lookbackDays: 2
        )

        let decoded = try JSONDecoder().decode(ExportSchedule.self, from: JSONEncoder().encode(schedule))

        XCTAssertEqual(decoded.target, .apiEndpoint)
        XCTAssertEqual(decoded.lookbackDays, 2)
    }
}
