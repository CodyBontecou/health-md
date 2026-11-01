import XCTest

/// Flag-on reach test for the automation sub-pages. Each one opens from the hub and cancels
/// without saving.
final class GlassAutomationPagesUITests: XCTestCase {
    func testEveryAutomationPageOpensFromTheHub() {
        continueAfterFailure = false
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true
        )
        app.launchArguments += ["-NewExperienceEnabled", "YES"]
        app.launch()

        app.buttons["Automations"].tap()
        let card = app.staticTexts["Default"]
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        for title in ["Metrics", "Formats", "Customize format", "Output", "Daily notes", "Individual entries"] {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), title)
            row.tap()
            let cancel = app.buttons["Cancel"]
            XCTAssertTrue(cancel.waitForExistence(timeout: 5), title)
            if let directory = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT_DIR"] {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("page-\(title).png")
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
            }
            cancel.tap()
            XCTAssertTrue(row.waitForExistence(timeout: 5), title)
        }
    }

    func testDestinationPagesOpenFromSettings() {
        continueAfterFailure = false
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true
        )
        app.launchArguments += ["-NewExperienceEnabled", "YES"]
        app.launch()

        app.buttons["Settings"].tap()
        let pages = [("Folder", "glass.folderDestination"), ("Mac Destination", "glass.macDestination"), ("CLI", "glass.cliDestination")]
        for (title, identifier) in pages {
            let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), title)
            row.tap()
            XCTAssertTrue(app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5), title)
            if let directory = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT_DIR"] {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("dest-\(title).png")
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
            }
            app.navigationBars.buttons.firstMatch.tap()
        }
    }

    func testLockBlocksEditsAndAppSupportCanTurnItOff() {
        continueAfterFailure = false
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true
        )
        app.launchArguments += ["-NewExperienceEnabled", "YES"]
        app.launch()

        app.buttons["Settings"].tap()
        let support = app.buttons["App & support"]
        XCTAssertTrue(support.waitForExistence(timeout: 5))
        support.tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.appSupport"].waitForExistence(timeout: 5))
        let toggle = app.switches[UITestLaunchHelper.ConfigurationProtection.toggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        app.buttons["Automations"].tap()
        let newProfile = app.buttons["New profile"]
        XCTAssertTrue(newProfile.waitForExistence(timeout: 5))
        newProfile.tap()
        let toast = app.buttons[UITestLaunchHelper.ConfigurationProtection.toast]
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        toast.tap()

        XCTAssertTrue(app.descendants(matching: .any)["glass.appSupport"].waitForExistence(timeout: 5))
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
    }

    func testGlassPaywallOffersPurchaseAndRestore() {
        continueAfterFailure = false
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: false,
            scheduleEnabled: true
        )
        app.launchArguments += ["-NewExperienceEnabled", "YES"]
        app.launch()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let account = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Health.md")).firstMatch
        XCTAssertTrue(account.waitForExistence(timeout: 5))
        account.tap()
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Paywall.restoreButton].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Paywall.unlockButton].exists)
        if let directory = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("paywall.png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
    }

    func testDiagnosticsOpensFromAppSupportWithItsSafeguards() {
        continueAfterFailure = false
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true
        )
        app.launchArguments += ["-NewExperienceEnabled", "YES"]
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["App & support"].tap()
        let diagnostics = app.buttons["Diagnostics"]
        var swipes = 0
        while !diagnostics.isHittable && swipes < 5 {
            app.swipeUp()
            swipes += 1
        }
        diagnostics.tap()
        XCTAssertTrue(app.switches["diagnostics.enabled"].waitForExistence(timeout: 5))
        if let directory = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("diagnostics.png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        // Share stays unreachable until a bundle is prepared and reviewed.
        XCTAssertFalse(app.buttons["diagnostics.share"].exists)
    }

    func testClinicianReportAndOnboardingKeepWorkingWithTheFlagOn() {
        continueAfterFailure = false
        let onboarding = UITestLaunchHelper.configuredApp(healthAuthorized: true, showOnboarding: true)
        onboarding.launchArguments += ["-NewExperienceEnabled", "YES"]
        onboarding.launch()
        func shot(_ name: String) {
            guard let directory = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT_DIR"] else { return }
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        sleep(3)
        shot("onboarding")
        onboarding.terminate()

        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true
        )
        app.launchArguments += ["-NewExperienceEnabled", "YES"]
        app.launch()
        app.buttons["Settings"].tap()
        let report = app.buttons["Clinician report"]
        XCTAssertTrue(report.waitForExistence(timeout: 5))
        report.tap()
        XCTAssertTrue(app.textFields["clinicianReport.displayName"].waitForExistence(timeout: 5))
        shot("clinician")
    }

    func testRegularWidthShowsAutomationsAndSettingsInTwoPanes() throws {
        continueAfterFailure = false
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true
        )
        app.launchArguments += ["-NewExperienceEnabled", "YES"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        sleep(1)
        guard app.windows.firstMatch.frame.width > 900 else {
            throw XCTSkip("This device is compact in landscape.")
        }
        func shot(_ name: String) {
            guard let directory = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT_DIR"] else { return }
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }

        app.buttons["Automations"].tap()
        // The list and the first automation's detail are on screen together.
        XCTAssertTrue(app.staticTexts["Default"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Run now"].waitForExistence(timeout: 5))
        shot("duo-automations")

        app.buttons["Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.folderDestination"].waitForExistence(timeout: 5))
        app.buttons["App & support"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.appSupport"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["App & support"].exists, "The hub must stay beside the detail.")
        shot("duo-settings")
    }
}
