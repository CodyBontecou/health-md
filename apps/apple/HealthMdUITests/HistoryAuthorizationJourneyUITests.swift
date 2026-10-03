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

    func testUnknownHistoryPreviewHasAccessibleActionOnNativeRoot() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchEnvironment["UITEST_HISTORY_ASSESSMENT"] = "unknown"
        app.launch()
        let message = app.staticTexts["export.historyWarning.message"]
        reveal(message, in: app)
        XCTAssertTrue(message.label.contains("Empty data and completed queries do not prove full history"))
        XCTAssertFalse(app.staticTexts["export.historyWarning.execution"].exists)
        let action = app.buttons["export.historyWarning.reviewAccess"]
        reveal(action, in: app)
        action.tap()
        XCTAssertTrue(app.staticTexts["Adjust Health Permissions"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Open Health App"].exists)
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
            let exists = element.exists
            // Follow the actual element's scrolling ancestor, not an app-wide
            // swipe that can hit the tablet sidebar. If not yet exposed, use
            // the largest public scrolling viewport, not a substituted control.
            let ancestor = exists ? app.scrollViews.containing(.any, identifier: element.identifier).firstMatch : nil
            let largest = app.scrollViews.allElementsBoundByIndex.max {
                $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
            }
            guard let scroll = ancestor?.exists == true ? ancestor : largest else { break }
            let viewport = scroll.frame.intersection(app.frame)
            let tabs = app.tabBars.firstMatch
            let bottom = tabs.exists ? min(viewport.maxY, tabs.frame.minY) : viewport.maxY
            let visible = CGRect(x: viewport.minX, y: viewport.minY,
                                 width: viewport.width, height: max(0, bottom - viewport.minY))
            let center = exists ? CGPoint(x: element.frame.midX, y: element.frame.midY) : .zero
            if exists && element.isHittable && visible.contains(center) { return }
            let above = exists && center.y < visible.minY
            scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.5 : 0.7)).press(
                forDuration: 0.05,
                thenDragTo: scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.7 : 0.5))
            )
        }
        if !element.exists || !element.isHittable {
            let stage = app.descendants(matching: .any)["export.synthetic.historyPreviewStage"]
            print("HISTORY_ROOT_DIAGNOSTIC stage=\(stage.exists ? stage.label : "absent") app=\(app.frame)")
            for id in ["export.historyWarning", "export.historyWarning.message", "export.historyWarning.reviewAccess"] {
                let controls = app.descendants(matching: .any).matching(identifier: id)
                let geometry = controls.allElementsBoundByIndex.prefix(2).map {
                    "type=\($0.elementType.rawValue),frame=\($0.frame),hittable=\($0.isHittable)"
                }
                print("HISTORY_ROOT_DIAGNOSTIC id=\(id) count=\(controls.count) geometry=\(geometry)")
            }
        }
        XCTAssertTrue(element.exists && element.isHittable, "History warning control should be reachable")
    }
}
