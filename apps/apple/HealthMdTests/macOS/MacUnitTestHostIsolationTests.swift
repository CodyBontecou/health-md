#if os(macOS)
import AppKit
import UserNotifications
import XCTest
@testable import HealthMd

@MainActor
final class MacUnitTestHostIsolationTests: XCTestCase {
    func testUnitHostMountsOnlyItsEmptySceneInsteadOfRuntimeViews() {
        XCTAssertTrue(TestMode.isUnitTesting)
        let windows = NSApplication.shared.windows
        let titles = windows.map(\.title)
        let host = windows.first { $0.title == "Health.md Unit Test Host" }
        XCTAssertNotNil(host, "The app-hosted suite must mount its isolated test scene")
        if let host {
            XCTAssertLessThan(host.frame.width, 512, "The unit host must not allocate a full runtime window")
            XCTAssertLessThan(host.frame.height, 512, "The unit host must not allocate a full runtime window")
        }
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
