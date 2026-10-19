import XCTest
@testable import HealthMd

final class ScheduledExportTargetScheduleTests: XCTestCase {
    func testSingleScheduleMinuteStorageRoundTripAndDowngradeRequireNewOptIn() throws {
        let suite = "MinuteCadence.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for minutes in [30, 60] {
            var schedule = ExportSchedule(isEnabled: true, todayRefreshEnabled: true,
                todayRefreshIntervalMinutes: minutes, lastExportDate: Date(timeIntervalSince1970: 123))
            schedule.save(userDefaults: defaults)
            XCTAssertEqual(ExportSchedule.load(userDefaults: defaults), schedule)
            var wire = try XCTUnwrap(JSONSerialization.jsonObject(with:
                try XCTUnwrap(defaults.data(forKey: "exportSchedule"))) as? [String: Any])
            XCTAssertEqual(wire["todayRefreshEnabled"] as? Bool, false)
            for key in ["todayRefreshIntervalMinutes", "todayRefreshRequestedV2", "todayRefreshPersistenceVersion"] {
                wire.removeValue(forKey: key)
            }
            defaults.set(try JSONSerialization.data(withJSONObject: wire), forKey: "exportSchedule")
            schedule = ExportSchedule.load(userDefaults: defaults)
            XCTAssertFalse(schedule.todayRefreshEnabled)
            XCTAssertEqual(schedule.todayRefreshMinutes, minutes)
            XCTAssertEqual(schedule.lastExportDate, Date(timeIntervalSince1970: 123))
        }
    }

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

    func testUnversionedMinuteIntentRetainsChoiceButCannotEnableRefresh() throws {
        // A minute key alone is not activation authority; the explicit v2 flag is required.
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
        XCTAssertEqual(reencoded["todayRefreshIntervalMinutes"] as? Int, 30)
        XCTAssertFalse(decoded.todayRefreshEnabled)
        XCTAssertEqual(reencoded["todayRefreshEnabled"] as? Bool, false)
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
