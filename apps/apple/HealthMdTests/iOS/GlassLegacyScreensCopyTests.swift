#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class GlassLegacyScreensCopyTests: XCTestCase {
    func testConnectedAppsStatusUsesLastSuccessfulExport() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        XCTAssertEqual(ConnectedAppsStatusText.status(connected: false, lastSync: now, now: now, calendar: calendar),
                       String(localized: "Not connected"))
        XCTAssertEqual(ConnectedAppsStatusText.status(connected: true, lastSync: nil, now: now, calendar: calendar),
                       String(localized: "Connected"))
        let today = ConnectedAppsStatusText.status(connected: true, lastSync: now.addingTimeInterval(-60), now: now, calendar: calendar)
        let earlier = ConnectedAppsStatusText.status(connected: true, lastSync: now.addingTimeInterval(-3 * 86_400), now: now, calendar: calendar)
        XCTAssertTrue(today.hasPrefix("Connected · last sync"), today)
        XCTAssertNotEqual(today, earlier, "Earlier days include the date")
    }

    func testWHOOPChipsFollowFetchedResources() {
        XCTAssertEqual(ConnectedAppsStatusText.whoopSnapshots.count, WHOOPResourceName.allCases.count)
        XCTAssertEqual(ConnectedAppsStatusText.whoopSnapshots.first, String(localized: "Recovery"))
    }

    func testReleaseNotesPresentOnlyForAnUnseenVersionWithNotes() {
        XCTAssertNotNil(HealthMdReleaseNotes.unseenCurrentNotes(version: "3.5.0", latestSeenVersion: nil))
        XCTAssertNotNil(HealthMdReleaseNotes.unseenCurrentNotes(version: "3.5.0", latestSeenVersion: "3.4.5"))
        XCTAssertNil(HealthMdReleaseNotes.unseenCurrentNotes(version: "3.5.0", latestSeenVersion: "3.5.0"))
        XCTAssertNil(HealthMdReleaseNotes.unseenCurrentNotes(version: "0.0.1", latestSeenVersion: nil))
    }

    func testCurrentMarketingVersionHasReleaseNotes() {
        XCTAssertNotNil(
            HealthMdReleaseNotes.notes(for: HealthMdReleaseNotes.currentAppVersion),
            "Every shipped version needs What's New rows"
        )
    }
}
#endif
