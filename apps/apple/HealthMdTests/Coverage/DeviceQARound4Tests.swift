import XCTest
import StoreKit
@testable import HealthMd

/// Regressions from device QA round 4: next-run labels, endpoint cleartext
/// policy, restore cancellation and the no-data export toast.
final class DeviceQARound4Tests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    // MARK: Next run includes Refresh today

    private func dailyAtSix(refreshHours: Int?) -> ExportSchedule {
        ExportSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 6,
            todayRefreshEnabled: refreshHours != nil,
            todayRefreshIntervalHours: refreshHours ?? ExportSchedule.defaultTodayRefreshIntervalHours
        )
    }

    func testNextRunIsTheNextRefreshSlotWhenItComesFirst() {
        let next = ScheduleDateMath.nextAnyRunDate(schedule: dailyAtSix(refreshHours: 3), now: at(7, 12, 42), calendar: calendar)
        XCTAssertEqual(next, at(7, 15))
    }

    func testNextRunIsTomorrowsDailyRunWithoutRefresh() {
        let next = ScheduleDateMath.nextAnyRunDate(schedule: dailyAtSix(refreshHours: nil), now: at(7, 12, 42), calendar: calendar)
        XCTAssertEqual(next, at(8, 6))
    }

    func testNextRunAfterTheLastRefreshSlotIsTomorrowMorning() {
        let next = ScheduleDateMath.nextAnyRunDate(schedule: dailyAtSix(refreshHours: 3), now: at(7, 22), calendar: calendar)
        XCTAssertEqual(next, at(8, 6))
    }

    // MARK: Endpoint cleartext policy (ATS NSAllowsLocalNetworking)

    func testHTTPSIsAcceptedForAnyHost() {
        XCTAssertNil(APIExportSettings.endpointProblem(for: "https://api.example.com/health"))
        XCTAssertNotNil(APIExportSettings.supportedEndpointURL(from: " https://api.example.com/health "))
    }

    func testPlainHTTPToAnInternetHostIsRejected() {
        XCTAssertEqual(APIExportSettings.endpointProblem(for: "http://httpbin.org/post"), .cleartextToInternetHost)
        XCTAssertNil(APIExportSettings.supportedEndpointURL(from: "http://httpbin.org/post"))
    }

    func testPlainHTTPToLocalHostsIsAccepted() {
        for url in [
            "http://192.168.1.5:8080/ingest",
            "http://127.0.0.1/x",
            "http://localhost:3000/x",
            "http://nas.local/x",
            "http://homeserver/x",
            "http://[::1]:8080/x",
        ] {
            XCTAssertNil(APIExportSettings.endpointProblem(for: url), url)
        }
    }

    func testMalformedEndpointsAreInvalid() {
        for url in ["", "foo", "ftp://example.com", "https://"] {
            XCTAssertEqual(APIExportSettings.endpointProblem(for: url), .invalid, url)
        }
    }

    func testNumericLookingInternetHostIsNotTreatedAsAnIP() {
        XCTAssertEqual(APIExportSettings.endpointProblem(for: "http://1.2.3.example.com/x"), .cleartextToInternetHost)
    }

    // MARK: Restore cancellation

    func testCancellingTheAppleAccountPromptIsNotAnError() {
        XCTAssertTrue(PurchaseManager.isUserCancellation(StoreKitError.userCancelled))
        XCTAssertTrue(PurchaseManager.isUserCancellation(SKError(.paymentCancelled)))
        XCTAssertTrue(PurchaseManager.isUserCancellation(URLError(.cancelled)))
        XCTAssertFalse(PurchaseManager.isUserCancellation(StoreKitError.notAvailableInStorefront))
        XCTAssertFalse(PurchaseManager.isUserCancellation(URLError(.notConnectedToInternet)))
    }

    #if os(iOS)
    // MARK: No-data export toast

    func testNoHealthDataShowsNoFailedToast() {
        XCTAssertNil(ContentView.failureToastStatus("API export failed", reason: .noHealthData))
        XCTAssertEqual(ContentView.failureToastStatus("API export failed", reason: .deviceLocked), "API export failed")
    }

    // MARK: Schedule row names the refresh cadence

    func testScheduleRowNamesTheRefreshInterval() {
        let base = ScheduledExportEntry(profileID: UUID(), isEnabled: true, frequency: .daily, preferredHour: 6)
        var refreshing = base
        refreshing.todayRefreshEnabled = true
        refreshing.todayRefreshMinutes = 180

        let plain = AutomationFacts.scheduleShortLabel(base)
        let withRefresh = AutomationFacts.scheduleShortLabel(refreshing)
        XCTAssertTrue(withRefresh.hasPrefix(plain), withRefresh)
        XCTAssertTrue(withRefresh.contains(ScheduleSheetCopy.refreshChipTitle(minutes: 180)), withRefresh)
    }
    #endif
}
