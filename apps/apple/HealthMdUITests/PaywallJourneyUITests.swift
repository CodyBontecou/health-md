import XCTest

/// The root boundary must require access even when historical quota is unused.
final class PaywallJourneyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func assertGate(in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.staticTexts[UITestLaunchHelper.Paywall.title].waitForExistence(timeout: 10), file: file, line: line)
        XCTAssertFalse(app.buttons[UITestLaunchHelper.Export.exportButton].exists, file: file, line: line)
        XCTAssertFalse(app.buttons["Start Setup"].exists, file: file, line: line)
        XCTAssertFalse(app.buttons[UITestLaunchHelper.Paywall.dismissButton].exists, file: file, line: line)
    }

    func testFreshInstallRequiresAccessBeforeSetup() {
        let app = UITestLaunchHelper.configuredApp(showOnboarding: true)
        app.launch()
        assertGate(in: app)
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Paywall.restoreButton].exists)
    }

    // Keep the existing CI selector while checking the new root-gate policy.
    func testPaywallShown_whenQuotaExhausted() {
        let app = UITestLaunchHelper.configuredApp(healthAuthorized: true, vaultSelected: true, freeExportsUsed: 5)
        app.launch()
        assertGate(in: app)
    }

    func testUnusedHistoricalAllowanceCannotBypassGate() {
        let app = UITestLaunchHelper.configuredApp(healthAuthorized: true, vaultSelected: true, freeExportsUsed: 0)
        app.launch()
        assertGate(in: app)
    }

    func testGateSurvivesDismissGestureAndForeground() {
        let app = UITestLaunchHelper.configuredApp(showOnboarding: true)
        app.launch()
        assertGate(in: app)
        app.swipeDown()
        assertGate(in: app)
        XCUIDevice.shared.press(.home)
        app.activate()
        assertGate(in: app)
    }

    func testUnlockedUserCanReachExportsWithoutQuotaCopy() {
        let app = UITestLaunchHelper.configuredApp(healthAuthorized: true, vaultSelected: true, purchaseUnlocked: true)
        app.launch()
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.exportButton].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Export.freeExportsLabel].exists)
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
    }
}
