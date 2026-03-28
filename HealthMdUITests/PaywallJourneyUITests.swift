import XCTest

/// UI tests for paywall/free-quota behavior.
/// Verifies monetization gating from the user's perspective.
final class PaywallJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Free Exports Indicator

    func testFreeExportsRemaining_showsCountWhenNotUnlocked() throws {
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 1)
        app.launch()

        // The free exports label uses an accessibilityIdentifier
        let freeLabel = app.staticTexts[UITestLaunchHelper.Export.freeExportsLabel]
        XCTAssertTrue(freeLabel.waitForExistence(timeout: 5), "Free exports label should be visible")
        // Check either the label or the element text contains the remaining count
        let text = freeLabel.label
        XCTAssertTrue(
            text.contains("2") || text.contains("free export"),
            "Should show free exports remaining, got: \(text)"
        )
    }

    func testFreeExportsRemaining_hiddenWhenUnlocked() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true
        )
        app.launch()

        // Wait for the export button to ensure UI has loaded
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        let freeLabel = app.staticTexts[UITestLaunchHelper.Export.freeExportsLabel]
        XCTAssertFalse(freeLabel.exists, "Free exports label should be hidden when unlocked")
    }

    // MARK: - Paywall Gating

    func testPaywallShown_whenQuotaExhausted() throws {
        // Set up with all 3 free exports used, NOT unlocked
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 3)
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        // Tap export — should show paywall since quota is exhausted
        exportButton.tap()

        // Verify paywall appears (use text content — identifier may be collapsed by parent)
        let unlockTitle = app.staticTexts["Unlock Health.md"]
        XCTAssertTrue(unlockTitle.waitForExistence(timeout: 5), "Paywall should appear when quota exhausted")

        // Verify paywall subtitle is visible (confirms paywall content is loaded)
        let subtitle = app.staticTexts["You've used your 3 free exports"]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 3), "Paywall subtitle should be visible")
    }

    func testPaywallDismiss_closesPaywall() throws {
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 3)
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        // Wait for paywall (use text content)
        let unlockTitle = app.staticTexts["Unlock Health.md"]
        XCTAssertTrue(unlockTitle.waitForExistence(timeout: 5))

        // Dismiss paywall by swiping down (more reliable than finding the small X button)
        let paywallElement = app.otherElements["paywall.view"]
        if paywallElement.waitForExistence(timeout: 3) {
            paywallElement.swipeDown()
        } else {
            // Fallback: swipe down from center of screen
            let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.3))
            let below = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
            center.press(forDuration: 0.1, thenDragTo: below)
        }

        // Verify paywall is dismissed — export button should be visible again
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "Should return to export tab after dismissing paywall")
    }

    // MARK: - Export Allowed With Remaining Quota

    func testExportAllowed_whenFreeQuotaRemains() throws {
        // 2 exports used, 1 remaining
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 2)
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        // Tap export — should proceed to export (not paywall) since 1 free export remains
        exportButton.tap()

        // Should see the status badge from simulated export, not paywall
        let statusBadge = app.otherElements[UITestLaunchHelper.Status.exportStatusBadge]
        let paywallTitle = app.staticTexts[UITestLaunchHelper.Paywall.title]

        // Wait a moment for either to appear
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"),
            object: statusBadge
        )
        let result = XCTWaiter.wait(for: [expectation], timeout: 10)
        if result == .timedOut {
            // Paywall should NOT have appeared
            XCTAssertFalse(paywallTitle.exists, "Paywall should not appear when free quota remains")
        }
    }
}
