import XCTest

/// Synthetic SDK-adapter outcomes through real Export navigation/execution UI.
/// These tests do not prove physical HealthKit permission behavior.
final class HistoryAuthorizationJourneyUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private var recordingFailure = false

    override func record(_ issue: XCTIssue) {
        if issue.type == .assertionFailure && !recordingFailure {
            recordingFailure = true
            let app = XCUIApplication()
            if app.state == .runningForeground {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Synthetic history failure screen"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            recordingFailure = false
        }
        super.record(issue)
    }

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
        assertDistinctPreviewIdentifiers(in: app)
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
        assertDistinctPreviewIdentifiers(in: app)
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

    /// These exact assertions replace the in-process UIView traversal, which
    /// cannot enumerate virtual SwiftUI AX nodes. This real-root journey runs
    /// in both phone and iPad CI; the isolated native component suite also checks them.
    private func assertDistinctPreviewIdentifiers(in app: XCUIApplication) {
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "export.historyWarning").count, 1,
                       "One containing card must own its ID rather than overwrite every child")
        XCTAssertTrue(app.staticTexts["export.historyWarning.message"].exists)
        XCTAssertTrue(app.buttons["export.historyWarning.reviewAccess"].exists)
        XCTAssertTrue(app.buttons["export.historyWarning.details"].exists)
        XCTAssertFalse(app.staticTexts["export.historyWarning.execution"].exists, "Preview remains distinct from execution")
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
            var bottom = tabs.exists ? min(viewport.maxY, tabs.frame.minY) : viewport.maxY
            // The completion badge and export footer are pinned above the tab
            // bar. A pan at 70% of the AX scroll frame lands on them, not on the
            // page (the exact bounded/pending execution failures showed no travel).
            let export = app.buttons[UITestLaunchHelper.Export.exportButton]
            if (!exists || element.identifier != UITestLaunchHelper.Export.exportButton) && export.exists && export.isHittable {
                // SchedulingExportFooter adds 8pt inner and 12pt top padding;
                // its hit-testing area begins above the button's AX frame.
                bottom = min(bottom, export.frame.minY - 20)
                let quota = app.staticTexts[UITestLaunchHelper.Export.freeExportsLabel]
                if quota.exists { bottom = min(bottom, quota.frame.minY - 20) }
            }
            let status = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
            if status.exists { bottom = min(bottom, status.frame.minY) }
            let visible = CGRect(x: viewport.minX, y: viewport.minY,
                                 width: viewport.width, height: max(0, bottom - viewport.minY)).insetBy(dx: 4, dy: 4)
            let center = exists ? CGPoint(x: element.frame.midX, y: element.frame.midY) : .zero
            let safelyVisible = exists && (element.elementType == .button
                ? visible.contains(element.frame) : visible.contains(center))
            if safelyVisible && element.isHittable { return }
            guard visible.height > 44 else { break }
            let above = exists && center.y < visible.minY
            let pickers = scroll.datePickers.allElementsBoundByIndex.map(\.frame)
            let preferredY = visible.minY + visible.height * (above ? 0.25 : 0.75)
            let anchors = scroll.staticTexts.allElementsBoundByIndex.compactMap { text -> CGPoint? in
                let intersection = text.frame.intersection(visible.insetBy(dx: 4, dy: 12))
                guard intersection.width > 8, intersection.height > 8 else { return nil }
                let point = CGPoint(x: intersection.midX, y: intersection.midY)
                return pickers.contains(where: { $0.contains(point) }) ? nil : point
            }
            guard let point = anchors.min(by: { abs($0.y - preferredY) < abs($1.y - preferredY) }) else { break }
            let room = above ? visible.maxY - point.y : point.y - visible.minY
            let travel = min(visible.height * 0.55, room - 4)
            guard travel > 12 else { break }
            let start = scroll.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - scroll.frame.minX, dy: point.y - scroll.frame.minY))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: above ? travel : -travel)),
                        withVelocity: .slow, thenHoldForDuration: 0.15)
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
