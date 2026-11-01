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
        // At regular width the name is in both panes, and the detail is already open.
        let card = app.staticTexts["Default"].firstMatch
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

    func testLockedUserMeetsTheGlassHardPaywall() {
        continueAfterFailure = false
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: false,
            scheduleEnabled: true
        )
        app.launchArguments += ["-NewExperienceEnabled", "YES"]
        app.launch()

        // A locked user meets the hard gate first, and it cannot be dismissed.
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Paywall.restoreButton].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons[UITestLaunchHelper.Paywall.dismissButton].exists)
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
        let onboarding = UITestLaunchHelper.configuredApp(healthAuthorized: true, showOnboarding: true, purchaseUnlocked: true)
        onboarding.launchArguments += ["-NewExperienceEnabled", "YES"]
        onboarding.launch()
        func shot(_ name: String) {
            guard let directory = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT_DIR"] else { return }
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
        }
        let connect = onboarding.buttons["Connect Apple Health"]
        XCTAssertTrue(connect.waitForExistence(timeout: 10))
        shot("onboarding")
        connect.tap()
        // The request still happens on the Health step, after its explanation.
        XCTAssertTrue(onboarding.staticTexts["Choose What Health.md Can Read"].waitForExistence(timeout: 5))
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

    func testComposerFieldToggleSavesAndUpdatesTheCount() {
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
        let card = app.staticTexts["Default"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        app.buttons["Edit sentence →"].tap()

        let all = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "All 2")).firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        let before = all.label
        let field = app.switches["Total Sleep"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()

        let changed = NSPredicate(format: "label != %@", before)
        expectation(for: changed, evaluatedWith: all)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(app.switches["Total Sleep"].exists, "The field must leave the note once off.")
    }

    func testTappingTheCurrentTabReturnsToItsRoot() {
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
        let row = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Mac Destination")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.macDestination"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The hub must be back on screen.")
    }
}
