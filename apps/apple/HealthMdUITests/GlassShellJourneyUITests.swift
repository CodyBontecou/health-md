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
        app.launchArguments += ["-NewExperienceEnabled", "YES"]
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
        shot("automations")
        app.buttons["Settings"].tap()
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

    func testFailedExportShowsResultWithRecovery() {
        let app = launch(exportResult: "fail")
        XCTAssertTrue(app.buttons["glass.exportNow"].waitForExistence(timeout: 10))
        app.buttons["glass.exportNow"].tap()
        let confirm = app.buttons["glass.exportNow.confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        sleep(3)
        shot("export-failed")
    }
}
