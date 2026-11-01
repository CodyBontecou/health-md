import XCTest

/// Flag-on journey through the Liquid Glass shell. Setting `GLASS_SCREENSHOT_DIR` in the
/// runner environment also saves screenshots for comparison with the design files.
final class GlassShellJourneyUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(exportResult: String? = nil) -> XCUIApplication {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            scheduleEnabled: true,
            exportResult: exportResult
        )
        app.launch()
        return app
    }

    private func shot(_ name: String) {
        guard let directory = ProcessInfo.processInfo.environment["GLASS_SCREENSHOT_DIR"] else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    func testTabsReachEveryRootAndExportNowCompletes() {
        let app = launch(exportResult: "success")
        XCTAssertTrue(app.descendants(matching: .any)["glass.archive"].waitForExistence(timeout: 10))
        shot("archive")

        app.buttons["Automations"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.automations"].waitForExistence(timeout: 5))
        shot("automations")
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.settings"].waitForExistence(timeout: 5))
        shot("settings")
        app.buttons["Archive"].tap()

        app.buttons["glass.exportNow"].tap()
        let confirm = app.buttons["glass.exportNow.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        shot("export-now")
        app.buttons["30 days"].tap()
        XCTAssertTrue(confirm.label.contains("30"))
        shot("export-now-30")
        app.buttons["Yesterday"].tap()
        confirm.tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: confirm)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.descendants(matching: .any)["glass.archive"].waitForExistence(timeout: 10))
        shot("after-export")
    }

    func testComposerAndAppSupportAreReachable() {
        let app = launch()
        XCTAssertTrue(app.buttons["Automations"].waitForExistence(timeout: 10))
        app.buttons["Automations"].tap()
        app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "Default")).firstMatch.tap()
        XCTAssertTrue(app.buttons["Run now"].waitForExistence(timeout: 5))
        shot("automation-detail")
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Schedule")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["Save"].waitForExistence(timeout: 5))
        shot("schedule")
        app.navigationBars.buttons["Save"].tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Metrics")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["Save"].waitForExistence(timeout: 5))
        shot("metrics")
        app.navigationBars.buttons["Save"].tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Formats")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["Cancel"].waitForExistence(timeout: 5))
        shot("formats")
        app.navigationBars.buttons["Cancel"].tap()
        let edit = app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "Edit sentence")).firstMatch
        edit.tap()
        XCTAssertTrue(app.buttons["All settings"].waitForExistence(timeout: 5))
        shot("composer")
        app.buttons["Preview"].tap()
        sleep(2)
        shot("composer-preview")
        XCTAssertFalse(app.buttons["All settings"].isHittable, "The preview should cover the composer")
        app.swipeDown(velocity: .fast)
        XCTAssertTrue(app.buttons["All settings"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        app.navigationBars.buttons.firstMatch.tap()
        app.buttons["Settings"].tap()
        app.buttons.containing(NSPredicate(format: "label BEGINSWITH %@", "API Endpoint")).firstMatch.tap()
        XCTAssertTrue(app.navigationBars.buttons["Done"].waitForExistence(timeout: 5))
        shot("api-destination")
        app.navigationBars.buttons["Done"].tap()
        app.buttons["App & support"].tap()
        sleep(1)
        shot("app-support")
    }

    /// Pro Max landscape has regular width, like an unfolded iPhone Duo.
    func testRegularWidthUsesRailAndTwoPanes() throws {
        let app = launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let exportNow = app.buttons["glass.exportNow"]
        XCTAssertTrue(exportNow.waitForExistence(timeout: 10))
        sleep(1)
        shot("regular-width")
        // Pro is 874 pt wide and compact in landscape; Pro Max is 956 pt and regular.
        guard app.windows.firstMatch.frame.width > 900 else {
            throw XCTSkip("This device is compact in landscape.")
        }
        XCTAssertGreaterThan(exportNow.frame.minX, app.windows.firstMatch.frame.width * 0.8)
    }

    func testIPadLandsOnArchive() throws {
        let app = launch()
        // The runner reports a phone idiom even on iPad, so measure the window.
        guard app.windows.firstMatch.frame.width > 900 else { throw XCTSkip("iPad only.") }
        XCTAssertTrue(app.descendants(matching: .any)["glass.archive"].waitForExistence(timeout: 10))
        shot("ipad-archive")
        // iPad now runs the shared shell, so Automations carries profiles.
        app.buttons["Automations"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["glass.automations"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Default"].waitForExistence(timeout: 5))
        shot("ipad-automations")
    }

    func testFailedExportShowsResultWithRecovery() {
        let app = launch(exportResult: "fail")
        XCTAssertTrue(app.buttons["glass.exportNow"].waitForExistence(timeout: 10))
        app.buttons["glass.exportNow"].tap()
        let confirm = app.buttons["glass.exportNow.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["No Health Data Found"].waitForExistence(timeout: 10))
        shot("export-failed")
    }
}
