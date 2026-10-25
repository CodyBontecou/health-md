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
            text.contains("4"),
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

    func testFreeExportsRemaining_hiddenWhenUnlockedWithAnalyticsOffline() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            freeExportsUsed: 5,
            analyticsTransport: "offline",
            remoteConfig: "offline"
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        let freeLabel = app.staticTexts[UITestLaunchHelper.Export.freeExportsLabel]
        XCTAssertFalse(freeLabel.exists, "Unlocked users should not see quota copy when analytics is offline")
    }

    // MARK: - Paywall Gating

    func testPaywallShown_whenQuotaExhausted() throws {
        // Set up with all 5 free exports used, NOT unlocked
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 5)
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        // Tap export — should show paywall since quota is exhausted
        exportButton.tap()

        let paywallTitle = app.staticTexts[UITestLaunchHelper.Paywall.title]
        XCTAssertTrue(paywallTitle.waitForExistence(timeout: 5), "Paywall should appear when quota exhausted")

        // Verify paywall subtitle is visible (confirms paywall content is loaded).
        let subtitle = app.staticTexts[UITestLaunchHelper.Paywall.subtitle]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 3), "Paywall subtitle should be visible")
    }

    func testPaywallShown_whenQuotaExhaustedWithAnalyticsOffline() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            freeExportsUsed: 5,
            analyticsTransport: "offline",
            remoteConfig: "offline"
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let paywallTitle = app.staticTexts[UITestLaunchHelper.Paywall.title]
        XCTAssertTrue(paywallTitle.waitForExistence(timeout: 5), "Paywall should appear with analytics offline")

        let subtitle = app.staticTexts[UITestLaunchHelper.Paywall.subtitle]
        XCTAssertTrue(subtitle.waitForExistence(timeout: 3), "Paywall content should load with analytics offline")
    }

    func testPaywallDismiss_closesPaywall() throws {
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 5)
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let paywallTitle = app.staticTexts[UITestLaunchHelper.Paywall.title]
        XCTAssertTrue(paywallTitle.waitForExistence(timeout: 5))

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
        // 4 exports used, 1 remaining
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 4)
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        // Tap export — should proceed to export (not paywall) since 1 free export remains.
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

    func testExportAllowed_whenFreeQuotaRemainsWithAnalyticsOffline() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            freeExportsUsed: 4,
            analyticsTransport: "offline",
            remoteConfig: "offline"
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let statusBadge = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 10), "Export should succeed with analytics offline")
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists, "Paywall should not appear while quota remains")
    }
    func testFirstExportOffersSchedulingWithoutOpeningPaywall() throws {
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 0)
        app.launchEnvironment["UITEST_SUPPRESSED_UPGRADE_PROMPTS"] = ""
        app.launch()
        let export = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        let schedule = app.buttons["upgradePrompt.scheduleButton"]
        XCTAssertTrue(schedule.waitForExistence(timeout: 10))
        let firstCapture = XCTAttachment(screenshot: app.screenshot())
        firstCapture.name = "First export scheduling guidance"
        firstCapture.lifetime = .keepAlways
        add(firstCapture)
        XCTAssertTrue(app.staticTexts["upgradePrompt.remaining"].label.contains("4"))
        schedule.tap()
        XCTAssertTrue(app.switches["schedule.enableToggle"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
    }

    func testThirdExportOffersLifetimeWithTwoRemainingAndCanContinueFree() throws {
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 2)
        app.launchEnvironment["UITEST_SUPPRESSED_UPGRADE_PROMPTS"] = ""
        app.launch()
        let export = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        let upgrade = app.buttons["upgradePrompt.upgradeButton"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 10))
        let thirdCapture = XCTAttachment(screenshot: app.screenshot())
        thirdCapture.name = "Third export lifetime offer"
        thirdCapture.lifetime = .keepAlways
        add(thirdCapture)
        XCTAssertTrue(app.staticTexts["upgradePrompt.remaining"].label.contains("2"))
        app.buttons["upgradePrompt.notNowButton"].tap()
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[UITestLaunchHelper.Export.freeExportsLabel].label.contains("2"))
        XCTAssertFalse(app.staticTexts[UITestLaunchHelper.Paywall.title].exists)
    }

    func testThirdExportLifetimeActionOpensReviewablePaywall() throws {
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 2)
        app.launchEnvironment["UITEST_SUPPRESSED_UPGRADE_PROMPTS"] = ""
        app.launch()
        let export = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        let upgrade = app.buttons["upgradePrompt.upgradeButton"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 10))
        upgrade.tap()
        XCTAssertTrue(app.staticTexts[UITestLaunchHelper.Paywall.title].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[UITestLaunchHelper.Paywall.subtitle].label.contains("3 of your 5"))
    }

    func testThirdExportGuidanceSupportsDarkModeAndLargeText() throws {
        let app = UITestLaunchHelper.freeQuotaApp(exportsUsed: 2)
        app.launchEnvironment["UITEST_SUPPRESSED_UPGRADE_PROMPTS"] = ""
        app.launchArguments += ["-AppleInterfaceStyle", "Dark", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        let export = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        export.tap()
        let upgrade = app.buttons["upgradePrompt.upgradeButton"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 10))
        if !upgrade.isHittable { app.swipeUp() }
        XCTAssertTrue(upgrade.isHittable)
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "Third export dark large text"
        capture.lifetime = .keepAlways
        add(capture)
        upgrade.tap()
        XCTAssertTrue(app.staticTexts[UITestLaunchHelper.Paywall.title].waitForExistence(timeout: 5))
    }

}
