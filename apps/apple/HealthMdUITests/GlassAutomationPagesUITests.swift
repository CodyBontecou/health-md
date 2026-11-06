import XCTest

/// Flag-on reach test for the automation sub-pages. Each one is pushed from the hub and
/// goes back without changing anything (the pages save as they change).
final class GlassAutomationPagesUITests: XCTestCase {
    func testEveryAutomationPageOpensFromTheHub() {
        continueAfterFailure = false
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true
        )
        app.launch()

        app.buttons["Automations"].tap()
        // At regular width the name is in both panes, and the detail is already open.
        let card = app.staticTexts["Default"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()

        // AutomationDetailG rows read "Formats & detail" and "Format"; the pages keep their titles.
        let pages = [
            ("metrics", "Metrics"), ("formats", "Formats"), ("formatCustom", "Customize format"),
            ("output", "Output"), ("dailyNotes", "Daily notes"), ("entries", "Individual entries"),
        ]
        for (identifier, title) in pages {
            let row = app.buttons["glass.automation.\(identifier)"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 5), title)
            row.tap()
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 5), title)
            XCTAssertFalse(bar.buttons["Save"].exists, "\(title) saves as it changes")
            if let directory = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT_DIR"] {
                let url = URL(fileURLWithPath: directory).appendingPathComponent("page-\(title).png")
                try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
            }
            bar.buttons.firstMatch.tap()
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
        app.launch()

        app.buttons["Settings"].tap()
        let pages = [("folder", "glass.folderDestination"), ("mac", "glass.macDestination"), ("cli", "glass.cliDestination")]
        for (title, identifier) in pages {
            let row = app.buttons["glass.settings.\(title)"]
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
        app.launch()

        app.buttons["Settings"].tap()
        let support = app.buttons["glass.settings.appSupport"]
        XCTAssertTrue(support.waitForExistence(timeout: 5))
        support.tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.appSupport"].waitForExistence(timeout: 5))
        let toggle = app.switches[UITestLaunchHelper.ConfigurationProtection.toggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        app.buttons["Automations"].tap()
        // AutomationsGlass names the add action "New automation".
        let newProfile = app.buttons["New automation"]
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
        app.launch()

        app.buttons["Settings"].tap()
        app.buttons["glass.settings.appSupport"].tap()
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
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        sleep(1)
        // iPadAutomationsG / iPadSettingsG: two panes are iPad-only. A regular-width phone
        // (Pro Max landscape, unfolded Duo) keeps the phone column. The runner reports a
        // phone idiom even on iPad, so measure the window's short side.
        let window = app.windows.firstMatch.frame
        guard window.width > 900, min(window.width, window.height) >= 600 else {
            throw XCTSkip("Two panes are iPad-only; this device keeps the phone column.")
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
        let appSupport = app.buttons["glass.settings.appSupport"]
        appSupport.tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.appSupport"].waitForExistence(timeout: 5))
        XCTAssertTrue(appSupport.exists, "The hub must stay beside the detail.")
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
        app.launch()
        app.buttons["Automations"].tap()
        let card = app.staticTexts["Default"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        card.tap()
        app.buttons["Edit sentence →"].tap()

        // ComposeGlass: field checks are staged until Save and stay listed so they can be
        // undone; Save commits them and the automation's metric count follows.
        let count = NSPredicate(format: "label ENDSWITH %@", " metrics")
        let composerCount = app.buttons.matching(count).firstMatch
        XCTAssertTrue(composerCount.waitForExistence(timeout: 5))
        let before = composerCount.label
        let field = app.buttons["Total Sleep"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "On")
        field.tap()
        expectation(for: NSPredicate(format: "value == %@", "Off"), evaluatedWith: field)
        waitForExpectations(timeout: 5)

        app.buttons["glass.composer.save"].tap()
        XCTAssertTrue(app.buttons["Run now"].waitForExistence(timeout: 5))
        let detailCount = app.staticTexts.matching(count).firstMatch
        XCTAssertTrue(detailCount.waitForExistence(timeout: 5))
        XCTAssertNotEqual(detailCount.label, before, "Saving an unchecked field must update the count.")

        // The saved note no longer lists the field.
        app.buttons["Edit sentence →"].tap()
        XCTAssertTrue(app.buttons["glass.composer.save"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Total Sleep"].exists, "The field must leave the note once saved off.")
    }

    func testTappingTheCurrentTabReturnsToItsRoot() {
        continueAfterFailure = false
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true
        )
        app.launch()
        app.buttons["Settings"].tap()
        let row = app.buttons["glass.settings.mac"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.macDestination"].waitForExistence(timeout: 5))
        app.buttons["Settings"].tap()
        XCTAssertTrue(row.waitForExistence(timeout: 5), "The hub must be back on screen.")
    }
}
