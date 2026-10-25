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
        // The default metric set includes unresolved readable-range types. The
        // real All Time resolver correctly rejects that range independently of
        // the advisory limited-history warning. Finish its dialog before tapping
        // controls behind it; XCTest otherwise consumes Details to dismiss it.
        let unavailable = app.staticTexts["All Time Unavailable"]
        XCTAssertTrue(unavailable.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "The earliest date could not be determined for every selected metric."
        )).firstMatch.exists)
        app.buttons["Done"].tap()
        XCTAssertTrue(unavailable.waitForNonExistence(timeout: 5))
        let message = app.staticTexts["export.historyWarning.message"]
        reveal(message, in: app)
        // Selecting a range invalidates the old preview before the asynchronous
        // assessment publishes. Wait for the expected state, not just the card.
        let limitedMessage = app.staticTexts.matching(NSPredicate(
            format: "identifier == %@ AND label CONTAINS %@",
            "export.historyWarning.message", "Earlier data is unknown, not missing"
        )).firstMatch
        XCTAssertTrue(limitedMessage.waitForExistence(timeout: 5),
                      "Limited assessment must publish its warning; actual: \(message.label)")
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
        // The real export viewport has one stable owner on both native roots. A
        // descendant-containing query can repeatedly snapshot transient SwiftUI
        // children and timed out on the hosted iPad before any pan was attempted.
        let owners = app.scrollViews.matching(identifier: UITestLaunchHelper.Export.contentScroll)
        let scroll = owners.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 5), "Native export scroll owner must exist")
        guard scroll.exists else { return }
        XCTAssertEqual(owners.count, 1, "Exactly one native export viewport must own the identifier")
        for _ in 0..<12 {
            let exists = element.exists
            let viewport = scroll.frame.intersection(app.frame)
            // Both native roots lay this identified viewport inside their safe
            // area. A broad TabBar firstMatch snapshot hangs on the SDK27 large-
            // text phone root before any pan; use the viewport's own boundary.
            // The pinned export/status overlays still reduce it below.
            var bottom = viewport.maxY
            // The completion badge and export footer are pinned above the tab
            // bar. A pan at 70% of the AX scroll frame lands on them, not on the
            // page (the exact bounded/pending execution failures showed no travel).
            let export = app.buttons[UITestLaunchHelper.Export.exportButton]
            if (!exists || element.identifier != UITestLaunchHelper.Export.exportButton) && export.exists && export.isHittable {
                let exportFrame = export.frame
                // The phone footer occludes the bottom of the scroll viewport.
                // The iPad action is in the top header; treating it as a footer
                // reduces pans to the status bar and never reveals lower cards.
                if exportFrame.midY > viewport.midY {
                    // SchedulingExportFooter adds 8pt inner and 12pt top padding.
                    bottom = min(bottom, exportFrame.minY - 20)
                    let quota = app.staticTexts[UITestLaunchHelper.Export.freeExportsLabel]
                    if quota.exists { bottom = min(bottom, quota.frame.minY - 20) }
                }
            }
            let status = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
            if status.exists {
                let statusFrame = status.frame
                if statusFrame.midY > viewport.midY { bottom = min(bottom, statusFrame.minY) }
            }
            let visible = CGRect(x: viewport.minX, y: viewport.minY,
                                 width: viewport.width, height: max(0, bottom - viewport.minY)).insetBy(dx: 4, dy: 4)
            let center = exists ? CGPoint(x: element.frame.midX, y: element.frame.midY) : .zero
            let safelyVisible = exists && (element.elementType == .button
                ? visible.contains(element.frame) : visible.contains(center))
            if safelyVisible && element.isHittable { return }
            guard visible.height > 44 else { break }
            let above = exists && center.y < visible.minY
            // Both native roots expose the selected preset as an AX trait. A
            // non-custom preset has no date pickers; enumerating its virtual
            // DatePicker descendants stalled the actual large-text iPad query.
            let custom = app.buttons[UITestLaunchHelper.Export.datePresetCustomButton]
            let pickers: [CGRect]
            // A virtualized preset may be absent from AX. In that case retain
            // the two exact picker checks; skip them only for known non-Custom.
            if !custom.exists || custom.isSelected {
                pickers = [UITestLaunchHelper.Export.customStartDatePicker,
                           UITestLaunchHelper.Export.customEndDatePicker].compactMap { identifier in
                    let picker = app.datePickers[identifier]
                    return picker.exists ? picker.frame : nil
                }
            } else {
                pickers = []
            }
            let preferredY = visible.minY + visible.height * (above ? 0.25 : 0.75)
            // Querying every virtual StaticText costs one remote AX snapshot
            // per node. This consumed the pending phone fixture's lifetime and
            // the iPad lane deadline. Pan inside the real scroll viewport instead,
            // avoiding date-picker wheels and the pinned footer above.
            let xPositions = [visible.midX, visible.minX + 12, visible.maxX - 12]
            let yPositions = [preferredY, visible.midY,
                              visible.minY + visible.height * (above ? 0.75 : 0.25)]
            let anchors = yPositions.flatMap { y in xPositions.map { CGPoint(x: $0, y: y) } }
            guard let point = anchors.first(where: { candidate in
                visible.contains(candidate) && !pickers.contains(where: { $0.contains(candidate) })
            }) else { break }
            let room = above ? visible.maxY - point.y : point.y - visible.minY
            let travel = min(visible.height * 0.55, room - 4)
            guard travel > 12 else { break }
            // Preserve the selected scroll owner's geometry without repeatedly
            // re-resolving an ancestor query containing a transient child.
            let start = app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: point.x - app.frame.minX, dy: point.y - app.frame.minY))
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
