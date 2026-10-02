import XCTest
@testable import HealthMd

final class ExportDateRangePresetTests: XCTestCase {
    private var calendar: Calendar!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        defaultsSuiteName = "ExportDateRangePresetTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: defaultsSuiteName)
        defaults.removePersistentDomain(forName: defaultsSuiteName)
    }

    override func tearDown() {
        if let defaultsSuiteName {
            defaults.removePersistentDomain(forName: defaultsSuiteName)
        }
        defaults = nil
        defaultsSuiteName = nil
        calendar = nil
        super.tearDown()
    }

    func testTodayResolvesToCurrentCalendarDay() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 13, hour: 15, minute: 45)
        let manualStart = makeDate(year: 2026, month: 5, day: 1, hour: 9)
        let manualEnd = makeDate(year: 2026, month: 5, day: 3, hour: 20)

        let range = ExportDateRangePreset.today.resolvedRange(
            referenceDate: referenceDate,
            currentStartDate: manualStart,
            currentEndDate: manualEnd,
            calendar: calendar
        )

        XCTAssertEqual(range?.startDate, calendar.startOfDay(for: referenceDate))
        XCTAssertEqual(range?.endDate, calendar.startOfDay(for: referenceDate))
    }

    func testYesterdayResolvesToPreviousCalendarDay() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 13, hour: 15, minute: 45)
        let expectedYesterday = calendar.date(
            byAdding: .day,
            value: -1,
            to: calendar.startOfDay(for: referenceDate)
        )!

        let range = ExportDateRangePreset.yesterday.resolvedRange(
            referenceDate: referenceDate,
            currentStartDate: referenceDate,
            currentEndDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(range?.startDate, expectedYesterday)
        XCTAssertEqual(range?.endDate, expectedYesterday)
    }

    func testCustomPreservesManuallySelectedRange() {
        let manualStart = makeDate(year: 2026, month: 4, day: 20, hour: 8, minute: 30)
        let manualEnd = makeDate(year: 2026, month: 4, day: 22, hour: 21, minute: 15)

        let range = ExportDateRangePreset.custom.resolvedRange(
            referenceDate: makeDate(year: 2026, month: 5, day: 13),
            currentStartDate: manualStart,
            currentEndDate: manualEnd,
            calendar: calendar
        )

        XCTAssertEqual(range?.startDate, manualStart)
        XCTAssertEqual(range?.endDate, manualEnd)
    }

    func testConsecutiveCustomWeeksCanBeSavedAndReopenedEarlierAndLaterWithoutToday() throws {
        let referenceDate = makeDate(year: 2026, month: 5, day: 28)
        // Complete a week, reopen it, then complete an earlier and a later
        // week. No Today preset is saved between these selections.
        for (startDay, endDay) in [(8, 14), (1, 7), (15, 21)] {
            let start = makeDate(year: 2026, month: 5, day: startDay)
            let end = makeDate(year: 2026, month: 5, day: endDay)
            let range = try XCTUnwrap(ExportDateRangePreset.custom.resolvedRange(
                referenceDate: referenceDate,
                currentStartDate: start,
                currentEndDate: end,
                calendar: calendar
            ))
            ExportDateRangeSelectionStore(userDefaults: defaults).save(
                preset: .custom,
                startDate: range.startDate,
                endDate: range.endDate,
                referenceDate: referenceDate,
                calendar: calendar
            )

            // A new store reads persisted state, rather than retaining an
            // in-memory selection. This does not simulate a native calendar.
            let reopened = ExportDateRangeSelectionStore(userDefaults: defaults).load(
                referenceDate: referenceDate,
                calendar: calendar
            )
            XCTAssertEqual(reopened.preset, .custom)
            XCTAssertEqual(reopened.startDate, start)
            XCTAssertEqual(reopened.endDate, end)
            XCTAssertEqual(calendar.dateComponents([.day], from: start, to: end).day, 6)
            let reselected = try XCTUnwrap(reopened.preset.resolvedRange(
                referenceDate: referenceDate,
                currentStartDate: reopened.startDate,
                currentEndDate: reopened.endDate,
                calendar: calendar
            ))
            XCTAssertEqual(reselected.startDate, start)
            XCTAssertEqual(reselected.endDate, end)
        }
    }

    func testSecondCustomWeekReplacesRollingOffsetsOnNextLaunch() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 28)
        let store = ExportDateRangeSelectionStore(userDefaults: defaults)
        for (startDay, endDay) in [(8, 14), (15, 21)] {
            store.save(
                preset: .custom,
                startDate: makeDate(year: 2026, month: 5, day: startDay),
                endDate: makeDate(year: 2026, month: 5, day: endDay),
                referenceDate: referenceDate,
                calendar: calendar
            )
        }

        let reopened = ExportDateRangeSelectionStore(userDefaults: defaults).load(
            referenceDate: makeDate(year: 2026, month: 5, day: 29),
            calendar: calendar
        )
        XCTAssertEqual(reopened.preset, .custom)
        XCTAssertEqual(reopened.startDate, makeDate(year: 2026, month: 5, day: 16))
        XCTAssertEqual(reopened.endDate, makeDate(year: 2026, month: 5, day: 22))
    }

    func testAllTimeResolvesFromEarliestAvailableDateThroughProvidedEndDate() {
        let earliest = makeDate(year: 2024, month: 1, day: 5, hour: 10)
        let latest = makeDate(year: 2026, month: 5, day: 12, hour: 18)

        let range = ExportDateRangePreset.allTime.resolvedRange(
            referenceDate: makeDate(year: 2026, month: 5, day: 13),
            currentStartDate: latest,
            currentEndDate: latest,
            allTimeStartDate: earliest,
            allTimeEndDate: latest,
            calendar: calendar
        )

        XCTAssertEqual(range?.startDate, calendar.startOfDay(for: earliest))
        XCTAssertEqual(range?.endDate, calendar.startOfDay(for: latest))
    }

    func testAllTimeWithoutAvailableDataReturnsNil() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 13)

        let range = ExportDateRangePreset.allTime.resolvedRange(
            referenceDate: referenceDate,
            currentStartDate: referenceDate,
            currentEndDate: referenceDate,
            calendar: calendar
        )

        XCTAssertNil(range)
    }

    func testSelectionStoreLoadsSavedPreset() {
        let store = ExportDateRangeSelectionStore(userDefaults: defaults)
        let savedReferenceDate = makeDate(year: 2026, month: 5, day: 13)
        let nextLaunchDate = makeDate(year: 2026, month: 5, day: 14)

        store.save(
            preset: .yesterday,
            startDate: savedReferenceDate,
            endDate: savedReferenceDate,
            referenceDate: savedReferenceDate,
            calendar: calendar
        )

        let selection = store.load(referenceDate: nextLaunchDate, calendar: calendar)

        XCTAssertEqual(selection.preset, .yesterday)
        XCTAssertEqual(selection.startDate, makeDate(year: 2026, month: 5, day: 13))
        XCTAssertEqual(selection.endDate, makeDate(year: 2026, month: 5, day: 13))
    }

    func testSelectionStoreRollsCustomRangeForwardBySavedOffsets() {
        let store = ExportDateRangeSelectionStore(userDefaults: defaults)
        let savedReferenceDate = makeDate(year: 2026, month: 5, day: 13, hour: 17)
        let customStart = makeDate(year: 2026, month: 5, day: 11, hour: 9)
        let customEnd = makeDate(year: 2026, month: 5, day: 13, hour: 18)

        store.save(
            preset: .custom,
            startDate: customStart,
            endDate: customEnd,
            referenceDate: savedReferenceDate,
            calendar: calendar
        )

        let selection = store.load(
            referenceDate: makeDate(year: 2026, month: 5, day: 14, hour: 8),
            calendar: calendar
        )

        XCTAssertEqual(selection.preset, .custom)
        XCTAssertEqual(selection.startDate, makeDate(year: 2026, month: 5, day: 12))
        XCTAssertEqual(selection.endDate, makeDate(year: 2026, month: 5, day: 14))
    }

    func testSelectionStorePreservesCustomEndOffsetForYesterdayAnchoredRange() {
        let store = ExportDateRangeSelectionStore(userDefaults: defaults)
        let savedReferenceDate = makeDate(year: 2026, month: 5, day: 13)

        store.save(
            preset: .custom,
            startDate: makeDate(year: 2026, month: 5, day: 10),
            endDate: makeDate(year: 2026, month: 5, day: 12),
            referenceDate: savedReferenceDate,
            calendar: calendar
        )

        let selection = store.load(
            referenceDate: makeDate(year: 2026, month: 5, day: 14),
            calendar: calendar
        )

        XCTAssertEqual(selection.preset, .custom)
        XCTAssertEqual(selection.startDate, makeDate(year: 2026, month: 5, day: 11))
        XCTAssertEqual(selection.endDate, makeDate(year: 2026, month: 5, day: 13))
    }

    func testSelectionStoreKeepsAllTimeStoredRangeUntilDataSourceRefreshesIt() {
        let store = ExportDateRangeSelectionStore(userDefaults: defaults)
        let start = makeDate(year: 2024, month: 1, day: 5, hour: 10)
        let end = makeDate(year: 2026, month: 5, day: 12, hour: 18)

        store.save(
            preset: .allTime,
            startDate: start,
            endDate: end,
            referenceDate: makeDate(year: 2026, month: 5, day: 13),
            calendar: calendar
        )

        let selection = store.load(
            referenceDate: makeDate(year: 2026, month: 5, day: 20),
            calendar: calendar
        )

        XCTAssertEqual(selection.preset, .allTime)
        XCTAssertEqual(selection.startDate, makeDate(year: 2024, month: 1, day: 5))
        XCTAssertEqual(selection.endDate, makeDate(year: 2026, month: 5, day: 12))
    }

    private func makeDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int = 0,
        minute: Int = 0
    ) -> Date {
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}
