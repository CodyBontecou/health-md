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
