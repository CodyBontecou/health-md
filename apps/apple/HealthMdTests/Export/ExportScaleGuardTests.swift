import XCTest
@testable import HealthMd

/// Unit tests for the pure Export tab confirmation-guard decision helper.
///
/// These tests use a fixed Gregorian UTC calendar so day boundaries stay
/// deterministic regardless of the host machine's locale or time zone.
final class ExportScaleGuardTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private func verdict(
        start: Date,
        end: Date,
        granularDataEnabled: Bool = false,
        formatCount: Int = 1,
        dailyNotesOnlyMode: Bool = false
    ) -> ExportScaleGuard.Verdict {
        ExportScaleGuard.verdict(
            startDate: start,
            endDate: end,
            granularDataEnabled: granularDataEnabled,
            formatCount: formatCount,
            dailyNotesOnlyMode: dailyNotesOnlyMode,
            calendar: calendar
        )
    }

    // MARK: - Proceed cases

    func testSingleDayRangeProceeds() {
        let verdict = verdict(
            start: date(2025, 6, 1),
            end: date(2025, 6, 1)
        )
        XCTAssertEqual(verdict, .proceed)
    }

    func testSameDayRangeWithDifferentTimesProceeds() {
        let verdict = verdict(
            start: date(2025, 6, 1, hour: 23, minute: 59),
            end: date(2025, 6, 1, hour: 0, minute: 1)
        )
        XCTAssertEqual(verdict, .proceed)
    }

    func testExactlyThresholdDaysProceeds() {
        // 2025-01-01 through 2025-03-31 is exactly 90 inclusive days
        // (31 + 28 + 31; 2025 is not a leap year).
        let verdict = verdict(
            start: date(2025, 1, 1),
            end: date(2025, 3, 31)
        )
        XCTAssertEqual(verdict, .proceed)
    }

    // MARK: - Confirmation boundary

    func testOneDayPastThresholdRequiresConfirmation() throws {
        let verdict = verdict(
            start: date(2025, 1, 1),
            end: date(2025, 4, 1)
        )

        guard case .confirm(let scale) = verdict else {
            return XCTFail("Expected confirmation for 91 days, got \(verdict)")
        }
        XCTAssertEqual(scale.dayCount, 91)
        XCTAssertEqual(scale.estimatedFileCount, 91)
        XCTAssertFalse(scale.includesGranularData)
    }

    // MARK: - Large ranges

    func testLargeAllTimeStyleRangeReportsScaleWithGranularWarning() throws {
        // 2010-01-01 through 2025-01-01 spans 5,480 inclusive days, the scale
        // that triggered the original accidental All Time export incident.
        let verdict = verdict(
            start: date(2010, 1, 1),
            end: date(2025, 1, 1),
            granularDataEnabled: true,
            formatCount: 3
        )

        guard case .confirm(let scale) = verdict else {
            return XCTFail("Expected confirmation for 5,480 days, got \(verdict)")
        }
        XCTAssertEqual(scale.dayCount, 5480)
        XCTAssertEqual(scale.estimatedFileCount, 5480 * 3)
        XCTAssertTrue(scale.includesGranularData)
    }

    func testGranularDisabledOmitsGranularWarning() throws {
        let verdict = verdict(
            start: date(2010, 1, 1),
            end: date(2025, 1, 1),
            granularDataEnabled: false,
            formatCount: 3
        )

        guard case .confirm(let scale) = verdict else {
            return XCTFail("Expected confirmation, got \(verdict)")
        }
        XCTAssertFalse(scale.includesGranularData)
    }

    // MARK: - Daily Notes Only

    func testDailyNotesOnlyEstimatesOneOutputPerDay() throws {
        let verdict = verdict(
            start: date(2025, 1, 1),
            end: date(2025, 4, 1),
            formatCount: 4,
            dailyNotesOnlyMode: true
        )

        guard case .confirm(let scale) = verdict else {
            return XCTFail("Expected confirmation, got \(verdict)")
        }
        XCTAssertEqual(scale.dayCount, 91)
        XCTAssertEqual(scale.estimatedFileCount, 91)
    }

    func testZeroFormatCountStillEstimatesOneFilePerDay() throws {
        let verdict = verdict(
            start: date(2025, 1, 1),
            end: date(2025, 4, 1),
            formatCount: 0
        )

        guard case .confirm(let scale) = verdict else {
            return XCTFail("Expected confirmation, got \(verdict)")
        }
        XCTAssertEqual(scale.estimatedFileCount, 91)
    }

    // MARK: - Robustness

    func testReversedDatesAreTreatedAsInclusiveRange() throws {
        let verdict = verdict(
            start: date(2025, 4, 1),
            end: date(2025, 1, 1)
        )

        guard case .confirm(let scale) = verdict else {
            return XCTFail("Expected confirmation, got \(verdict)")
        }
        XCTAssertEqual(scale.dayCount, 91)
        XCTAssertEqual(scale.estimatedFileCount, 91)
    }
}
