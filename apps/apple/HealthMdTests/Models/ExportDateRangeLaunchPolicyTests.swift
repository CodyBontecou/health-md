import XCTest
@testable import HealthMd

/// Tests the interrupted-launch downgrade decision and the interactive-export
/// lifecycle marker that feeds it, so a crashed All Time export cannot re-arm
/// heavy launch work on every relaunch.
final class ExportDateRangeLaunchPolicyTests: XCTestCase {
    private var calendar: Calendar!
    private var defaults: UserDefaults!
    private var defaultsSuiteName: String!

    override func setUp() {
        super.setUp()
        calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        defaultsSuiteName = "ExportDateRangeLaunchPolicyTests.\(UUID().uuidString)"
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

    // MARK: - Interrupted All Time Downgrade

    func testInterruptedAllTimeRestoresToday() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 14, hour: 9)
        let persisted = allTimeSelection(
            start: makeDate(year: 2019, month: 3, day: 2),
            end: makeDate(year: 2026, month: 5, day: 13)
        )

        let selection = ExportDateRangeLaunchPolicy.selectionToRestore(
            persisted: persisted,
            hadInterruptedInteractiveExport: true,
            resolvesAllTimeRange: true,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(selection.preset, .today)
        XCTAssertEqual(selection.startDate, makeDate(year: 2026, month: 5, day: 14))
        XCTAssertEqual(selection.endDate, makeDate(year: 2026, month: 5, day: 14))
    }

    func testCleanAllTimeLaunchRestoreKeepsAllTime() {
        let persisted = allTimeSelection(
            start: makeDate(year: 2019, month: 3, day: 2),
            end: makeDate(year: 2026, month: 5, day: 13)
        )

        let selection = ExportDateRangeLaunchPolicy.selectionToRestore(
            persisted: persisted,
            hadInterruptedInteractiveExport: false,
            resolvesAllTimeRange: true,
            referenceDate: makeDate(year: 2026, month: 5, day: 14),
            calendar: calendar
        )

        XCTAssertEqual(selection, persisted)
    }

    func testInterruptedCustomSelectionIsNeverDowngraded() {
        let persisted = ExportDateRangeSelection(
            preset: .custom,
            startDate: makeDate(year: 2025, month: 1, day: 10),
            endDate: makeDate(year: 2025, month: 1, day: 20)
        )

        let selection = ExportDateRangeLaunchPolicy.selectionToRestore(
            persisted: persisted,
            hadInterruptedInteractiveExport: true,
            resolvesAllTimeRange: true,
            referenceDate: makeDate(year: 2026, month: 5, day: 14),
            calendar: calendar
        )

        XCTAssertEqual(selection, persisted)
    }

    func testInterruptedTodayAndYesterdaySelectionsAreNeverDowngraded() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 14)
        let today = ExportDateRangeSelection(
            preset: .today,
            startDate: makeDate(year: 2026, month: 5, day: 14),
            endDate: makeDate(year: 2026, month: 5, day: 14)
        )
        let yesterday = ExportDateRangeSelection(
            preset: .yesterday,
            startDate: makeDate(year: 2026, month: 5, day: 13),
            endDate: makeDate(year: 2026, month: 5, day: 13)
        )

        for persisted in [today, yesterday] {
            let selection = ExportDateRangeLaunchPolicy.selectionToRestore(
                persisted: persisted,
                hadInterruptedInteractiveExport: true,
                resolvesAllTimeRange: true,
                referenceDate: referenceDate,
                calendar: calendar
            )

            XCTAssertEqual(selection, persisted)
        }
    }

    // MARK: - Missing Persisted Range Fallback

    func testForegroundAllTimeWithoutPersistedRangeFallsBackToToday() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 14, hour: 9)
        // The store substitutes the default today range when the absolute
        // keys are missing; All Time with those dates has nothing to reuse.
        let persisted = allTimeSelection(
            start: makeDate(year: 2026, month: 5, day: 14),
            end: makeDate(year: 2026, month: 5, day: 14)
        )

        let selection = ExportDateRangeLaunchPolicy.selectionToRestore(
            persisted: persisted,
            hadInterruptedInteractiveExport: false,
            resolvesAllTimeRange: false,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(selection.preset, .today)
        XCTAssertEqual(selection.startDate, makeDate(year: 2026, month: 5, day: 14))
        XCTAssertEqual(selection.endDate, makeDate(year: 2026, month: 5, day: 14))
    }

    func testInitialLaunchKeepsAllTimeWithoutPersistedRangeSoItCanBeResolved() {
        let referenceDate = makeDate(year: 2026, month: 5, day: 14, hour: 9)
        let persisted = allTimeSelection(
            start: makeDate(year: 2026, month: 5, day: 14),
            end: makeDate(year: 2026, month: 5, day: 14)
        )

        let selection = ExportDateRangeLaunchPolicy.selectionToRestore(
            persisted: persisted,
            hadInterruptedInteractiveExport: false,
            resolvesAllTimeRange: true,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(selection.preset, .allTime)
    }

    func testForegroundAllTimeWithValidPersistedRangeIsRestoredWithoutRequery() {
        let persisted = allTimeSelection(
            start: makeDate(year: 2019, month: 3, day: 2),
            end: makeDate(year: 2026, month: 5, day: 13)
        )

        let selection = ExportDateRangeLaunchPolicy.selectionToRestore(
            persisted: persisted,
            hadInterruptedInteractiveExport: false,
            resolvesAllTimeRange: false,
            referenceDate: makeDate(year: 2026, month: 5, day: 14),
            calendar: calendar
        )

        XCTAssertEqual(selection, persisted)
    }

    func testForegroundAllTimeWithFutureDatedPersistedRangeFallsBackToToday() {
        // Stale-invalid range: an end date past the reference day (for example
        // after a device clock change) must not survive a foreground restore.
        let referenceDate = makeDate(year: 2026, month: 5, day: 14, hour: 9)
        let persisted = allTimeSelection(
            start: makeDate(year: 2019, month: 3, day: 2),
            end: makeDate(year: 2026, month: 6, day: 30)
        )

        let selection = ExportDateRangeLaunchPolicy.selectionToRestore(
            persisted: persisted,
            hadInterruptedInteractiveExport: false,
            resolvesAllTimeRange: false,
            referenceDate: referenceDate,
            calendar: calendar
        )

        XCTAssertEqual(selection.preset, .today)
        XCTAssertEqual(selection.startDate, makeDate(year: 2026, month: 5, day: 14))
        XCTAssertEqual(selection.endDate, makeDate(year: 2026, month: 5, day: 14))
    }

    // MARK: - Interactive Export Lifecycle Marker

    func testInterruptedMarkerIsConsumedOnceAndClearsTheStore() {
        let store = ExportDateRangeSelectionStore(userDefaults: defaults)
        store.markInteractiveExportBegan()

        XCTAssertTrue(store.consumeInterruptedInteractiveExportMarker())
        XCTAssertFalse(store.consumeInterruptedInteractiveExportMarker())
    }

    func testEndedExportClearsTheMarkerForTheNextLaunch() {
        let store = ExportDateRangeSelectionStore(userDefaults: defaults)
        store.markInteractiveExportBegan()
        store.markInteractiveExportEnded()

        XCTAssertFalse(store.consumeInterruptedInteractiveExportMarker())
    }

    private func allTimeSelection(start: Date, end: Date) -> ExportDateRangeSelection {
        ExportDateRangeSelection(preset: .allTime, startDate: start, endDate: end)
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
