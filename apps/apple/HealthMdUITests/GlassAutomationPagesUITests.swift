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
}
