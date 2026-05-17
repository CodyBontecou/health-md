import XCTest

/// UI tests for the first-run export journey: auth -> vault -> export.
/// Uses test-mode DI hooks to simulate authorized state and vault selection.
final class ExportJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - First-Run Export Journey

    func testFirstRunExportJourney_showsExportButton_andCompletesExport() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        // Verify app launched and is on the export tab (default)
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "Export button should be visible on launch")

        // Verify health badge shows connected (CompactStatusBadge is a Button)
        let healthBadge = app.buttons[UITestLaunchHelper.Export.healthBadge]
        XCTAssertTrue(healthBadge.waitForExistence(timeout: 3), "Health badge should be visible")

        // Verify vault badge shows connected
        let vaultBadge = app.buttons[UITestLaunchHelper.Export.vaultBadge]
        XCTAssertTrue(vaultBadge.waitForExistence(timeout: 3), "Vault badge should be visible")

        // Tap export button — in test mode, simulateTestExport runs immediately.
        exportButton.tap()

        // After the simulated export, the status badge should appear
        // ExportStatusBadge is a complex view — use descendants query
        let statusBadge = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 10), "Export status badge should appear after export")
    }

    func testExportPreview_rendersHealthKitFixtureValues() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            useHealthKitExportPreviewFixtures: true
        )
        app.launch()

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5), "Preview button should be visible on launch")
        previewButton.tap()

        let markdownRow = app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
        XCTAssertTrue(markdownRow.waitForExistence(timeout: 10), "Markdown preview row should render from HealthKit fixtures")
        markdownRow.tap()

        let fileContent = app.staticTexts[UITestLaunchHelper.ExportPreview.fileContent]
        XCTAssertTrue(fileContent.waitForExistence(timeout: 5), "Rendered export content should be visible")

        let renderedExport = fileContent.label
        XCTAssertTrue(renderedExport.contains("12,500 steps"), "Preview should render fixture activity values")
        XCTAssertTrue(renderedExport.contains("**Resting HR:** 58 bpm"), "Preview should render fixture heart values")
        XCTAssertTrue(renderedExport.contains("**Blood Pressure:** 120/80 mmHg"), "Preview should render fixture vitals values")
        XCTAssertTrue(renderedExport.contains("Heart Rate Samples (5 readings)"), "Preview should render granular fixture samples")
        XCTAssertTrue(renderedExport.contains("Running"), "Preview should render fixture workout values")
    }

    func testExportButton_disabledWithoutHealthAuth() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: false,
            vaultSelected: true,
            purchaseUnlocked: true
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertFalse(exportButton.isEnabled, "Export button should be disabled without health authorization")
    }

    func testExportButton_disabledWithoutVault() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            purchaseUnlocked: true
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertFalse(exportButton.isEnabled, "Export button should be disabled without vault selected")
    }

    // MARK: - Export Target

    func testExportTargetSelector_visible() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["EXPORT TARGET"].waitForExistence(timeout: 5), "Export target section should be visible")
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.localTargetOption].waitForExistence(timeout: 3), "Local target row should be visible")
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.macTargetOption].waitForExistence(timeout: 3), "Mac target row should be visible")
    }

    func testMacTarget_disabledWhenDisconnected() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "disconnected"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertFalse(macTarget.isEnabled, "Mac target should be disabled when no Mac is connected")
        XCTAssertTrue(
            accessibilityText(of: macTarget).contains("No Mac connected")
                || accessibilityText(of: macTarget).contains("Open Health.md"),
            "Mac row should explain disconnected state"
        )
    }

    func testMacTarget_disabledWhenConnectedButNoFolderSelected() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "connected",
            macExportStatus: "noFolder"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertFalse(macTarget.isEnabled, "Mac target should be disabled until the Mac has a destination folder")
        XCTAssertTrue(
            accessibilityText(of: macTarget).contains("No folder selected")
                || accessibilityText(of: macTarget).contains("Choose a folder on Mac"),
            "Mac row should explain that the Mac needs a folder"
        )
    }

    func testMacTarget_enabledWhenReady() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "connected",
            macExportStatus: "ready"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertTrue(waitForEnabled(macTarget), "Mac target should be enabled when the connected Mac is ready")
    }

    func testPathPreview_changesForMacTarget() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "connected",
            macExportStatus: "ready",
            macDestinationPath: "/tmp/ReadyMacVault"
        )
        app.launch()

        let pathPreview = app.descendants(matching: .any)[UITestLaunchHelper.Export.pathPreview]
        scrollUntilExists(pathPreview, in: app)
        XCTAssertTrue(pathPreview.exists, "Path preview should be present")
        let localPreview = waitForAccessibilityText(of: pathPreview, containing: "TestVault")
        XCTAssertTrue(localPreview.contains("TestVault"), "Local preview should mention the local test vault, got: \(localPreview)")

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        scrollUntilHittable(macTarget, in: app, swipingUp: false)
        XCTAssertTrue(waitForEnabled(macTarget), "Mac target should become enabled")
        macTarget.tap()

        scrollUntilExists(pathPreview, in: app)
        let macPreview = waitForAccessibilityText(of: pathPreview, containing: "Mac: /tmp/ReadyMacVault")
        XCTAssertTrue(macPreview.contains("Mac: /tmp/ReadyMacVault"), "Mac preview should mention the Mac destination, got: \(macPreview)")
        XCTAssertNotEqual(localPreview, macPreview, "Path preview should change after selecting the Mac target")
    }

    func testPreviewAvailable_withoutLocalFolderForMacTarget() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            purchaseUnlocked: true,
            syncState: "connected",
            macExportStatus: "ready"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertTrue(waitForEnabled(macTarget), "Mac target should be enabled")
        macTarget.tap()

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5), "Preview button should be visible")
        XCTAssertTrue(previewButton.isEnabled, "Preview should remain available for Mac-only export without a local folder")
    }

    func testPaywallShown_forMacTargetWhenQuotaExhausted() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            freeExportsUsed: 3,
            syncState: "connected",
            macExportStatus: "ready"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertTrue(waitForEnabled(macTarget), "Mac target should be enabled")
        macTarget.tap()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "Export button should be visible")
        XCTAssertTrue(exportButton.isEnabled, "Mac target should satisfy export readiness even without local folder")
        exportButton.tap()

        let unlockTitle = app.staticTexts["Unlock Health.md"]
        XCTAssertTrue(unlockTitle.waitForExistence(timeout: 5), "Paywall should appear before a Mac payload is prepared when quota is exhausted")
    }

    // MARK: - Date Range Presets

    func testDateRangePresets_visibleAndCustomPickersHiddenByDefault() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["DATE RANGE"].waitForExistence(timeout: 5), "Date Range section should be visible")
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.datePresetTodayButton].waitForExistence(timeout: 3), "Today preset should be visible")
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.datePresetYesterdayButton].waitForExistence(timeout: 3), "Yesterday preset should be visible")
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.datePresetAllTimeButton].waitForExistence(timeout: 3), "All Time preset should be visible")
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.datePresetCustomButton].waitForExistence(timeout: 3), "Custom preset should be visible")

        let startPicker = app.descendants(matching: .any)[UITestLaunchHelper.Export.customStartDatePicker]
        let endPicker = app.descendants(matching: .any)[UITestLaunchHelper.Export.customEndDatePicker]
        XCTAssertFalse(startPicker.exists, "Start Date picker should be hidden until Custom is selected")
        XCTAssertFalse(endPicker.exists, "End Date picker should be hidden until Custom is selected")
    }

    func testDateRangePresets_customRevealsStartAndEndPickers() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        let customPreset = app.buttons[UITestLaunchHelper.Export.datePresetCustomButton]
        XCTAssertTrue(customPreset.waitForExistence(timeout: 5), "Custom preset should be visible")
        customPreset.tap()

        let startPicker = app.descendants(matching: .any)[UITestLaunchHelper.Export.customStartDatePicker]
        let endPicker = app.descendants(matching: .any)[UITestLaunchHelper.Export.customEndDatePicker]
        XCTAssertTrue(startPicker.waitForExistence(timeout: 3), "Start Date picker should appear after tapping Custom")
        XCTAssertTrue(endPicker.waitForExistence(timeout: 3), "End Date picker should appear after tapping Custom")
    }

    // MARK: - Tab Navigation

    func testTabNavigation_switchesBetweenTabs() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        // Start on export tab
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        // Navigate to schedule tab
        let scheduleTab = tabButton(
            in: app,
            identifier: UITestLaunchHelper.Tab.schedule,
            label: "Schedule"
        )
        XCTAssertTrue(scheduleTab.exists, "Schedule tab should exist")
        scheduleTab.tap()

        // Schedule controls are inline on the tab — the toggle is the anchor
        let scheduleToggle = app.switches[UITestLaunchHelper.Schedule.enableToggle]
        XCTAssertTrue(scheduleToggle.waitForExistence(timeout: 3), "Schedule toggle should appear inline")

        // Navigate to sync tab
        let syncTab = tabButton(
            in: app,
            identifier: UITestLaunchHelper.Tab.sync,
            label: "Sync"
        )
        syncTab.tap()

        // Navigate back to export
        let exportTab = tabButton(
            in: app,
            identifier: UITestLaunchHelper.Tab.export,
            label: "Export"
        )
        exportTab.tap()
        XCTAssertTrue(exportButton.waitForExistence(timeout: 3))
    }

    // MARK: - Helpers

    private func tabButton(in app: XCUIApplication, identifier: String, label: String) -> XCUIElement {
        let identified = app.buttons[identifier]
        if identified.exists { return identified }
        return app.buttons[label]
    }

    private func accessibilityText(of element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return [element.label, value].joined(separator: " ")
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<6 where !element.exists {
            scrollView.swipeUp()
        }
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, swipingUp: Bool) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<6 where !element.isHittable {
            swipingUp ? scrollView.swipeUp() : scrollView.swipeDown()
        }
    }

    private func waitForAccessibilityText(
        of element: XCUIElement,
        containing expectedText: String,
        timeout: TimeInterval = 5
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var text = accessibilityText(of: element)
        while Date() < deadline {
            text = accessibilityText(of: element)
            if text.contains(expectedText) { return text }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return text
    }
}
