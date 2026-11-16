import SwiftUI
import XCTest
@testable import HealthMd

/// Issue #168: after one completed Custom range, a second Custom week (earlier or later) must be
/// reachable without first resetting to Today.
final class CustomDateRangeEditingTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func day(_ value: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: value, hour: 9))!
    }

    func testLaterWeekIsReachableByMovingFromFirst() {
        // First range Oct 1–7; the user then sets From to Oct 15, past the old To.
        let moved = CustomDateRangeEditing.settingStart(day(15), end: day(7), calendar: calendar)
        XCTAssertEqual(moved.start, day(15))
        XCTAssertEqual(moved.end, day(15), "To follows From instead of From being blocked")

        let finished = CustomDateRangeEditing.settingEnd(day(21), start: moved.start, calendar: calendar)
        XCTAssertEqual(finished.start, day(15))
        XCTAssertEqual(finished.end, day(21))
    }

    func testEarlierWeekIsReachableByMovingToFirst() {
        // First range Oct 15–21; the user then sets To to Oct 7, before the old From.
        let moved = CustomDateRangeEditing.settingEnd(day(7), start: day(15), calendar: calendar)
        XCTAssertEqual(moved.start, day(7), "From follows To instead of To being blocked")
        XCTAssertEqual(moved.end, day(7))

        let finished = CustomDateRangeEditing.settingStart(day(1), end: moved.end, calendar: calendar)
        XCTAssertEqual(finished.start, day(1))
        XCTAssertEqual(finished.end, day(7))
    }

    func testEditsInsideTheRangeLeaveTheOtherEndpoint() {
        XCTAssertEqual(CustomDateRangeEditing.settingStart(day(3), end: day(7), calendar: calendar).end, day(7))
        XCTAssertEqual(CustomDateRangeEditing.settingEnd(day(5), start: day(1), calendar: calendar).start, day(1))
    }

    func testSameDayWithDifferentTimesIsNotAnInversion() {
        let laterSameDay = calendar.date(byAdding: .hour, value: 8, to: day(7))!
        XCTAssertEqual(CustomDateRangeEditing.settingStart(laterSameDay, end: day(7), calendar: calendar).end, day(7))
    }

    func testBindingsCarryTheOtherEndpoint() {
        var start = day(1)
        var end = day(7)
        let startBinding = Binding(get: { start }, set: { start = $0 })
        let endBinding = Binding(get: { end }, set: { end = $0 })

        CustomDateRangeEditing.startBinding(start: startBinding, end: endBinding).wrappedValue = day(15)
        XCTAssertGreaterThanOrEqual(end, start)

        CustomDateRangeEditing.endBinding(start: startBinding, end: endBinding).wrappedValue = day(2)
        XCTAssertEqual(start, day(2))
        XCTAssertEqual(end, day(2))
    }
}
