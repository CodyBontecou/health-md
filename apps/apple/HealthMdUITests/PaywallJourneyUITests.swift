import XCTest

/// Setup stays available; export entry points enforce the one-action allowance.
final class PaywallJourneyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testFreshInstallCanBeginSetupWithoutAccess() {
        let app = UITestLaunchHelper.configuredApp(showOnboarding: true)
        app.launch()
        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
    }

    // Retain the CI selector. Exhaustion gates the requested export, not app launch.
    func testPaywallShown_whenQuotaExhausted() {
        let app = UITestLaunchHelper.configuredApp(healthAuthorized: true, vaultSelected: true, freeExportsUsed: 1)
        app.launch()
        let export = app.buttons["glass.exportNow"]
        XCTAssertTrue(export.waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
        export.tap()
        let confirm = app.buttons["glass.exportNow.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts[UITestLaunchHelper.Paywall.title].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Paywall.restoreButton].exists)
    }

    func testUnusedAllowanceCanReachExportControls() {
        let app = UITestLaunchHelper.configuredApp(healthAuthorized: true, vaultSelected: true, freeExportsUsed: 0)
        app.launch()
        XCTAssertTrue(app.buttons["glass.exportNow"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
    }

    func testForegroundKeepsUnpaidSetupReachable() {
        let app = UITestLaunchHelper.configuredApp(showOnboarding: true)
        app.launch()
        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
    }

    func testUnlockedUserCanReachExportsWithoutQuotaCopy() {
        let app = UITestLaunchHelper.configuredApp(healthAuthorized: true, vaultSelected: true, purchaseUnlocked: true)
        app.launch()
        XCTAssertTrue(app.buttons["glass.exportNow"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Export.freeExportsLabel].exists)
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
    }
}
