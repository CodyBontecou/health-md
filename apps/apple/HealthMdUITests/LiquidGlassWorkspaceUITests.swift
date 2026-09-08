import XCTest

/// Exercises the native workspace against the existing export and persistence services.
final class LiquidGlassWorkspaceUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    private func launch(protected: Bool = false) -> XCUIApplication {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true, vaultSelected: true, purchaseUnlocked: true,
            configurationProtectionEnabled: protected,
            useHealthKitExportPreviewFixtures: true, exportResult: "success"
        )
        app.launch()
        XCTAssertTrue(app.buttons["home.editExport"].waitForExistence(timeout: 10))
        return app
    }

    private func open(_ route: String, in app: XCUIApplication) {
        UITestLaunchHelper.openWorkspace(route, in: app)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<24 {
            if element.isHittable, element.frame.midY > app.frame.height * 0.17,
               element.frame.midY < app.frame.height * 0.66 { return }
            let movingUp = !element.exists || element.frame.midY > app.frame.height * 0.5
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: movingUp ? 0.6 : 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: movingUp ? 0.4 : 0.55))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
        }
    }

    private func duplicateDefaultInSelector(_ app: XCUIApplication) {
        app.buttons["export.profiles.row.Default"].tap()
        let duplicate = app.buttons["Duplicate"]
        for _ in 0..<8 where !duplicate.isHittable { app.swipeUp() }
        XCTAssertTrue(duplicate.isHittable)
        duplicate.tap()
        let keep = app.buttons["Keep It"]
        if keep.waitForExistence(timeout: 2) { keep.tap() }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["export.profiles.select.Default 2"].waitForExistence(timeout: 5))
    }

    func testVisualizationDatePresetsAndEarlierPeriods() {
        let app = launch(protected: true)
        let range = app.buttons["home.dates.range"]
        XCTAssertTrue(range.waitForExistence(timeout: 10))
        let original = range.value as? String
        XCTAssertTrue(app.buttons["home.dates.week"].isSelected)
        XCTAssertFalse(app.buttons["home.dates.next"].isEnabled)
        reveal(range, in: app)
        capture("Visualization date controls")
        app.buttons["home.dates.previous"].tap()
        XCTAssertNotEqual(range.value as? String, original)
        XCTAssertTrue(app.buttons["home.dates.next"].isEnabled)
        XCTAssertTrue(app.buttons["home.dates.latest"].exists)
        app.buttons["home.dates.next"].tap()
        XCTAssertEqual(range.value as? String, original)
        app.buttons["home.dates.month"].tap()
        XCTAssertTrue(app.buttons["home.dates.month"].isSelected)
        let chart = app.descendants(matching: .any)["home.health.steps.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        XCTAssertTrue(chart.label.contains("30 selected days"))
        reveal(chart, in: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)).tap()
        let reading = app.descendants(matching: .any)["home.health.steps.value"].firstMatch
        let firstDay = Calendar.current.date(byAdding: .day, value: -29, to: Date())!
        XCTAssertTrue(reading.label.contains(firstDay.formatted(.dateTime.month(.abbreviated).day())))
        capture("Thirty day movement with selected historical date")
        reveal(app.buttons["home.dates.previous"], in: app)
        app.buttons["home.dates.previous"].tap()
        app.buttons["home.dates.latest"].tap()
        app.buttons["home.dates.week"].tap()
        XCTAssertEqual(range.value as? String, original)
        XCTAssertEqual(app.buttons["home.profile.selector"].value as? String, "Default")
        XCTAssertFalse(app.descendants(matching: .any)[UITestLaunchHelper.ConfigurationProtection.toast].firstMatch.exists,
                       "Read-only chart dates are available while export configuration is protected")
    }

    private func chooseVisualizationDate(_ id: String, from original: Date, to date: Date, in app: XCUIApplication) {
        app.datePickers[id].tap()
        let calendar = Calendar.current
        let originalMonth = calendar.dateInterval(of: .month, for: original)!.start
        let targetMonth = calendar.dateInterval(of: .month, for: date)!.start
        let months = calendar.dateComponents([.month], from: originalMonth, to: targetMonth).month!
        for _ in 0..<abs(months) {
            app.buttons[months < 0 ? "DatePicker.PreviousMonth" : "DatePicker.NextMonth"].tap()
        }
        let label = date.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let day = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", label)).firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 5))
        day.tap()
        let dismissCalendar = app.buttons["PopoverDismissRegion"]
        if dismissCalendar.exists {
            dismissCalendar.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.7)).tap()
        }
    }

    private func finishVisualizationDates(_ app: XCUIApplication, apply: Bool) {
        let button = app.buttons[apply ? "home.dates.apply" : "home.dates.cancel"]
        XCTAssertTrue(button.exists)
        XCTAssertTrue(button.isEnabled)
        // Native calendar dismissal can leave a stale AX hit point on iOS 26.
        button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(app.datePickers["home.dates.start"].waitForNonExistence(timeout: 5))
    }

    func testVisualizationCustomDatesCanBeCancelledAndApplied() {
        let app = launch()
        let range = app.buttons["home.dates.range"]
        XCTAssertTrue(range.waitForExistence(timeout: 10))
        let original = range.value as? String
        let today = Calendar.current.startOfDay(for: Date())
        let originalStart = Calendar.current.date(byAdding: .day, value: -6, to: today)!
        let start = Calendar.current.date(byAdding: .day, value: -5, to: today)!
        let end = Calendar.current.date(byAdding: .day, value: -1, to: today)!
        app.buttons["home.dates.custom"].tap()
        XCTAssertTrue(app.datePickers["home.dates.start"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.datePickers["home.dates.end"].exists)
        capture("Custom visualization date range")
        chooseVisualizationDate("home.dates.start", from: originalStart, to: start, in: app)
        finishVisualizationDates(app, apply: false)
        XCTAssertEqual(range.value as? String, original)
        XCTAssertTrue(app.buttons["home.dates.week"].isSelected)
        reveal(range, in: app)
        range.tap()
        chooseVisualizationDate("home.dates.start", from: originalStart, to: start, in: app)
        chooseVisualizationDate("home.dates.end", from: today, to: end, in: app)
        finishVisualizationDates(app, apply: true)
        XCTAssertTrue(app.buttons["home.dates.custom"].isSelected)
        XCTAssertNotEqual(range.value as? String, original)
        let chart = app.descendants(matching: .any)["home.health.steps.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 5))
        XCTAssertTrue(chart.label.contains("5 selected days"))
        let reading = app.descendants(matching: .any)["home.health.steps.value"].firstMatch
        XCTAssertTrue(reading.label.contains(end.formatted(.dateTime.month(.abbreviated).day())))
        reveal(range, in: app)
        range.tap()
        let tooEarly = Calendar.current.date(byAdding: .month, value: -4, to: start)!
        chooseVisualizationDate("home.dates.start", from: start, to: tooEarly, in: app)
        XCTAssertFalse(app.buttons["home.dates.apply"].isEnabled)
        capture("Custom range limit")
        finishVisualizationDates(app, apply: false)
        XCTAssertTrue(chart.label.contains("5 selected days"))
    }

    func testAllVisualizationsFollowThirtyDayRange() {
        let app = launch()
        app.buttons["home.dates.month"].tap()
        let sleep = app.descendants(matching: .any)["home.health.sleep.chart"].firstMatch
        reveal(sleep, in: app)
        XCTAssertTrue(sleep.label.contains("30 selected days"))
        capture("Thirty day sleep stages")
        let hrv = app.buttons["home.signals.hrv"]
        reveal(hrv, in: app)
        hrv.tap()
        let signals = app.descendants(matching: .any)["home.health.hrv.chart"].firstMatch
        XCTAssertTrue(signals.label.contains("30 selected days"))
        reveal(signals, in: app)
        capture("Thirty day health signals")
        let exports = app.descendants(matching: .any)["home.export.activity.count"].firstMatch
        reveal(exports, in: app)
        XCTAssertTrue(exports.label.contains("30 days"))
        capture("Thirty day export activity")
    }

    func testProfileSelectorActivatesDirectlyAndReflectsTheSelection() {
        let app = launch()
        let homeSelector = app.buttons["home.profile.selector"]
        XCTAssertTrue(homeSelector.waitForExistence(timeout: 5))
        XCTAssertEqual(homeSelector.value as? String, "Default")
        homeSelector.tap()
        duplicateDefaultInSelector(app)
        capture("Direct profile selector")
        app.buttons["export.profiles.select.Default 2"].tap()
        XCTAssertTrue(app.navigationBars["Export Profiles"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(homeSelector.value as? String, "Default 2")
        capture("Home with the selected profile")
        homeSelector.tap()
        XCTAssertTrue(app.buttons["export.profiles.select.Default 2"].isSelected)
        XCTAssertFalse(app.buttons["export.profiles.select.Default"].isSelected)
        app.buttons["export.profiles.select.Default"].tap()
        XCTAssertEqual(homeSelector.value as? String, "Default")
    }

    func testProfileDetailKeepsActivationVisibleWhileScrolling() {
        let app = launch()
        app.buttons["home.profile.selector"].tap()
        duplicateDefaultInSelector(app)
        app.buttons["export.profiles.row.Default 2"].tap()
        let activate = app.buttons["export.profiles.makeActive"]
        XCTAssertTrue(activate.waitForExistence(timeout: 5))
        XCTAssertTrue(activate.isHittable, "Activation is visible immediately without scrolling")
        capture("Profile detail with persistent activation")
        app.swipeUp()
        XCTAssertTrue(activate.isHittable, "Activation stays visible while reading settings")
        activate.tap()
        XCTAssertTrue(app.navigationBars["Export Profiles"].waitForNonExistence(timeout: 5))
        XCTAssertEqual(app.buttons["home.profile.selector"].value as? String, "Default 2")
    }

    func testProfileSelectionRespectsConfigurationProtection() {
        let app = launch()
        app.buttons["home.profile.selector"].tap()
        duplicateDefaultInSelector(app)
        app.buttons["export.profiles.done"].tap()
        UITestLaunchHelper.openSettings(in: app)
        let protection = app.switches[UITestLaunchHelper.ConfigurationProtection.toggle]
        XCTAssertTrue(protection.waitForExistence(timeout: 5))
        protection.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        UITestLaunchHelper.openExportHome(in: app)
        app.buttons["home.profile.selector"].tap()
        app.buttons["export.profiles.select.Default 2"].tap()
        XCTAssertTrue(app.buttons["export.profiles.select.Default"].isSelected)
        XCTAssertFalse(app.buttons["export.profiles.select.Default 2"].isSelected)
        XCTAssertTrue(app.descendants(matching: .any)[UITestLaunchHelper.ConfigurationProtection.toast].firstMatch.exists)
        app.buttons["export.profiles.row.Default 2"].tap()
        let activate = app.buttons["export.profiles.makeActive"]
        XCTAssertTrue(activate.waitForExistence(timeout: 5))
        activate.tap()
        XCTAssertTrue(activate.exists, "A rejected activation keeps the detail open")
        app.navigationBars["Default 2"].buttons.firstMatch.tap()
        XCTAssertTrue(app.buttons["export.profiles.select.Default"].waitForExistence(timeout: 5))
        app.buttons["export.profiles.select.Default"].tap()
        XCTAssertTrue(app.navigationBars["Export Profiles"].waitForNonExistence(timeout: 5),
                      "Tapping the already-active profile is allowed because it changes no configuration")
        XCTAssertEqual(app.buttons["home.profile.selector"].value as? String, "Default")
    }

    func testHealthFeedAndCompactProfileEditor() {
        let app = launch()
        let steps = app.descendants(matching: .any)["home.health.steps.value"]
        XCTAssertTrue(steps.waitForExistence(timeout: 10))
        XCTAssertTrue(steps.label.contains("12,500"), "The chart header uses the injected HealthKit reading")
        capture("Health overview feed")
        app.buttons["home.editExport"].tap()
        XCTAssertTrue(app.buttons["export.workspace.files"].waitForExistence(timeout: 5))
        capture("Compact editable profile")
        let filename = app.buttons[UITestLaunchHelper.Export.filenameEditorButton]
        for _ in 0..<5 where !filename.isHittable { app.swipeUp() }
        filename.tap()
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.outputEditorSaveButton].waitForExistence(timeout: 5),
                      "The filename row opens its editor directly")
    }

    func testChartSelectionShowsTheSelectedDaysReading() {
        let app = launch()
        let chart = app.descendants(matching: .any)["home.health.steps.chart"].firstMatch
        XCTAssertTrue(chart.waitForExistence(timeout: 10))
        reveal(chart, in: app)
        chart.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        let value = app.descendants(matching: .any)["home.health.steps.value"]
        let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS '7,630'"), object: value)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed, "Chart: \(chart.debugDescription); selected value: \(value.label)")
        capture("Selected day in health chart")
        for _ in 0..<3 { app.swipeUp() }
        capture("Heart trend and export activity")
    }

    func testAdditionalHealthVisualizationsAndSelections() {
        let app = launch()
        let energy = app.buttons["home.movement.activeEnergy"]
        XCTAssertTrue(energy.waitForExistence(timeout: 10))
        energy.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.health.activeEnergy.value"].label.contains("520"))
        app.buttons["home.movement.exercise"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.health.exercise.value"].label.contains("45"))
        app.buttons["home.movement.steps"].tap()
        capture("Movement chart with metric selection")

        let rem = app.buttons["home.sleep.stage.rem"]
        reveal(rem, in: app)
        XCTAssertTrue(rem.isHittable)
        rem.tap()
        let composition = app.descendants(matching: .any)["home.sleep.composition.value"].firstMatch
        XCTAssertTrue(composition.label.contains("REM"))
        XCTAssertTrue(composition.label.contains("1h 36m"))
        capture("Sleep composition and weekly stages")
        let sleepChart = app.descendants(matching: .any)["home.health.sleep.chart"].firstMatch
        reveal(sleepChart, in: app)
        sleepChart.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.5)).tap()
        XCTAssertTrue(composition.label.contains("7h 6m"), "Selecting another day resets the stage focus and shows its total")

        let hrv = app.buttons["home.signals.hrv"]
        reveal(hrv, in: app)
        XCTAssertTrue(hrv.isHittable)
        hrv.tap()
        let value = app.descendants(matching: .any)["home.health.hrv.value"].firstMatch
        XCTAssertTrue(value.waitForExistence(timeout: 5))
        XCTAssertTrue(value.label.contains("56"))
        capture("Health signals and HRV trend")
        reveal(app.buttons["home.signals.respiratoryRate"], in: app)
        app.buttons["home.signals.respiratoryRate"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.health.respiratoryRate.value"].label.contains("14.4"))
    }

    func testSavedProfileFactEditsSupportCancelAndSave() {
        let app = launch()
        app.buttons["export.profiles"].tap()
        app.buttons["export.profiles.row.Default"].tap()
        let row = app.buttons["export.profiles.fact.dictionary.Data dictionary"]
        for _ in 0..<8 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.isHittable)
        row.tap()
        let toggle = app.switches["Data dictionary"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let original = toggle.value as? String
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        app.buttons["Cancel"].tap()
        row.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, original, "Cancel discards the isolated profile draft")
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertNotEqual(toggle.value as? String, original, "The draft changes before saving")
        app.buttons["export.profiles.editor.confirm"].tap()
        row.tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertNotEqual(toggle.value as? String, original, "Save persists through the profile coordinator")
    }

    func testFilesEditorRetainsFormatSelectionAcrossNavigation() {
        let app = launch()
        capture("Liquid Glass export profile")
        open("files", in: app)
        let json = app.switches["JSON"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        let previous = json.value as? String
        json.tap()
        app.navigationBars.buttons.firstMatch.tap()
        open("files", in: app)
        XCTAssertNotEqual(app.switches["JSON"].value as? String, previous)
        app.segmentedControls.buttons["Names & folders"].tap()
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.filenameEditorButton].waitForExistence(timeout: 5))
        app.buttons[UITestLaunchHelper.Export.filenameEditorButton].tap()
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.outputEditorSaveButton].waitForExistence(timeout: 5))
        capture("Filename pattern editor")
        app.buttons[UITestLaunchHelper.Export.outputEditorSaveButton].tap()
        app.segmentedControls.buttons["Existing files"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Append"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["Append"].tap()
        XCTAssertTrue(app.segmentedControls.buttons["Append"].isSelected)
        capture("Existing file behavior")
    }

    func testDailyNoteAndEntrySettingsAreDirectlyReachable() {
        let app = launch()
        open("notes", in: app)
        let enabled = app.switches["Inject health metrics into daily notes"]
        XCTAssertTrue(enabled.waitForExistence(timeout: 5))
        if ["0", "Disabled"].contains(enabled.value as? String ?? "") { enabled.tap() }
        XCTAssertTrue(app.textFields["Daily notes folder"].waitForExistence(timeout: 5))
        capture("Daily note injection")
        app.navigationBars.buttons.firstMatch.tap()
        open("entries", in: app)
        XCTAssertTrue(app.navigationBars["Individual Tracking"].waitForExistence(timeout: 5))
        capture("Individual entry tracking")
    }

    func testPreviewAndExportUseExistingPipeline() {
        let app = launch()
        app.buttons[UITestLaunchHelper.Export.previewButton].tap()
        let export = app.buttons[UITestLaunchHelper.ExportPreview.exportButton]
        XCTAssertTrue(export.waitForExistence(timeout: 20))
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: export)
        wait(for: [ready], timeout: 30)
        capture("Actual export preview")
        export.tap()
        XCTAssertTrue(app.buttons["View Exported File"].waitForExistence(timeout: 15))
        app.buttons["View Exported File"].tap()
        XCTAssertTrue(app.descendants(matching: .any)[UITestLaunchHelper.ExportedFile.viewer].waitForExistence(timeout: 10))
        capture("Exported file")
    }

    func testActivityConnectionsAndProfilesNavigation() {
        let app = launch()
        app.tabBars.buttons["Activity"].tap()
        XCTAssertTrue(app.navigationBars["Activity"].waitForExistence(timeout: 5))
        app.tabBars.buttons["Connections"].tap()
        XCTAssertTrue(app.buttons["connections.settings"].waitForExistence(timeout: 5))
        app.buttons["connections.settings"].tap()
        XCTAssertTrue(app.descendants(matching: .any)[UITestLaunchHelper.ConfigurationProtection.toggle].waitForExistence(timeout: 5))
        capture("Settings")
        app.tabBars.buttons["Home"].tap()
        app.buttons["export.profiles"].tap()
        XCTAssertTrue(app.navigationBars["Export Profiles"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["export.profiles.row.Default"].exists)
        capture("Saved export profiles")
    }

    func testProtectedSettingsRemainInspectableAndCannotChange() {
        let app = launch(protected: true)
        open("files", in: app)
        let json = app.switches["JSON"]
        XCTAssertTrue(json.waitForExistence(timeout: 5))
        let before = json.value as? String
        json.tap()
        XCTAssertEqual(json.value as? String, before)
        XCTAssertTrue(app.descendants(matching: .any)[UITestLaunchHelper.ConfigurationProtection.toast].waitForExistence(timeout: 5))
    }
}
