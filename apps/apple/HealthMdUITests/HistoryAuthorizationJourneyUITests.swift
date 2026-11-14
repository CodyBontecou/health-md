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
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
        app.launch()
        let allTime = app.buttons[UITestLaunchHelper.Export.datePresetAllTimeButton]
        reveal(allTime, in: app)
        allTime.tap()
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
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
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
        let status = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["View Exported File"].exists)
        // The completion toast owns the bottom overlay until the user dismisses it;
        // the shell then presents the retained history assessment in that space.
        let dismissStatus = app.buttons["Dismiss export status"]
        XCTAssertTrue(dismissStatus.waitForExistence(timeout: 5))
        dismissStatus.tap()
        XCTAssertTrue(status.waitForNonExistence(timeout: 5))
        let execution = app.staticTexts["export.historyWarning.execution"]
        XCTAssertTrue(execution.waitForExistence(timeout: 10))
        XCTAssertTrue(execution.label.contains("Rechecked for this export"))
    }

    func testUnknownHistoryPreviewHasAccessibleActionOnNativeRoot() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchEnvironment["UITEST_HISTORY_ASSESSMENT"] = "unknown"
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
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
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
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
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
        app.launch()
        defer { app.terminate() }
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()
        // Exporting closes the settings sheet; the glass shell hosts the history check.
        let continueButton = app.buttons["export.historyWarning.continueUnverified"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 10))
        continueButton.tap()
        let status = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["View Exported File"].exists)
        let dismissStatus = app.buttons["Dismiss export status"]
        XCTAssertTrue(dismissStatus.waitForExistence(timeout: 5))
        dismissStatus.tap()
        XCTAssertTrue(status.waitForNonExistence(timeout: 5))
        let execution = app.staticTexts["export.historyWarning.execution"]
        XCTAssertTrue(execution.waitForExistence(timeout: 10))
        XCTAssertTrue(execution.label.contains("without a completed history assessment"))
        XCTAssertFalse(execution.label.contains("Rechecked"))
        XCTAssertFalse(app.buttons["export.historyWarning.cancelCheck"].exists)
    }

    func testAllTimeCompleteDiscoveryAdmitsExportAndRetainsHistoryDisclosure() {
        let app = discoveryApp("complete")
        app.launch()
        selectAllTime(in: app)
        app.buttons[UITestLaunchHelper.Export.exportButton].tap()
        let status = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(status.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["View Exported File"].exists)
        app.buttons["Dismiss export status"].tap()
        XCTAssertTrue(status.waitForNonExistence(timeout: 5))
        let execution = app.staticTexts["export.historyWarning.execution"]
        XCTAssertTrue(execution.waitForExistence(timeout: 10))
        XCTAssertTrue(execution.label.contains("Rechecked for this export"))
    }

    func testAllTimeCompleteDiscoveryRendersSyntheticPreview() {
        let app = discoveryApp("complete", previewFixtures: true)
        app.launch()
        selectAllTime(in: app)
        app.buttons[UITestLaunchHelper.Export.previewButton].tap()
        XCTAssertTrue(app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
            .waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["View Exported File"].exists, "Preview must not run capture")
    }

    func testAllTimeEmptyDiscoveryCannotAdmitCapture() {
        assertDiscoveryCannotAdmitCapture("empty", expected: "No readable historical data was found")
    }

    func testAllTimeFailedDiscoveryCannotAdmitCapture() {
        assertDiscoveryCannotAdmitCapture("failure",
            expected: "The earliest date could not be determined for every selected metric")
    }

    private func assertDiscoveryCannotAdmitCapture(_ scenario: String, expected: String) {
        let app = discoveryApp(scenario)
        app.launch()
        defer { app.terminate() }
        selectAllTime(in: app)
        app.buttons[UITestLaunchHelper.Export.exportButton].tap()
        let message = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", expected)).firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10), "\(scenario) must block All Time admission")
        XCTAssertFalse(app.buttons["View Exported File"].exists)
        XCTAssertFalse(app.buttons["export.historyWarning.continueUnverified"].exists,
                       "Required readable-range discovery cannot be bypassed as advisory history")
    }

    func testAllTimePendingDiscoveryCanCancelButCannotContinueUnverified() {
        let app = discoveryApp("delayed")
        app.launch()
        defer { app.terminate() }
        selectAllTime(in: app)
        app.buttons[UITestLaunchHelper.Export.exportButton].tap()
        let cancel = app.buttons["export.historyWarning.cancelRangeCheck"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["export.historyWarning.continueUnverified"].exists)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["View Exported File"].exists)
        XCTAssertFalse(app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge].exists)
    }

    func testBackgroundingPendingHistoryInvalidatesAdmission() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchEnvironment["UITEST_HISTORY_ASSESSMENT"] = "pending"
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
        app.launch()
        defer { app.terminate() }
        app.buttons[UITestLaunchHelper.Export.exportButton].tap()
        let continuation = app.buttons["export.historyWarning.continueUnverified"]
        XCTAssertTrue(continuation.waitForExistence(timeout: 10))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(continuation.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["glass.exportNow"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["View Exported File"].exists)
        XCTAssertFalse(app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge].exists)
    }

    func testWideCustomRangeCancelDoesNotAdmitCapture() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
        app.launch()
        selectWideCustomRange(in: app)
        app.buttons[UITestLaunchHelper.Export.exportButton].tap()
        let cancel = app.buttons["export.confirmLargeExport.cancelButton"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["View Exported File"].exists)
        cancel.tap()
        XCTAssertTrue(cancel.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.buttons["View Exported File"].exists)
        XCTAssertFalse(app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge].exists)
    }

    func testWideCustomRangeConfirmAdmitsCaptureAfterExplicitDecision() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
        app.launch()
        selectWideCustomRange(in: app)
        app.buttons[UITestLaunchHelper.Export.exportButton].tap()
        let confirm = app.buttons["export.confirmLargeExport.confirmButton"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["View Exported File"].exists)
        confirm.tap()
        XCTAssertTrue(app.buttons["View Exported File"].waitForExistence(timeout: 10))
        XCTAssertFalse(confirm.exists)
    }

    private func discoveryApp(_ scenario: String, previewFixtures: Bool = false) -> XCUIApplication {
        let app = UITestLaunchHelper.configuredApp(healthAuthorized: true, vaultSelected: true,
            purchaseUnlocked: true, useHealthKitExportPreviewFixtures: previewFixtures)
        app.launchEnvironment["UITEST_EARLIEST_STEP_DISCOVERY"] = scenario
        app.launchEnvironment["UITEST_HISTORY_ASSESSMENT"] = "unknown"
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
        return app
    }

    private func selectAllTime(in app: XCUIApplication) {
        let preset = app.buttons[UITestLaunchHelper.Export.datePresetAllTimeButton]
        reveal(preset, in: app)
        preset.tap()
        XCTAssertTrue(preset.isSelected)
    }

    private func selectWideCustomRange(in app: XCUIApplication) {
        let custom = app.buttons[UITestLaunchHelper.Export.datePresetCustomButton]
        reveal(custom, in: app)
        custom.tap()
        let start = app.descendants(matching: .any)[UITestLaunchHelper.Export.customStartDatePicker]
        reveal(start, in: app)
        start.tap()
        let previousMonth = app.buttons["DatePicker.PreviousMonth"]
        XCTAssertTrue(previousMonth.waitForExistence(timeout: 5))
        let calendar = Calendar(identifier: .gregorian)
        let today = Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "MMMM yyyy"
        let monthHeader = app.buttons["DatePicker.Show"]
        XCTAssertEqual(monthHeader.value as? String, formatter.string(from: today))
        for offset in 1...4 {
            previousMonth.tap()
            let expectedMonth = calendar.date(byAdding: .month, value: -offset, to: today)!
            let transitioned = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", formatter.string(from: expectedMonth)),
                object: monthHeader)
            XCTAssertEqual(XCTWaiter.wait(for: [transitioned], timeout: 5), .completed,
                           "Each native calendar month must commit before the next navigation")
        }
        let targetMonth = calendar.date(byAdding: .month, value: -4, to: today)!
        let firstDay = calendar.date(from: calendar.dateComponents([.year, .month], from: targetMonth))!
        formatter.dateFormat = "EEEE, MMMM d"
        let day = app.buttons[formatter.string(from: firstDay)]
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isSelected == true"), object: day)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       "The intended first day must be selected in the native calendar")
        app.buttons["PopoverDismissRegion"].tap()
        XCTAssertTrue(previousMonth.waitForNonExistence(timeout: 5))
        formatter.dateFormat = "MMM d, yyyy"
        let committedDate = start.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@", formatter.string(from: firstDay))).firstMatch
        XCTAssertTrue(committedDate.waitForExistence(timeout: 5),
                      "The wide-range start date must be committed before capture")
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
