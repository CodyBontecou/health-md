import XCTest

/// Synthetic SDK-adapter outcomes through real Export navigation/execution UI.
/// These tests do not prove physical HealthKit permission behavior.
final class HistoryAuthorizationJourneyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAllTimeLimitedHistoryShowsBoundaryAndPermissionGuide() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchEnvironment["UITEST_HISTORY_ASSESSMENT"] = "limited"
        app.launch()
        let allTime = app.buttons[UITestLaunchHelper.Export.datePresetAllTimeButton]
        reveal(allTime, in: app)
        allTime.tap()
        let message = app.staticTexts["export.historyWarning.message"]
        reveal(message, in: app)
        XCTAssertTrue(message.label.contains("Earlier data is unknown, not missing"))
        XCTAssertFalse(app.staticTexts["export.historyWarning.execution"].exists)
        let details = app.buttons["export.historyWarning.details"]
        reveal(details, in: app)
        details.tap()
        let boundary = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "sample end boundary")).firstMatch
        XCTAssertTrue(boundary.waitForExistence(timeout: 5))
        XCTAssertTrue(boundary.label.contains("Earlier starts are preserved"))
        XCTAssertTrue(boundary.label.contains("Dependencies for:"))
        details.tap()
        let action = app.buttons["export.historyWarning.reviewAccess"]
        reveal(action, in: app)
        action.tap()
        XCTAssertTrue(app.staticTexts["Adjust Health Permissions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Health App"].exists)
    }

    func testBoundedUnknownHistoryRechecksExecutionWithoutClaimingFullAccess() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchEnvironment["UITEST_HISTORY_ASSESSMENT"] = "unknown"
        app.launch()
        let custom = app.buttons[UITestLaunchHelper.Export.datePresetCustomButton]
        reveal(custom, in: app)
        custom.tap()
        let message = app.staticTexts["export.historyWarning.message"]
        reveal(message, in: app)
        XCTAssertTrue(message.label.contains("Empty data and completed queries do not prove full history"))
        XCTAssertFalse(app.staticTexts["export.historyWarning.execution"].exists)
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        reveal(exportButton, in: app)
        exportButton.tap()
        XCTAssertTrue(app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge].waitForExistence(timeout: 10))
        let execution = app.staticTexts["export.historyWarning.execution"]
        reveal(execution, in: app)
        XCTAssertTrue(execution.label.contains("Rechecked for this export"))
        XCTAssertTrue(app.buttons["View Exported File"].exists)
    }

    func testUnavailableHistoryAtLargeTextHasAccessibleAction() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchEnvironment["UITEST_HISTORY_ASSESSMENT"] = "unavailable"
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch()
        let message = app.staticTexts["export.historyWarning.message"]
        reveal(message, in: app)
        XCTAssertTrue(message.label.contains("Readable records can still be exported"))
        let action = app.buttons["export.historyWarning.reviewAccess"]
        reveal(action, in: app)
        XCTAssertTrue(action.isHittable)
        action.tap()
        XCTAssertTrue(app.staticTexts["Adjust Health Permissions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Health App"].exists)
    }

    func testDelayedAssessmentCanContinueUnverifiedWithoutBlockingReadableExport() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchEnvironment["UITEST_HISTORY_ASSESSMENT"] = "pending"
        app.launch()
        defer { app.terminate() }
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()
        let continueButton = app.buttons["export.historyWarning.continueUnverified"]
        reveal(continueButton, in: app)
        continueButton.tap()
        let status = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        let execution = app.staticTexts["export.historyWarning.execution"]
        reveal(execution, in: app)
        XCTAssertTrue(execution.label.contains("without a completed history assessment"))
        XCTAssertFalse(execution.label.contains("Rechecked"))
        XCTAssertFalse(app.buttons["export.historyWarning.cancelCheck"].exists)
        XCTAssertTrue(app.buttons["View Exported File"].exists)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "History warning control should be reachable")
    }
}
