#if os(macOS)
import AppKit
import UserNotifications
import XCTest
@testable import HealthMd

@MainActor
final class MacUnitTestHostIsolationTests: XCTestCase {
    func testUnitHostMountsOnlyItsEmptySceneInsteadOfRuntimeViews() {
        XCTAssertTrue(TestMode.isUnitTesting)
        let titles = NSApplication.shared.windows.map(\.title)
        XCTAssertTrue(titles.contains("Health.md Unit Test Host"),
                      "The app-hosted suite must mount its isolated test scene")
        XCTAssertFalse(titles.contains("Mac Destination"),
                       "Runtime views start discovery and must not mount in the unit host")
    }

    func testUnitHostLaunchDoesNotInstallTheAppsNotificationDelegate() {
        XCTAssertTrue(TestMode.isUnitTesting)
        let center = UNUserNotificationCenter.current()
        let previous = center.delegate
        defer { center.delegate = previous }
        let delegate = MacAppDelegate()

        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification)
        )

        XCTAssertTrue(center.delegate === previous,
                      "The unit host must not replace notification ownership with its runtime delegate")
    }
}
#endif
