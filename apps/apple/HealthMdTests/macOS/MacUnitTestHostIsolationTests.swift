#if os(macOS)
import AppKit
import UserNotifications
import XCTest
@testable import HealthMd

@MainActor
final class MacUnitTestHostIsolationTests: XCTestCase {
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
